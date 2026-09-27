# Redis on Windows with MinGW64

This repository contains the Redis Windows portability layer and its first-class
MSYS2/MinGW64 build and test path. The supported development shell is the
MSYS2 `MINGW64` environment.

## Prerequisites

Install MSYS2 MinGW64 tools, a MinGW64 Tcl interpreter, Git, and the normal
Redis build dependencies. When invoking the wrappers from WSL or another host
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

## Affinity and executable hardening

The Windows CPU-list options validate and apply processor-group affinity.
See the branch behavior guide for the exact option names and constraints.
The CLI and benchmark enable ASLR; the server and its aliases keep the fixed
image layout required by QFork. Focused checks are:

```bash
./build-mingw.sh -j2 all interop-test
./runtest-mingw.sh --single windows/config --single windows/cpuaffinity --single windows/iocp --clients 1 --quiet --timeout 300
./build/mingw64/redis-affinity-test.exe
bash tests/windows/pe-hardening.sh build/mingw64
```

The source-declared Windows package revision is read from
`packaging/mingw/windows-revision`; explicit inputs must match it.
