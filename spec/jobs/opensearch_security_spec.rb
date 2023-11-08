require 'rspec'
require 'json'
require 'bosh/template/test'
require 'bosh/template/test/link'

describe 'opensearch job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('opensearch') }

  describe 'config/opensearch-security/config.yml' do
    let(:template) { job.template('config/opensearch-security/config.yml') }

    context 'with no manifest' do
      let(:config) do
        config = YAML.load(template.render({}))
      end
  
      it 'configures default settings' do
        clientcert_auth_domain_config = config['config']['dynamic']['authc']['clientcert_auth_domain']
        expect(clientcert_auth_domain_config['description']).to eq("Authenticate via SSL client certificates")
        expect(clientcert_auth_domain_config['http_enabled']).to eq(true)
        expect(clientcert_auth_domain_config['transport_enabled']).to eq(true)
        expect(clientcert_auth_domain_config['order']).to eq(1)
        expect(clientcert_auth_domain_config['http_authenticator']).to eq({
          "type" => "clientcert",
          "config" => {
            "username_attribute" => "cn",
          },
          "challenge" => false,
        })
        expect(clientcert_auth_domain_config['authentication_backend']).to eq({
          "type" => "noop"
        })
      end
    end

    describe 'with proxy auth settings' do
      let(:link) do
        Bosh::Template::Test::Link.new(
          name: 'opensearch_dashboards',
          instances: [
            Bosh::Template::Test::LinkInstance.new(address: 'dashboard-1'),
          ],
        )
      end

      let(:manifest) do
        {
          'opensearch' => {
            'enable_proxy_auth' => true,
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest, consumes: [link]))
      end

      it 'configures http settings' do
        http_xff_config = config['config']['dynamic']['http']['xff']
        expect(http_xff_config).to eq({
          "enabled" => true,
          "internalProxies" => "dashboard-1",
          "remoteIpHeader" => "x-forwarded-for",
        })
      end

      it 'configures proxy auth domain settings' do
        proxy_auth_config = config['config']['dynamic']['authc']['proxy_auth_domain']
        expect(proxy_auth_config['http_enabled']).to eq(true)
        expect(proxy_auth_config['transport_enabled']).to eq(true)
        expect(proxy_auth_config['order']).to eq(0)
        expect(proxy_auth_config['http_authenticator']).to eq({
          "type" => "extended-proxy",
          "config" => {
            "user_header" => "x-proxy-user",
            "roles_header" => "x-proxy-roles",
            "attr_header_prefix" => "x-proxy-ext-",
          },
          "challenge" => false,
        })
        expect(proxy_auth_config['authentication_backend']).to eq({
          "type" => "noop"
        })
      end
    end
  end
end
