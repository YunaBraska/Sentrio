#!/bin/sh
set -eu

test "$#" = 2

version=$1
build_version=$2

case "${version}" in
  ''|*[!0-9.]*|.*|*.|*..*)
    printf '%s\n' "Invalid marketing version: ${version}. Expected Major.Minor.Patch." >&2
    exit 2
    ;;
esac
previous_ifs=$IFS
IFS=.
set -- ${version}
IFS=$previous_ifs
if [ "$#" -ne 3 ]; then
  printf '%s\n' "Invalid marketing version: ${version}. Expected Major.Minor.Patch." >&2
  exit 2
fi

case "${build_version}" in
  ''|*[!0-9.]*|.*|*.|*..*)
    printf '%s\n' "Invalid build version: ${build_version}. Expected one to three numeric components." >&2
    exit 2
    ;;
esac
previous_ifs=$IFS
IFS=.
set -- ${build_version}
IFS=$previous_ifs
if [ "$#" -gt 3 ]; then
  printf '%s\n' "Invalid build version: ${build_version}. Expected one to three numeric components." >&2
  exit 2
fi
