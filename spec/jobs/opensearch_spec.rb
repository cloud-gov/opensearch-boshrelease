require 'rspec'
require 'json'
require 'bosh/template/test'
require 'bosh/template/test/link'

describe 'opensearch job' do
  let(:release) { Bosh::Template::Test::ReleaseDir.new(File.join(File.dirname(__FILE__), '../..')) }
  let(:job) { release.job('opensearch') }

  describe 'config.json' do
    let(:template) { job.template('config/opensearch.yml') }

    context 'with no manifest' do
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

      it 'does not configure optional settings' do
        expect(config['path.repo']).to be_nil
        expect(config['plugins.security.authcz.admin_dn']).to be_nil
        expect(config['plugins.security.nodes_dn']).to be_nil
        expect(config['plugins.security.ssl.transport.enforce_hostname_verification']).to be_nil
        expect(config['plugins.security.ssl.http.enabled']).to be_nil
        expect(config['s3.client.default.protocol']).to be_nil
      end
    end

    describe 'with path settings' do
      let(:manifest) do
        {
          'opensearch' => {
            'path_repo' => '/shared/file/path'
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'configures path repo' do
        expect(config['path.repo']).to eq(['/shared/file/path'])
      end
    end

    describe 'with security settings' do
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

    describe 'with multi-node cluster settings' do
      context 'when links are provided' do
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

      context 'when values are provided in manifest' do
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
    end

    describe 'with single node cluster settings' do
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
        expect(config['discovery.seed_hosts']).to eq(['host-1', 'host-2'])
      end

      it 'sets discovery type' do
        expect(config['discovery.type']).to eq('single-node')
      end
    end

    describe 'with node settings' do
      let(:instance) do
        Bosh::Template::Test::InstanceSpec.new(name: 'instance-name', index: 0)
      end

      let(:manifest) do
        {
          'opensearch' => {
            'node' => {
              'attributes' => {
                'temp' => 'warm',
                'foo' => 'bar'
              }
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest, spec: instance))
      end

      it 'sets the node name' do
        expect(config['node.name']).to eq('instance-name/0')
      end

      it 'sets the node attributes' do
        expect(config['node.attr.foo']).to eq('bar')
        expect(config['node.attr.temp']).to eq('warm')
      end

      describe 'node roles' do
        let(:manifest) do
          {
            'opensearch' => {
              'node' => {
                'allow_cluster_manager' => allow_cluster_manager,
                'allow_data' => allow_data,
                'allow_ingest' => allow_ingest,
              }
            }
          }
        end

        let(:config) do
          config = YAML.load(template.render(manifest, spec: instance))
        end

        context 'when node is a cluster manager' do
          let(:allow_cluster_manager) { true }
          let(:allow_data) { false }
          let(:allow_ingest) { false }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['cluster_manager'])
          end
        end
  
        context 'when node is a data node' do
          let(:allow_cluster_manager) { false }
          let(:allow_data) { true }
          let(:allow_ingest) { false }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['data'])
          end
        end
  
        context 'when node is an ingest node' do
          let(:allow_cluster_manager) { false }
          let(:allow_data) { false }
          let(:allow_ingest) { true }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['ingest'])
          end
        end
  
        context 'when node is a data and ingest node' do
          let(:allow_cluster_manager) { false }
          let(:allow_data) { true }
          let(:allow_ingest) { true }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['data', 'ingest'])
          end
        end
  
        context 'when node is a manager and data node' do
          let(:allow_cluster_manager) { true }
          let(:allow_data) { true }
          let(:allow_ingest) { false }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['cluster_manager', 'data'])
          end
        end
  
        context 'when node has all roles' do
          let(:allow_cluster_manager) { true }
          let(:allow_data) { true }
          let(:allow_ingest) { true }
  
          it 'sets the node roles correctly' do
            expect(config['node.roles']).to eq(['cluster_manager', 'data', 'ingest'])
          end
        end
      end
    end

    describe 'with network settings' do
      let(:instance) do
        Bosh::Template::Test::InstanceSpec.new(ip: '127.0.0.1')
      end

      let(:manifest) do
        {
          'opensearch' => {
            'http_host' => 'localhost'
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest, spec: instance))
      end

      it 'sets the bind host' do
        expect(config['network.bind_host']).to eq('0.0.0.0')
      end

      it 'sets the publish host' do
        expect(config['network.publish_host']).to eq('127.0.0.1')
      end

      it 'sets the http host' do
        expect(config['http.host']).to eq('localhost')
      end
    end

    describe 'with s3 repository settings' do
      context 'using defaults' do
        let(:manifest) do
          {
            'opensearch' => {
              'repository' => {
                's3' => {
                  'access_key' => 'fake-access-key',
                  'secret_key' => 'fake-secret-key',
                }
              }
            }
          }
        end
    
        let(:config) do
          config = YAML.load(template.render(manifest))
        end

        it 'sets the protocol to the default' do
          expect(config['s3.client.default.protocol']).to eq('https')
        end

        it 'sets the read timeout to the default' do
          expect(config['s3.client.default.read_timeout']).to eq('50s')
        end
      end

      context 'with configured settings' do
        let(:manifest) do
          {
            'opensearch' => {
              'repository' => {
                's3' => {
                  'access_key' => 'fake-access-key',
                  'secret_key' => 'fake-secret-key',
                  'protocol' => 'http',
                  'read_timeout' => '30s',
                  'region' => 'region-1'
                }
              }
            }
          }
        end
    
        let(:config) do
          config = YAML.load(template.render(manifest))
        end

        it 'sets the protocol correctly' do
          expect(config['s3.client.default.protocol']).to eq('http')
        end

        it 'sets the read timeout correctly' do
          expect(config['s3.client.default.read_timeout']).to eq('30s')
        end

        it 'sets the region correctly' do
          expect(config['s3.client.default.region']).to eq('region-1')
        end
      end
    end

    describe 'with config options' do
      let(:manifest) do
        {
          'opensearch' => {
            'config_options' => {
              'indices.query.bool.max_clause_count' => 2048
            }
          }
        }
      end
  
      let(:config) do
        config = YAML.load(template.render(manifest))
      end

      it 'sets the config options' do
        expect(config['indices.query.bool.max_clause_count']).to eq(2048)
      end
    end
  end
end
