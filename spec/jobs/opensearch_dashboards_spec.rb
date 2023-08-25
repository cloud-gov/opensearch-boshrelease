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
    end
  end
end
