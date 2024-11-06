#!/usr/bin/env bash

WHEEL_SRC_DIR=$1
BLOB_PREFIX=$2

if [ -z "$WHEEL_SRC_DIR" ]; then
  echo "path to opensearch-dashboards-cf-auth-proxy source code required as first argument. exiting"
  exit 1
fi

if [ -z "$BLOB_PREFIX" ]; then
  echo "blob prefix required as second argument. exiting"
  exit 1
fi

find "$WHEEL_SRC_DIR" \
  -type f \
  -name "*.whl" \
  -exec bash -c 'path="$1"; blob_prefix="$2"; file_name=$(basename $1); bosh add-blob $path "$blob_prefix/$file_name"' shell {} "$BLOB_PREFIX" \;
