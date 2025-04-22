#!/bin/bash

set -x
JOB_NAME=prepare_deploy
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

<%
  opensearch_host = p("prepare_deploy.opensearch_manager.host")
  opensearch_port = p("prepare_deploy.opensearch_manager.port")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
url="$MASTER_URL/<%= p('prepare_deploy.count_test.index_pattern') %>/_cluster/settings?pretty"

result=$(curl  --key ${JOB_DIR}/config/ssl/smoketest.key \
    --cert ${JOB_DIR}/config/ssl/smoketest.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    $url )

