#!/bin/sh
set -eu

test "$#" = 2

app_name='Sentrio'
version=$1
build_number=$2
workspace_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/sentrio-app-store.XXXXXX")
dist_dir="${workspace_dir}/dist/app-store"
app_dir="${dist_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"

: "${APP_STORE_BUNDLE_ID:?}"
: "${APP_STORE_TEAM_ID:?}"
: "${MACOS_APP_STORE_APPLICATION_IDENTITY:?}"
: "${MACOS_APP_STORE_PROFILE_PATH:?}"

rm -rf "${dist_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.build-*' \
  --exclude 'dist' \
  "${workspace_dir}/" "${build_dir}/"
cd "${build_dir}"
export SENTRIO_APP_STORE=1

swift build -c release --arch arm64 --product "${app_name}" --scratch-path .build-app-store-arm64
swift build -c release --arch x86_64 --product "${app_name}" --scratch-path .build-app-store-x86_64
arm64_bin=$(swift build -c release --arch arm64 --product "${app_name}" --scratch-path .build-app-store-arm64 --show-bin-path)
x86_64_bin=$(swift build -c release --arch x86_64 --product "${app_name}" --scratch-path .build-app-store-x86_64 --show-bin-path)
lipo -create \
  -output "${contents_dir}/MacOS/${app_name}" \
  "${arm64_bin}/${app_name}" \
  "${x86_64_bin}/${app_name}"
lipo -info "${contents_dir}/MacOS/${app_name}"
if strings "${contents_dir}/MacOS/${app_name}" | grep -q '/usr/sbin/system_profiler'; then
  echo 'App Store build must not contain system_profiler.' >&2
  exit 1
fi

find "${arm64_bin}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${contents_dir}/Resources/" \;
find "${arm64_bin}" -maxdepth 1 -type d -name '*.appintents' -exec sh -c '
  destination=$1
  shift
  for metadata_dir do
    if [ -d "${metadata_dir}/Metadata.appintents" ]; then
      cp -R "${metadata_dir}/Metadata.appintents" "${destination}/"
    fi
  done
' sh "${contents_dir}/Resources" {} +

icon_source="${workspace_dir}/Assets.xcassets/AppIcon.appiconset"
test -d "${icon_source}"
iconset=$(mktemp -d)
trap 'rm -rf "${iconset}" "${build_dir}"' EXIT HUP INT TERM
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
cp "${MACOS_APP_STORE_PROFILE_PATH}" "${contents_dir}/embedded.provisionprofile"
printf 'APPL????' > "${contents_dir}/PkgInfo"
cp "${workspace_dir}/scripts/Sentrio-AppStore-Info.plist" "${contents_dir}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_STORE_BUNDLE_ID}" "${contents_dir}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${contents_dir}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${contents_dir}/Info.plist"

entitlements="${iconset}/Sentrio-AppStore.entitlements"
cp "${workspace_dir}/scripts/Sentrio-AppStore.entitlements" "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${APP_STORE_TEAM_ID}.${APP_STORE_BUNDLE_ID}" "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${APP_STORE_TEAM_ID}" "${entitlements}"
/usr/libexec/PlistBuddy -c 'Add :keychain-access-groups array' "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string ${APP_STORE_TEAM_ID}.${APP_STORE_BUNDLE_ID}" "${entitlements}"
codesign --force --entitlements "${entitlements}" --options runtime --timestamp --sign "${MACOS_APP_STORE_APPLICATION_IDENTITY}" "${app_dir}"
codesign --verify --deep --strict --verbose=2 "${app_dir}"
