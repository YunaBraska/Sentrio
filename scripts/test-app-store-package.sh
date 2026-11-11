#!/bin/sh
set -eu

case "${0##*/}" in
  swift)
    scratch=''
    show_bin_path=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --scratch-path)
          shift
          scratch=$1
          ;;
        --show-bin-path) show_bin_path=true ;;
      esac
      shift
    done
    test -n "${scratch}"
    bundle="${scratch}/out/Products/Release/Sentrio_SentrioCore.bundle"
    mkdir -p "${bundle}/en.lproj"
    cat > "${bundle}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.sentrio.resources</string></dict></plist>
EOF
    touch "${bundle}/en.lproj/Localizable.strings" "${scratch}/out/Products/Release/Sentrio"
    if [ "${show_bin_path}" = true ]; then
      printf '%s\n' "${scratch}/out/Products/Release"
    fi
    exit
    ;;
  lipo)
    if [ "$1" = '-create' ]; then
      touch "$3"
    fi
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
  codesign) exit ;;
esac

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' 0 HUP INT TERM
mkdir -p "${tmp}/bin" "${tmp}/work"
for command in swift lipo iconutil codesign; do
  ln -s "${root}/scripts/test-app-store-package.sh" "${tmp}/bin/${command}"
done
touch "${tmp}/profile"
export PATH="${tmp}/bin:${PATH}"
export APP_STORE_BUNDLE_ID='berlin.yuna.sentrio'
export APP_STORE_TEAM_ID='TEAMID'
export MACOS_APP_STORE_APPLICATION_IDENTITY='test identity'
export MACOS_APP_STORE_PROFILE_PATH="${tmp}/profile"
cd "${tmp}/work"
sh "${root}/scripts/package-app-store.sh" 1.2.3 4

app="${root}/dist/app-store/Sentrio.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "${app}/Contents/Info.plist")" = 'public.app-category.utilities'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Contents/Resources/Sentrio_SentrioCore.bundle/Contents/Info.plist")" = 'test.sentrio.resources'
test -f "${app}/Contents/Resources/Sentrio_SentrioCore.bundle/Contents/Resources/en.lproj/Localizable.strings"
