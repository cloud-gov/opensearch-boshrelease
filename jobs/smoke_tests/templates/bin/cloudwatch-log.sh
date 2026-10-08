#!/bin/bash
set -eu

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

<% if p('smoke_tests.s3_cloudwatch.bucket') %>
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
  org_guid = p("smoke_tests.org_guid")
  space_guid = p('smoke_tests.space_guid')
  rds_instance = p('smoke_tests.rds_instance')
  log_group = p('smoke_tests.log_group') 
%>

# Service configuration
MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>*"
ORG_GUID="<%= org_guid %>"
SPACE_GUID="<%= space_guid %>"
RDS_INSTANCE="<%= rds_instance %>"
LOG_GROUP="<%= log_group %>"
S3_BUCKET="<%= p('smoke_tests.s3_cloudwatch.bucket') %>"
S3_REGION="<%= p('smoke_tests.s3.region') %>"

# Validate required properties
if [ -z "$ORG_GUID" ] || [ -z "$RDS_INSTANCE" ] || [ -z "$SPACE_GUID" ]; then
    echo "ERROR: One or more required properties (RDS_INSTANCE, ORG_GUID, SPACE_GUID) are not defined."
    exit 1
fi

if [ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ]; then
    echo "ERROR: One or more required properties (S3_BUCKET, S3_REGION) are not defined."
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

S3_PREFIX="orgs/${ORG_GUID}/${SPACE_GUID}"
S3_KEY="${S3_PREFIX}/$(date -u +"%Y/%m/%d/%H/%M")"


# =============================================================================
# UPLOAD SIMPLE LOG MESSAGE TO THE CLOUDWATCH LOGS BUCKET
# =============================================================================
db_instance=$RDS_INSTANCE
LOG_STREAM="${db_instance}.0"

# Simple log message with smoke test ID
LOG_MESSAGE="Smoke test ${SMOKE_ID}: This is a test of cloudwatch logs"
S3_LOG_FILE="smoke_test_cloudwatch_${SMOKE_ID}.log"

echo "Generated Smoke Test ID: $SMOKE_ID"

# Build the record the way the delivery stream writes it. cf-tags.conf parses
# the object body as JSON and cloudwatch.conf consumes timestamp/message/
# logGroup/logStream, so those key names have to match exactly.
LOG=$(jq -nc \
    --argjson timestamp "$current_time_ms" \
    --arg message "$LOG_MESSAGE" \
    --arg log_group "$LOG_GROUP" \
    --arg log_stream "$LOG_STREAM" \
    --arg org_value "$ORG_GUID" \
    --arg space_value "$SPACE_GUID" \
    '{
        "timestamp": $timestamp,
        "message": $message,
        "logGroup": $log_group,
        "logStream": $log_stream,
        "Tags": {
            "Organization GUID": $org_value,
            "Space GUID": $space_value
        }
    }')

# Save the record to a file. The delivery stream writes newline delimited JSON
# as text/plain and the key carries no .gz suffix, so this must stay
# uncompressed or the ingestor will not parse it.
echo "$LOG" > "$S3_LOG_FILE"
echo "Generated LOG: $LOG"

echo "Uploading cloudwatch log to S3..."
if command -v aws &> /dev/null; then
    if [ -f "$S3_LOG_FILE" ]; then
        if aws s3api put-object --bucket "${S3_BUCKET}" --key "${S3_KEY}" --body "$S3_LOG_FILE" --region "${S3_REGION}" --content-type "text/plain" --server-side-encryption AES256; then
            echo "Successfully uploaded cloudwatch log to s3://${S3_BUCKET}/${S3_KEY}"
            echo "   Log Group: $LOG_GROUP"
            echo "   Log Stream: $LOG_STREAM"
            echo "   Smoke ID: $SMOKE_ID"
            echo "   Message: $LOG_MESSAGE"
            rm -f "$S3_LOG_FILE"
        else
            echo "ERROR: Failed to upload cloudwatch log to S3"
            rm -f "$S3_LOG_FILE"
            exit 1
        fi
    else
        echo "ERROR: Log file '$S3_LOG_FILE' not found. Cannot upload to S3."
        exit 1
    fi
else
    echo "ERROR: AWS CLI not found, cannot upload to S3"
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
            
            if [[ "$group_value" == "$LOG_GROUP" && "$stream_value" == "$LOG_STREAM" ]]; then
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

<% end %>