# Redis 8.8.3 core behavior and upgrade guide for Windows

## Scope and release identity

This guide describes the unofficial Redis 8.8.3 Windows x64 MinGW port. The
Redis core baseline is the exact upstream Redis 8.8.3 tag at commit
`76ec1c311045cf2f28332a95631259cc67ad4b51`, integrated incrementally through
Redis 8.0.6, 8.2.8, 8.4.5, 8.6.5, 8.8.1, 8.8.2, and 8.8.3 with this fork's IOCP networking,
FDAPI descriptors, QFork persistence, Windows service, Event Log, console, and
MinGW64 layers.

The Windows package identity is:

- canonical branch: `mingw-8.8`;
- upstream release tag: `8.8.3`;
- package revision tag: `v8.8.3-windows.1`;
- portable archive: `Redis-x64-8.8.3-mingw-r1.zip`; and
- adjacent checksum: `Redis-x64-8.8.3-mingw-r1.zip.sha256`.

The preceding 8.8.1 packages remain immutable as tags
`v8.8.1-windows.1` and `v8.8.1-windows.2`; a new upstream release starts a
new package revision at 1.

`BUILDINFO.txt` inside the ZIP records the exact 40-character source commit
and tree used for the binaries. The package revision tag, BUILDINFO, archive,
checksum, and tested extraction must agree. Never move a published tag or
silently replace an archive; a changed Windows package requires a new revision.

## Upstream delta and Windows qualification state

The 8.8.3 line carries the prior 8.8.1 Windows hardening and the upstream
8.8.3 maintenance fixes. The public package is not considered released until
the exact source tip passes the CI-only qualification workflow.

The inherited Windows hardening reviewed and, where needed, fixed or explicitly bounded:

- UTF-8-to-UTF-16 Windows API boundaries for filesystem, environment, console,
  service, Event Log, and command-line handling;
- rejection of invalid UTF-8 at Windows conversion boundaries instead of
  falling back to the active ANSI code page;
- ASCII-only DNS node/service resolver inputs, with punycode required for
  international hostnames;
- case-insensitive Windows identity rules for environment variables,
  Redis checker/Sentinel aliases, and AOF filename comparisons;
- case-insensitive and slash-insensitive ordinary Windows path behavior while
  excluding raw device/verbatim namespaces from the portable contract;
- same-volume atomic replacement and bounded retry behavior for Windows
  sharing violations;
- QFork executable identity, fixed-address image, and package-source
  provenance checks;
- Tcl Windows test process ownership so repository test cleanup cannot stop an
  unrelated installed Redis service; and
- hiredis Windows resolver assertions so non-ASCII DNS names/services fail
  predictably instead of being treated as UTF-8 hostnames.

The inherited upstream 8.8.2 fixes cover ACL key resolution for SORT,
GEORADIUS, and XREAD variants; TLS certificate common-name extraction with
embedded NULs; blocked-client and pending-TLS lifetime safety; RDB slotinfo
range validation; and Vector Sets persistence/search hardening.

The 8.8.3 import rechecks queued-command ACL key permissions at EXEC and
preserves module command-filter cache invalidation. The new
`cluster-bus-port-protected-mode` defaults to `no`; enabling it requires
`tls-cluster`, and cluster peers must present certificates independently of
`tls-auth-clients`. This Windows revision adds static TLS, processor-group
CPU affinity, client ASLR, and IOCP retry accounting owned by each event loop.

The required public qualification runs on Windows/MinGW64 and records the
resolved hosted MSYS2 toolchain rather than claiming a fixed compiler version.
It includes:

- clean core-only package build from the exact source tip;
- `interop-test.exe --legacy` and `interop-test.exe --modern`;
- `hiredis-test.exe -h 127.0.0.1 -p 6493 --skip-throughput --skip-inherit-fd`;
- `./runtest-mingw.sh --clients 1 --quiet --timeout 600`;
- `./runtest-mingw.sh --cluster`;
- `./runtest-mingw.sh --sentinel`;
- `./runtest-mingw.sh --moduleapi --clients 1 --quiet --timeout 300`; and
- `./runtest-mingw-service.sh` for isolated elevated Windows service, restart,
  Event Log, and cleanup coverage.

Plaintext and TLS qualification run against one identical package. Passing
historical results do not qualify this source; every final tip needs fresh CI
evidence. The package revision comes from `packaging/mingw/windows-revision`.

The workflow also performs ZIP checksum, manifest, license, PE/import, fresh
extraction, packaged replication, a 30-minute QFork persistence soak, a short
benchmark, sanitized test evidence, and provenance/SBOM attestations. No local
build, tag, archive, or release operation is part of this process.

## Core-only distribution

This archive is Redis 8.8.3 core only. It does not build or ship the bundled
Redis Search, JSON, TimeSeries, probabilistic, or Vector Sets modules included
with the full upstream Redis 8 distribution. Those components add independent
build systems, worker-thread behavior, persistence paths, dependencies, and
license obligations that have not been qualified for this Windows port.

The core package includes the Redis server, Sentinel mode, CLI, benchmark, RDB
and AOF checkers, Event Log message resources, Windows configurations, and the
licenses and notices listed in the package README. Redis core features such as
Array, GCRA, expanded stream operations, Cluster slot migration/statistics, and
Functions are included where they are part of the Redis server itself.

Do not advertise this ZIP as the complete upstream Redis 8 binary
distribution. Native third-party modules must be built as x64 PE DLLs against
the included Redis Module API and validated independently.

## Licensing and notices

Redis 8 uses the tri-license payload in `LICENSE.txt`: recipients may use the
applicable Redis code under the Redis Source Available License 2.0, Server Side
Public License v1, or GNU Affero General Public License v3 terms described
there. `REDISCONTRIBUTIONS.txt` documents contribution licensing and the
portions retaining BSD-3-Clause treatment.

Binary redistribution must preserve:

- `LICENSE.txt`;
- `REDISCONTRIBUTIONS.txt`;
- `WINDOWS-NOTICES.txt`;
- `THIRD-PARTY-NOTICES.txt`;
- the OpenSSL, CC0, GCC Runtime Library Exception, GPLv3, and MinGW-w64 companion texts;
- this guide, the Windows release notes, and BUILDINFO; and
- access to the exact corresponding source revision.

The standard build statically links OpenSSL 3, records its version and MSYS2
package in BUILDINFO, and includes `OPENSSL-LICENSE.txt`.

The Redis 8 core adds linked fast_float, TRE, and xxHash code. Their notices,
along with hiredis, jemalloc, Lua, HdrHistogram, fpconv, linenoise, CRC, hash,
and toolchain notices, are reproduced in `THIRD-PARTY-NOTICES.txt`. This
guide records engineering scope and is not legal advice.

## Windows behavior differences

| Area | Upstream Linux/POSIX behavior | This Windows core package |
| --- | --- | --- |
| Event loop | epoll, kqueue, or another POSIX backend | IOCP with synthetic FDAPI descriptors and one-shot readiness rearming |
| Network transports | TCP, Unix sockets, and optional TLS | TCP and native TLS over IPv4/IPv6; Unix sockets are unsupported |
| Client I/O threads | Multiple read/write I/O threads may be configured | Exactly one client I/O thread is enforced |
| Background persistence | fork copy-on-write child | QFork starts a Windows child and restores the tracked heap at matching addresses |
| CPU affinity | CPU lists select processors for server and worker threads | Strict thread affinity within one Windows processor group per list |
| Executable layout | Normal PIE/ASLR conventions | CLI and benchmark enable ASLR and NX; the server and its aliases keep ASLR disabled for QFork |
| Service integration | daemon, systemd, or syslog conventions | Foreground console or Windows SCM service with Application Event Log support |
| Native modules | ELF shared objects and POSIX fork assumptions | x64 PE DLLs; module-created fork children are unsupported |
| Interactive CLI | POSIX terminal handling | Native Windows console input and ANSI translation; redirected input is a separate path |
| Distribution | Upstream source/full module distribution | Flat core-only Windows x64 ZIP |

The single client-I/O-thread rule does not mean Redis has only one thread.
Background I/O and other internal workers still run where supported. It means
client socket ownership remains on the main thread until IOCP-specific
qualification proves upstream's multi-threaded client I/O safe.

## Networking and security

The package uses IOCP rather than a POSIX readiness backend. FDAPI values are
synthetic handles; code and modules must not treat them as raw Winsock SOCKETs
or CRT descriptors. IOCP notifications may be one-shot, so handlers that need
future events must use the owning rearm path.

The example configurations bind to `127.0.0.1` and keep protected mode
enabled. Before adding non-loopback addresses, configure ACL authentication,
firewall rules, and TLS settings. The standard MinGW build supports native TLS
listeners, CLI/benchmark and `rediss://`, replication (including diskless and
dedicated RDB channels), Cluster links, and Sentinel. Runtime defaults remain
ordinary TCP; configure certificates and the TLS options to enable encryption.
`BUILD_TLS=no` builds an explicit plaintext-only variant. Unix sockets remain
unsupported.

TLS uses a shared FDAPI BIO and retains IOCP completion ownership during
synchronous operations. QFork children serialize into the parent-owned
replication pipe; SSL objects and encryption remain in the parent. See
WINDOWS-MINGW-README.md for configuration and native TLS tests.

IOCP preserves the connection write barrier for `appendfsync always` across
separate read and write completions. Deferred accept and write retries belong
to the owning event loop through delayed close and teardown, with a 100 ms
accept cadence, 10 ms write cadence, and fair batches of at most 64 writers.

Startup rejects client `io-threads` values other than 1. The retired
`io-threads-do-reads` option is ignored by Redis 8.8.

`server-cpulist`, `bio-cpulist`, `bgsave-cpulist`, and `aof-rewrite-cpulist`
retain their underscore aliases. Each list must select available processors
within one Windows processor group. Invalid lists fail before workers start;
Windows may still refuse a valid request, which is reported in the log.

Windows include paths are literal and do not support POSIX wildcard expansion.
List every included configuration file explicitly and use paths writable by
the intended console user or service account.

## Windows text, naming, and filesystem contract

Redis keeps arguments, configuration values, environment values, paths, and
diagnostics as UTF-8. Invalid UTF-8 is rejected; valid strings are converted
to UTF-16 for Windows `W` APIs rather than interpreted through the active code
page. Environment-variable names and the Sentinel/checker executable aliases
follow Windows case-insensitive rules. DNS hostnames and resolver service
labels remain ASCII-only; use punycode (`xn--...`) for international hostnames.
This resolver rule is separate from the Windows SCM `service-name`, which uses
the UTF-8-to-UTF-16 service boundary.

Use ordinary UTF-8 drive-absolute or UNC paths. File operations support Unicode
and internally generated extended-length paths, but raw `\\?\`, `\\.\`, device,
or verbatim namespaces are not a portable configuration contract. Keep the
process `dir` short, absolute, and below `MAX_PATH`, because the global working
directory also affects relative CRT and Win32 operations.

Ordinary Windows volumes are treated case-insensitively and slash styles are
equivalent. Redis does not normalize Unicode composition or qualify
per-directory case-sensitive NTFS mode. Windows `redis_lstat` is stat-like and
does not promise POSIX symlink semantics, so avoid symlinks, junctions, mount
points, and other reparse points in Redis-owned trees. Multi-part AOF cleanup,
old-style detection, and upgrade filename identity follow the same
case-insensitive rule. Atomic replacement is same-volume only and uses
write-through `MoveFileExW`; Windows has no direct equivalent of POSIX
directory `fsync()`. Storage caches and transient sharing
violations from antivirus, backup, or indexing software can therefore still
affect crash durability or cause an operation to fail after its bounded retry.

## Persistence, replication, and QFork

RDB saves, AOF rewrites, and full synchronization use QFork. QFork starts the
same `redis-server.exe` image as a child, maps the tracked jemalloc heap at
matching virtual addresses, restores changed pages, and runs the upstream
child operation. The package therefore keeps the customized
`jemalloc-5.3.0-redis` allocator and fixed-address executable constraints.

Allow enough Windows commit/pagefile capacity for the parent, child, copied
pages, output buffers, and workload churn. Memory pressure can fail a
background operation even when the parent remains responsive. Monitor Redis
persistence status and Windows commit usage; do not disable the pagefile for a
QFork deployment without workload-specific evidence.

The examples retain disk-backed replication synchronization. Diskless
replication is not the default Windows contract and requires separate workload
qualification. For AOF deployments, preserve the complete append-only
directory and manifest together. Use the packaged checkers before recovery:

    redis-check-rdb.exe dump.rdb
    redis-check-aof.exe appendonlydir\appendonly.aof.manifest

Never copy or replace active persistence files without first stopping the
exact owning Redis process.

## Windows service and Event Log

Service operations require an elevated Windows token. Always use an explicit,
unique service name; never experiment against an unrelated production
`Redis` service. The package README shows the supported action-first syntax.

The service example runs as the account configured by the installer or SCM and
writes inside its configured directory. Grant only the required read/write
permissions to the configuration, data, and log paths. Installation does not
start a service, and uninstallation does not stop one.

`EventLog.dll` supplies message resources for the Windows Application Event
Log. Redis service registrations share the Redis Event Log source name, so
uninstalling one side-by-side service can remove the shared registration until
another service installs it again. The package service gate uses a unique
temporary name and verifies cleanup.

## Console and automation

In a real Windows console, redis-cli uses native console input and ANSI output
translation. Redirected stdin/stdout and the repository's fake-TTY test path
are intentionally different. Automation should use non-interactive CLI modes
and must not depend on prompt parsing, terminal width, or ANSI translation.

Server console mode writes to stdout when `logfile` is empty or `stdout`.
Service mode also enables Windows Event Log output. Review log destinations and
directory permissions before deployment.

## Upgrade and rollback

Before replacing an existing Redis instance:

1. Record the old executable version, source package, configuration, service
   name/account, persistence mode, ACLs, replication topology, and rollback
   procedure.
2. Produce and verify a final RDB or AOF backup with the old version's checker.
3. Extract this ZIP into a new directory; do not overwrite a running install.
4. Compare the deployment configuration with the packaged Windows template and
   upstream Redis 8.8 configuration changes.
5. Start on an isolated loopback port and validate application commands,
   persistence, restart recovery, replication, ACLs, and latency.
6. Stop the exact old process or service, wait for its PID and port to close,
   then switch using an explicit configuration and service name.
7. Retain the old binaries and verified backup until rollback is no longer
   required.

Redis persistence compatibility is not a substitute for an application-level
rollback test. Newer commands or encodings may not be understood by an older
server, and replication across major versions must be qualified in the actual
topology.

## Package qualification contract

The Windows revision tag may be created only after all of these checks agree on
one clean source commit and one never-before-used extraction:

- clean MinGW64 core build and executable version/Git identity;
- full Redis root, Cluster, Sentinel, and Module API source suites;
- Windows interop and hiredis resolver/runtime suites;
- deterministic package manifest, SHA-256, ZIP CRC, and duplicate-name audit;
- exact license, notice, configuration, guide, release-note, and BUILDINFO
  payload;
- x86-64 PE type, resource, import, runtime-DLL, debug-section, and ASLR audit;
- extracted PING, ACL, RDB/AOF creation, packaged checker, and restart recovery;
- sustained packaged QFork RDB/AOF cycles under concurrent writes with exact
  child-process ownership;
- isolated packaged Windows service start, restart, Event Log, stop, uninstall,
  and cleanup; and
- final process, service, port, scratch-directory, Git, and checksum audit.

The package makes no benchmark or clean-machine compatibility claim unless a
separate recorded protocol supports it. The legacy Visual Studio/MSI, NuGet,
and Chocolatey paths remain quarantined and are not artifacts of this MinGW
release. Automated qualification covers non-interactive CLI use; human
interactive editing in a physical Windows console remains a deployment check,
not a package performance or terminal-compatibility claim.

## Support boundary

This is an unofficial community Windows port, not an official Redis Ltd.
Windows binary distribution. Test backups and recovery before production use.
When reporting a problem, include BUILDINFO.txt, executable `--version`
output, the exact configuration, Windows version, service/console mode, and a
minimal reproduction that does not expose secrets.
