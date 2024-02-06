require 'rspec'
require 'json'
require 'bosh/template/test'
require 'bosh/template/test/link'

describe 'opensearch_dashboards job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('opensearch_dashboards') }

  describe 'config/opensearch_dashboards.conf' do
    let(:template) { job.template('config/opensearch_dashboards.conf') }

    context 'with no manifest' do
      let(:config) do
        config = YAML.load(template.render({}))
      end
  
      it 'configures default settings' do
        expect(config['server.port']).to eq(5601)
        expect(config['server.host']).to eq('0.0.0.0')
        expect(config['opensearchDashboards.index']).to eq('.opensearch_dashboards')
        expect(config['opensearchDashboards.defaultAppId']).to eq('discover')
        expect(config['opensearch.ssl.verificationMode']).to eq('full')
        expect(config['opensearch.requestTimeout']).to eq(300000)
        expect(config['opensearch.shardTimeout']).to eq(30000)
      end

      it 'does not configure optional settings' do
        expect(config['opensearch.username']).to be_nil
        expect(config['opensearch.password']).to be_nil
        expect(config['opensearch.ssl.certificate']).to be_nil
        expect(config['opensearch.ssl.key']).to be_nil
        expect(config['opensearch.ssl.certificateAuthorities']).to be_nil
      end
    end

    context 'with manifest' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'port' => 1234,
            'host' => 'dashboard',
            'index' => 'dashboard-index',
            'defaultAppId' => 'fake-app-id',
            'request_timeout' => 10,
            'shard_timeout' => 5,
          }
        }
      end

      let(:config) do
        config = YAML.load(template.render(manifest))
      end
  
      it 'configures settings' do
        expect(config['server.port']).to eq(1234)
        expect(config['server.host']).to eq('dashboard')
        expect(config['opensearchDashboards.index']).to eq('dashboard-index')
        expect(config['opensearchDashboards.defaultAppId']).to eq('fake-app-id')
        expect(config['opensearch.requestTimeout']).to eq(10)
        expect(config['opensearch.shardTimeout']).to eq(5)
      end
    end

    describe 'with host/port settings' do
      context 'with no settings' do
        let(:config) do
          config = YAML.load(template.render({}))
        end
        
        it 'sets port correctly' do
          expect(config['opensearch.hosts']).to eq('https://localhost:9200')
        end
      end

      context 'with manifest settings' do
        let(:manifest) do
          {
            'opensearch_dashboards' => {
              'opensearch' => {
                'host' => 'dashboard',
                'port' => '2222'
              }
            }
          }
        end

        let(:config) do
          config = YAML.load(template.render(manifest))
        end
        
        it 'sets port correctly' do
          expect(config['opensearch.hosts']).to eq('https://dashboard:2222')
        end
      end

      context 'with node link' do
        let(:manifest) do
          {
            'opensearch_dashboards' => {
              'opensearch' => {
                'ssl' => {
                  'certificate' => 'fake-cert',
                  'private_key' => 'changeme'
                }
              }
            }
          }
        end
  
        let(:link) do
          Bosh::Template::Test::Link.new(
            name: 'opensearch',
            instances: [
              Bosh::Template::Test::LinkInstance.new(),
            ],
            properties: {
              'opensearch' => {
                'port' => '1111',
                'node' => {
                  'ssl' => {
                    'ca' => 'fake-ca'
                  }
                }
              }
            }
          )
        end
  
        let(:config) do
          config = YAML.load(template.render(manifest, consumes: [link]))
        end
        
        it 'sets port correctly' do
          expect(config['opensearch.hosts']).to eq('https://localhost:1111')
        end
      end
    end

    describe 'with auth settings' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'username' => 'fake-user',
            'password' => 'changeme',
          }
        }
      end

      let(:config) do
        config = YAML.load(template.render(manifest))
      end
      
      it 'sets username correctly' do
        expect(config['opensearch.username']).to eq('fake-user')
      end

      it 'sets password correctly' do
        expect(config['opensearch.password']).to eq('changeme')
      end
    end

    describe 'with opensearch SSL settings' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'opensearch' => {
              'ssl' => {
                'certificate' => 'fake-cert',
                'private_key' => 'changeme',
                'verification_mode' => 'certificate',
              }
            }
          }
        }
      end

      let(:link) do
        Bosh::Template::Test::Link.new(
          name: 'opensearch',
          instances: [
            Bosh::Template::Test::LinkInstance.new(),
          ],
          properties: {
            'opensearch' => {
              'port' => '9200',
              'node' => {
                'ssl' => {
                  'ca' => 'fake-ca'
                }
              }
            }
          }
        )
      end

      let(:config) do
        config = YAML.load(template.render(manifest, consumes: [link]))
      end

      it 'sets the SSL certificate for Opensearch communication' do
        expect(config['opensearch.ssl.certificate']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/dashboard-opensearch.crt')
      end

      it 'sets the SSL private key for Opensearch communication' do
        expect(config['opensearch.ssl.key']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/dashboard-opensearch.key')
      end

      it 'sets the SSL CA for Opensearch communication' do
        expect(config['opensearch.ssl.certificateAuthorities']).to eq(['/var/vcap/jobs/opensearch_dashboards/config/ssl/opensearch.ca'])
      end

      it 'sets the SSL verification mode for Opensearch communication' do
        expect(config['opensearch.ssl.verificationMode']).to eq('certificate')
      end
    end

    describe 'with server SSL settings' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'server' => {
              'ssl' => {
                'enabled' => true,
                'certificate' => 'fake-cert',
                'private_key' => 'changeme',
              }
            }
          }
        }
      end

      let(:link) do
        Bosh::Template::Test::Link.new(
          name: 'opensearch',
          instances: [
            Bosh::Template::Test::LinkInstance.new(),
          ],
          properties: {
            'opensearch' => {
              'port' => '9200',
              'node' => {
                'ssl' => {
                  'ca' => 'fake-ca'
                }
              }
            }
          }
        )
      end

      let(:config) do
        config = YAML.load(template.render(manifest, consumes: [link]))
      end

      it 'enables server SSL' do
        expect(config['server.ssl.enabled']).to eq(true)
      end

      it 'sets the server SSL certificate' do
        expect(config['server.ssl.certificate']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/dashboard-web.crt')
      end

      it 'sets the server SSL private key' do
        expect(config['server.ssl.key']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/dashboard-web.key')
      end

      it 'sets the server SSL CA' do
        expect(config['server.ssl.certificateAuthorities']).to eq(['/var/vcap/jobs/opensearch_dashboards/config/ssl/opensearch.ca'])
      end
    end

    describe 'with config options' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'config_options' => {
              'foo' => 'bar'
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'sets the config options' do
        expect(config['foo']).to eq('bar')
      end
    end

    describe 'with proxy auth ' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'opensearch' => {
              'enable_proxy_auth' => true
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'sets the proxy auth config' do
        expect(config['opensearch.requestHeadersAllowlist']).to eq([
          "securitytenant",
          "Authorization",
          "x-forwarded-for",
          "x-proxy-user",
          "x-proxy-roles",
          "x-proxy-ext-spaceids",
          "x-proxy-ext-orgids"
        ])
        expect(config['opensearch_security.auth.type']).to eq("proxy")
        expect(config['opensearch_security.proxycache.user_header']).to eq("x-proxy-user")
        expect(config['opensearch_security.proxycache.roles_header']).to eq("x-proxy-roles")
      end
    end
  end
end
