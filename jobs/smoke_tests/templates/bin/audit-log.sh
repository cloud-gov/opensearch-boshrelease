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
export PATH=/var/vcap/packages/cf-cli-8-linux/bin:${PATH}
# Template variables
<%
  opensearch_host = p("smoke_tests.opensearch_manager.host")
  opensearch_port = p("smoke_tests.opensearch_manager.port")
  index = p("smoke_tests.index")
  api = p("cloudfoundry.system_domain")
  client = p("cloudfoundry.client_id")
  password = p("cloudfoundry.client_password")
  target_org = p("cloudfoundry.smoke_test_org")
%>

cf api "<%= api %>"
cf auth "<%= client %>" "<%= password %>" --client-credentials



# Service configuration
MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>*"
S3_BUCKET="<%= p('smoke_tests.s3_audit.bucket') %>"
S3_REGION="<%= p('smoke_tests.s3.region') %>"
ENVIRONMENT="<%= p('smoke_tests.s3.environment') %>"
SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

cf target -o $target_org
cf create-space $SMOKE_ID
cf delete-space $SMOKE_ID

# =============================================================================
# POLLING AND VALIDATION
# =============================================================================

# Polling configuration
TRIES=${1:-420}  # Default to 420 seconds(7 minutes)
SLEEP=10

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
        "bool": {
        "must": [
            {
            "term": {
                "type": "audit.space.create"
            }
            },
            {
            "term": {
                "target.name": "$SMOKE_ID"
            }
            }
        ]
        }
    },
    "size": 1
    }')
    
    if [[ $result == *"$SMOKE_ID"* ]]; then
        echo -e "\nSUCCESS: Found log containing $SMOKE_ID"
        
        # Parse and validate organization and space fields
        org_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["org_id"]')
        space_opensearch=$(echo "$result" | jq -r '.hits.hits[0]._source["@cf"]["space_id"]')
        
        if [[ "$org_opensearch" == "$org_value" && "$space_opensearch" == "$space_value" ]]; then
            echo "SUCCESS: Actor log contains 'org id' and 'space id' fields."
            
            # Parse and validate Actor fields
            target_value=$(echo "$result" | jq -r '.hits.hits[0]._source["target"]["type"]')
            actor_value=$(echo "$result" | jq -r '.hits.hits[0]._source["actor"]["type"]')
            
            if [[ "$target_value" == "app" && "$actor_value" == "user" ]]; then
                echo "SUCCESS: Actor log contains 'target type' and 'actor type' fields."
                exit 0
            else
                echo "ERROR: Actor log does not contain both 'target type' and 'actor type' fields."
                exit 1
            fi
        else
            echo "ERROR: Actor log does not contain both 'org id' and 'space id' fields."
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