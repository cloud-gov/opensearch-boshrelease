set -eu

JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export JQ_PACKAGE_DIR=/var/vcap/packages/jq
export PATH=$JQ_PACKAGE_DIR/bin:$PATH


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
  index = p("smoke_tests.index")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INGESTOR_HOST="<%= ingestor_host %>"
INGESTOR_PORT="<%= ingestor_port %>"
INDEX="<%= index %>"


SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
LOG="1012 <13>1 $(date -u +"%Y-%m-%dT%H:%M:%SZ") 0.0.0.0 d20d2020-d200-d200-d200-d20d20d20d20 [SMOKE/TEST/ERRAND/0] - [org=smoke-tests organization_id=$INDEX job=smoke_tests index=0 app_id=smoke_tests instance_id=0]  {\"smoke-id\":\"$SMOKE_ID\"}"

<% if p('smoke_tests.tls.use_tls') %>
INGEST="openssl s_client -cert $JOB_DIR/config/ssl/ingestor.crt -key $JOB_DIR/config/ssl/ingestor.key -CAfile ${JOB_DIR}/config/ssl/opensearch.ca -connect $INGESTOR_HOST:$INGESTOR_PORT"
<% else %>
INGEST="nc -q 5 $INGESTOR_HOST $INGESTOR_PORT"
<% end %>

# Send the log
echo "SENDING APP LOG :$LOG"
echo "$LOG" | $INGEST > /dev/null

# Polling configuration
TRIES=${1:-300}  # Default to 300 seconds if not specified
SLEEP=5

echo -n "Polling for $TRIES seconds"

while [ $TRIES -gt 0 ]; do
  result=$(curl --key ${JOB_DIR}/config/ssl/smoketest.key \
    --cert ${JOB_DIR}/config/ssl/smoketest.crt  \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    -s $MASTER_URL/_search?q=$SMOKE_ID)

  if [[ $result == *"$SMOKE_ID"* ]]; then
    echo -e "\nSUCCESS: Found log containing $SMOKE_ID"

    # Parse the JSON using jq
    org_value=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["org_id"]')
    space_value=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["space_id"]')

    # Validate that the fields exist and have cf values
    if [[ "$org_value" != "null" && "$space_value" != "null"]]; then
      echo "SUCCESS: App Log contains 'org id' and 'space id' fields."
      exit 0
    else
      echo "ERROR: App Log does not contain both 'org id' and 'space id' fields."
      exit 1 
    fi

  else
    sleep $SLEEP
    echo -n "."
    TRIES=$((TRIES-SLEEP))
  fi
done

echo -e "\nERROR:  Couldn't find app log containing: $SMOKE_ID"
echo "Last search result: $result"
exit 1