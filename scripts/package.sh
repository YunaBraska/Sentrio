#!/bin/sh
set -eu

test "$#" = 1

app_name='Sentrio'
version=$1
dist_dir='dist'
app_dir="${dist_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
script_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
signing_identity=${MACOS_SIGNING_IDENTITY:--}
notary_profile=${MACOS_NOTARY_PROFILE:-}

rm -rf "${dist_dir}" .build-release-arm64 .build-release-x86_64
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"

swift build -c release --arch arm64 --product "${app_name}" --scratch-path .build-release-arm64
swift build -c release --arch x86_64 --product "${app_name}" --scratch-path .build-release-x86_64
lipo -create \
  -output "${contents_dir}/MacOS/${app_name}" \
  .build-release-arm64/arm64-apple-macosx/release/"${app_name}" \
  .build-release-x86_64/x86_64-apple-macosx/release/"${app_name}"
lipo -info "${contents_dir}/MacOS/${app_name}"

binary_dir=.build-release-arm64/arm64-apple-macosx/release
find "${binary_dir}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${contents_dir}/Resources/" \;
find "${binary_dir}" -maxdepth 1 -type d -name '*.appintents' -exec sh -c '
  destination=$1
  shift
  for metadata_dir do
    if [ -d "${metadata_dir}/Metadata.appintents" ]; then
      cp -R "${metadata_dir}/Metadata.appintents" "${destination}/"
    fi
  done
' sh "${contents_dir}/Resources" {} +

cat > "${contents_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Sentrio</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleIdentifier</key>
    <string>com.sentrio.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.sentrio.app.busylight</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>sentrio</string>
            </array>
        </dict>
    </array>
    <key>NSAppleScriptEnabled</key>
    <true/>
    <key>NSSupportsAppIntents</key>
    <true/>
</dict>
</plist>
EOF

icon_source="${script_dir}/Assets.xcassets/AppIcon.appiconset"
test -d "${icon_source}"
iconset=$(mktemp -d)
trap 'rm -rf "${iconset}"' EXIT HUP INT TERM
mkdir -p "${iconset}/AppIcon.iconset"
cp "${icon_source}/16-mac.png" "${iconset}/AppIcon.iconset/icon_16x16.png"
cp "${icon_source}/32-mac.png" "${iconset}/AppIcon.iconset/icon_16x16@2x.png"
cp "${icon_source}/32-mac.png" "${iconset}/AppIcon.iconset/icon_32x32.png"
cp "${icon_source}/64-mac.png" "${iconset}/AppIcon.iconset/icon_32x32@2x.png"
cp "${icon_source}/128-mac.png" "${iconset}/AppIcon.iconset/icon_128x128.png"
cp "${icon_source}/256-mac.png" "${iconset}/AppIcon.iconset/icon_128x128@2x.png"
cp "${icon_source}/256-mac.png" "${iconset}/AppIcon.iconset/icon_256x256.png"
cp "${icon_source}/512-mac.png" "${iconset}/AppIcon.iconset/icon_256x256@2x.png"
cp "${icon_source}/512-mac.png" "${iconset}/AppIcon.iconset/icon_512x512.png"
cp "${icon_source}/1024-mac.png" "${iconset}/AppIcon.iconset/icon_512x512@2x.png"
iconutil -c icns "${iconset}/AppIcon.iconset" -o "${contents_dir}/Resources/AppIcon.icns"
printf 'APPL????' > "${contents_dir}/PkgInfo"

if [ "${signing_identity}" = '-' ]; then
  codesign --force --deep --sign - --timestamp=none "${app_dir}"
else
  codesign --force --deep --options runtime --sign "${signing_identity}" --timestamp "${app_dir}"
fi
codesign --verify --deep --verbose=2 "${app_dir}"

ditto -c -k --sequesterRsrc --keepParent "${app_dir}" "${dist_dir}/${app_name}-${version}.zip"
dmg_stage=$(mktemp -d)
trap 'rm -rf "${iconset}" "${dmg_stage}"' EXIT HUP INT TERM
cp -R "${app_dir}" "${dmg_stage}/"
ln -s /Applications "${dmg_stage}/Applications"
hdiutil create -volname "${app_name}" -srcfolder "${dmg_stage}" -ov -format UDZO "${dist_dir}/${app_name}-${version}.dmg"
hdiutil verify "${dist_dir}/${app_name}-${version}.dmg"
if [ -n "${notary_profile}" ]; then
  xcrun notarytool submit "${dist_dir}/${app_name}-${version}.dmg" --keychain-profile "${notary_profile}" --wait --timeout 30m
  xcrun stapler staple "${dist_dir}/${app_name}-${version}.dmg"
fi
