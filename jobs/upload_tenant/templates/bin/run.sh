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
  client = p("upload_tenant.cf.client_id")
  password = p("upload_tenant.cf.client_password")
%>
cf api "<%= api %>"
cf auth "<%= client %>" "<%= password %>" --client-credentials

for org in `cf orgs | tail -n +4`; do
ORG_GUID=\"$(cf org ${org} --guid)\"
org_quoted=\"$org\"
curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/tenants/${org} \
  -H 'Content-Type: application/json' -d "{ \"description\": \"A tenant for the ${org} team.\" }"
  
curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/roles/${org}-tenant \
  -H 'Content-Type: application/json' -d '{"tenant_permissions":[{"tenant_patterns": ['"${org_quoted}"'],"allowed_actions": ["kibana_all_write"]}]}'

curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/rolesmapping/${org}-tenant \
  -H 'Content-Type: application/json' -d '{"backend_roles": ['${ORG_GUID}']}'

done

exit 0
