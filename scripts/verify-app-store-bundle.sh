#!/bin/sh
set -eu

test "$#" = 1
app_dir=$1
test -d "${app_dir}"

contents_dir="${app_dir}/Contents"
executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${contents_dir}/Info.plist")
entitlements=$(mktemp)
trap 'rm -f "${entitlements}"' 0 HUP INT TERM

codesign --verify --deep --strict --verbose=2 "${app_dir}"
codesign -d --entitlements :- "${app_dir}" > "${entitlements}" 2>/dev/null
plutil -lint \
  "${entitlements}" \
  "${contents_dir}/Info.plist" \
  "${contents_dir}/Resources/PrivacyInfo.xcprivacy"

test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${entitlements}")" = true
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.camera' "${entitlements}")" = true
test "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "${contents_dir}/Info.plist")" = 'public.app-category.utilities'
test "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "${contents_dir}/Info.plist")" = false
test "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType' "${contents_dir}/Resources/PrivacyInfo.xcprivacy")" = 'NSPrivacyAccessedAPICategoryUserDefaults'
test "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "${contents_dir}/Resources/PrivacyInfo.xcprivacy")" = 'CA92.1'
test ! -e "${contents_dir}/Frameworks/Sparkle.framework"

if /usr/libexec/PlistBuddy -c 'Print :NSAppleScriptEnabled' "${contents_dir}/Info.plist" >/dev/null 2>&1; then
  printf '%s\n' 'App Store bundle enables unused AppleScript support.' >&2
  exit 1
fi

for localization in da de en es fi fr it ja ko nl pl pt-BR ru sv tr zh-Hans; do
  purpose_file="${contents_dir}/Resources/${localization}.lproj/InfoPlist.strings"
  plutil -lint "${purpose_file}" >/dev/null
  test -n "$(plutil -extract NSMicrophoneUsageDescription raw -o - "${purpose_file}")"
  test -n "$(plutil -extract NSCameraUsageDescription raw -o - "${purpose_file}")"
done

if otool -L "${contents_dir}/MacOS/${executable_name}" | grep -q 'Sparkle'; then
  printf '%s\n' 'App Store bundle links Sparkle.' >&2
  exit 1
fi

if strings "${contents_dir}/MacOS/${executable_name}" | grep -qF 'github.com/sponsors'; then
  printf '%s\n' 'App Store bundle contains an external sponsorship purchase link.' >&2
  exit 1
fi

printf '%s\n' 'App Store bundle verification passed.'
