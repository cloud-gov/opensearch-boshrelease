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
INDEX="<%= index %>"
S3_BUCKET="<%= p('smoke_tests.s3_audit.bucket') %>"
S3_REGION="<%= p('smoke_tests.s3.region') %>"
ENVIRONMENT="<%= p('smoke_tests.s3.environment') %>"

# Validate required properties
if [ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ] || [ -z "$ENVIRONMENT" ]; then
    echo "ERROR: One or more required properties (S3_BUCKET, S3_REGION, ENVIRONMENT) are not defined."
    exit 1
fi

# =============================================================================
# GENERATE IDENTIFIERS AND TIMESTAMPS
# =============================================================================

S3_PREFIX=$(date -u +"%Y/%m/%d/%H")
SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
S3_LOG_FILE="smoke_test_log_${SMOKE_ID}.log"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
S3_KEY="${S3_PREFIX}/${TIMESTAMP}-${SMOKE_ID}.gz"
current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# =============================================================================
# CREATE AND UPLOAD LOG
# =============================================================================

# Construct the LOG JSON object (using jq for proper formatting)
LOG=$(jq -nc \
    --arg timestamp "$current_time" \
    --arg smoke_id "$SMOKE_ID" \
    '{
        "guid": "024d7b3a-1732-4ae4-9e2a-f36eaa2c741c",
        "created_at": $timestamp,
        "updated_at": $timestamp,
        "type": "audit",
        "smoke_test_id": $smoke_id,
        "actor": {
            "guid": "smoke-tests",
            "type": "user",
            "name": ""
        },
        "target": {
            "type": "app",
            "name": "tester"
        },
        "data": {
            "app_port": 8080
        },
        "space": {
            "guid": "5db8fd06-ac53-4ed0-a224-b0bad2e463d2"
        },
        "organization": {
            "guid": "c9b54579-7056-46c3-9870-334330e9be75"
        },
        "organization_name": "smoke-test",
        "space_name": "audit"
    } ')

# Save log to file and compress
echo "$LOG" > temp_log.json
gzip temp_log.json
mv temp_log.json.gz "$S3_LOG_FILE"
echo "Generated LOG: $LOG"

# Upload log to S3
echo "Uploading failure log to S3..."
if command -v aws &> /dev/null; then
    if [ -f "$S3_LOG_FILE" ]; then
        aws s3 cp "$S3_LOG_FILE" "s3://${S3_BUCKET}/${S3_KEY}" --region "${S3_REGION}"
        if [ $? -eq 0 ]; then
            echo "Successfully uploaded failure log to s3://${S3_BUCKET}/${S3_KEY}"
        else
            echo "Failed to upload log to S3"
        fi
    else
        echo "WARNING: Log file '$S3_LOG_FILE' not found. Skipping S3 upload."
    fi
else
    echo "AWS CLI not found, skipping S3 upload"
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
            "term": {
                "smoke_test_id": "'$SMOKE_ID'"
            }
        },
        "size": 1
    }')
    
    if [[ $result == *"$SMOKE_ID"* ]]; then
        echo -e "\nSUCCESS: Found log containing $SMOKE_ID"
        
        # Parse and validate organization and space fields
        org_value=$(echo "$result" | jq -r '.hits.hits[0]._source."@cf.org_id"')
        space_value=$(echo "$result" | jq -r '.hits.hits[0]._source."@cf.space_id"')
        
        if [[ -n "$org_value" && -n "$space_value" ]]; then
            echo "SUCCESS: Actor log contains 'org id' and 'space id' fields."
            
            # Parse and validate Actor fields
            target_value=$(echo "$result" | jq -r '.hits.hits[0]._source."target.type')
            actor_value=$(echo "$result" | jq -r '.hits.hits[0]._source."actor.type"')
            
            if [[ -n "$target_value" && -n "$actor_value" ]]; then
                echo "SUCCESS: Actor log contains 'target type' and 'actor type' fields."
                echo "$result"
                exit 0
            else
                echo "ERROR: Actor log does not contain both 'target type' and 'actor type' fields."
                echo "Full JSON result: $result"
                exit 1
            fi
        else
            echo "ERROR: Actor log does not contain both 'org id' and 'space id' fields."
            echo "Full JSON result: $result"
            exit 1
        fi
    else
        sleep $SLEEP
        echo -n "."
        TRIES=$((TRIES-SLEEP))
    fi
done

# Timeout handling
echo -e "\nERROR: Timed out waiting for Actor log with $SMOKE_ID"
echo "Last search result: $result"
exit 1