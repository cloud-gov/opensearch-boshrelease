# opensearch-boshrelease

A BOSH release for [Opensearch](https://opensearch.org/)

## How to update the vendored Python version

1. Follow these steps: <https://github.com/cloud-gov/internal-docs/blob/main/docs/runbooks/BOSH/building-bosh-releases.md#vendoring-python>
1. Follow these steps to ensure that the changes to `.final_builds/package/python3` get updated in the `final-builds-opensearch.tgz` file tracked in S3: <https://github.com/cloud-gov/internal-docs/blob/main/docs/runbooks/BOSH/building-bosh-releases.md#updating-vendored-packages-in-a-forked-release>

## How to add blobs for Logstash filter plugins

1. Install Java locally and download Logstash version from `config/blobs.yml` to your local machine
1. From the directory for Logstash on your machine, install the relevant plugin:

    ```shell
    bin/logstash-plugin install logstash-filter-alter
    ```

1. Check what version of the plugin was installed:

    ```shell
    bin/logstash-plugin list --verbose | grep logstash-filter-alter
    ```

1. [Create an offline version of the plugin for use with BOSH](https://www.elastic.co/guide/en/logstash/current/offline-plugins.html) and make sure to use the correct version from the previous step in the filename:

    ```shell
    bin/logstash-plugin prepare-offline-pack --output logstash-filter-alter-3.0.3.zip logstash-filter-alter
    ```

1. Add the filter plugin to the blobs referencing the path to the generated offline file on your machine:

    ```shell
    bosh add-blob logstash/logstash-filter-alter-3.0.3.zip /path/to/logstash-filter-alter-3.0.3.zip
    ```

1. Upload the updated blobs the S3 blobstore:

    ```shell
    bosh upload-blobs
    ```
