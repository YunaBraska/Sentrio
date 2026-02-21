#!/usr/bin/env bash
# build.sh — builds Sentrio.app for distribution
# Usage:  ./build.sh [VERSION]
#   VERSION defaults to the current date/time in format YYYY.MM.DDDHHММ
#   (DDD = day of year, e.g. 2026.02.0521048)
set -euo pipefail

APP_NAME="Sentrio"
BUILD_DIR="./build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
VERSION="${1:-$(date -u '+%Y.%m.%j%H%M')}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Building ${APP_NAME} ${VERSION}..."

# Universal binary (Apple Silicon + Intel). Falls back to native arch if cross-compile unavailable.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BINARY=".build/apple/Products/Release/$APP_NAME"
else
    swift build -c release
    BINARY=".build/release/$APP_NAME"
fi

echo "→ Assembling .app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

# ── Info.plist ─────────────────────────────────────────────────────────────────
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Sentrio</string>
    <key>CFBundleIdentifier</key>
    <string>com.sentrio.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>Sentrio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© $(date +%Y) Yuna Braska</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Sentrio uses the microphone input level to show a live activity indicator next to your input device.</string>
</dict>
</plist>
EOF

# ── App icon (.icns) ───────────────────────────────────────────────────────────
echo "→ Generating app icon…"
ICON_SRC="${SCRIPT_DIR}/Assets.xcassets/AppIcon.appiconset"
if [[ ! -d "${ICON_SRC}" ]]; then
    echo "✗ Missing app icon sources at: ${ICON_SRC}" >&2
    exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
    echo "✗ iconutil not found (required to build AppIcon.icns)" >&2
    exit 1
fi

TMP_ICON_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_ICON_DIR}"' EXIT

ICONSET="${TMP_ICON_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET}"

cp "${ICON_SRC}/16-mac.png"   "${ICONSET}/icon_16x16.png"
cp "${ICON_SRC}/32-mac.png"   "${ICONSET}/icon_16x16@2x.png"
cp "${ICON_SRC}/32-mac.png"   "${ICONSET}/icon_32x32.png"
cp "${ICON_SRC}/64-mac.png"   "${ICONSET}/icon_32x32@2x.png"
cp "${ICON_SRC}/128-mac.png"  "${ICONSET}/icon_128x128.png"
cp "${ICON_SRC}/256-mac.png"  "${ICONSET}/icon_128x128@2x.png"
cp "${ICON_SRC}/256-mac.png"  "${ICONSET}/icon_256x256.png"
cp "${ICON_SRC}/512-mac.png"  "${ICONSET}/icon_256x256@2x.png"
cp "${ICON_SRC}/512-mac.png"  "${ICONSET}/icon_512x512.png"
cp "${ICON_SRC}/1024-mac.png" "${ICONSET}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET}" -o "${CONTENTS}/Resources/AppIcon.icns"

printf "APPL????" > "$CONTENTS/PkgInfo"

echo "→ Done: ${APP_DIR}  (version ${VERSION})"
echo ""
echo "To run:    open $APP_DIR"
echo "To install: cp -r $APP_DIR /Applications/"
