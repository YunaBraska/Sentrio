#!/bin/sh
set -eu

test "$#" -gt 0

script_dir=$(unset CDPATH; cd "$(dirname "$0")/.." && pwd)
resolved_file="${script_dir}/Package.resolved"
backup_file=$(mktemp)
resolved_was_present=false
if [ -f "${resolved_file}" ]; then
    cp "${resolved_file}" "${backup_file}"
    resolved_was_present=true
fi

cleanup() {
    if [ "${resolved_was_present}" = true ]; then
        cp "${backup_file}" "${resolved_file}"
    else
        rm -f "${resolved_file}"
    fi
    rm -f "${backup_file}"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

"$@"
