# Windows changes for Redis 7.4.11

This file records the Windows behavior and upgrade guidance on `mingw-7.4`.
The current-line section describes this branch. Earlier-line sections preserve
historical behavior and upgrade notes with their original version boundaries.

Publication and full qualification are on hold; package names below identify
candidates or historical releases, not qualification of this rewritten source.

## Redis 7.4 (current line)


### Scope and release identity

This is the authoritative behavior and upgrade guide for the unofficial Redis
Community Edition 7.4.11 Windows x64 MinGW port. The source baseline is the
exact upstream Redis `7.4.11` tag, commit
`aaf0ce63b3239f4b51f86ca1da8711b055721993`, with the applicable upstream
security fixes, integrated with this fork's IOCP networking, FDAPI descriptors,
QFork persistence, Windows service, Event Log, console, and MinGW64 layers.
The source tree and produced binaries report `7.4.11`.

The Windows release identity is:

- canonical maintenance branch: `mingw-7.4`;
- no public release tag: the 7.4 line is qualification-only under the current
  publication policy;
- CI qualification archive identity: `Redis-x64-7.4.11-mingw-r1.zip`; and
- CI checksum: `Redis-x64-7.4.11-mingw-r1.zip.sha256`.

These names identify the first CI qualification revision of the 7.4.11
baseline. They do not authorize publication: the release workflow intentionally
rejects `mingw-7.4` because this line is outside the current Windows publication
policy. Keep its full qualification evidence for regression and security
tracking; do not create or push a 7.4 release tag or package.

Except for the differences documented here, command, RESP, ACL, Lua, Function,
replication, Cluster, Sentinel, persistence, and Module API behavior follows
upstream Redis 7.4.11. `00-RELEASENOTES` is the source for upstream release and
command-level changes. This guide supersedes `WINDOWS-7.4-PORTING.md` for an
approved release; the porting ledger remains useful for implementation history.

#### Redis 7.4.11 security-fix provenance

Redis 7.4.11 is an upstream `SECURITY` release. It fixes pending-TLS and
blocked-client use-after-free paths, ACL key-resolution and wrong-arity
out-of-bounds checks, and validates RDB `SLOT_INFO` ranges to reject crafted
corrupt payloads before memory corruption. These fixes are part of the exact
7.4.11 source baseline and apply to the Windows port without changing Redis
command semantics.

Qualification must run the complete source suites and the relevant corrupt-RDB,
ACL, blocked-client, TLS, and persistence regressions with the MinGW server,
then confirm a successful authenticated `PING`. Do not substitute a 7.4.11 or
earlier binary while retaining 7.4.11 metadata.

### Windows revision 1 maintenance

This candidate adds processor-group CPU affinity and enables dynamic-base,
high-entropy ASLR, NX, and base relocations for the CLI, benchmark, and standalone
test programs. The server, Sentinel, and checker aliases retain the fixed image
layout required by the branch's bundled jemalloc and QFork implementation.

IOCP retries are owned by each event loop through attachment, delayed close,
and teardown. Accept retries retain their 100 ms cadence; blocked writes use
a 10 ms cadence and fair batches of at most 64 sockets. Retained completion
ownership prevents callbacks on closed or recycled descriptors, and connection
write barriers preserve the AOF flush-before-reply contract.

The startup-only CPU options are `server-cpulist`, `bio-cpulist`, `bgsave-cpulist`, `aof-rewrite-cpulist`.
Each list must select available processors within one Windows processor group.
Invalid lists fail before worker creation; refused Windows API calls are logged.
The underscore option aliases are preserved.

`packaging/mingw/windows-revision` declares revision 1. Packaging, CI
qualification, and release evidence reject conflicting revisions. The package
remains plaintext and core only, with single-threaded Windows client I/O.
Every final source tip requires fresh Windows qualification before publication.
The 7.4 line remains qualification only and has no public release tag.

### Licensing and notices

Redis 7.4 changed the upstream license model. Upstream Redis 7.4.11 is offered
under the user's choice of the Redis Source Available License 2.0 (`RSALv2`) or
the Server Side Public License v1 (`SSPLv1`) as set out in `LICENSE.txt`.
`REDISCONTRIBUTIONS.txt` records the continued BSD-3-Clause treatment of the
applicable portions described there. The fork-specific Windows portability
code and modifications retain their BSD-3-Clause notices in
`WINDOWS-NOTICES.txt`.

The 7.4 Windows source and binary distributions must preserve, without
renaming or omission:

- `LICENSE.txt`;
- `REDISCONTRIBUTIONS.txt`;
- `WINDOWS-NOTICES.txt`; and
- `THIRD-PARTY-NOTICES.txt` plus the packaged CC0, GCC Runtime Library
  Exception, GPLv3, and MinGW-w64 runtime license texts.

The old 7.2 `COPYING`/lowercase `license.txt` package convention is not the
7.4 license payload. In particular, a Windows case-insensitive filesystem must
not be used to collapse differently named historical license files into an
ambiguous result. Publication requires explicit review of the selected license,
source/object distribution obligations, notices, package metadata, and any
downstream MSI, NuGet, or Chocolatey metadata. This document is an engineering
guide, not legal advice.

### Linux/POSIX and Windows behavior differences

| Area | Original Redis 7.4.11 on Linux/POSIX | This Windows port |
| --- | --- | --- |
| Event loop | A POSIX backend such as `epoll` or `kqueue` | IOCP with synthetic FDAPI descriptors and one-shot readiness rearming |
| Network transports | TCP, optional Unix sockets, and optional TLS builds | TCP over IPv4/IPv6 only in the standard package; Unix sockets and TLS modes are rejected |
| Client I/O threads | Multiple client read/write I/O threads may be configured | `io-threads 1` and `io-threads-do-reads no` are required and enforced at startup |
| Background persistence | POSIX `fork()` copy-on-write child | QFork launches a fresh Windows process and maps the Redis heap at matching virtual addresses |
| Address randomization | Normal PIE/ASLR conventions | Client tools enable ASLR and NX; server aliases keep a fixed image for QFork |
| Lua allocator | Dedicated jemalloc arena plus a private explicit tcache | Dedicated arena retained; QFork builds use `MALLOCX_TCACHE_NONE` and do not create/destroy the private Lua tcache |
| BIO completion notification | Pipe readiness follows the selected POSIX event backend | IOCP handler drains and explicitly rearms the one-shot completion pipe |
| Crash/watchdog path | POSIX signals, `sigaction`, and SIGALRM software watchdog | Native SEH and abort reporting; no POSIX signal recursion contract and no functional SIGALRM watchdog |
| Interactive CLI | POSIX terminal/TTY handling | Native `ReadConsoleInput` and ANSI console translation for a real console; separate binary fake-TTY path for tests |
| ACL connection close | Descriptor teardown is normally observed immediately by tests | Revocation is immediate, but Winsock close-after-reply draining can briefly retain the client in `CLIENT LIST` |
| Native modules | Usually ELF shared objects; module fork API available | x64 PE DLLs; module-created fork children are unsupported and QFork persistence callbacks have a restricted contract |
| Service integration | Daemon/systemd/upstart/syslog conventions | Console or Windows SCM service with Windows Application Event Log support |
| Benchmark startup | Initial connection setup depends on the POSIX client path | Initial TCP connections complete before IOCP attachment and before measured time starts |
| Distribution | Source/install conventions vary | Flat Windows x64 ZIP after release gates; no MSYS2 or MinGW installation is required at runtime |

The single client-I/O-thread restriction does not mean the whole process has
only one thread. Redis still uses background I/O and other internal workers
where supported. It means client read/write ownership remains on the main
thread because the Windows IOCP, FDAPI, and QFork combination has not been
qualified for upstream's multi-threaded client-I/O mode.

### Networking, FDAPI, CLI, and benchmark behavior

#### IOCP and transports

The server uses Windows IO completion ports rather than a POSIX readiness
backend. The FDAPI layer presents Redis with small synthetic file descriptors
that map to Winsock sockets, files, pipes, or Windows handles. Code and modules
must not assume that one of these values is a raw `SOCKET`, CRT descriptor, or
POSIX file descriptor, nor bypass the owning API to close or duplicate it.
IOCP readiness is often one-shot, so a handler that expects another event must
queue the next operation explicitly.

TCP over IPv4 and IPv6 is supported. The standard MinGW package does not build
OpenSSL and rejects TLS listeners, TLS replication, and TLS Cluster links rather
than accepting settings it cannot honor. Unix-domain sockets are unsupported
and an active `unixsocket` configuration is rejected. Use a separate trusted
TLS proxy or VPN only after evaluating its authentication, failure, timeout,
and operational model; it is not equivalent to a Redis TLS build.

Listener setup uses Winsock exclusive-address behavior rather than depending
on the POSIX `SO_REUSEADDR` model. After stop or crash, deployment automation
must wait for the exact old process to exit and for its port to close before
starting a replacement. `tcp-keepalive` is translated to Winsock
`SIO_KEEPALIVE_VALS`: Redis supplies the initial and retry timing while Windows
retains control of the remaining probe/failure policy. Validate host, firewall,
proxy, and load-balancer idle timeouts together.

Protected mode recognizes `127.0.0.1` and `::1` as loopback. The packaged
examples use the conservative `127.0.0.1` bind; add IPv6 or non-loopback
addresses deliberately and secure them with ACLs, authentication, firewall
rules, and transport protection. Configuration `include` paths are literal on
Windows: POSIX wildcard expansion such as `conf.d/*.conf` is unavailable, so
list every file explicitly.

Startup fails if `io-threads` is not `1` or if `io-threads-do-reads` is `yes`.
Treat that failure as an unsupported configuration, not a tunable warning.

#### BIO completion pipe

Redis 7.4 uses a pipe to notify the event loop about completed background I/O
work, including lazy-free work used by synchronous database flushes. POSIX
readiness backends naturally report later bytes. On this IOCP port, read
readiness is one-shot: the Windows handler drains the notification pipe and
then calls the IOCP rearm path before dispatching completions. Without the
rearm, one `FLUSHDB` can finish while the next client waits indefinitely.

Release tests must exercise at least two successive synchronous `FLUSHDB`
operations, verify the resulting `DBSIZE`, and confirm that the server remains
responsive. Any future completion-pipe consumer must preserve the same
drain-then-rearm ownership rule.

#### Real console, redirected I/O, and fake TTYs

In an actual Windows console, `redis-cli` uses `ReadConsoleInput` for keyboard
events and the native ANSI console translator for interactive output. This is
the supported human-interactive path and must be tested in a real console, not
inferred from redirected test results.

The test-only `FAKETTY_WITH_PROMPT` mode is deliberately different. It treats
stdin as a binary pipe, reads through ordinary descriptors, uses a fixed
80-column width, and relies on blocking, flushed Tcl writes so prompt-driven
tests cannot deadlock. `FAKETTY` can make output take TTY-oriented formatting,
but it does not turn redirected stdin into a Win32 console. Redirected
stdout/stderr bypass the console ANSI parser and use CRT byte writes. Raw RESP,
RDB, and pipe output uses binary mode to prevent CR/LF translation.

Neither fake-TTY environment variable is a deployment interface. Scripts
should use non-interactive CLI modes and must not depend on the prompt parser,
console escape translation, or console window width.

#### ACL close timing

ACL deletion or revocation follows upstream semantics and immediately removes
the client's authorization. The Windows close-after-reply path may retain the
socket briefly so Winsock can drain the final response. During that interval,
`CLIENT LIST` can still show the revoked connection even though it cannot
continue authorized work. Tests and orchestration must wait with a bounded
poll for disappearance instead of assuming POSIX-immediate descriptor teardown.

#### `redis-benchmark` timing

On Windows, `redis-benchmark` completes its initial TCP connections before it
attaches those clients to the IOCP event loops and before the measured interval
begins. A high client count or remote target can therefore make startup visibly
longer without that time appearing in reported request latency or throughput.
Connection-establishment performance must be measured separately when it
matters.

With `-k 0`, replacement connections occur during the measured run; their cost
can reduce throughput or pause a worker loop, and per-request timing resumes
after reconnect. Release integration coverage proves functional benchmark
operation only. A release performance claim requires an explicit, repeatable
Windows benchmark protocol, recorded hardware/configuration, warmup, multiple
runs, and an approved regression threshold.

### Windows text, naming, and filesystem contract

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
points, and other reparse points in Redis-owned trees. Multi-part AOF
old-style/upgrade filename identity follows the same case-insensitive rule.
Atomic replacement is same-volume only and uses write-through `MoveFileExW`;
Windows has no direct equivalent of POSIX directory `fsync()`. Storage caches
and transient sharing
violations from antivirus, backup, or indexing software can therefore still
affect crash durability or cause an operation to fail after its bounded retry.

### Configuration contract

The packaged `redis.windows.conf` and `redis.windows-service.conf` are Windows
compatibility templates, not complete replacements for reviewing upstream
`redis.conf`. Before release, every active template directive must be checked
against Redis 7.4.11. A deployment should compare its configuration with the
upstream-aligned file and then apply these intentional Windows choices:

| Setting | Windows package contract | Notes |
| --- | --- | --- |
| `bind` | `127.0.0.1` in the examples | Add `::1` or non-loopback addresses only after a security review |
| `port` | Plain TCP listener | Standard package has no TLS listener |
| `unixsocket` | Disabled and unsupported | Remove active Unix-socket directives |
| `tls-port`, `tls-replication`, `tls-cluster` | Disabled and rejected | OpenSSL is not included |
| `io-threads` / reads | `1` / `no` | Other values fail startup |
| `repl-diskless-sync` | `no` in Windows examples | Diskless QFork sync remains a workload-specific option requiring validation |
| Console logging | Empty `logfile`; Event Log off | Writes to the launching console |
| Service logging | File log plus Event Log | Paths resolve under the service process rules below |
| `appendonly` | `no` in examples | Enabling it requires managing the complete multi-part AOF directory |
| `persistence-available` | `yes` for normal use | Windows-only `no` is a diagnostic mode, not production tuning |

Keep `daemonize no` and `supervised no`; Windows uses a console process or the
SCM service interface. `daemonize yes` does not create a POSIX daemon and can
attempt an unsuitable default pidfile path. Linux OOM-score adjustment, THP
checks, process-title controls, systemd/upstart, and
POSIX signal behavior do not map directly to this build. Enabling unsupported
Linux-only controls can fail startup or `CONFIG SET`.

On Windows, `syslog-enabled yes` selects the Application Event Log and
`syslog-ident` is included in message text. `syslog-facility` is not registered
by the Windows parser; remove or comment it out because an active directive
makes startup fail. Review Redis 7.4's `hide-user-data-from-log` setting for the
deployment's diagnostics/privacy balance. Also review the 7.4 connection-rate
settings rather than copying an older configuration unchanged.

`CONFIG REWRITE` requires write permission on the configuration directory.
Relative paths in an SCM service process resolve from the executable directory;
paths discovered during installation can also depend on the elevated install
command's current directory. Prefer absolute paths for configuration, includes,
data, AOF, ACL, log, module, and Sentinel state files, and grant only the service
identity the required access.

The Windows-only `persistence-available no` option deliberately removes
commands that need QFork persistence or full-sync state. It exists for isolated
diagnostics and service tests, not as a general way to run production Redis.

Cluster configuration is atomically replaced and uses a companion
`<cluster-config-file>.lock` held with `LockFileEx` for the life of the node.
Each node needs a distinct writable path. The lock file's presence is normal;
only the held OS lock indicates ownership, so do not delete it merely because
it exists or treat it as portable dataset state.

### Persistence, QFork, Lua, and replication

#### QFork and fixed virtual addresses

Windows background RDB saves, AOF rewrites, and diskless full synchronization
use QFork instead of POSIX `fork()`. QFork starts a fresh copy of the server,
maps the Redis heap at the same virtual addresses with copy-on-write protection,
reconnects selected Redis roots, performs the child operation, and then
discards the child's private writes. It is a Redis persistence mechanism, not a
general-purpose process fork API.

The server and its aliases use `--disable-dynamicbase` and
`--disable-high-entropy-va` so the QFork child can reproduce address-sensitive
heap and image mappings. NX compatibility remains, but reduced ASLR is an
intentional security tradeoff. Account for it in host isolation, network
exposure, patching, ACLs, endpoint protection, and risk review. The final PE
audit must confirm the flags expected by the QFork design rather than applying
a generic hardening tool that silently re-enables incompatible relocation.

This line uses the customized `deps/jemalloc` 5.3.0-redis tree and its Windows
heap/page tracking. Do not replace it with the older 6.2 tree or an unmodified
upstream allocator. QFork needs enough Windows commit/pagefile capacity for
the mapped heap and copy-on-write pages. Capacity planning must include the
real dataset, fragmentation, modules, active defragmentation, and concurrent
background activity.

#### Lua arena and tcache difference

Redis 7.4 allocates Lua VM memory from a dedicated jemalloc arena so Lua code
memory is counted and does not obstruct defragmentation. Upstream also creates
a private explicit Lua tcache for each VM. That tcache is incompatible with
the Windows QFork external heap's 4 MiB page/fill metadata.

On `_WIN32` QFork builds, Lua keeps the dedicated arena but allocates with
`MALLOCX_TCACHE_NONE`; it does not create or destroy the explicit private
tcache. Linux and Windows `NO_QFORKIMPL` utility builds retain upstream's
normal tcache path. This is an allocator implementation difference, not a
change to Lua command or Function semantics. Release validation must include
Lua `EVAL`, Functions, memory accounting, persistence/reload, and QFork child
activity in the same build.

Lua debugging remains synchronous on Windows. Use `SCRIPT DEBUG sync` or
`redis-cli --ldb-sync-mode`. A forked debugger session is unsupported because
QFork is not a general interactive fork implementation.

#### RDB, AOF, and replication

Redis 7.4 writes RDB format version 12. Redis 7.2 RDB version 11 files remain
loadable by 7.4, but Redis 7.2 cannot load a newly written RDB12 file. AOF
continues to use the Redis 7 multi-part manifest layout under
`appenddirname`; back up, restore, and move the entire directory, including the
manifest and every referenced base/incremental file.

Windows sharing, close, and rename rules differ from POSIX. The port adapts
temporary persistence files and atomic replacement, but a file cannot be
removed while an incompatible handle remains open. Backups must also include
RDB files, configuration, ACL data, Sentinel state, and native module binaries.

Disk-backed and diskless full synchronization are supported through QFork.
The Windows examples prefer `repl-diskless-sync no`; enabling diskless sync
requires workload-specific validation of network failure, authentication,
memory pressure, child cleanup, and replica load modes. For an RDB-only full
sync, the Windows sender half-closes and drains the peer before final close, or
until `repl-timeout`, so overlapped bytes are not discarded. Failed QFork
creation, socket handoff, load, or cleanup must not leave a child process or a
partial persistence file.

### Redis 7.2 to 7.4 upgrade boundaries

Redis 7.4.11 can load a 7.2.14 RDB11 dataset, so the supported direction is to
back up the complete 7.2 deployment and start 7.4 against a copy. The reverse
direction is not symmetric:

- Redis 7.4 writes RDB12 even if the application has not yet used a new 7.4
  command. Once 7.4 has persisted the dataset, do not plan an in-place binary
  downgrade to 7.2.
- Redis 7.4 adds expiration of individual hash fields through `HEXPIRE`,
  `HPEXPIRE`, `HEXPIREAT`, `HPEXPIREAT`, `HPERSIST`, `HEXPIRETIME`,
  `HPEXPIRETIME`, `HTTL`, and `HPTTL`. Their state is represented by the new
  hash-field expiration structures and RDB12 encoding. AOF or replication
  streams containing these commands are unsuitable for 7.2.
- The new hash-field expiration engine adds active expiration behavior,
  `hexpired` keyspace events, `subexpiry` keyspace information, and related
  memory/expiry accounting. Validate clients that parse `INFO`, keyspace
  notifications, TTL results, or memory metrics.
- Redis 7.4 bounds scripts created through `EVAL` with LRU eviction and exposes
  the `evicted_scripts` metric. Applications that treated every evaluated
  script as permanently cached must use `SCRIPT LOAD`/`EVALSHA` deliberately
  and handle `NOSCRIPT`.
- `ACL LOAD` no longer disconnects all clients. Audit automation that depended
  on the older disconnect side effect, and separately test explicit user
  revocation with the Windows close timing described above.
- Redis 7.4 adds or changes client-visible behavior including `XREAD` with the
  `+` ID, `HSCAN NOVALUES`, same-slot `SORT`/`SORT_RO BY` and `GET` in Cluster,
  `CLIENT KILL MAXAGE`, Lua `os.clock()`, and additional INFO/MEMORY/CLIENT
  metrics. Review command allowlists, ACL categories, proxies, client parsers,
  and monitoring.
- Keep the complete multi-part AOF directory together. New commands in AOF or
  replication streams cannot be replayed by an older server even though the
  directory layout already existed in 7.2.
- Rebuild and retest every native module against the 7.4.11
  `src/redismodule.h`. Never carry a Linux `.so` or assume that a 7.2 Windows
  DLL is ABI- and behavior-safe merely because it loads.
- Review every active configuration directive against the 7.4.11 examples.
  Do not copy TLS, Unix-socket, client-I/O-thread, Linux supervision, or POSIX
  path assumptions into the Windows deployment.

A conservative standalone upgrade stops writes, takes an offline-consistent
backup, verifies the backup with the 7.2 checkers, starts 7.4.11 on a copy,
tests the application and persistence cycle, and retains the untouched 7.2
backup for rollback to a separate environment. Replication, Sentinel, and
Cluster upgrades require the normal upstream version-ordering and failover
planning plus Windows-specific QFork, port-close, and service checks. Do not
attempt rollback by pointing 7.2 at files already rewritten by 7.4.

### Native modules

Native modules must be x64 Windows PE DLLs built against this tree's
`src/redismodule.h`. Test fixtures may retain a `.so` filename for upstream
harness compatibility, but their contents are Windows DLL images. The portable
package does not bundle application modules.

The MinGW server uses the fork's small native `LoadLibraryExW`/
`GetProcAddress` adapter for module loading. The former LGPL dlfcn-win32 shim
is not part of this release, and CLI/benchmark binaries do not link a dynamic
loader adapter. Module load/unload and QFork image restoration must still be
validated with real PE test modules before tagging.

The general `RedisModule_Fork`, child heartbeat/exit, and fork-child kill API
pointers are not populated in the Windows module API table. A module must
feature-detect those APIs and avoid them. RDB, AUX, AOF-rewrite, and
persistence-event callbacks that execute in a QFork child have this narrower
contract:

- callback code and writable globals must live in the primary module image;
- fork-visible data must be plain data or Redis/module-allocator memory, and
  inherited Redis/module containers must be treated as immutable;
- child-local scratch allocation must not be linked back into inherited state;
- code must not depend on process-private CRT/C++ state, libc `malloc` state,
  `thread_local`/dynamic TLS, `DllMain` or `atexit` effects, mutable helper-DLL
  globals, Win32 handles, sockets, mutexes, or concurrently changing module
  threads;
- delay imports, CFG/XFG, unsupported static TLS, unsafe writable PE sections,
  and extended load-config state can be rejected by the QFork module-image
  validator; and
- APIs that require the parent IOCP event loop, clients, blocking operations,
  timers, new threads, propagation, or mutation of the inherited snapshot are
  unavailable in the persistence child.

Windows-only `RedisModule_Win32Pipe`, `RedisModule_Win32PipeRead`,
`RedisModule_Win32PipeWrite`, and `RedisModule_Win32PipeClose` are the supported
pipe primitives for module event-loop integration. A private CRT pipe does not
participate in the process-wide FDAPI mapping. Modules must handle nonblocking
partial reads/writes and follow descriptor ownership rules.

Parent-process Module API behavior otherwise follows upstream 7.4.11,
including the 7.4 additions. Release qualification requires the full Module API
suite, real Windows PE fixtures, load/unload and persistence callbacks, module
defragmentation, RDB/AOF reload, crash isolation, and a QFork cycle.

### Crash reporting and watchdog behavior

Windows crash diagnostics are owned by the native vectored/SEH and abort
handlers in `Win32_StackTrace`. They should produce the Windows exception and
stack information available from the running executable and its symbols.
Redis' POSIX `sigaction` crash handlers, recursive signal-log assertions, and
SIGALRM/`setitimer` software watchdog do not exist in this portability layer.
`watchdog-period` therefore does not provide the upstream POSIX watchdog
guarantee.

Changing `crash-log-enabled` does not install or remove the native handler in
the same manner as a POSIX build. Skipping upstream signal-recursion tests on
Windows is not evidence that native crash reporting works. Release gates must
exercise a controlled native exception and abort in isolated processes, retain
the resulting log, and verify that no test service, listener, or QFork child is
left behind.

### Windows service, Event Log, and Sentinel helpers

Run service management from an elevated Windows command prompt. The service
action is the first argument and `--service-name` must precede the Redis
configuration and overrides:

```bat
redis-server.exe --service-install --service-name Redis7411 redis.windows-service.conf
redis-server.exe --service-start --service-name Redis7411
redis-server.exe --service-stop --service-name Redis7411
redis-server.exe --service-uninstall --service-name Redis7411
```

Installation creates an automatic-start service using
`NT AUTHORITY\NetworkService` by default but does not start it. Uninstallation
requests deletion but does not stop a running service; retain the exact
install/start/stop/uninstall sequence. Use a unique service name and exact PID
when testing. Never stop or remove an unrelated installed Redis service.

SCM can report `Running` before Redis has completed listener initialization.
After every start or restart, wait for an authenticated `PING` and the
deployment's readiness checks. `STOP` and `PRESHUTDOWN` notifications enter the
graceful shutdown path on the main thread. Before replacing or restarting a
binary, wait for SCM state, exact process exit, and port closure.

Console mode writes to stdout when `logfile` is empty or `stdout`. In service
mode, the configured file sink remains active and Application Event Log output
is enabled. All named Redis services share the Event Log source `redis`. The
first service installation registers the message-resource path; installing
another service name does not refresh it. Uninstalling any named Redis service
can remove the shared source registration and impair message rendering for
surviving services until a Redis service is installed again. Coordinate
side-by-side service lifecycle and keep the registered executable available.

Sentinel notification and reconfiguration helpers use Windows process creation,
wait, and termination semantics. Batch scripts require an explicit interpreter
such as `cmd.exe /c`; they are not POSIX `execve` targets. Validate quoting,
timeouts, retry status, working directory, credentials, and file permissions
with the exact production helper.

### Package contents and deployment checklist

The release-gated flat x64 ZIP must contain at least the server and Sentinel
alias, CLI, benchmark, RDB/AOF checkers, Event Log resource, Windows console,
service and Sentinel examples, release notes, this guide, and the complete
license/notice payload listed above. Runtime executables must not require an
external MSYS2 or MinGW installation. The legacy Visual Studio/MSI projects are
best-effort and are not substitutes for validating the MinGW package.

Before accepting the CI-only `mingw-7.4` qualification, all of the following are required against
the exact candidate commit:

1. Perform a clean `./build-mingw.sh -j2` build and verify server, CLI,
   benchmark, checker, Sentinel alias, and Event Log resources identify the
   intended 7.4.11 source.
2. Run the full root, dedicated Cluster, dedicated Sentinel, and full Module
   API suites with the repository-owned MinGW wrappers.
3. Run focused hash-field-expiration/RDB12, crafted corrupt-stream `RESTORE`,
   ACL close, CLI real-console and fake-TTY, two-`FLUSHDB` BIO, AOF, AOF-race,
   replication, active-defrag, QFork Lua/Function, and module persistence tests.
4. Run long RDB save/reload, AOF rewrite/restart, disk-backed and diskless full
   synchronization, QFork allocation, failpoint, and repeated restart soaks
   under representative memory and Windows commit pressure.
5. Build `Redis-x64-7.4.11-mingw-r1.zip` in CI, verify its SHA-256 file and manifest,
   and audit PE architecture, imports, fixed-address/ASLR flags, resources,
   license files, absence of build/debug artifacts, and absence of external
   MinGW runtime dependencies.
6. Extract the archive into a never-before-used directory and run only the
   extracted binaries: version checks, authenticated command smoke, RDB/AOF
   checker use, persistence/restart, Sentinel/Cluster where applicable, and
   the benchmark functional and approved performance protocol.
7. From an elevated token, install a uniquely named isolated service, verify
   the exact executable and two distinct start/restart PIDs, authenticated
   reads/writes, graceful stop, file logging, Event Log message rendering,
   uninstall, process exit, port closure, service deletion, and test-directory
   cleanup.
8. Review deployment configuration, license selection and notices, source
   publication obligations, release notes, behavior documentation, archive
   checksum, and the exact commit/tag relationship. Create and push the
   annotated tag only after every required gate is accepted.

Before deploying the accepted archive:

1. Back up the RDB, complete multi-part AOF directory, configuration and ACL
   files, Sentinel/Cluster state, module DLLs, and service command line. Keep an
   untouched 7.2-compatible copy for rollback to a separate environment.
2. Rebuild native modules for this exact source and audit every QFork child
   callback against the restricted Windows contract.
3. Review bind/protected-mode, ACL/authentication, firewall and transport
   security, absolute paths, directory ACLs, service identity, Event Log
   registration, Windows commit/pagefile capacity, antivirus/EDR exclusions,
   backup software, and port-close timing.
4. Compare every active configuration directive with Redis 7.4.11; remove TLS,
   Unix-socket, client-I/O-thread, Linux daemon/supervision, wildcard include,
   and unsupported syslog settings.
5. Exercise representative application commands, hash-field expiration,
   scripts/Functions, `BGSAVE`, AOF rewrite, restart/reload, replication,
   Cluster, Sentinel, modules, service restart, monitoring, backup, and restore
   using the production configuration and dataset scale.
6. Record the annotated tag, source commit, archive checksum, host/toolchain,
   configuration, module builds, and test evidence. Do not downgrade in place
   after Redis 7.4 has written RDB12 or 7.4-only AOF/replication commands.

## Redis 7.2 (historical line)


### Scope and release identity

This is an unofficial Windows x64 integration of the Redis 7.2.14 behavior
baseline, including its upstream security fixes, onto this fork's IOCP
networking, FDAPI descriptors, QFork persistence,
Windows service/Event Log, console, and MinGW64 build layers. The source tree
reports `7.2.14`; the canonical `mingw-7.2` branch is the maintenance line.
The immutable `v7.2.14` tag identifies the original promotion archive. The
corrected Windows maintenance revision is identified as `v7.2.14-windows.1`
and packaged as `Redis-x64-7.2.14-mingw-r1.zip` after its gates pass.

This guide documents behavior that differs from the original Redis 7.2.14
Linux/POSIX distribution, plus the upgrade boundaries that matter when moving
from this fork's Redis 6.2 line. Redis command, protocol, persistence-format,
replication, Cluster, Sentinel, ACL, Lua, and Function behavior otherwise
follows upstream Redis 7.2.14. See `00-RELEASENOTES` for the complete upstream
release history and command-level compatibility notes.

The required clean build, focused and full test suites, package extraction,
long persistence soak, and exact service-restart gates are the maintenance
revision's release gates. The original `v7.2.14` archive remains immutable.

#### Upstream security-fix provenance

The 7.2.14 source baseline includes the applicable upstream security fixes for
Lua parser/runtime isolation, blocked-client eviction, RESTORE/RDB validation,
and full-sync while a yielding script or Function is running. The Windows
full-sync path retains an additional IOCP disconnect cleanup guard in
`12c1730f7`; do not replace it with the unadapted POSIX patch. XACKDEL-specific
fixes are not applicable because that command is absent from this 7.2 line.
The standard package is x64 and excludes TLS. Visual Studio/MSI,
clean-machine, antivirus, and unrelated external deployment checks are not
covered by this local release matrix.

### Linux/POSIX and Windows behavior differences

| Area | Original Redis 7.2.14 on Linux/POSIX | This Windows port |
| --- | --- | --- |
| Event loop | OS-specific POSIX backend such as `epoll` or `kqueue` | IOCP with synthetic FDAPI descriptors |
| Network transports | TCP, optional Unix sockets, and optional TLS builds | TCP only in the standard package; Unix sockets are rejected and TLS is not built |
| Client I/O threads | Configurable multi-threaded reads/writes | `io-threads 1` and `io-threads-do-reads no` are required and enforced at startup |
| Background persistence | POSIX `fork()` copy-on-write child | QFork starts a fresh Windows process and maps a copy-on-write Redis heap at fixed virtual addresses |
| Native modules | Usually ELF shared objects; module fork API available | x64 PE modules; module-created fork children are unsupported and the fork API entries are unavailable in the Windows module table; persistence callbacks have a restricted QFork contract |
| Lua debugger | Synchronous or forked debugger session | `SCRIPT DEBUG sync` only; forked `SCRIPT DEBUG yes` is rejected when execution starts |
| Daemon/supervision | `daemonize`, systemd/upstart integration, Unix signals | Console process or Windows SCM service; no POSIX daemon or systemd/upstart behavior |
| System integration | syslog, Linux OOM score, THP checks, CPU affinity, process titles | Windows Application Event Log and SCM; the listed Linux controls do not have equivalent behavior in this build |
| Distribution | Source build/install conventions vary by platform | Flat x64 ZIP; no external MinGW runtime, MSYS2, Tcl, or Visual Studio installation is required at runtime |

### Networking, CLI, and benchmark behavior

- The server uses the Windows IOCP event backend and the fork's FDAPI mapping.
  TCP over IPv4 and IPv6 is supported. The standard package rejects a configured
  Unix-domain socket and rejects TLS listeners, TLS replication, and TLS Cluster
  links because OpenSSL is not included.
- Listener setup uses Winsock's exclusive-address behavior rather than relying
  on the POSIX `SO_REUSEADDR` model. A port can remain unavailable briefly after
  a process exits; service automation must wait for the exact old process and
  port to close before starting a replacement.
- `tcp-keepalive` is translated to Winsock `SIO_KEEPALIVE_VALS`: the configured
  interval controls the first probe and the retry interval is derived from it,
  while the remaining probe/failure policy is controlled by Windows. Validate
  firewalls, load balancers, and idle timeouts on the target host.
- Protected mode recognizes both `127.0.0.1` and `::1` as loopback. The shipped
  server examples bind only to `127.0.0.1`; add `::1` deliberately if IPv6
  loopback is required and validate the host's IPv6 configuration.
- Configuration `include` paths are literal on Windows. POSIX wildcard/glob
  expansion is not available, so list every included file explicitly instead of
  using a pattern such as `conf.d/*.conf`.
- Server I/O-thread mode is deliberately unavailable. Startup fails when
  `io-threads` is not 1 or `io-threads-do-reads` is `yes`; this prevents unsafe
  client ownership and QFork interactions in the IOCP path.
- Windows raw-pipe input and `redis-cli --rdb` file or standard-output paths use
  binary mode, so the CRT does not translate line endings in RESP or RDB bytes.
- `redis-benchmark` completes its initial TCP client connections before attaching
  them to IOCP event loops and before timing begins. Large or remote client sets
  may therefore take longer to initialize. With `-k 0`, replacement connections
  happen during the measured run and may reduce throughput or briefly pause a
  worker loop; per-request timing begins after the reconnect.

### Packaged configuration defaults

The packaged `redis.windows.conf` and `redis.windows-service.conf` are
Windows-oriented compatibility templates, not substitutes for reviewing every
Redis 7.2 option. Their active directives are validated by the release tests;
comments retained for less common options are reference material. Compare a
deployment configuration with the source tree's upstream-aligned `redis.conf`
and then apply these intentional package differences:

| Setting | Packaged Windows examples | Upstream 7.2.14 example/default | Notes |
| --- | --- | --- | --- |
| `bind` | `127.0.0.1` | `127.0.0.1 -::1` in `redis.conf` | Conservative IPv4-loopback package default |
| `repl-diskless-sync` | `no` | `yes` | The examples prefer disk-backed full synchronization; diskless QFork replication remains supported and tested |
| `io-threads` / reads | `1` / `no` | Same runtime defaults | Explicit in the Windows templates because other values are rejected |
| Console logging | empty `logfile`; Event Log off | empty `logfile`; syslog off | Writes to the launching console |
| Service logging | `server_log.txt`; Event Log on | Not applicable | Writes to both the file and Windows Application Event Log |
| `appendonly` | `no` | `no` | Enable only after planning the complete multi-part AOF directory |

Windows is not a POSIX daemon environment. Keep `daemonize no` and
`supervised no`; use the console or the Windows service interface. Setting
`daemonize yes` does not detach on Windows; it logs a warning and still attempts
the best-effort default POSIX pidfile path (`/var/run/redis.pid`) unless an
explicit writable pidfile is configured, so do not use it. Linux `oom-score-adj`
is unsupported and enabling it makes startup/`CONFIG SET` fail. Transparent-
huge-page checks, CPU-affinity and
process-title controls, watchdog signal behavior, and other POSIX signal
semantics do not map directly to this build. Windows crash reporting and
service stop notifications use the native portability layer instead.

On Windows, `syslog-enabled yes` selects the Application Event Log and
`syslog-ident` is included in the message text. `syslog-facility` is unsupported
and is not registered by the Windows parser; remove or comment it out because
an active `syslog-facility` directive makes startup fail.

`CONFIG REWRITE` needs write access to the configuration file's directory.
Relative paths in an SCM service process resolve from the executable directory.
At installation time, path discovery resolves relative `dir` and include paths
from the elevated install command's current directory, and the installer grants
its default `NT AUTHORITY\NetworkService` account access to the discovered
configuration/include and data directories. Use absolute paths or install from
the extracted executable directory. Grant permissions separately for ACL files,
log directories, modules, and any other external path.

The Windows-only `persistence-available no` option is intended for diagnostics
and deliberately removes commands that require QFork persistence or full-sync
state. It is not a general production tuning option.

Cluster configuration files are atomically replaced on Windows and use a
companion `<cluster-config-file>.lock` held with `LockFileEx` for the life of
the node. Give each node a distinct writable configuration path. Treat the
companion as a runtime lock artifact rather than portable dataset state: its
mere presence is normal, it need not be backed up or deleted, and only the
held OS lock—not file existence—indicates that another node owns the path.

### Persistence, QFork, and replication

Windows background RDB saves, AOF rewrites, and diskless full synchronization
use QFork instead of POSIX `fork()`. QFork launches a fresh copy of the server,
maps the Redis heap at the same virtual addresses with copy-on-write protection,
reconnects selected Redis roots, performs the requested child operation, and
then discards the child's private writes. It is a persistence mechanism, not a
general-purpose fork implementation.

The MinGW executables intentionally disable dynamic-base and high-entropy ASLR
so the mapped heap can occupy the same addresses in parent and child. The port
uses the bundled jemalloc 5.3.0 tree and its Windows heap/page-tracking hooks;
do not substitute the completed 6.2 line's jemalloc 5.2.1 tree. QFork also
depends on sufficient Windows commit/pagefile capacity for the mapped heap and
copy-on-write pages. Size and monitor system commit for the real dataset,
fragmentation, modules, and concurrent background work rather than relying on
old fixed `--maxheap` or pagefile formulas.

Disabling image-base randomization is a deliberate QFork compatibility and
security tradeoff. The executables retain NX compatibility, but deployments
must account for the reduced ASLR protection when evaluating host isolation,
network exposure, patching, and access controls.

Redis 7.2 multi-part AOF uses a manifest under the configured `appenddirname`
directory (default `appendonlydir`), with base and
incremental files, rotations, history cleanup, and atomic replacement. Windows
close/share/rename rules are handled by this port, but backup and restore must
always treat the entire AOF directory as one unit. Keep the manifest, every
referenced AOF part, RDB files, configuration, ACL data, Sentinel state, and
module binaries together.

Disk-backed and diskless full synchronization are both supported. The package
examples intentionally set `repl-diskless-sync no`, unlike upstream's default
of `yes`; enable it only after validating network, memory, credentials, module
loading, and QFork child cleanup under the intended workload. Replica diskless
load modes (`disabled`, `on-empty-db`, and `swapdb`) retain upstream semantics.
Failed child creation, socket handoff, or load must not leave a stale QFork
process or a partial persistence file.

For an RDB-only full sync, the Windows sender half-closes its socket and drains
the peer before final close (or until `repl-timeout`) so pending overlapped bytes
are not discarded. File cleanup also obeys Windows sharing rules: a file cannot
be unlinked while a conflicting handle remains open, so some replication cleanup
is synchronous and can block or fail until the handle is released.

Active defragmentation is supported through the customized jemalloc allocation
hints and is disabled by default, as upstream. The Windows regression suite
covers real movement together with a QFork save/reload cycle; production users
should still measure latency and memory behavior on their own dataset.

### Redis 6.2 to 7.2 upgrade boundaries

- Redis 7.2 writes RDB format version 11. Older Redis versions that support only
  an earlier RDB version cannot load a newly written 7.2 RDB. Do not plan an
  in-place binary downgrade after Redis 7.2 has persisted the dataset.
- Redis 7 uses the multi-part AOF directory described above rather than the
  single-file layout used by older releases. Back up and move the complete
  directory, not only `appendonly.aof`.
- Older ziplist-based RDB encodings remain loadable but Redis 7 uses listpack
  encodings for current data structures. Confirm memory and module assumptions
  after conversion and rewrite.
- Redis 7.x adds Functions (`FUNCTION`, `FCALL`, `FCALL_RO`), sharded Pub/Sub,
  list and sorted-set pop families such as `LMPOP`/`ZMPOP`, `WAITAOF`, newer
  `CLIENT` metadata/touch controls, and Cluster shard identity. Replication and
  AOF streams containing new commands are not suitable for an older server.
- Rebuild and retest every native module against this tree's `redismodule.h` and
  the QFork restrictions below. Never copy Linux module binaries into this
  package.

### Functions, Lua, and native modules

Redis Functions add persisted engine and library state beyond ordinary
`redisServer` roots. Function load, RDB/AOF serialization, replication load,
and QFork child reconstruction are integrated, but the fresh child does not
inherit a Linux forked Lua runtime. Exercise Function execution in the live
parent and persistence/reload as separate gates.

Lua debugging on Windows is synchronous only. Use `SCRIPT DEBUG sync` or
`redis-cli --ldb-sync-mode`. A non-sync debugger request may be accepted by the
configuration command, but execution is rejected rather than creating a forked
debugger child.

Native modules must be x64 Windows PE images built against this tree's
`src/redismodule.h`; Linux ELF `.so` files are not loadable. The test harness
uses a `.so` filename for compatibility, but those files are Windows DLLs. No
modules are bundled in the portable ZIP.

The general `RedisModule_Fork`, child heartbeat/exit, and fork-child kill API
pointers are not populated in the Windows module API table. Module-created fork
children are unsupported; modules must feature-detect these pointers and avoid
them rather than dereferencing a missing API. RDB, AUX, AOF-rewrite, and
persistence-event callbacks that run in a QFork child have a narrower contract:

- The callback and its writable globals must live in the primary module image.
  Do not depend on mutable state in helper DLLs.
- Windows-only `RedisModule_Win32Pipe`, `RedisModule_Win32PipeRead`,
  `RedisModule_Win32PipeWrite`, and `RedisModule_Win32PipeClose` are the
  supported pipe primitives for module event-loop integration. A private CRT
  pipe does not participate in the process-wide synthetic FD map; handle
  nonblocking partial reads and writes.
- Fork-visible data must be plain data or live in Redis/module-allocator memory.
  Treat inherited Redis and module containers as immutable; child-local scratch
  allocation is allowed only when it is not linked back into inherited state.
- Do not depend on process-private CRT/C++ state, `malloc` allocations,
  `thread_local` or dynamic TLS, `DllMain`/`atexit` side effects, Win32 handles,
  sockets, mutexes, or concurrently changing module-thread state.
- Delay imports, CFG/XFG, non-boilerplate static TLS, unsafe writable PE
  sections, and extended load-config state are rejected by the module-image
  validator. The resolved primary DLL is held open without write/delete sharing
  until the QFork child exits.
- APIs requiring the parent IOCP event loop, client networking, blocking work,
  timers, new threads, thread-safe contexts, propagation, or mutation of the
  inherited snapshot are rejected in the persistence child. Parent execution of
  the normal module APIs remains available.

### Service, Event Log, and console behavior

Run service-management commands from an elevated command prompt. The service
action must be the first argument, and `--service-name` must precede the Redis
configuration and overrides:

```bat
redis-server.exe --service-install --service-name Redis7214 redis.windows-service.conf
redis-server.exe --service-start --service-name Redis7214
redis-server.exe --service-stop --service-name Redis7214
redis-server.exe --service-uninstall --service-name Redis7214
```

Installation creates an automatic-start service running as
`NT AUTHORITY\NetworkService`, but does not start it. Uninstallation requests
SCM deletion but does not stop a running service; a running service remains
marked for deletion until it stops and open SCM handles are closed. Retain the
install/start/stop/uninstall sequence. Use a unique service name, absolute
executable/configuration paths when outside the extracted directory, and exact
PIDs when verifying or cleaning up a test. Never stop or remove an unrelated
installed `Redis` service.

SCM can report the service as `Running` before the Redis worker has finished
initializing its listener. After every start or restart, wait for a successful
authenticated `PING` and any deployment-specific readiness checks before
accepting traffic.

SCM `STOP` and `PRESHUTDOWN` notifications are converted into Redis' graceful
shutdown path on the main thread. The service reports stopped only after the
actual worker has exited; callers should still wait for the SCM state, process
exit, and port closure before restart or replacement.

In console mode, Redis writes to stdout when `logfile` is empty or the literal
`stdout`, and to the named file otherwise. `syslog-enabled yes` additionally
writes to the Windows Application Event Log. SCM service mode enables
Application Event Log output automatically and retains the configured logfile
sink, so the packaged service example writes both `server_log.txt` and the
Application Event Log.

All named Redis services share the Event Log source named `redis`. The first
installation supplies the registered message-resource path; installing another
name does not refresh it. Uninstalling any one named Redis service removes the
shared registration and may break message rendering for surviving services
until a Redis service is installed again. Coordinate side-by-side service
removal and keep the registered executable path available.

Sentinel's external notification and reconfiguration helpers use Windows
process creation and wait/terminate APIs. A timed-out helper exits with a
failure status and is retried; do not assume POSIX signal-kill or shell quoting
semantics when deploying `notification-script`, `client-reconfig-script`, or
`deny-scripts-reconfig` hooks. Batch or command scripts need an explicit
interpreter such as `cmd.exe /c`; they are not direct POSIX `execve` targets.

### Package contents and deployment checklist

The flat x64 ZIP contains `redis-server.exe`, the `redis-sentinel.exe` alias,
`redis-cli.exe`, `redis-benchmark.exe`, RDB/AOF checkers, `EventLog.dll`, the
console/service/Sentinel examples, `README.txt`, release notes, license, and
this guide. The built-in service registers the message resource embedded in
`redis-server.exe`; `EventLog.dll` is also shipped as a standalone legacy
message-resource artifact. The executables statically link the MinGW runtime
components used by the build; normal Windows system DLLs remain expected
imports.

The historical Visual Studio, NuGet, Chocolatey, and MSI files under `msvs/`
consume an older signed-binary layout and are not the Redis 7.2 package path or
a release gate. Use `package-mingw.sh`, retain its adjacent SHA-256 file, and
record the exact source commit that produced the archive.

Before deployment:

1. Back up the RDB, complete multi-part AOF directory, configuration and ACL
   files, Sentinel state, and module binaries.
2. Rebuild native modules for this exact ABI and review every QFork persistence
   callback against the restricted contract.
3. Review bind/protected-mode, ACLs, authentication, absolute paths, directory
   permissions, service identity, Windows commit/pagefile capacity, and
   antivirus policy.
4. Run representative `PING`, authentication, command, `BGSAVE`, AOF rewrite,
   restart/reload, replication, Cluster, Sentinel, module, and exact service
   restart checks with the production configuration and workload.
5. Retain the source commit, package checksum, and test evidence. Do not
   downgrade after writing Redis 7.2-specific commands or persistence formats.

## Redis 6.2 (historical line)


### Scope and identity

This is an unofficial Windows x64 port of the Redis 6.2.22 core, based on
upstream commit `b0f7a7f4d97`, combined with this fork's IOCP networking,
QFork persistence, Windows service, Event Log, console, and MinGW64 packaging
layers.

The completed Windows line reports `6.2.22` through `INFO server`, executable
`--version` output, module version APIs, RDB metadata, and the portable package
filename. Retain the ZIP checksum and source commit when identifying an exact
Windows build.

RESP2 remains the default protocol, so existing Redis 5 clients normally keep
working. RESP3, ACLs, client-side caching, and other Redis 6 behavior are
opt-in unless configured.

### Commands, protocol, and security

No Redis 5 top-level command was removed. New top-level commands include:

- Security and protocol: `ACL`, `HELLO`, and `RESET`.
- Strings and algorithms: `BITFIELD_RO`, `GETEX`, `GETDEL`, and `STRALGO`.
- Lists, sets, and hashes: `LPOS`, `LMOVE`, `BLMOVE`, `SMISMEMBER`, and
  `HRANDFIELD`.
- Sorted sets and geospatial indexes: `ZMSCORE`, `ZRANDMEMBER`, `ZDIFF`,
  `ZDIFFSTORE`, `ZINTER`, `ZUNION`, `ZRANGESTORE`, `GEOSEARCH`, and
  `GEOSEARCHSTORE`.
- Streams and operations: `XAUTOCLAIM`, `COPY`, and coordinated `FAILOVER`.

Existing commands also gain Redis 6.2 options, including `SET GET/EXAT/PXAT`,
`ZADD GT/LT`, unified `ZRANGE BYSCORE/BYLEX/REV`, `XADD NOMKSTREAM/MINID/LIMIT`,
additional `XPENDING` ranges and idle filtering, `CLIENT PAUSE WRITE`, and
richer client and Sentinel introspection.

ACLs support named users, command categories, key patterns, Pub/Sub channel
patterns, an in-memory ACL log, external ACL files, and `AUTH username
password`. The legacy `requirepass` option remains a compatibility layer for
the `default` ACL user. `HELLO 3` enables RESP3, including push replies used by
client tracking and Pub/Sub. Client-side caching is available through `CLIENT
TRACKING`; its table is bounded by `tracking-table-max-keys`.

The Windows IOCP listener preserves the address family of IPv4 and IPv6
connections. Protected mode recognizes both `127.0.0.1` and `::1` as loopback,
including when replication or Sentinel hostname resolution selects IPv6 first.

### Compatibility changes from Redis 5

Applications should review these Redis 6 behavior changes:

- `SPOP key count` returns an empty collection, rather than null, when the key
  is missing.
- `GEORADIUS`/`GEORADIUSBYMEMBER` with `STORE` or `STOREDIST` now deletes an
  existing destination and returns zero when the source key is missing.
- `PUBSUB NUMPAT` counts unique pattern strings rather than total pattern
  subscriptions.
- `EXISTS` no longer updates LRU/LFU state, and `OBJECT` does not expose
  logically expired keys.
- Expiration of a watched key can invalidate `EXEC`; `SWAPDB` also invalidates
  affected watches.
- Some `AUTH`, `HELLO`, `SELECT`, and `MOVE` errors changed. Clients should not
  depend on exact error strings.
- `SORT` behavior on writable replicas and some RESP3 reply shapes differ from
  Redis 5.
- A requested bind address that is unavailable now aborts startup unless the
  address is prefixed with `-`, such as `-::1`. Addresses already in use still
  fail startup.
- New or extended commands may be written to AOF or replication streams. After
  using them, an older Redis 5 replica or downgrade target may not understand
  the stream.

The RDB format version remains 9, but always back up RDB, AOF, configuration,
Sentinel, and ACL files before upgrading. Test rollback before using Redis
6-only commands or module data.

The old `SLAVEOF` command and `slave-*` configuration spellings remain aliases.
New configurations should use `REPLICAOF` and `replica-*` names.

### Configuration and defaults

The packaged console and service examples bind to `127.0.0.1`, keep protected
mode enabled, leave AOF disabled, use `tcp-keepalive 300`, and use these
snapshot points:

```text
save 3600 1
save 300 100
save 60 10000
```

Review those values when replacing an older Windows configuration. Important
Redis 6 options include:

- ACLs: `aclfile`, inline `user` rules, `acllog-max-len`, and
  `acl-pubsub-default`.
- Networking and performance: `tracking-table-max-keys`,
  `active-expire-effort`, and `maxmemory-eviction-tenacity`.
- Persistence and replication: `repl-diskless-load`, `rdb-del-sync-files`,
  `sanitize-dump-payload`, `lazyfree-lazy-user-flush`, and `masteruser`.
- Cluster and replica behavior: `cluster-allow-replica-migration`,
  `cluster-allow-reads-when-down`, and `replica-announced`.

`CONFIG REWRITE` needs write access to the configuration file's directory.
The Windows service installer grants its NetworkService account access to the
main configuration/include directories and the configured Redis `dir`.
Service-relative paths resolve from the executable directory at runtime, while
install-time ACL discovery resolves them from the install command's current
directory; install from the executable directory or use absolute paths. Grant
permissions separately for external ACL files, log-file directories, modules,
and other paths. Starting Redis with command-line options does not disable the
built-in `save` defaults; use `--save ""` when persistence must be disabled.

Server multi-I/O-thread mode is unavailable in this Windows build. Startup
rejects `io-threads` other than 1 and `io-threads-do-reads yes`; retain the safe
defaults `io-threads 1` and `io-threads-do-reads no`.

The packaged Windows configuration files are intentionally compact examples,
not exhaustive Redis 6 references. Use `CONFIG GET *` and the source tree's
upstream-aligned `redis.conf` for additional options, while ignoring POSIX-only
settings. That upstream reference file is not part of the portable ZIP.

### Persistence and replication

RDB background saves and AOF rewrites use the Windows QFork implementation and
a customized jemalloc 5.2.1 heap-tracking layer. Diskless replication is
supported on both sides: a primary can stream a QFork-generated RDB, and a
replica can use `repl-diskless-load disabled`, `on-empty-db`, or `swapdb`.
`swapdb` retains the old dataset until the new stream is usable and restores
both data and the cluster slot map if loading fails.

Redis 6 replication supports ACL credentials through `masteruser` and
`masterauth`, improved partial resynchronization, full-sync timeouts,
replication progress fields in `INFO`, and `FAILOVER` for coordinated
primary/replica handoff.

QFork is a Windows-specific substitute for the RDB/AOF fork paths, not a
general POSIX `fork()` implementation. Evaluate memory use and fork latency on
production-sized datasets before rollout.

### Cluster and Sentinel

Redis Cluster uses Redis 6.2 command and failover behavior over the Windows
IOCP transport, including replica migration controls, resharding, manual
takeover, diskless `swapdb` recovery, and newer `INFO` error statistics.

The package includes `redis-sentinel.exe`, implemented by the server executable
in Sentinel mode, plus `sentinel.conf`. Sentinel supports ACL-protected
monitored instances (`sentinel auth-user` and `auth-pass`), ACL protection for
Sentinel itself, separate `sentinel-user` and `sentinel-pass` credentials
between Sentinels, stable `SENTINEL MYID`, hostname resolution and announcement
options, command introspection, and configuration rewrite.

Do not enable TLS-only Cluster or Sentinel settings in the standard MinGW
package; TLS is not built into it.

### Modules and Lua debugging

The Redis 6.2 module API is available for native Windows PE modules, including
authentication, command filters, blocked clients and blocked-on-key operations,
timers, streams, keyspace and server events, INFO fields, RDB/AUX persistence,
propagation, scan, lazy-free, and datatype callbacks. Modules must be built for
Windows x64 against this tree's `src/redismodule.h`; Linux shared objects cannot
be loaded. The upstream test build uses a `.so` suffix for harness compatibility,
but the file is still a Windows DLL.

No modules are bundled in the portable ZIP. Existing Redis 5 Windows modules
should be rebuilt and retested before production use.

Callbacks executed inside a Windows QFork persistence child have a narrower
contract than ordinary live-parent module callbacks. A compatible module is a
single x64 PE DLL whose RDB, AUX, AOF-rewrite, and persistence-event callbacks
reside in that primary image. Fork-visible globals must be plain data or point
to memory obtained through the Redis module allocator so the target lives in
the QFork heap. Delay imports, CFG/XFG or other nonzero extended PE load-config
state, and module-defined static TLS are rejected. At each persistence
snapshot, the primary DLL is resolved to its final volume path and held open
without write or delete sharing until the child has terminated.

Persistence callbacks must not depend on process-private CRT/C++ state,
`malloc` pointers, `thread_local` or dynamically allocated TLS, custom
`DllMain`/`atexit` behavior, Win32 handles, sockets, mutexes, helper-DLL mutable
state, or concurrently changing module-thread state. Modules must quiesce or
synchronize their own threads around fork-visible globals. Treat pre-fork
Redis/module-allocator objects as read-only: do not insert into, remove from,
resize, or free snapshot-owned containers or objects. Redis allocation APIs
may be used for child-local scratch objects that are not linked into those
containers. Keep persistence callbacks limited to persistence IO, logging,
Redis strings/contexts, and such scratch allocation; blocking, networking,
process, and thread-safe-context work is unsupported in the QFork child.
Detectable PE or callback-image violations fail module loading or the
background persistence start cleanly.

The general `RedisModule_Fork` family is not exposed on Windows. Active
defragmentation is supported through this port's customized jemalloc allocation
hints; the Windows regression covers real movement with 4 MiB allocator pages
and a QFork save/reload cycle. Lua debugging is supported only in synchronous
mode: use `SCRIPT DEBUG sync` or `redis-cli --ldb-sync-mode`; forked `SCRIPT
DEBUG yes` sessions are unsupported.

### CLI, benchmark, service, and console

`redis-cli` adds ACL authentication (`--user`, `--pass`, `--askpass`), RESP3
(`-3`), RESP3 push display control, URI usernames, command-error exit status
(`-e`), and newer key and memory inspection behavior. `redis-benchmark` adds
ACL users, multi-thread mode, cluster mode, client tracking, error display,
precision control, and HDR Histogram latency accounting.

On Windows, `redis-benchmark` completes its initial TCP client connections
before attaching them to IOCP event loops and before benchmark timing begins.
Very large or remote initial client sets may therefore take longer to
initialize. With `-k 0`, replacement connections occur during the measured run
and can reduce total throughput or pause a worker loop, although per-request
latency timing begins after each reconnect.

Windows raw-pipe input and `redis-cli --rdb` file or standard-output paths use
binary mode, so redirected RESP streams and RDB bytes are not altered by CRT
newline translation.

The Windows service interface remains:

```text
redis-server.exe --service-install [--service-name name] <config and options>
redis-server.exe --service-start [--service-name name]
redis-server.exe --service-stop [--service-name name]
redis-server.exe --service-uninstall [--service-name name]
```

Service management requires elevation. The default installed service runs as
`NT AUTHORITY\NetworkService`. Service mode always logs to the Windows
Application Event Log; console mode does so only with `syslog-enabled yes`.
The Event Source is fixed as `redis`, while `syslog-ident` is included in the
message text. Built-in installation registers the service executable's embedded
message table; the ZIP also carries `EventLog.dll` as a standalone/legacy
message resource.

All named services share that one Event Log registration. The first built-in
install that creates it supplies `EventMessageFile`; later named installs do
not refresh the path, and built-in uninstall of any name removes the shared
registration. For multiple or side-by-side services, manage individual service
deletion with SCM tools, keep the registered executable in place, and recreate
the shared source from the intended surviving executable after removal or a
path change. Windows does not support Redis daemonization; use console mode or
the service interface.

### Portable package and runtime dependencies

The flat x64 ZIP contains `redis-server.exe`, `redis-sentinel.exe`,
`redis-cli.exe`, `redis-benchmark.exe`, `redis-check-aof.exe`,
`redis-check-rdb.exe`, `EventLog.dll`, console/service/Sentinel configuration
examples, `README.txt`, the license, release notes, and this behavior guide. A
separate `.sha256` file provides an integrity checksum for a ZIP obtained from a
trusted channel.

The MinGW support runtimes (`libgcc`, `libstdc++`, and winpthreads) are linked
without external MinGW DLL dependencies. Normal Windows system DLLs, including
MSVCRT, remain imports. The target does not need MSYS2, Tcl, or Visual Studio;
test modules and build-only validation binaries are not shipped.

### Windows-specific constraints

- x64 MinGW is the supported release build. The Visual Studio/MSI projects are
  legacy best-effort files.
- The standard package has no OpenSSL/TLS support. `tls-port`, `rediss://`, TLS
  replication, and TLS cluster links are unavailable.
- Unix domain sockets are unavailable; use TCP on loopback or another bound
  interface.
- Server multi-I/O-thread mode is unavailable and rejected at startup; keep
  `io-threads 1` and `io-threads-do-reads no`.
- General module fork APIs and asynchronous/forked Lua debugger sessions are
  unavailable.
- POSIX daemon, systemd/upstart, Linux OOM-score, CPU-affinity, process-title,
  THP, and signal behavior does not map directly to Windows; use the Windows
  service and Event Log facilities.
- QFork requires a stable virtual-address layout. The MinGW executables
  intentionally disable dynamic-base and high-entropy ASLR at link time.
- This is an unofficial port. Validate persistence, replication, modules,
  service permissions, antivirus policy, and performance under the exact
  Windows version and workload used in production.

### Upgrade checklist

1. Back up RDB, AOF, configuration, Sentinel, and ACL files.
2. Install the portable files side-by-side and retain the ZIP checksum/source
   commit. If using built-in services, account for the shared Event Log
   registration described above.
3. Review snapshot defaults, directory permissions, protected mode, bind
   addresses, ACLs, and replication credentials.
4. Keep clients on RESP2 initially; enable RESP3 deliberately.
5. Rebuild native modules, retest any defragmentation callbacks, and confirm
   they do not require module fork.
6. Avoid old Redis 5 replicas or downgrade after using Redis 6-only commands.
7. Exercise `PING`, authentication, representative commands, `BGSAVE`, AOF
   rewrite, restart/reload, replication, and any Cluster, Sentinel, or service
   paths used by the deployment.
