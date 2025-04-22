#!/bin/bash

set -x
JOB_NAME=finish_deploy
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

<%
  opensearch_host = p("finish_deploy.opensearch_manager.host")
  opensearch_port = p("finish_deploy.opensearch_manager.port")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
url="$MASTER_URL/_cluster/settings?pretty"
query_body='{
    "persistent": {
        "cluster.routing.allocation.enable": "all",
    },
    "transient": {
      "cluster.routing.allocation.enable": "all",
    }
}'
result=$(curl  --key ${JOB_DIR}/config/ssl/opensearch-admin.key \
    --cert ${JOB_DIR}/config/ssl/opensearch-admin.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    $url -H "content-type: application/json" -d "$query_body")
