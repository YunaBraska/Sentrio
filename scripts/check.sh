#!/bin/sh
set -eu

sh scripts/test-package.sh
swift test
