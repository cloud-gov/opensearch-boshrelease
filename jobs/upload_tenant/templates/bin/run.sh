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
ORG_GUID=${cf ${org} --guid}
curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/tenants/${org} \
  -H 'Content-Type: application/json' -d'{ "description": "A tenant for the ${org} team." }'

curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/roles/${org}-tenant \
  -H 'Content-Type: application/json' -d'{"tenant_permissions": [{"tenant_patterns": ["${org}"],"allowed_actions": ["kibana_all_reaid"]}]}'

curl -X PUT \
  ${CA} ${CERT} ${KEY} \
  -s https://localhost:9200/_plugins/_security/api/rolesmapping/${org}-tenant \
  -H 'Content-Type: application/json' -d'{"backend_roles": ["${ORG_GUID}"]}'

done

exit 0