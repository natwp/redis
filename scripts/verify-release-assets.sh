#!/usr/bin/env bash
# Verify qualified bytes before attestation and again before publication.
set -euo pipefail
export LC_ALL=C
[[ $# == 1 ]] || { echo "usage: $0 RELEASE_ASSET_DIR" >&2; exit 2; }
cd "$1"
tag=${RELEASE_TAG:?}
source_sha=${RELEASE_SOURCE_SHA:?}
source_branch=${RELEASE_SOURCE_BRANCH:?}
version=${RELEASE_VERSION:?}
revision=${RELEASE_REVISION:?}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$revision" =~ ^[1-9][0-9]*$ ]]
[[ "$source_sha" =~ ^[0-9a-f]{40}$ && "${RELEASE_SOURCE_TREE:?}" =~ ^[0-9a-f]{40}$ ]]
[[ "${RELEASE_QUALIFICATION_RUN_ID:?}" =~ ^[1-9][0-9]*$ ]]
[[ "$source_branch" == "mingw-${version%.*}" && "$tag" == "v${version}-windows.${revision}" ]]
case "$source_branch" in
    mingw-8.10|mingw-8.8) tls_build=yes ;;
    mingw-7.2|mingw-6.2) tls_build=no ;;
    *) echo 'source branch is not release eligible' >&2; exit 1 ;;
esac
[[ -z "$(find . -mindepth 1 -maxdepth 1 ! -type f -print -quit)" ]] || {
    echo 'release assets must be regular files in one directory' >&2; exit 1;
}
mapfile -d '' -t archives < <(find . -maxdepth 1 -type f -name '*.zip' -print0)
(( ${#archives[@]} == 1 )) || { echo 'expected exactly one release ZIP' >&2; exit 1; }
archive="${archives[0]}"
archive_name="$(basename "$archive")"
[[ "$archive_name" == "Redis-x64-${version}-mingw-r${revision}.zip" ]] || { echo 'release archive name does not match source identity' >&2; exit 1; }
archive_sha="$(sha256sum "$archive" | sed 's/[[:space:]].*$//')"
required_assets=(
  BUILDINFO.txt
  SHA256SUMS.txt
  TEST-REPORT.md
  benchmark.csv
  package-manifest.txt
  package-binary-identity.tsv
  release-evidence.json
  sbom.spdx.json
  toolchain.txt
)
for asset in "${required_assets[@]}"; do
  [[ -s "./$asset" ]] || { echo "missing or empty release asset: $asset" >&2; exit 1; }
done
[[ -s "$archive" ]] || { echo 'release ZIP is empty' >&2; exit 1; }
expected_assets=("$archive")
for asset in "${required_assets[@]}"; do
  expected_assets+=("./$asset")
done
mapfile -d '' -t assets < <(find . -maxdepth 1 -type f -print0 | sort -z)
if ! diff -u \
    <(printf '%s\n' "${expected_assets[@]}" | sort) \
    <(printf '%s\n' "${assets[@]}" | sort); then
  echo 'release assets contain missing or unexpected files' >&2
  exit 1
fi
[[ "$(cat SHA256SUMS.txt)" == "$archive_sha  $archive_name" ]] || {
  echo 'release checksum does not identify exactly the expected archive' >&2; exit 1;
}
sha256sum -c SHA256SUMS.txt
jq -e \
  --arg tag "$tag" \
  --arg sha "$source_sha" \
  --arg branch "$source_branch" \
  --arg version "$version" \
  --argjson revision "$revision" \
  --arg archive "$archive_name" \
  --arg archive_sha "$archive_sha" \
  --arg tls_build "$tls_build" \
  --arg workflow_url "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${RELEASE_QUALIFICATION_RUN_ID}" '
    .release.tag == $tag and
    .release.branch == $branch and
    .release.version == $version and
    .release.windows_revision == $revision and
    .source.commit == $sha and
    .package.archive == $archive and
    .package.sha256 == $archive_sha and
    .package.scope == "Redis core only" and
    .package.tls.build == $tls_build and
    .qualification.transports == (if $tls_build == "yes" then ["plaintext", "TLS"] else ["plaintext"] end) and
    .qualification.workflow_url == $workflow_url and
    .qualification.all_required_tests == "passed" and
    .qualification.release_binary_identity == "passed" and
    .attestations.required_before_publication.build_provenance == true and
    .attestations.required_before_publication.sbom == true
  ' ./release-evidence.json >/dev/null
jq -e --arg archive "$archive_name" --arg archive_sha "$archive_sha" \
  --slurpfile evidence ./release-evidence.json '
  (.spdxVersion == "SPDX-2.3" and .SPDXID == "SPDXRef-DOCUMENT") and
  (if ($evidence[0].package.tls.build // "no") == "yes" then
    (.packages | length == 2) and
    (.packages[1].SPDXID == "SPDXRef-OpenSSL") and
    (.packages[1].name == "OpenSSL" and .packages[1].filesAnalyzed == false) and
    (.packages[1].licenseDeclared == "Apache-2.0") and
    (.packages[1].versionInfo == $evidence[0].package.tls.openssl_version) and
    (.packages[1].sourceInfo == ("MSYS2 package: " + $evidence[0].package.tls.openssl_package)) and
    ($evidence[0].package.tls.linkage == "static") and
    ($evidence[0].qualification.transports == ["plaintext", "TLS"]) and
    (any(.relationships[];
      .spdxElementId == "SPDXRef-Package" and
      .relationshipType == "STATIC_LINK" and
      .relatedSpdxElement == "SPDXRef-OpenSSL"))
  else (.packages | length == 1) end) and
  (.packages[0].packageFileName == $archive) and
  (.packages[0].filesAnalyzed == true) and
  (any(.packages[0].checksums[]; .algorithm == "SHA256" and .checksumValue == $archive_sha)) and
  (.packages[0].packageVerificationCode.packageVerificationCodeValue | test("^[0-9a-f]{40}$")) and
  (
    ([.SPDXID] + [.packages[]?.SPDXID] + [.files[]?.SPDXID]) as $ids
    | ($ids | length == (unique | length))
    and ([.files[]?.fileName] | length == (unique | length))
    and (all(.files[];
      (.fileName | test("^\\./[^/\\\\]+$")) and
      ([.checksums[] | select(.algorithm == "SHA1" and (.checksumValue | test("^[0-9a-f]{40}$")))] | length == 1) and
      ([.checksums[] | select(.algorithm == "SHA256" and (.checksumValue | test("^[0-9a-f]{64}$")))] | length == 1)))
    and ([.relationships[]?.spdxElementId, .relationships[]?.relatedSpdxElement]
      | all(. as $id | ($ids | index($id) != null)))
  )
' ./sbom.spdx.json >/dev/null || {
  echo 'invalid SPDX SBOM: duplicate or dangling identifiers' >&2
  exit 1
}
command -v unzip >/dev/null 2>&1 || { echo 'unzip is required to verify release binary identity' >&2; exit 1; }
identity_header=$'build_file\tpackage_file\tsha256\tsize'
[[ "$(sed -n '1p' ./package-binary-identity.tsv)" == "$identity_header" ]] || {
  echo 'invalid package binary identity header' >&2
  exit 1
}
verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT
# Inspect paths before extraction; the package contract is flat.
unzip -Z1 "$archive" > "$verify_dir/archive-entries.txt"
while IFS= read -r entry; do
    [[ -n "$entry" && "$entry" != */* && "$entry" != *\\* && "$entry" != .* &&
       "$entry" != *$'\r'* && "$entry" != *$'\t'* ]] || {
        echo 'release ZIP contains an unsafe or non-flat path' >&2; exit 1;
    }
done < "$verify_dir/archive-entries.txt"
[[ -z "$(sort "$verify_dir/archive-entries.txt" | uniq -d)" ]] || {
    echo 'release ZIP contains duplicate entries' >&2; exit 1;
}
rm "$verify_dir/archive-entries.txt"
unzip -q "$archive" -d "$verify_dir"
[[ -z "$(find "$verify_dir" -mindepth 1 ! -type f -print -quit)" ]] || {
    echo 'release ZIP contains a non-regular file' >&2; exit 1;
}
[[ ! -e "$verify_dir/.release-audit" ]]
mkdir "$verify_dir/.release-audit"
cmp -s ./BUILDINFO.txt "$verify_dir/BUILDINFO.txt" || {
  echo 'released BUILDINFO.txt differs from the copy inside the ZIP' >&2
  exit 1
}
cmp -s ./package-manifest.txt "$verify_dir/PACKAGE-MANIFEST.txt" || {
  echo 'released package manifest differs from the copy inside the ZIP' >&2
  exit 1
}
buildinfo_commit="$(sed -n 's/^Source commit: //p' ./BUILDINFO.txt)"
buildinfo_tree="$(sed -n 's/^Source tree: //p' ./BUILDINFO.txt)"
buildinfo_version="$(sed -n 's/^Redis version: //p' ./BUILDINFO.txt)"
buildinfo_revision="$(sed -n 's/^Windows package revision: //p' ./BUILDINFO.txt)"
buildinfo_tag="$(sed -n 's/^Release tag: //p' ./BUILDINFO.txt)"
[[ "$buildinfo_commit" == "$source_sha" && "$buildinfo_version" == "$version" && \
   "$buildinfo_revision" == "$revision" && "$buildinfo_tag" == "$tag" ]] || {
  echo 'BUILDINFO release identity does not match the requested release' >&2
  exit 1
}
remote_tree="$RELEASE_SOURCE_TREE"
[[ "$buildinfo_tree" == "$remote_tree" ]] || {
  echo 'BUILDINFO source tree does not match the release commit tree' >&2
  exit 1
}
jq -e --arg tree "$buildinfo_tree" '.source.tree == $tree' \
  ./release-evidence.json >/dev/null || {
    echo 'release evidence source tree does not match BUILDINFO' >&2
    exit 1
  }
actual_sbom_files="$verify_dir/.release-audit/actual-sbom-files.tsv"
expected_sbom_files="$verify_dir/.release-audit/expected-sbom-files.tsv"
while IFS= read -r -d '' package_file; do
  package_file_name="$(basename "$package_file")"
  package_file_sha1="$(sha1sum "$package_file" | sed 's/[[:space:]].*$//')"
  package_file_sha256="$(sha256sum "$package_file" | sed 's/[[:space:]].*$//')"
  printf '%s\t%s\t%s\n' "$package_file_name" "$package_file_sha1" "$package_file_sha256"
done < <(find "$verify_dir" -mindepth 1 -maxdepth 1 -type f -print0) | sort > "$actual_sbom_files"
jq -r '.files[] | [
    (.fileName | sub("^\\./"; "")),
    ([.checksums[] | select(.algorithm == "SHA1")][0].checksumValue),
    ([.checksums[] | select(.algorithm == "SHA256")][0].checksumValue)
  ] | @tsv' ./sbom.spdx.json | sort > "$expected_sbom_files"
if ! diff -u "$expected_sbom_files" "$actual_sbom_files"; then
  echo 'SPDX file inventory does not match the release ZIP' >&2
  exit 1
fi
actual_verification_code="$(cut -f2 "$actual_sbom_files" | sort | tr -d '\n' | sha1sum | sed 's/[[:space:]].*$//')"
sbom_verification_code="$(jq -r '.packages[0].packageVerificationCode.packageVerificationCodeValue' ./sbom.spdx.json)"
[[ "$actual_verification_code" == "$sbom_verification_code" ]] || {
  echo 'SPDX package verification code does not match the release ZIP' >&2
  exit 1
}
expected_identity_pairs=(
  $'redis-server.exe\tredis-server.exe'
  $'redis-server.exe\tredis-sentinel.exe'
  $'redis-check-aof.exe\tredis-check-aof.exe'
  $'redis-check-rdb.exe\tredis-check-rdb.exe'
  $'redis-cli.exe\tredis-cli.exe'
  $'redis-benchmark.exe\tredis-benchmark.exe'
  $'EventLog.dll\tEventLog.dll'
)
actual_identity_pairs=()
identity_count=0
for alias in redis-sentinel.exe redis-check-aof.exe redis-check-rdb.exe; do
  cmp "$verify_dir/redis-server.exe" "$verify_dir/$alias" || {
    echo 'QFork server aliases do not have identical bytes' >&2; exit 1;
  }
done
while IFS=$'\t' read -r build_name package_name file_sha file_size; do
  [[ -n "$build_name" && -n "$package_name" ]] || { echo 'invalid empty identity record' >&2; exit 1; }
  [[ "$build_name" != */* && "$build_name" != *'\\'* && "$build_name" != .* ]] || {
    echo "unsafe build identity path: $build_name" >&2
    exit 1
  }
  [[ "$package_name" != */* && "$package_name" != *'\\'* && "$package_name" != .* ]] || {
    echo "unsafe package identity path: $package_name" >&2
    exit 1
  }
  [[ "$file_sha" =~ ^[0-9a-f]{64}$ && "$file_size" =~ ^[0-9]+$ ]] || {
    echo "invalid package identity digest or size for $package_name" >&2
    exit 1
  }
  packaged_file="$verify_dir/$package_name"
  [[ -f "$packaged_file" ]] || { echo "identity file is absent from ZIP: $package_name" >&2; exit 1; }
  actual_sha="$(sha256sum "$packaged_file" | sed 's/[[:space:]].*$//')"
  actual_size="$(wc -c < "$packaged_file" | tr -d '[:space:]')"
  [[ "$actual_sha" == "$file_sha" && "$actual_size" == "$file_size" ]] || {
    echo "release ZIP does not match binary identity record: $package_name" >&2
    exit 1
  }
  actual_identity_pairs+=("$build_name"$'\t'"$package_name")
  identity_count=$((identity_count + 1))
done < <(sed '1d' ./package-binary-identity.tsv)
(( identity_count == 7 )) || { echo "expected seven package identity records, found $identity_count" >&2; exit 1; }
if ! diff -u \
    <(printf '%s\n' "${expected_identity_pairs[@]}") \
    <(printf '%s\n' "${actual_identity_pairs[@]}"); then
  echo 'package binary identity contains missing, duplicate, reordered, or unexpected mappings' >&2
  exit 1
fi
if [[ "$tls_build" == yes ]]; then
    grep -Fx 'TLS build: yes (built in; static OpenSSL)' BUILDINFO.txt >/dev/null
    jq -e --arg version "$(sed -n 's/^OpenSSL version: //p' BUILDINFO.txt)" \
        --arg package "$(sed -n 's/^OpenSSL package: //p' BUILDINFO.txt)" '
        ($version | startswith("3.")) and
        ($package | startswith("mingw-w64-x86_64-openssl ")) and
        .package.tls.openssl_version == $version and
        .package.tls.openssl_package == $package' release-evidence.json >/dev/null
else
    grep -Fx 'TLS build: no' BUILDINFO.txt >/dev/null
fi
printf 'Release archive, source identity, transport evidence and SPDX checksums verified\n'
