#!/bin/sh
set -eu

sh scripts/test-package.sh
sh scripts/test-app-store-package.sh
swift test
