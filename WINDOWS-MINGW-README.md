# Redis on Windows with MinGW64

This repository contains the Redis Windows portability layer and its first-class
MSYS2/MinGW64 build and test path. The supported development shell is the
MSYS2 `MINGW64` environment.

## Prerequisites

Install MSYS2 MinGW64 tools, a MinGW64 Tcl interpreter, Git, and the normal
Redis build dependencies, including OpenSSL 3 static development libraries:

```bash
pacman -S --needed make git curl tar diffutils mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-tcl mingw-w64-x86_64-openssl \
  mingw-w64-x86_64-pkgconf mingw-w64-x86_64-zstd
```

When invoking the wrappers from WSL or another host
shell, select MSYS2 with one of these mechanisms:

```bash
export MSYS_BASH=/path/to/msys2/usr/bin/bash.exe
./build-mingw.sh -j2
```

or:

```bash
./build-mingw.sh --msys-bash /path/to/msys2/usr/bin/bash.exe -j2
```

For repeated local use, put the same `MSYS_BASH=...` assignment in the ignored
`.local/mingw.env` file. The wrappers do not source arbitrary local scripts.
When they are already running inside an MSYS2 `MINGW64` shell, no path is
needed.

## Build and test

```bash
./build-mingw.sh -j2
./runtest-mingw.sh --clients 1 --quiet --timeout 600
./runtest-mingw.sh --cluster
./runtest-mingw.sh --sentinel
./runtest-mingw.sh --moduleapi --clients 1 --quiet --timeout 300
./runtest-mingw-service.sh
```

The service test needs an elevated Windows token. Use private test ports and
do not stop or reconfigure unrelated Redis services.

For focused CPU-affinity and executable-hardening checks in MINGW64 after a
build:

    ./build/mingw64/redis-affinity-test.exe
    ./runtest-mingw.sh --single windows/config --single windows/cpuaffinity --clients 1 --quiet --timeout 300
    bash tests/windows/pe-hardening.sh build/mingw64

These checks cover synthetic processor groups, native thread-mask readback,
startup configuration validation, QFork persistence affinity, and PE flags and
relocations. Physical multi-group qualification requires a host with multiple
processor groups. Focused checks do not replace the complete CI qualification.

## Performance investigations

Performance automation is on hold. The diagnostic harnesses retain the
controlled A/B and gprof protocols for future investigations after the CI
policy is reviewed. Run one investigation at a time with a common toolchain,
explicit source commits, matching client settings, and recorded binary
identities. Diagnostic results do not qualify a release.

Separate builds use `-pg` for gprof call graphs and sampling. Their timings are
kept separate from the uninstrumented A/B results. The profiled server keeps
the existing fixed image base, which gprof needs to resolve Windows samples.
An explicit `nm` symbol table preserves static function names in the profiles.
The profiler runtime uses native CRT file functions to avoid symbol collisions
with older FDAPI baselines; its original and adapted hashes are recorded.
Profiles do not attribute time inside Windows DLLs; use the recorded kernel
CPU measurements alongside the call graphs. The harnesses build diagnostic
binaries without creating release packages or release qualification evidence.

## Native TLS

The standard build includes built-in TLS and statically links OpenSSL 3. It
requires no OpenSSL DLLs. `./build-mingw.sh BUILD_TLS=no -j2` builds an explicit
plaintext-only variant; switching `BUILD_TLS=yes|no` rebuilds the affected
objects and hiredis archive. Other values, including `module`, are rejected.

TLS remains disabled until configured. Client connections, CLI, benchmark,
`rediss://` URLs, replication, Cluster links and Sentinel use the native TLS
transport. Diskless synchronization, including a dedicated RDB channel, keeps
encryption in the parent process while QFork writes the snapshot to a pipe.

For a TLS-only listener, set `port 0`, `tls-port 6379`, `tls-cert-file`,
`tls-key-file`, and `tls-ca-cert-file`. Client certificates are required by
default. Use `tls-replication yes` on replicas and Sentinel, and `tls-cluster yes`
for Cluster bus connections. Configure `tls-client-cert-file` and
`tls-client-key-file` when the outbound certificate differs from the server
certificate. `tls-expected-peer-name` verifies configured peer identities in
addition to CA trust. The packaged configuration files contain commented examples.

Use quoted certificate paths with forward slashes, for example
`"C:/Redis/certificates/server.crt"`; UTF-8 paths with spaces and Unicode are
supported. The service account needs read access to its private key and
certificates. To renew certificates, install the new files and issue one
`CONFIG SET tls-cert-file ... tls-key-file ... tls-ca-cert-file ...`. Redis
validates the new context before replacing it; existing connections retain
their context until they reconnect. Persist the changed paths in the
configuration file or with `CONFIG REWRITE`.

Focused native checks:

```bash
make -f Makefile.mingw interop-test
./build/mingw64/interop-test.exe --legacy
./build/mingw64/interop-test.exe --modern
./runtest-mingw.sh --tls --single unit/tls --single windows/tls --clients 1 --quiet --timeout 600
./runtest-mingw.sh --tls --single unit/cluster/cluster-response-tls --single unit/cluster/tls-peer-impersonation --clients 1 --quiet --timeout 600
./runtest-mingw.sh --sentinel --tls --single 00-base
```

`--tls` prepares TclTLS 1.7.22 from its checksum-pinned official release in
ignored `.local/test-deps/` and generates ignored test certificates. Only the
test harness receives its Tcl package path. Tests and keys are excluded from
packages. The suite selector (`--cluster`, `--sentinel`, or `--moduleapi`) must
precede `--tls`. Full suites run in CI; service tests accept `-TLS` after the
TLS fixtures have been prepared.

## Windows port boundaries

The Windows path uses IOCP networking, the Win32 file-descriptor layer, and the
QFork persistence implementation. Client I/O remains single-threaded until a
separate Windows qualification proves otherwise. Core-only package builds keep
bundled Redis modules outside the release boundary.

The first release qualification boundary is x86-64 PE binaries built with the
MSYS2/MinGW64 toolchain on GitHub Actions `windows-2022` runners. Windows
Server 2025 runs are useful forward-compatibility evidence, but do not replace
the pinned release qualification. x86-32, MSVC, and legacy Windows Server
2012 R2 are not release targets yet.

## CI and releases

Pull requests run public-source hygiene and lightweight offline checks with a
ten-minute job limit. A manual `windows_smoke` dispatch on a `release-*` branch can run
one MinGW64 build, focused Redis tests, and Windows interop checks, with a
thirty-minute limit. It starts after hygiene succeeds. All Windows workflows
share one concurrency group, and transport matrices allow one job at a time.

Full qualification, performance automation, and publication are on hold.
Canonical branch pushes do not start full qualification. Before those retained
workflows are enabled again, their evidence selection and API usage must be
reviewed for explicit serial runs and the five-minute GitHub request interval.
Long jobs are restricted to `release-*` branches. Development branches retain
only short checks and established regression tests, including manual runs.

A public release still requires all Windows source suites, service and Event
Log coverage, package audits, replication, persistence, and binary identity
checks for its exact source commit. Redis 8 qualifies the stripped package over
TLS only. TLS-disabled builds, plaintext transport suites, and plaintext
benchmarks are excluded from TLS-enabled release CI. Evidence records those
checks as skipped. A rewritten commit needs fresh qualification.
Packages, attestations, tags, and uploads are produced by explicitly enabled
CI only. Existing immutable releases must not be replaced.

The package revision remains declared in `packaging/mingw/windows-revision`.
See [RELEASE-POLICY.md](RELEASE-POLICY.md) for release gates, maintained-line
order, branch naming, and the conditions for ending the hold.

## Troubleshooting

- `MSYS2 bash is not configured`: set `MSYS_BASH`, pass `--msys-bash PATH`, or
  create `.local/mingw.env`.
- `MinGW Tcl not found`: install the MinGW64 Tcl package and run the wrapper
  from an MSYS2 `MINGW64` shell.
- stale allocator or dependency state after switching branches: run
  `./build-mingw.sh distclean` before rebuilding.
