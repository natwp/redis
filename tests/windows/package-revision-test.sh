#!/usr/bin/env bash
# Exercise revision selection without building any release package.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
resolver="$repo_root/scripts/windows-package-revision.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/packaging/mingw"
file="$fixture/packaging/mingw/windows-revision"

reject() {
    if bash "$resolver" "$fixture" "$@" >"$fixture/output" 2>&1; then
        echo 'revision resolver accepted invalid or mismatched source metadata' >&2
        exit 1
    fi
}
reject
for invalid in '' 0 -1 01 '1 2' '1 ' $'1\n2' $'1\n' $'1\r'; do
    printf '%s\n' "$invalid" > "$file"
    reject
done
for revision in 1 2 17; do
    printf '%s\n' "$revision" > "$file"
    [[ "$(bash "$resolver" "$fixture")" == "$revision" ]]
    [[ "$(bash "$resolver" "$fixture" "$revision")" == "$revision" ]]
    reject 0
    reject invalid
    reject "$((revision + 1))"
done
printf '2' > "$file"
[[ "$(bash "$resolver" "$fixture")" == 2 ]]
echo 'Windows source revision tests passed'
