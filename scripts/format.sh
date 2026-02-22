#!/usr/bin/env bash
set -euo pipefail

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "swiftformat is required. Install it with: brew install swiftformat" >&2
    exit 1
fi

swiftformat Package.swift Sources Tests
