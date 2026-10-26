#!/bin/sh
set -eu

case "${0##*/}" in
  swift)
    show_bin_path=false
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--scratch-path' ]; then
        shift
        scratch=$1
      elif [ "$1" = '--show-bin-path' ]; then
        show_bin_path=true
      fi
      shift
    done
    mkdir -p "${scratch}/out/Products/Release/Sentrio_SentrioCore.bundle/Contents/Resources/en.lproj"
    mkdir -p "${scratch}/artifacts/sparkle/Sparkle/bin" "${scratch}/artifacts/sparkle/Sparkle/Sparkle.framework"
    cat > "${scratch}/artifacts/sparkle/Sparkle/bin/generate_appcast" <<'EOF'
#!/bin/sh
set -eu
output=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      shift
      output=$1
      ;;
  esac
  shift
done
test -n "${output}"
printf 'appcast %s\n' "${output}" >> "${PACKAGE_TEST_LOG}"
touch "${output}"
EOF
    cat > "${scratch}/artifacts/sparkle/Sparkle/bin/sign_update" <<'EOF'
#!/bin/sh
set -eu
printf 'verify appcast\n' >> "${PACKAGE_TEST_LOG}"
EOF
    chmod +x "${scratch}/artifacts/sparkle/Sparkle/bin/generate_appcast" "${scratch}/artifacts/sparkle/Sparkle/bin/sign_update"
    touch "${scratch}/out/Products/Release/Sentrio" "${scratch}/out/Products/Release/Sentrio_SentrioCore.bundle/Contents/Resources/en.lproj/Localizable.strings"
    if [ "${show_bin_path}" = true ]; then
      printf '%s\n' "${scratch}/out/Products/Release"
    fi
    exit
    ;;
  lipo)
    if [ "$1" = '-create' ]; then
      test -f "$4"
      test -f "$5"
      touch "$3"
    fi
    exit
    ;;
  install_name_tool)
    printf 'rpath %s\n' "$*" >> "${PACKAGE_TEST_LOG}"
    exit
    ;;
  iconutil)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '-o' ]; then
        shift
        touch "$1"
        break
      fi
      shift
    done
    exit
    ;;
  codesign)
    printf 'codesign %s\n' "$*" >> "${PACKAGE_TEST_LOG}"
    exit
    ;;
  ditto)
    if [ "$#" = 2 ]; then
      mkdir -p "$2"
      exit
    fi
    printf 'zip %s\n' "$6" >> "${PACKAGE_TEST_LOG}"
    touch "$6"
    exit
    ;;
  hdiutil)
    if [ "$1" = 'create' ]; then
      for last do :; done
      touch "${last}"
    fi
    exit
    ;;
  xcrun)
    printf '%s\n' "$*" >> "${PACKAGE_TEST_LOG}"
    if [ "${PACKAGE_TEST_FAIL:-}" = 'true' ] && [ "$1" = 'notarytool' ]; then
      exit 1
    fi
    exit
    ;;
esac

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "${root}/scripts/Sentrio.entitlements")" = true
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' 0 HUP INT TERM
mkdir -p "${tmp}/bin" "${tmp}/work"
for command in swift lipo install_name_tool iconutil codesign ditto hdiutil xcrun; do
  ln -s "${root}/scripts/test-package.sh" "${tmp}/bin/${command}"
done
export PACKAGE_TEST_LOG="${tmp}/events"
export PATH="${tmp}/bin:${PATH}"
export MACOS_SIGNING_IDENTITY='test identity'
export MACOS_NOTARY_PROFILE='test profile'
export MACOS_UPDATE_PRIVATE_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
export MACOS_UPDATE_PUBLIC_KEY='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
cd "${tmp}/work"
sh "${root}/scripts/package.sh" 1.2.3

grep -q '^codesign .*--entitlements .*Sentrio.entitlements ' "${PACKAGE_TEST_LOG}"
grep -q '^rpath -add_rpath @executable_path/../Frameworks ' "${PACKAGE_TEST_LOG}"
grep -q '^notarytool submit .*\.zip .* --timeout 90m$' "${PACKAGE_TEST_LOG}"
grep -q '^notarytool submit .*\.dmg .* --timeout 90m$' "${PACKAGE_TEST_LOG}"
app_submission=$(grep -n '^notarytool submit .*\.zip ' "${PACKAGE_TEST_LOG}" | cut -d: -f1)
app_staple=$(grep -n '^stapler staple .*\.app$' "${PACKAGE_TEST_LOG}" | cut -d: -f1)
release_zip=$(grep -nF 'zip dist/Sentrio-1.2.3.zip' "${PACKAGE_TEST_LOG}" | cut -d: -f1)
dmg_submission=$(grep -n '^notarytool submit .*\.dmg ' "${PACKAGE_TEST_LOG}" | cut -d: -f1)
dmg_staple=$(grep -n '^stapler staple .*\.dmg$' "${PACKAGE_TEST_LOG}" | cut -d: -f1)
test -n "${app_submission}"
test -n "${app_staple}"
test -n "${release_zip}"
test -n "${dmg_submission}"
test -n "${dmg_staple}"
test "${app_submission}" -lt "${app_staple}"
test "${app_staple}" -lt "${release_zip}"
test "${release_zip}" -lt "${dmg_submission}"
test "${dmg_submission}" -lt "${dmg_staple}"
grep -q '^stapler validate .*\.app$' "${PACKAGE_TEST_LOG}"
grep -q '^stapler validate .*\.dmg$' "${PACKAGE_TEST_LOG}"
test -f dist/Sentrio-1.2.3.zip
test -f dist/Sentrio-1.2.3.dmg
test -f dist/appcast.xml
test -d dist/Sentrio.app/Contents/Frameworks/Sparkle.framework
test -f dist/Sentrio.app/Contents/Resources/Sentrio_SentrioCore.bundle/Contents/Resources/en.lproj/Localizable.strings
grep -q '<key>SUFeedURL</key>' dist/Sentrio.app/Contents/Info.plist
grep -q '<string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>' dist/Sentrio.app/Contents/Info.plist
grep -q '^appcast dist/appcast.xml$' "${PACKAGE_TEST_LOG}"
grep -q '^verify appcast$' "${PACKAGE_TEST_LOG}"

: > "${PACKAGE_TEST_LOG}"
export PACKAGE_TEST_FAIL=true
if sh "${root}/scripts/package.sh" 1.2.3; then
  printf '%s\n' 'Packaging continued after notarization failed.' >&2
  exit 1
fi
test ! -f dist/Sentrio-1.2.3.zip
test ! -f dist/Sentrio-1.2.3.dmg
test ! -f dist/appcast.xml

: > "${PACKAGE_TEST_LOG}"
unset PACKAGE_TEST_FAIL MACOS_NOTARY_PROFILE MACOS_UPDATE_PRIVATE_KEY MACOS_UPDATE_PUBLIC_KEY
export MACOS_SIGNING_IDENTITY='-'
sh "${root}/scripts/package.sh" 1.2.3
test -f dist/Sentrio-1.2.3.zip
test -f dist/Sentrio-1.2.3.dmg
test ! -f dist/appcast.xml
if grep -q '<key>SUFeedURL</key>' dist/Sentrio.app/Contents/Info.plist; then
  printf '%s\n' 'An ad-hoc build configured automatic updates.' >&2
  exit 1
fi
if grep -Eq '^(notarytool|stapler)' "${PACKAGE_TEST_LOG}"; then
  printf '%s\n' 'An ad-hoc build attempted notarization.' >&2
  exit 1
fi
