# Windows release and CI policy

## Current CI scope

Pull requests run public-source hygiene and lightweight offline validation in
one job with a ten-minute limit. A manual release-branch dispatch can opt into
one Windows build and focused smoke test, limited to thirty minutes and started only after
the hygiene job succeeds. Smoke checks do not qualify a release.

Full qualification, performance automation, and publication are on hold.
Full qualification no longer starts on branch pushes. Its retained jobs and
the release jobs are explicitly disabled. Dependabot configuration is removed;
dependency updates are reviewed manually.

All Windows workflows share one concurrency group without cancelling an active
run. Transport matrices permit one job at a time. Dispatch the next long run
only after the previous run has finished, across all maintained branches.
Long qualification and release jobs are restricted to `release-*` refs even
after the hold is lifted. Development branches run only short checks and
established regression tests; never full suites, benchmarks, or diagnostic
experiments.

Before enabling qualification or publication, review the retained workflows'
historical push-run evidence assumptions and release-ref checks for the new
manual, serial process. Preserve every required release gate. GitHub API
requests, including retries and requests hidden by CLI pagination, must be at
least five minutes apart. Existing evidence for an earlier source commit does
not qualify rewritten history.

## Branches and release scope

Development and maintenance use `mingw-<major.minor>` branches. Release
candidates use `release-<version>` branches. A release branch records a
candidate; it does not establish that a package has been qualified or published.

After upstream publishes a maintenance release, qualify the five lines in
order: 8.10, 8.8, 7.4, 7.2, and 6.2. Only after all exact source tips pass may
the eligible lines be published, in order: 8.10, 8.8, 7.2, and 6.2. Redis 7.4
remains qualification-only. Redis 8 retains one TLS-capable package per line.

Upstream imports preserve Redis and Windows-upstream ancestry and attribution.
Source changes continue to use reviewed pull requests. Publication stays
disabled until upstream is ready and the hold is explicitly lifted. Never
create release tags or upload packages locally.

## Package and evidence contract

Packages are built only in GitHub Actions. Qualification performs one clean
MinGW64 build, strips the candidate before any source-tree suite runs, stages
the ZIP from those exact bytes, and then points the source-tree suites at the
extracted package. A final binary-identity and archive-checksum gate re-extracts
the unchanged ZIP so release evidence cannot inherit files modified by a test.
Publication independently matches the ZIP to its BUILDINFO, manifest, evidence,
SPDX file checksums, and SPDX package verification code. The release workflow
uploads, attests, and publishes that same artifact without rebuilding it. Each
release carries the ZIP, `SHA256SUMS.txt`, `BUILDINFO.txt`, `package-manifest.txt`,
`package-binary-identity.tsv`, `toolchain.txt`, `TEST-REPORT.md`,
`release-evidence.json`, `benchmark.csv`, and `sbom.spdx.json`. For non-TLS releases, the benchmark
uses loopback, persistence disabled, one benchmark thread, 50 clients,
pipeline 1, a discarded 10,000-request warmup, and three 50,000-request
measurements for PING, SET, and GET. A throughput decrease or p95 increase
above 15% is an advisory warning; it does not silently turn into a release
blocker. TLS-enabled releases skip the plaintext benchmark; `benchmark.csv`
records the skip, and evidence must not claim plaintext qualification or
measured benchmark results.

The release workflow creates GitHub artifact attestations for both SLSA build
provenance and the SPDX SBOM. It creates the remote
`vX.Y.Z-windows.N` tag only after those attestations and all qualification
gates succeed. Publication creates all assets in a single release operation
and refuses to modify an existing release or use or move a pre-existing tag.
Repository administrators must also enable GitHub's release immutability
setting before the first public release so later UI or API operations cannot
alter the tag or assets.

## Credentials and settings

The workflows use the run-scoped `GITHUB_TOKEN` with job-level permissions.
They do not require a personal access token. A personal token pasted into a
chat, log, or issue must be revoked and replaced through a secure channel.
Repository rulesets, required-review settings, Actions approval policies, and
release immutability are administrative settings and are not encoded as
secrets in this repository.

Before the first public release, a repository administrator must:

- enable immutable releases;
- allow the pinned GitHub-owned actions and `msys2/setup-msys2` used by these
  workflows;
- protect every canonical `mingw-*` branch against deletion and, after the
  first public release, force pushes;
- require pull requests, one approving review, resolved conversations, and the
  `public-hygiene` PR check and separately required Windows qualification;
- keep both squash merging and merge commits available: ordinary maintenance
  is squash-merged, while upstream imports use merge commits to preserve
  Redis and tporadowski ancestry; and
- keep Dependabot automation disabled.

The release workflow itself rechecks the successful full-qualification run and
current tip of all five maintained lines immediately before it creates a tag.
It refuses to overwrite an existing release or use or move an existing tag.

## Source-declared package revision

`packaging/mingw/windows-revision` contains one positive integer. Packaging and
automatic qualification resolve it from the selected source; an explicit
revision must match. Redis 8 packages require static OpenSSL provenance and
plaintext plus TLS results. Older lines retain explicit plaintext evidence.
Release verification checks source version, revision, archive, BUILDINFO,
manifest, binary identities, and SPDX checksums before attestation.
