#!/usr/bin/env bash
# Resolve package identity from the selected source tree, never from a default.
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
    echo "usage: $0 SOURCE_ROOT [REQUESTED_REVISION]" >&2
    exit 2
fi

revision_file="$1/packaging/mingw/windows-revision"
requested_revision=${2:-}
[[ -f "$revision_file" ]] || {
    echo 'error: source is missing packaging/mingw/windows-revision' >&2
    exit 1
}
mapfile -t revision_lines < "$revision_file"
if (( ${#revision_lines[@]} != 1 )) || [[ ! "${revision_lines[0]}" =~ ^[1-9][0-9]*$ ]]; then
    echo 'error: packaging/mingw/windows-revision must contain one positive integer' >&2
    exit 1
fi
revision=${revision_lines[0]}
if [[ -n "$requested_revision" && "$requested_revision" != "$revision" ]]; then
    echo "error: requested Windows revision $requested_revision does not match source revision $revision" >&2
    exit 1
fi
printf '%s\n' "$revision"
