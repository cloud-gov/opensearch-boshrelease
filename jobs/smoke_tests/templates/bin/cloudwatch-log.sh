#!/bin/bash
set -eu

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

# Job configuration
JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export JQ_PACKAGE_DIR=/var/vcap/packages/jq
export AWS_PACKAGE_DIR=/var/vcap/packages/awscli
export PATH=$JQ_PACKAGE_DIR/bin:$AWS_PACKAGE_DIR/bin:$PATH

# Template variables
<%
  opensearch_host = p("smoke_tests.opensearch_manager.host")
  opensearch_port = p("smoke_tests.opensearch_manager.port")
  index = p("smoke_tests.index")
%>

# Service configuration
MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>*"
ORG_GUID="<%= p('smoke_tests.org_guid') %>"
SPACE_GUID="<%= p('smoke_tests.space_guid') %>"
RDS_INSTANCE="<%= p('smoke_tests.rds_instance') %>"

# Validate required properties
if [ -z "$ORG_GUID" ] || [ -z "$RDS_INSTANCE" ] || [ -z "$SPACE_GUID" ]; then
    echo "ERROR: One or more required properties (RDS_INSTANCE, ORG_GUID, SPACE_GUID) are not defined."
    exit 1
fi

<% if p('smoke_tests.count_test.run') %>

MIN=<%= p('smoke_tests.cloudwatch_count_test.minimum') %>
url="$MASTER_URL/$INDEX/_count?pretty"
query_body='{
  "query": {
    "bool": {
      "must": [
        {
          "range": {
            "<%= p('smoke_tests.count_test.time_field') %>": {
              "gte": "now-<%= p('smoke_tests.count_test.long_time_interval') %>",
              "lt": "now"
            }
          }
        },
        {
          "term": {
            "@type": "cloudwatch"
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
  echo "ERROR: expected at least ${MIN} cloudwatch documents, only got ${result}"
  exit 1
fi
<% end %>

# =============================================================================
# GENERATE IDENTIFIERS AND TIMESTAMPS
# =============================================================================
SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
current_time_ms=$(date -u +%s%3N)


# =============================================================================
# UPLOAD SIMPLE LOG MESSAGE TO CLOUDWATCH LOGS
# =============================================================================
db_instance=$RDS_INSTANCE
LOG_GROUP="/aws/rds/instance/${db_instance}/postgresql"
LOG_STREAM="${db_instance}.0"

# Simple log message with smoke test ID
LOG_MESSAGE="Smoke test ${SMOKE_ID}: This is a test of cloudwatch logs"

echo "Generated Smoke Test ID: $SMOKE_ID"
echo "Uploading log message to CloudWatch Logs..."

# Upload log to CloudWatch Logs
if command -v aws &> /dev/null; then
    # Get sequence token if needed
    SEQUENCE_TOKEN=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$LOG_STREAM" \
        --query 'logStreams[0].uploadSequenceToken' \
        --output text 2>/dev/null)

    # Prepare the log event
    LOG_EVENTS="[{\"timestamp\":$current_time_ms,\"message\":\"$LOG_MESSAGE\"}]"

    # Put log events
    if [ "$SEQUENCE_TOKEN" != "None" ] && [ "$SEQUENCE_TOKEN" != "" ] && [ "$SEQUENCE_TOKEN" != "null" ]; then
        aws logs put-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$LOG_STREAM" \
            --log-events "$LOG_EVENTS" \
            --sequence-token "$SEQUENCE_TOKEN"
    else
        aws logs put-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$LOG_STREAM" \
            --log-events "$LOG_EVENTS"
    fi

    if [ $? -eq 0 ]; then
        echo "✅ Successfully uploaded smoke test log to CloudWatch"
        echo "   Log Group: $LOG_GROUP"
        echo "   Log Stream: $LOG_STREAM"
        echo "   Smoke ID: $SMOKE_ID"
        echo "   Message: $LOG_MESSAGE"
    else
        echo "❌ Failed to upload log to CloudWatch Logs"
        exit 1
    fi
else
    echo "❌ AWS CLI not found, cannot upload to CloudWatch Logs"
    exit 1
fi


# =============================================================================
# POLLING AND VALIDATION
# =============================================================================

# Polling configuration
TRIES=${1:-300}  # Default to 300 seconds if not specified
SLEEP=5

echo -n "Polling for $TRIES seconds"
while [ $TRIES -gt 0 ]; do
    # Search for the log entry
    result=$(curl --key ${JOB_DIR}/config/ssl/smoketest.key \
    --cert ${JOB_DIR}/config/ssl/smoketest.crt \
    --cacert ${JOB_DIR}/config/ssl/opensearch.ca \
    -s -H "Content-Type: application/json" \
    -X POST "$MASTER_URL/_search" \
     -d '{
    "query": {
        "match_phrase": {
            "@message": "Smoke test '$SMOKE_ID': This is a test of cloudwatch logs"
        }
    },
        "size": 1
    }')
    
    if [[ $result == *"$SMOKE_ID"* ]]; then
        echo -e "\nSUCCESS: Found log containing $SMOKE_ID"
        
        # Parse and validate organization and space fields
        org_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["org_id"]')
        space_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["space_id"]')
        
         if [[ "$org_opensearch" == "$ORG_GUID" && "$space_opensearch" == "$SPACE_GUID" ]]; then
            echo "SUCCESS: CloudWatch log contains 'org id' and 'space id' fields."
            
            # Parse and validate CloudWatch fields
            group_value=$(echo "$result" | jq -r '.hits.hits[0]._source["cloudwatch_logs"]["log_group"]')
            stream_value=$(echo "$result" | jq -r '.hits.hits[0]._source["cloudwatch_logs"]["log_stream"]')
            
            if [[ "$group_value" == "/aws/rds/instance/${RDS_INSTANCE}/postgresql" && "$stream_value" == "${RDS_INSTANCE}.0" ]]; then
                echo "SUCCESS: CloudWatch log contains 'log group' and 'log stream' fields."
                exit 0
            else
                echo "ERROR: CloudWatch log does not contain both 'log group' and 'log stream' fields."
                exit 1
            fi
        else
            echo "ERROR: CloudWatch log does not contain both 'org id' and 'space id' fields."
            exit 1
        fi
    else
        sleep $SLEEP
        echo -n "."
        TRIES=$((TRIES-SLEEP))
    fi
done

# Timeout handling
echo -e "\nERROR: Timed out waiting for CloudWatch log with $SMOKE_ID"
echo "Last search result: $result"
exit 1