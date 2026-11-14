#!/bin/sh
set -eu

sh scripts/test-package.sh
sh scripts/test-app-store-package.sh

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "swiftformat is required. Install it with: brew install swiftformat" >&2
    exit 1
fi

set --
if swiftformat --rules | grep -q '^[[:space:]]*repeatedGuard[[:space:]]'; then
    set -- --disable repeatedGuard
fi
swiftformat "$@" Package.swift Sources Tests
swiftformat --lint "$@" Package.swift Sources Tests
SENTRIO_APP_STORE=1 scripts/with-preserved-package-resolution.sh \
    swift build --scratch-path .build-app-store-check
swift test
