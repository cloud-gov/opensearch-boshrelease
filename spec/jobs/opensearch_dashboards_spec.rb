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

    describe 'with port settings' do
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
                  'private_key' => 'fake-key'
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

    describe 'with opensearch SSL settings' do
      let(:manifest) do
        {
          'opensearch_dashboards' => {
            'opensearch' => {
              'ssl' => {
                'certificate' => 'fake-cert',
                'private_key' => 'fake-key'
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
        expect(config['opensearch.ssl.certificate']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/opensearch-dashboard.crt')
      end

      it 'sets the SSL private key for Opensearch communication' do
        expect(config['opensearch.ssl.key']).to eq('/var/vcap/jobs/opensearch_dashboards/config/ssl/opensearch-dashboard.key')
      end

      it 'sets the SSL CA for Opensearch communication' do
        expect(config['opensearch.ssl.certificateAuthorities']).to eq(['/var/vcap/jobs/opensearch_dashboards/config/ssl/opensearch.ca'])
      end
    end
  end
end
