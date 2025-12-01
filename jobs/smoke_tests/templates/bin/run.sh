#!/bin/bash

set -x
JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

<%
  opensearch_host = p("smoke_tests.opensearch_manager.host")
  opensearch_port = p("smoke_tests.opensearch_manager.port")
  index = p("smoke_tests.index")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>"



<% if p('smoke_tests.count_test.run') %>

MIN=<%= p('smoke_tests.count_test.minimum') %>
url="$MASTER_URL/<%= p('smoke_tests.count_test.index_pattern') %>/_count?pretty"
query_body='{ "query": {
  "range": {
    "<%= p('smoke_tests.count_test.time_field') %>": {
      "gte": "now-<%= p('smoke_tests.count_test.time_interval') %>",
      "lt": "now"
      }
    }
  }
}'
result=$(curl  --key ${JOB_DIR}/config/ssl/smoketest.key \
    --cert ${JOB_DIR}/config/ssl/smoketest.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    $url -H "content-type: application/json" -d "$query_body" | grep count | cut -d: -f2 | sed 's/,//' )

if [[ ${result} -lt ${MIN} ]]; then
  echo "ERROR: expected at least ${MIN} documents, only got ${result}"
  exit 1
fi
<% end %>


# app logs
<% if p('smoke_tests.app_log.enabled') %>
${JOB_DIR}/bin/app-log
<% end %>

# metric logs
<% if p('smoke_tests.s3_metric.bucket') %>
${JOB_DIR}/bin/metric-log
<% end %>

# cloudwatch logs
<% if p('smoke_tests.s3_cloudwatch.bucket') %>
${JOB_DIR}/bin/cloudwatch-log
<% end %>

