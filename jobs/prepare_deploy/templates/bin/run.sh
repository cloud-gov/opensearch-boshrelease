#!/bin/bash

set -x
JOB_NAME=prepare_deploy
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

<%
  opensearch_host = p("prepare_deploy.opensearch_manager.host")
  opensearch_port = p("prepare_deploy.opensearch_manager.port")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
url="$MASTER_URL/_cluster/settings?pretty"
query_body='{
    "persistent": {
        "cluster.routing.allocation.enable": "primaries"
    },
    "transient": {
      "cluster.routing.allocation.enable": "primaries"
    }
}'
result=$(curl -XPUT --key ${JOB_DIR}/config/ssl/opensearch-admin.key \
    --cert ${JOB_DIR}/config/ssl/opensearch-admin.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    $url -H "content-type: application/json" -d "$query_body")

