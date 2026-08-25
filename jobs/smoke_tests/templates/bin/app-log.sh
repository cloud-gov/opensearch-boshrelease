set -eu

JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export JQ_PACKAGE_DIR=/var/vcap/packages/jq
export PATH=$JQ_PACKAGE_DIR/bin:$PATH


<% if p('smoke_tests.app_log.enabled') %>

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
            "@index_type": "app"
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
org_value="c9b54579-7056-46c3-9870-334330e9be75"
space_value="5db8fd06-ac53-4ed0-a224-b0bad2e463d2"

# Expected http.* field values after the app-logmessage-app.conf filter renames
# [app][request][*] -> [http][request][*] and [app][resp_headers] -> [http][response][headers][details].
# Non-numeric [app][status] is routed to [http][request][status_text] (numeric would go to [http][request][status]).
#
# HOW TO TEST A PROBLEM FIELD:
# To validate a field that is misbehaving in production (wrong mapping, not
# renamed, landing under app.* instead of http.*, mapping conflict, etc.):
#   1. Add the raw input key/value to the MSG JSON below using the shape the
#      parser expects (see app-logmessage-app.conf for the [app]->[http] renames).
#   2. Add a *_value variable here with the value you expect AFTER parsing.
#   3. Extract the parsed field from OpenSearch with a jq line in the results
#      block below (mirror the existing *_opensearch assignments).
#   4. Add a matching if/else validation block that bumps $errors on mismatch.
# This reproduces the exact ingest -> parse -> index path, so a failing
# assertion here pinpoints whether the break is in the Logstash rename or the
# OpenSearch mapping. Note the numeric-vs-text status split above is a common
# source of mapping conflicts worth reproducing this way.
method_value="GET"
host_value="api.testdata.gov"
uri_value="https://aapple.jacks"
status_text_value="yellow"
req_header_value="text/csv"
resp_header_value="application/json"
duration_text_value="1m31.087861816s"

MSG="{\"smoke-id\":\"${SMOKE_ID}\",\"request\":{\"method\":\"${method_value}\",\"host\":\"${host_value}\",\"uri\":\"${uri_value}\",\"headers\":{\"accept\":\"${req_header_value}\"}},\"resp_headers\":{\"content-type\":\"${resp_header_value}\"},\"status\":\"${status_text_value}\",\"duration\":\"${duration_text_value}\"}"
LOG="1090 <14>1 $(date -u +'%Y-%m-%dT%H:%M:%SZ') 0.0.0.0 d20d2020-d200-d200-d200-d20d20d20d20 [SMOKE/TEST/ERRAND/0] - [tags@47450 app_id=\"8675309e-f567-4d58-9649-ba24fad5344c\" app_name=\"smoke_tests\" organization_id=\"${org_value}\" organization_name=\"smoke-tests\" job=\"smoke_tests\" space_id=\"${space_value}\" space_name=\"app\" source_type=\"APP/PROC/WEB\"] ${MSG}"

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
    org_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["org_id"]')
    space_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["space_id"]')

    # http.* fields produced by the app-logmessage-app.conf renames
    method_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["method"] // "null"')
    host_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["host"] // "null"')
    uri_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["uri"] // "null"')
    status_text_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["status_text"] // "null"')
    duration_text_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["duration_text"] // "null"')
    req_header_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["request"]["headers"]["details"]["accept"] // "null"')
    resp_header_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["http"]["response"]["headers"]["details"]["content-type"] // "null"')

    errors=0

    # Validate that the fields exist and have cf values
    if [[ "$org_opensearch" == "$org_value" && "$space_opensearch" == "$space_value" ]]; then
      echo "SUCCESS: App Log contains 'org id' and 'space id' fields."
    else
      echo "ERROR: APP Log does not contain both 'space id' and 'org id' fields."
      errors=$((errors + 1))
    fi

    # Validate the http.* field renames produced by app-logmessage-app.conf.
    # [app][request][method] -> [http][request][method]
    if [[ "$method_opensearch" == "$method_value" ]]; then
      echo "SUCCESS: http.request.method matches expected value '$method_value'."
    else
      echo "ERROR: http.request.method mismatch. Expected '$method_value', got '$method_opensearch'."
      errors=$((errors + 1))
    fi

    # [app][request][host] -> [http][request][host]
    if [[ "$host_opensearch" == "$host_value" ]]; then
      echo "SUCCESS: http.request.host matches expected value '$host_value'."
    else
      echo "ERROR: http.request.host mismatch. Expected '$host_value', got '$host_opensearch'."
      errors=$((errors + 1))
    fi

    # [app][request][uri] -> [http][request][uri]
    if [[ "$uri_opensearch" == "$uri_value" ]]; then
      echo "SUCCESS: http.request.uri matches expected value '$uri_value'."
    else
      echo "ERROR: http.request.uri mismatch. Expected '$uri_value', got '$uri_opensearch'."
      errors=$((errors + 1))
    fi

    # Non-numeric [app][status] is routed to [http][request][status_text]
    # (numeric values would instead land in [http][request][status]).
    if [[ "$status_text_opensearch" == "$status_text_value" ]]; then
      echo "SUCCESS: http.request.status_text matches expected value '$status_text_value'."
    else
      echo "ERROR: http.request.status_text mismatch. Expected '$status_text_value', got '$status_text_opensearch' (non-numeric status should route here)."
      errors=$((errors + 1))
    fi

    # Non-numeric [app][duration] (e.g. Go-style "1m31.087861816s") is routed to
    # [http][request][duration_text] (keyword). A plain number would instead land
    # in the [http][request][duration] double field.
    if [[ "$duration_text_opensearch" == "$duration_text_value" ]]; then
      echo "SUCCESS: http.request.duration_text matches expected value '$duration_text_value'."
    else
      echo "ERROR: http.request.duration_text mismatch. Expected '$duration_text_value', got '$duration_text_opensearch' (non-numeric duration should route here)."
      errors=$((errors + 1))
    fi

    # [app][request][headers] -> [http][request][headers][details] (flat_object)
    if [[ "$req_header_opensearch" == "$req_header_value" ]]; then
      echo "SUCCESS: http.request.headers.details.accept matches expected value '$req_header_value'."
    else
      echo "ERROR: http.request.headers.details.accept mismatch. Expected '$req_header_value', got '$req_header_opensearch'."
      errors=$((errors + 1))
    fi

    # [app][resp_headers] -> [http][response][headers][details] (flat_object)
    if [[ "$resp_header_opensearch" == "$resp_header_value" ]]; then
      echo "SUCCESS: http.response.headers.details.content-type matches expected value '$resp_header_value'."
    else
      echo "ERROR: http.response.headers.details.content-type mismatch. Expected '$resp_header_value', got '$resp_header_opensearch'."
      errors=$((errors + 1))
    fi

    if [[ $errors -eq 0 ]]; then
      echo "SUCCESS: App Log contains all expected http.* fields."
      exit 0
    else
      echo "ERROR: App Log failed $errors http.* field validation(s)."
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

<% end %>