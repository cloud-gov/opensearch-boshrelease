#!/bin/bash

set -x
JOB_NAME=smoke_tests
export JOB_DIR=/var/vcap/jobs/$JOB_NAME

# app logs
<% if p('smoke_tests.app_log.enabled') %>
  ${JOB_DIR}/bin/app-log || exit 1
<% end %>

# audit logs
<% if p('smoke_tests.s3_audit.bucket') %>
  ${JOB_DIR}/bin/audit-log || exit 1
<% end %>

# metric logs
<% if p('smoke_tests.s3_metric.bucket') %>
  ${JOB_DIR}/bin/metric-log || exit 1
<% end %>

# cloudwatch logs
<% if p('smoke_tests.s3_cloudwatch.bucket') %>
  ${JOB_DIR}/bin/cloudwatch-log || exit 1
<% end %>

