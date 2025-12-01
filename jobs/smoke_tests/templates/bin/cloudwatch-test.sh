set -eu

JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export JQ_PACKAGE_DIR=/var/vcap/packages/jq
export AWS_PACKAGE_DIR=/var/vcap/packages/awscli
export PATH=$JQ_PACKAGE_DIR/bin:$AWS_PACKAGE_DIR/bin:$PATH


<%
  opensearch_host = p("smoke_tests.opensearch_manager.host")
  opensearch_port = p("smoke_tests.opensearch_manager.port")
  index = p("smoke_tests.index")
%>

MASTER_URL="https://<%= opensearch_host %>:<%= opensearch_port %>"
INDEX="<%= index %>"

S3_BUCKET="<%= p('smoke_tests.s3_cloudwatch.bucket') %>"
S3_REGION="<%= p('smoke_tests.s3.region') %>"
ENVIRONMENT="<%= p('smoke_tests.s3.environment') %>"
# Check if properties are empty, exit if so.
if [ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ] || [ -z "$ENVIRONMENT" ]; then
  echo "ERROR: One or more required properties (S3_BUCKET, S3_REGION, ENVIRONMENT) are not defined."
  exit 1
fi

S3_PREFIX=$(date -u +"%Y/%m/%d/%H")
SMOKE_ID=$(LC_ALL=C; cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
S3_LOG_FILE="smoke_test_log_${SMOKE_ID}.log"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
S3_KEY="${S3_PREFIX}/${TIMESTAMP}-${SMOKE_ID}.gz"

rds_prefix="cg-aws-broker-"
case "$ENVIRONMENT" in
    "production")
        rds_prefix="${rds_prefix}prod"
        ;;
    "staging")
        rds_prefix="${rds_prefix}stage"
        ;;
    "development")
        rds_prefix="${rds_prefix}dev"
        ;;
esac
# Get time in microsecond format
current_time_ms=$(date -u +%s%3N)

# Upload log to S3
# Construct the LOG JSON object (using jq for proper formatting)
LOG=$(jq -n \
  --arg namespace "AWS/RDS" \
  --arg metric_name "WriteLatency" \
  --arg db_instance_identifier "${rds_prefix}-tester" \
  --arg timestamp "$current_time_ms" \
  --arg environment "$ENVIRONMENT" \
  '
  {
    "namespace": $namespace,
    "metric_name": $metric_name,
    "dimensions": {
      "DBInstanceIdentifier": $db_instance_identifier
    },
    "timestamp": ($timestamp | tonumber),
    "value": {
      "max": 0.0,
      "min": 0.0,
      "sum": 0.0,
      "count": 1.0
    },
    "unit": "Seconds",

    
    "Tags": {
      "Service offering name": "aws-rds",
      "Organization GUID": "c9b54579-7056-46c3-9870-334330e9be75",
      "Organization name": "smoke-test",
      "environment": $environment,
      "Service plan name": "micro-psql",
      "client": "Cloud Foundry",
      "Space GUID": "5db8fd06-ac53-4ed0-a224-b0bad2e463d2",
      "broker": "AWS broker",
      "Space name": "metrics",
      "Created at": "2024-12-20T19:08:54Z",
      "Instance GUID": "024d7b3a-1732-4ae4-9e2a-f36eaa2c741c"
    }
  } | paths(scalars) as $p | [$p | join("_"), getpath($p)] | {key: .[0], value: .[1]} | "\(.key)=\(.value)"
')

# Then compress the variable content to a file
echo "$LOG" | gzip > "$S3_LOG_FILE"

echo "Generated LOG: $LOG"  # Print the JSON object for debugging
# Upload log to S3
echo "Uploading failure log to S3..."
if command -v aws &> /dev/null; then
  if [ -f "$S3_LOG_FILE" ]; then # Check if the log file exists
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
    org_value=$(echo "$result" | jq -r '.hits.hits[0]._source."@cf.org_id"')
    space_value=$(echo "$result" | jq -r '.hits.hits[0]._source."@cf.space_id')

    # Validate that the fields exist and have values (you can customize the validation)
    if [[ -n "$org_value" && -n "$space_value" ]]; then
      echo "SUCCESS: cloudwatch Log contains 'org id' and 'space id' fields."
      # Parse the JSON using jq
      average_value=$(echo "$result" | jq -r '.hits.hits[0]._source."cloudwatch.average')
      db_instance_identifier_value=$(echo "$result" | jq -r '.hits.hits[0]._source."cloudwatch.db_instance_identifier')

      if [[ -n "$average_value" && -n "$db_instance_identifier_value" ]]; then
        echo "SUCCESS: cloudwatch Log contains 'average' and 'db instance identifier' fields."
        echo "$result"  # Output the full JSON result (optional)
        exit 0
      else 
        echo "ERROR: cloudwatch Log does not contain both 'average' and 'db instance identifier' fields."
        echo "Full JSON result: $result" #Output full JSON for debugging
        exit 1 # Or continue retrying, depending on your needs
      fi
    else
      echo "ERROR: cloudwatch Log does not contain both 'average' and 'db instance indentief' fields."
      echo "Full JSON result: $result" #Output full JSON for debugging
      exit 1 # Or continue retrying, depending on your needs
    fi

  else
    sleep $SLEEP
    echo -n "."
    TRIES=$((TRIES-SLEEP))
  fi
done

echo "ERROR: Timed out waiting for cloudwatch log with $SMOKE_ID"
exit 1

echo -e "\nERROR:  Couldn't find cloudwatch log containing: $SMOKE_ID"
echo "Last search result: $result"
exit 1