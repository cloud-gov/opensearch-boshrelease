#!/usr/bin/env bash

export PYTHON_VERSION="3.12"
PACKAGE_NAME=$1

if [ -z "$PACKAGE_NAME" ]; then
  echo "package name to download wheels for required as first argument. exiting"
  exit 1
fi

pip download "$PACKAGE_NAME" \
 --platform manylinux_2_17_x86_64 \
 --platform linux_x86_64 \
 --only-binary=:all: \
 --python-version "$PYTHON_VERSION" \
 --dest "vendor/$PACKAGE_NAME"
