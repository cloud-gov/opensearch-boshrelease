#!/bin/bash

set -x
JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

<%
  ingestor_host = nil
  if_link("ingestor") { |ingestor_link| ingestor_host = ingestor_link.instances.first.address }
  unless ingestor_host
    ingestor_host = p("smoke_tests.syslog_ingestor.host")
  end

  ingestor_port = nil
  if_link("ingestor") { |ingestor_link| ingestor_port = ingestor_link.p("logstash_ingestor.syslog_tls.port") }
  unless ingestor_port
    ingestor_port = p("smoke_tests.syslog_ingestor.port")
  end

  opensearch_host = p("smoke_tests.opensearch_manager.host")
  opensearch_port = p("smoke_tests.opensearch_manager.port")

%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INGESTOR_HOST="<%= ingestor_host %>"
INGESTOR_PORT="<%= ingestor_port %>"

SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
LOG="1012 <13>1 $(date -u +"%Y-%m-%dT%H:%M:%SZ") 0.0.0.0 d20d2020-d200-d200-d200-d20d20d20d20 [SMOKE/TEST/ERRAND/0] - [org=smoke-tests job=smoke_tests index=0 app_id=smoke_tests instance_id=0]  {\"smoke-id\":\"$SMOKE_ID\"}"

<% if p('smoke_tests.tls.use_tls') %>
INGEST="openssl s_client -cert $JOB_DIR/config/ssl/ingestor.crt -key $JOB_DIR/config/ssl/ingestor.key -CAfile ${JOB_DIR}/config/ssl/opensearch.ca -connect $INGESTOR_HOST:$INGESTOR_PORT"
<% else %>
INGEST="nc -q 5 $INGESTOR_HOST $INGESTOR_PORT"
<% end %>

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

echo "SENDING $LOG"
echo "$LOG" | $INGEST > /dev/null

TRIES=${1:-300}
SLEEP=5

echo -n "Polling for $TRIES seconds"
while [ $TRIES -gt 0 ]; do
  result=$(curl --key ${JOB_DIR}/config/ssl/smoketest.key \
    --cert ${JOB_DIR}/config/ssl/smoketest.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    -s $MASTER_URL/_search?q=$SMOKE_ID)
  if [[ $result == *"$SMOKE_ID"* ]]; then
    echo -e "\nSUCCESS: Found log containing $SMOKE_ID"
    echo $result
    exit 0
  else
    sleep $SLEEP
    echo -n "."
    TRIES=$((TRIES-SLEEP))
  fi
done

echo -e "\nERROR:  Couldn't find log containing: $SMOKE_ID"
echo "Last search result: $result"
exit 1