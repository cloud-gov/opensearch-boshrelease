#!/bin/bash

set -x
JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
<% if_link('opensearch') do |smoke_tests_syslog| %>
openssl pkcs8 -v1 "PBE-SHA1-3DES" \
-in "${JOB_DIR}/config/ssl/smoketest.pem" -topk8 \
-out "${JOB_DIR}/config/ssl/smoketest.key" -nocrypt
chmod 600 ${JOB_DIR}/config/ssl/smoketest.key
<% end %>
<%
  ingestor_host = nil
  if_link("ingestor") { |ingestor_link| ingestor_host = ingestor_link.instances.first.address }
  unless ingestor_host
    ingestor_host = p("smoke_tests.syslog_ingestor.host")
  end

  ingestor_port = nil
  if_link("ingestor") { |ingestor_link| ingestor_port = ingestor_link.p("logstash_ingestor.syslog.port") }
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
LOG="<13>$(date -u +"%Y-%m-%dT%H:%M:%SZ") 0.0.0.0 smoke-test-errand [job=smoke_tests index=0]  {\"smoke-id\":\"$SMOKE_ID\"}"

<% if p('smoke_tests.use_tls') %>
INGEST="openssl s_client -connect $INGESTOR_HOST:$INGESTOR_PORT"
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
  result=$(curl -s $MASTER_URL/_search?q=$SMOKE_ID)
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