#!/usr/bin/env bash

AUTH_PROXY_SRC_DIR=$1

if [ -z "$AUTH_PROXY_SRC_DIR" ]; then
  echo "path to opensearch-dashboards-cf-auth-proxy source code required as first argument. exiting"
  exit 1
fi

find "$AUTH_PROXY_SRC_DIR" \
  -type f \
  -name "*.whl" \
  -exec bash -c 'bosh add-blob {} auth-proxy/$(basename {})' \;
