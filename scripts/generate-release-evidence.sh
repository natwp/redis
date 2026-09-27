#!/usr/bin/env bash
# Generate sanitized release evidence and an SPDX 2.3 SBOM from a package that
# has already passed the complete Windows qualification workflow.

set -euo pipefail
export LC_ALL=C

usage() {
    echo "usage: $0 ARCHIVE EXTRACTED_DIR OUTPUT_DIR SOURCE_BRANCH WINDOWS_REVISION GATE_JSON TOOLCHAIN_FILE IDENTITY_FILE"
}

die() {
    echo "error: $*" >&2
    exit 1
}

if (( $# != 8 )); then
    usage >&2
    exit 2
fi

archive=$1
extracted_dir=$2
output_dir=$3
source_branch=$4
windows_revision=$5
gate_json=$6
toolchain_file=$7
identity_file=$8

for tool in awk date find git grep install jq sed sha1sum sha256sum sort tr wc; do
    command -v "$tool" >/dev/null 2>&1 || die "required evidence tool not found: $tool"
done
[[ -f "$archive" ]] || die "archive not found: $archive"
[[ -f "$archive.sha256" ]] || die "archive checksum not found: $archive.sha256"
[[ -d "$extracted_dir" ]] || die "extracted package not found: $extracted_dir"
[[ -f "$gate_json" ]] || die "qualification gate JSON not found: $gate_json"
[[ -f "$toolchain_file" ]] || die "toolchain inventory not found: $toolchain_file"
[[ -f "$identity_file" ]] || die "package binary identity report not found: $identity_file"
[[ "$windows_revision" =~ ^[1-9][0-9]*$ ]] || die "invalid Windows revision"
source_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$source_root/scripts/windows-package-revision.sh" "$source_root" "$windows_revision" >/dev/null
jq -e 'type == "object" and (.policy | type == "string")' "$gate_json" >/dev/null ||
    die "qualification gate JSON is invalid"

(
    cd "$(dirname "$archive")"
    sha256sum -c "$(basename "$archive").sha256"
) >/dev/null || die "archive checksum verification failed"

mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -print -quit | grep -q .; then
    die "evidence output directory must be empty: $output_dir"
fi

buildinfo="$extracted_dir/BUILDINFO.txt"
[[ -f "$buildinfo" ]] || die "BUILDINFO.txt is missing from extracted package"
version="$(sed -n 's/^Redis version: //p' "$buildinfo")"
source_commit="$(sed -n 's/^Source commit: //p' "$buildinfo")"
source_tree="$(sed -n 's/^Source tree: //p' "$buildinfo")"
openssl_version="$(sed -n 's/^OpenSSL version: //p' "$buildinfo")"
openssl_package="$(sed -n 's/^OpenSSL package: //p' "$buildinfo")"
buildinfo_revision="$(sed -n 's/^Windows package revision: //p' "$buildinfo")"
buildinfo_tag="$(sed -n 's/^Release tag: //p' "$buildinfo")"
[[ "$openssl_version" == 3.* && "$openssl_package" == mingw-w64-x86_64-openssl\ * ]] || die "missing OpenSSL provenance"
grep -Fx 'TLS build: yes (built in; static OpenSSL)' "$buildinfo" >/dev/null || die "package TLS mode mismatch"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid BUILDINFO version"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die "invalid BUILDINFO source commit"
[[ "$source_tree" =~ ^[0-9a-f]{40}$ ]] || die "invalid BUILDINFO source tree"
[[ "$buildinfo_revision" == "$windows_revision" ]] || die "BUILDINFO Windows revision mismatch"
[[ -n "$source_branch" ]] || die "source branch is empty"

release_tag="v${version}-windows.${windows_revision}"
[[ "$buildinfo_tag" == "$release_tag" ]] || die "BUILDINFO release tag mismatch"
[[ "$(git rev-parse HEAD)" == "$source_commit" ]] || die "BUILDINFO source commit does not match checkout"
[[ "$(git rev-parse 'HEAD^{tree}')" == "$source_tree" ]] || die "BUILDINFO source tree does not match checkout"
package_name="$(basename "$archive")"
archive_sha="$(sha256sum "$archive" | sed 's/[[:space:]].*$//')"
created_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
repository="${GITHUB_REPOSITORY:-natwp/redis}"
workflow_run_id="${GITHUB_RUN_ID:-unknown}"
workflow_run_attempt="${GITHUB_RUN_ATTEMPT:-unknown}"
workflow_url="https://github.com/${repository}/actions/runs/${workflow_run_id}"

install -m 0644 "$archive" "$output_dir/$package_name"
install -m 0644 "$archive.sha256" "$output_dir/SHA256SUMS.txt"
install -m 0644 "$buildinfo" "$output_dir/BUILDINFO.txt"
install -m 0644 "$extracted_dir/PACKAGE-MANIFEST.txt" "$output_dir/package-manifest.txt"
install -m 0644 "$toolchain_file" "$output_dir/toolchain.txt"
install -m 0644 "$identity_file" "$output_dir/package-binary-identity.tsv"

cat > "$output_dir/benchmark.csv" <<'EOF'
status,transport,reason
skipped,plaintext,excluded for TLS-enabled releases
EOF

IFS= read -r -d '' report_template <<'EOF' || true
# Redis __VERSION__ Windows qualification

- Release candidate: `__RELEASE_TAG__`
- Canonical branch: `__SOURCE_BRANCH__`
- Source commit: `__SOURCE_COMMIT__`
- Source tree: `__SOURCE_TREE__`
- Workflow run: __WORKFLOW_URL__ (attempt __WORKFLOW_ATTEMPT__)
- Completed: __CREATED_UTC__

| Qualification gate | Result |
| --- | --- |
| Public-source hygiene over full Git history | Passed |
| MinGW64 core, interop, launcher, and package build | Passed |
| Redis root test suite (TLS) | Passed |
| Cluster test suite (TLS) | Passed |
| Sentinel test suite (TLS) | Passed |
| Module API test suite (TLS) | Passed |
| Windows legacy and modern interop tests | Passed |
| Isolated Windows service and Event Log test (TLS) | Passed |
| ZIP checksum, extraction, manifest, licenses, PE and import audit | Passed |
| Release binaries identical to the bytes used by source-tree suites | Passed |
| Packaged master/replica full and incremental synchronization (TLS) | Passed |
| Packaged QFork RDB/AOF persistence and restart soak (TLS, 30 minutes) | Passed |
| Plaintext transport suites and TLS-disabled builds | Skipped |
| Plaintext loopback package benchmark | Skipped |

## Benchmark

Plaintext CI is excluded for TLS-enabled releases. The plaintext benchmark
was skipped; `benchmark.csv` records that decision without claiming measured
performance or a comparison with an earlier release.

## Toolchain

The resolved MSYS2/MinGW64 package versions used by this workflow are recorded
in `toolchain.txt` and in the archive's `BUILDINFO.txt`. This release does
not claim bit-for-bit reproducibility across changing hosted-runner toolchains.
EOF
report="${report_template//__VERSION__/$version}"
report="${report//__RELEASE_TAG__/$release_tag}"
report="${report//__SOURCE_BRANCH__/$source_branch}"
report="${report//__SOURCE_COMMIT__/$source_commit}"
report="${report//__SOURCE_TREE__/$source_tree}"
report="${report//__WORKFLOW_URL__/$workflow_url}"
report="${report//__WORKFLOW_ATTEMPT__/$workflow_run_attempt}"
report="${report//__CREATED_UTC__/$created_utc}"
report_file="$output_dir/TEST-REPORT.md"
printf '%s\n' "$report" > "$report_file"
[[ "$report" != *__* ]] || die "release report contains an unresolved template placeholder"
grep -Fq -- "- Release candidate: \`$release_tag\`" "$report_file" ||
    die "release report is missing the release tag"
grep -Fq -- "- Canonical branch: \`$source_branch\`" "$report_file" ||
    die "release report is missing the canonical branch"
grep -Fq -- "- Source commit: \`$source_commit\`" "$report_file" ||
    die "release report is missing the source commit"

files_json="$output_dir/.spdx-files.ndjson"
relationships_json="$output_dir/.spdx-relationships.ndjson"
verification_sha1s="$output_dir/.spdx-file-sha1s"
: > "$files_json"
: > "$relationships_json"
: > "$verification_sha1s"
file_count=0
while IFS= read -r package_file; do
    file_name="$(basename "$package_file")"
    file_sha1="$(sha1sum "$package_file" | sed 's/[[:space:]].*$//')"
    file_sha="$(sha256sum "$package_file" | sed 's/[[:space:]].*$//')"
    # File content is not a unique identifier: several Redis executables can
    # intentionally be byte-identical. Include the deterministic package file
    # name in the SPDX identifier so every file and relationship has a unique
    # target while remaining stable across CI runs.
    file_name_sha="$(printf '%s' "$file_name" | sha256sum | sed 's/[[:space:]].*$//')"
    file_id="SPDXRef-File-${file_name_sha:0:16}-${file_sha:0:16}"
    case "$file_name" in
        *.exe|*.dll) file_type=BINARY ;;
        *) file_type=TEXT ;;
    esac
    jq -cn \
        --arg id "$file_id" \
        --arg name "./$file_name" \
        --arg sha1 "$file_sha1" \
        --arg sha "$file_sha" \
        --arg type "$file_type" \
        '{SPDXID:$id,fileName:$name,checksums:[{algorithm:"SHA1",checksumValue:$sha1},{algorithm:"SHA256",checksumValue:$sha}],fileTypes:[$type],licenseConcluded:"NOASSERTION",copyrightText:"NOASSERTION"}' \
        >> "$files_json"
    jq -cn \
        --arg id "$file_id" \
        '{spdxElementId:"SPDXRef-Package",relationshipType:"CONTAINS",relatedSpdxElement:$id}' \
        >> "$relationships_json"
    printf '%s\n' "$file_sha1" >> "$verification_sha1s"
    file_count=$((file_count + 1))
done < <(find "$extracted_dir" -mindepth 1 -maxdepth 1 -type f | LC_ALL=C sort)
(( file_count > 0 )) || die "extracted package contains no files"
package_verification_code="$(LC_ALL=C sort "$verification_sha1s" | tr -d '\n' | sha1sum | sed 's/[[:space:]].*$//')"

jq -n \
    --arg created "$created_utc" \
    --arg namespace "https://github.com/${repository}/sbom/${source_commit}/${workflow_run_id}/attempt-${workflow_run_attempt}" \
    --arg name "Redis-x64-${version}-mingw-r${windows_revision}" \
    --arg version "$version" \
    --arg package_file_name "$package_name" \
    --arg archive_sha "$archive_sha" \
    --arg package_verification_code "$package_verification_code" \
    --arg openssl_version "$openssl_version" \
    --arg openssl_package "$openssl_package" \
    --slurpfile files "$files_json" \
    --slurpfile contains "$relationships_json" \
    '{
        spdxVersion:"SPDX-2.3",
        dataLicense:"CC0-1.0",
        SPDXID:"SPDXRef-DOCUMENT",
        name:($name + " SBOM"),
        documentNamespace:$namespace,
        creationInfo:{created:$created,creators:["Tool: natwp-release-evidence/1"]},
        packages:[{
            SPDXID:"SPDXRef-Package",
            name:$name,
            versionInfo:$version,
            packageFileName:$package_file_name,
            downloadLocation:"NOASSERTION",
            filesAnalyzed:true,
            packageVerificationCode:{packageVerificationCodeValue:$package_verification_code},
            checksums:[{algorithm:"SHA256",checksumValue:$archive_sha}],
            licenseConcluded:"NOASSERTION",
            licenseDeclared:"NOASSERTION",
            copyrightText:"NOASSERTION"
        },{
            SPDXID:"SPDXRef-OpenSSL",
            name:"OpenSSL",
            versionInfo:$openssl_version,
            downloadLocation:"https://www.openssl.org/source/",
            filesAnalyzed:false,
            licenseConcluded:"Apache-2.0",
            licenseDeclared:"Apache-2.0",
            copyrightText:"NOASSERTION",
            sourceInfo:("MSYS2 package: " + $openssl_package)
        }],
        files:$files,
        relationships:([{
            spdxElementId:"SPDXRef-DOCUMENT",
            relationshipType:"DESCRIBES",
            relatedSpdxElement:"SPDXRef-Package"
        },{
            spdxElementId:"SPDXRef-Package",
            relationshipType:"STATIC_LINK",
            relatedSpdxElement:"SPDXRef-OpenSSL"
        }] + $contains)
    }' > "$output_dir/sbom.spdx.json"
rm -f "$files_json" "$relationships_json" "$verification_sha1s"

jq -e --arg package_verification_code "$package_verification_code" '
    ([.SPDXID] + [.packages[]?.SPDXID] + [.files[]?.SPDXID]) as $ids |
    ($ids | length == (unique | length)) and
    (.packages | length == 2) and
    (.packages[1].SPDXID == "SPDXRef-OpenSSL" and .packages[1].licenseDeclared == "Apache-2.0" and .packages[1].filesAnalyzed == false) and
    (any(.relationships[]; .relationshipType == "STATIC_LINK" and .relatedSpdxElement == "SPDXRef-OpenSSL")) and
    (.packages[0].filesAnalyzed == true) and
    (.packages[0].packageVerificationCode.packageVerificationCodeValue == $package_verification_code) and
    (all(.files[];
        ([.checksums[] | select(.algorithm == "SHA1")] | length == 1) and
        ([.checksums[] | select(.algorithm == "SHA256")] | length == 1))) and
    ([.relationships[]?.spdxElementId, .relationships[]?.relatedSpdxElement]
        | all(. as $id | ($ids | index($id) != null)))
' "$output_dir/sbom.spdx.json" >/dev/null ||
    die "generated SPDX SBOM has duplicate or dangling identifiers"

jq -n \
    --arg schema_version "1" \
    --arg version "$version" \
    --arg windows_revision "$windows_revision" \
    --arg tag "$release_tag" \
    --arg branch "$source_branch" \
    --arg source_commit "$source_commit" \
    --arg source_tree "$source_tree" \
    --arg archive "$package_name" \
    --arg archive_sha256 "$archive_sha" \
    --arg workflow_url "$workflow_url" \
    --arg completed_utc "$created_utc" \
    --arg openssl_version "$openssl_version" \
    --arg openssl_package "$openssl_package" \
    --slurpfile maintained_lines "$gate_json" \
    '{
        schema_version:$schema_version,
        release:{version:$version,windows_revision:($windows_revision|tonumber),tag:$tag,branch:$branch},
        source:{commit:$source_commit,tree:$source_tree},
        package:{archive:$archive,sha256:$archive_sha256,scope:"Redis core only",tls:{build:"yes",linkage:"static",openssl_version:$openssl_version,openssl_package:$openssl_package}},
        qualification:{workflow_url:$workflow_url,completed_utc:$completed_utc,all_required_tests:"passed",transports:["TLS"],skipped_transports:["plaintext"],release_binary_identity:"passed",maintained_lines:$maintained_lines[0]},
        benchmark:{status:"skipped",transport:"plaintext",reason:"excluded for TLS-enabled releases",blocking:false},
        attestations:{required_before_publication:{build_provenance:true,sbom:true},created_by:"Publish Windows release workflow"}
    }' > "$output_dir/release-evidence.json"

printf 'RELEASE_EVIDENCE_OK tag=%s archive_sha256=%s\n' "$release_tag" "$archive_sha"
