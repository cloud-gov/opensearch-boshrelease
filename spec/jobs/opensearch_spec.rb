require 'rspec'
require 'json'
require 'bosh/template/test'
require 'bosh/template/test/link'

describe 'opensearch job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('opensearch') }

  describe 'config.json' do
    let(:template) { job.template('config/opensearch.yml') }

    let(:config) do
      config = YAML.load(template.render({}))
    end

    it 'configures default settings' do
      expect(config['bootstrap.memory_lock']).to eq(true)
      expect(config['path.logs']).to eq('/var/vcap/sys/log/opensearch')
      expect(config['path.data']).to eq('/var/vcap/store/opensearch')
      expect(config['plugins.security.allow_default_init_securityindex']).to eq(true)
      expect(config['network.bind_host']).to eq('0.0.0.0')
    end

    describe 'security' do
      let(:manifest) do
        {
          'opensearch' => {
            'admin' => {
              'dn' => 'admin-dn'
            },
            'node' => {
              'ssl' => {
                'dn' => ['node-1', 'node-2'],
                'certificate' => 'node-certificate',
              }
            },
            'http' => {
              'ssl' => {
                'certificate' => 'http-certificate'
              }
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'configures admin node name' do
        expect(config['plugins.security.authcz.admin_dn']).to eq(['admin-dn'])
      end

      it 'configures node names' do
        expect(config['plugins.security.nodes_dn']).to eq(['node-1', 'node-2'])
      end

      it 'configures node SSL settings' do
        expect(config['plugins.security.ssl.transport.enforce_hostname_verification']).to eq(false)
        expect(config['plugins.security.ssl.transport.pemkey_filepath']).to eq('ssl/opensearch-node.key')
        expect(config['plugins.security.ssl.transport.pemcert_filepath']).to eq('ssl/opensearch-node.crt')
        expect(config['plugins.security.ssl.transport.pemtrustedcas_filepath']).to eq('ssl/opensearch.ca')
      end

      it 'configures http SSL settings' do
        expect(config['plugins.security.ssl.http.enabled']).to eq(true)
        expect(config['plugins.security.ssl.http.clientauth_mode']).to eq('OPTIONAL')
        expect(config['plugins.security.ssl.http.pemkey_filepath']).to eq('ssl/opensearch-http.key')
        expect(config['plugins.security.ssl.http.pemcert_filepath']).to eq('ssl/opensearch-http.crt')
        expect(config['plugins.security.ssl.http.pemtrustedcas_filepath']).to eq('ssl/opensearch.ca')
      end
    end

    describe 'multi-node cluster settings from links' do
      let(:link_properties) do
        {
          'opensearch' => {
            'cluster_name' => 'opensearch-cluster'
          }
        }
      end
      
      let(:link) do
        Bosh::Template::Test::Link.new(
          name: 'opensearch',
          instances: [
            Bosh::Template::Test::LinkInstance.new(address: 'manager-1'),
            Bosh::Template::Test::LinkInstance.new(address: 'manager-2'),
          ],
          properties: link_properties
        )
      end
  
      let(:config) do
        config = YAML.load(template.render({}, consumes: [link]))
      end

      it 'sets cluster name' do
        expect(config['cluster.name']).to eq('opensearch-cluster')
      end

      it 'sets cluster manager hosts' do
        expect(config['cluster.initial_cluster_manager_nodes']).to eq(['manager-1','manager-2'])
      end

      it 'sets discovery hosts' do
        expect(config['discovery.seed_hosts']).to eq(['manager-1','manager-2'])
      end
    end

    describe 'multi-node cluster settings from manifest' do
      let(:manifest) do
        {
          'opensearch' => {
            'cluster_name' => 'foobar',
            'manager_hosts' => ['host-1', 'host-2'],
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'sets cluster name' do
        expect(config['cluster.name']).to eq('foobar')
      end

      it 'sets cluster manager hosts' do
        expect(config['cluster.initial_cluster_manager_nodes']).to eq(['host-1','host-2'])
      end

      it 'sets discovery seed hosts' do
        expect(config['discovery.seed_hosts']).to eq(['host-1','host-2'])
      end
    end

    describe 'single node cluster' do
      let(:manifest) do
        {
          'opensearch' => {
            'manager_hosts' => ['host-1', 'host-2'],
            'discovery' => {
              'single_node' => true
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'does not set cluster manager hosts' do
        expect(config['cluster.initial_cluster_manager_nodes']).to be_nil
      end

      it 'does set discovery seed hosts' do
        expect(config['discovery.seed_hosts']).to be(['host-1', 'host-2'])
      end

      it 'sets discovery type' do
        expect(config['discovery.type']).to eq('single-node')
      end
    end
  end
end
