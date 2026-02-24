#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-"$ROOT_DIR/docs/screenshots/generated"}"

mkdir -p "$OUTPUT_DIR"

SENTRIO_GENERATE_SCREENSHOTS=1 \
SENTRIO_SCREENSHOT_DIR="$OUTPUT_DIR" \
swift test --filter DocumentationScreenshotTests/test_generateDocumentationScreenshots

echo "Generated screenshots:"
echo "  $OUTPUT_DIR/bar_menu.png"
echo "  $OUTPUT_DIR/preferences.png"
echo "  $OUTPUT_DIR/preferences_output.png"
echo "  $OUTPUT_DIR/preferences_input.png"
echo "  $OUTPUT_DIR/preferences_busy_light.png"
echo "  $OUTPUT_DIR/preferences_general.png"
