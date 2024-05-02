#!/usr/bin/env bash

set -eu

export JOB_NAME=upload_tenant
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export PATH=/var/vcap/packages/cf-cli-8-linux/bin:${PATH}
export CF_COLOR=false

CA="--cacert ${JOB_DIR}/config/ssl/opensearch.ca"
CERT="--cert ${JOB_DIR}/config/ssl/opensearch-admin.crt"
KEY="--key ${JOB_DIR}/config/ssl/opensearch-admin.key"
<%
  api = p("upload_tenant.cf.domain")
  username = p("upload_tenant.cf.username")
  password = p("upload_tenant.cf.password")
%>
cf api "<%= api %>"
cf auth "<%= username %>" "<%= password %>"

for org in `cf orgs| tail -n +4`; do
org_guid= $(cf org ${org} --guid)
ORG_GUID=\"$(cf org ${org} --guid)\"
org_quoted=\"$org\"
curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/tenants/${org} \
  -H 'Content-Type: application/json' -d'{ "description": "A tenant for the ${org} team." }'

index="logs-app-${org_guid}-*"
curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/roles/${org}-tenant \
  -H 'Content-Type: application/json' -d'{"index_permissions":[{"index_patterns":["${index}"],"dls":"{\"bool\":/ {\"should\": [{\"terms\": { \"@cf.space_id\": [${attr.proxy.spaceids}] }}, {\"terms\": {\"@cf.org_id\": [${attr.proxy.orgids}]}}]}}","allowed_actions":["read"]}],"tenant_permissions":[{"tenant_patterns": ['"${org_quoted}"'],"allowed_actions": ["kibana_all_write"]}]}'


curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/rolesmapping/${org}-tenant \
  -H 'Content-Type: application/json' -d'{"backend_roles": ['${ORG_GUID}']}'

done

exit 0