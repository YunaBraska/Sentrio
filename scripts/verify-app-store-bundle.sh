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
test "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "${contents_dir}/Info.plist")" = 'public.app-category.utilities'
test "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "${contents_dir}/Info.plist")" = false
test ! -e "${contents_dir}/Frameworks/Sparkle.framework"

if otool -L "${contents_dir}/MacOS/${executable_name}" | grep -q 'Sparkle'; then
  printf '%s\n' 'App Store bundle links Sparkle.' >&2
  exit 1
fi

printf '%s\n' 'App Store bundle verification passed.'
