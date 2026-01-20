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
  index = p("smoke_tests.metric_index")
%>

# Service configuration
MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>*"
ORG_GUID="<%= p('smoke_tests.org_guid') %>"
SPACE_GUID="<%= p('smoke_tests.space_guid') %>"
RDS_INSTANCE="<%= p('smoke_tests.rds_instance') %>"
long_time_interval="<%= p('smoke_tests.count_test.long_time_interval') %>"

# Validate required properties
if [ -z "$ORG_GUID" ] || [ -z "$RDS_INSTANCE" ] || [ -z "$SPACE_GUID" ]; then
    echo "ERROR: One or more required properties (RDS_INSTANCE, ORG_GUID, SPACE_GUID) are not defined."
    exit 1
fi

<% if p('smoke_tests.count_test.run') %>

MIN=<%= p('smoke_tests.metric_count_test.minimum') %>
url="$MASTER_URL/$INDEX/_count?pretty"
query_body='{
  "query": {
    "bool": {
      "must": [
        {
          "range": {
            "<%= p('smoke_tests.count_test.time_field') %>": {
              "gte": "now-${long_time_interval}",
              "lt": "now"
            }
          }
        },
        {
          "term": {
            "@type": "metrics"
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
  echo "ERROR: expected at least ${MIN} metric documents, only got ${result}"
  exit 1
fi
<% end %>

# =============================================================================
# GENERATE IDENTIFIERS AND TIMESTAMPS
# =============================================================================
# Generate your ID
SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
# Convert to numeric using checksum for metric value
METRIC_VALUE=$(echo "$SMOKE_ID" | cksum | cut -f1 -d' ')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
current_time_ms=$(date -u +%s%3N)

# =============================================================================
# SEND METRIC TO CLOUDWATCH
# =============================================================================
org_value=$ORG_GUID
space_value=$SPACE_GUID
db_instance=$RDS_INSTANCE

echo "Sending smoke test metric to CloudWatch..."
echo "Smoke ID: $SMOKE_ID"
echo "DB Instance: $db_instance"
# Send metric to CloudWatch (will be picked up by your existing metric stream)
if command -v aws &> /dev/null; then
     aws cloudwatch put-metric-data \
        --namespace "AWS/RDS" \
        --metric-data '[
            {
                "MetricName": "WriteLatency",
                "Value": '$METRIC_VALUE',
                "Unit": "Seconds",
                "Timestamp": "'$TIMESTAMP'",
                "Dimensions": [
                    {
                        "Name": "DBInstanceIdentifier",
                        "Value": "'$db_instance'"
                    },
                    {
                        "Name": "ServiceOffering",
                        "Value": "aws-rds"
                    }
                ]
            }
        ]'
    
    if [ $? -eq 0 ]; then
        echo "Successfully sent smoke test metric to CloudWatch"
        echo "Metric Details:"
        echo "  - Namespace: AWS/RDS"
        echo "  - Metric: WriteLatency"
        echo "  - Value: $METRIC_VALUE"
        echo "  - DB Instance: $db_instance"
        echo "  - Timestamp: $TIMESTAMP"
    else
        echo "Failed to send metric to CloudWatch"
        exit 1
    fi
else
    echo "AWS CLI not found, cannot send metric to CloudWatch"
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
            "bool": {
                "must": [
                    {
                    "range": {
                        "<%= p('smoke_tests.count_test.time_field') %>": {
                        "gte": "now-${long_time_interval}",
                        "lt": "now"
                        }
                    }
                    },
                    {
                        "term": {
                            "@type": "metrics"
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
            echo "SUCCESS: Metric log contains 'org id' and 'space id' fields."
            
            # Parse and validate metric-specific fields
            average_value=$(echo "$result" | jq -r '.hits.hits[0]._source["metric"]["average"]')
            db_instance_identifier_value=$(echo "$result" | jq -r '.hits.hits[0]._source["metric"]["db_instance_identifier"]')
            
            if [[ "$average_value" == "5.0"  && "$db_instance_identifier_value" == "" ]]; then
                echo "SUCCESS: Metric log contains 'average' and 'db instance identifier' fields."
                exit 0
            else
                echo "ERROR: Metric log does not contain both 'average' and 'db instance identifier' fields."
                exit 1
            fi
        else
            echo "ERROR: Metric log does not contain both 'org id' and 'space id' fields."
            exit 1
        fi
    else
        sleep $SLEEP
        echo -n "."
        TRIES=$((TRIES-SLEEP))
    fi
done

# Timeout handling
echo -e "\nERROR: Timed out waiting for metric log with $SMOKE_ID"
echo "Last search result: $result"
exit 1