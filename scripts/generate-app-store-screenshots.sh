#!/bin/sh
set -eu

script_dir=$(unset CDPATH; cd "$(dirname "$0")/.." && pwd)
output_dir=${1:-"${script_dir}/docs/app-store/screenshots"}
fixture_dir=$(mktemp -d)
trap 'rm -rf "${fixture_dir}"' 0
trap 'exit 1' HUP INT TERM

SENTRIO_APP_STORE=1 \
SENTRIO_GENERATE_SCREENSHOTS=1 \
SENTRIO_SCREENSHOT_DIR="${fixture_dir}" \
"${script_dir}/scripts/with-preserved-package-resolution.sh" swift test \
    --scratch-path "${script_dir}/.build-app-store-screenshots" \
    --filter DocumentationScreenshotTests/test_generateDocumentationScreenshots

swift "${script_dir}/scripts/compose-app-store-screenshots.swift" "${fixture_dir}" "${output_dir}"

printf '%s\n' 'Generated App Store screenshots:'
for screenshot in "${output_dir}"/*.png; do
    printf '  %s\n' "${screenshot}"
done
