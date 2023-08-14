require 'rspec'
require 'json'
require 'bosh/template/test'

describe 'opensearch job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('opensearch') }

  describe 'config.json' do
    let(:template) { job.template('config/opensearch.yml') }

    let(:manifest) do
      {
        'opensearch.manager_hosts' => ["foobar"],
        'opensearch' => {
          'manager_hosts' => ['foobar2']
        }
      }
    end

    it 'configures default settings' do
      config = template.render(manifest)
      expect(config['bootstrap']['memory_lock']).to eq(true)
    end
  end
end
