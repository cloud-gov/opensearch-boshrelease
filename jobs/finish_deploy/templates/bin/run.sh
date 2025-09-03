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
echo 1
