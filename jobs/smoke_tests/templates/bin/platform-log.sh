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
INDEX="<%= index %>*"


<% if p('smoke_tests.count_test.run') %>

MIN=<%= p('smoke_tests.count_test.minimum') %>
url="$MASTER_URL/$INDEX/_count?pretty"
query_body='{
  "query": {
    "bool": {
      "must": [
        {
          "range": {
            "<%= p('smoke_tests.count_test.time_field') %>": {
              "gte": "now-<%= p('smoke_tests.count_test.time_interval') %>",
              "lt": "now"
            }
          }
        },
        {
          "term": {
            "@index_type": "platform"
          }
        }
      ]
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

SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
id_value="c9b54579-7056-46c3-9870-334330e9be75"
job_value="5db8fd06-ac53-4ed0-a224-b0bad2e463d2"
LOG="<14>1 $(date -u +'%Y-%m-%dT%H:%M:%S.%6NZ') ${id_value}.smoke-test.default.development.bosh smoke_test smoke_test - [instance@47450 director=\"\" deployment=\"development\" group=\"smoke-test\" az=\"z1\" id=\"${id_value}\"] {\"smoke_id\":\"${SMOKE_ID}\"}"

<% if p('smoke_tests.tls.use_tls') %>
INGEST="openssl s_client -cert $JOB_DIR/config/ssl/ingestor.crt -key $JOB_DIR/config/ssl/ingestor.key -CAfile ${JOB_DIR}/config/ssl/opensearch.ca -connect $INGESTOR_HOST:$INGESTOR_PORT"
<% else %>
INGEST="nc -q 5 $INGESTOR_HOST $INGESTOR_PORT"
<% end %>

# Send the log
echo "SENDING PLATFORM LOG: $LOG"
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
    
    # Parse the JSON using jq - check for @source.id and @source.job
    id_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@source"]["id"] // "null"')
    job_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@source"]["job"] // "null"')
    
    # Debug output
    echo "Expected id: $id_value, found: $id_opensearch"
    echo "Expected job: $job_value, found: $job_opensearch"
    
    # Validate that the fields exist and have expected values
    if [[ "$id_opensearch" == "$id_value" && "$job_opensearch" == "$job_value" ]]; then
      echo "SUCCESS: Platform Log contains correct '@source.id' and '@source.job' fields."
      exit 0
    else
      echo "ERROR: Platform Log does not contain both '@source.job' and '@source.id' fields with expected values."
      echo "Full search result for debugging:"
      echo "$result" | jq '.'
      exit 1
    fi
  else
    sleep $SLEEP
    echo -n "."
    TRIES=$((TRIES-SLEEP))
  fi
done

echo -e "\nERROR: Couldn't find platform log containing: $SMOKE_ID"
echo "Last search result: $result"
exit 1