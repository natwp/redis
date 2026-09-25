/* Native regression coverage for loop-local IOCP retries and teardown. */
#include "Win32_Interop/win32fixes.h"
#include "Win32_Interop/Win32_FDAPI.h"
#include "Win32_Interop/win32_wsiocp.h"
#include <errno.h>

static int failures;
#define check(condition, message) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL: IOCP %s (errno=%d)\n", message, errno); \
        failures++; \
    } \
} while (0)

static void unusedCallback(aeEventLoop *el, int fd, void *data, int mask) {
    (void)el; (void)fd; (void)data; (void)mask;
    check(0, "does not dispatch an unrelated socket");
}

static int accept_attempts;
static int failAcceptSocket(int af, int type, int protocol) {
    (void)af; (void)type; (void)protocol;
    accept_attempts++;
    errno = ENOBUFS;
    return -1;
}

static int listener(void) {
    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (fd < 0 || bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(fd, 16) != 0) {
        if (fd >= 0) close(fd);
        return -1;
    }
    WSIOCP_GetSocketState(fd)->masks |= LISTEN_SOCK;
    return fd;
}

static void testAcceptRetry(void) {
    aeEventLoop *first = aeCreateEventLoop(65536);
    aeEventLoop *second = aeCreateEventLoop(65536);
    int fd = listener(), other = listener(), guard = listener();
    check(first && second && fd >= 0 && other >= 0 && guard >= 0, "creates independent listeners");
    if (!first || !second || fd < 0 || other < 0 || guard < 0) return;
    /* Keep one registration while draining cancellation of the other one,
     * as Redis does with its main listener during connection cleanup. */
    check(aeCreateFileEvent(first, guard, AE_READABLE, unusedCallback, NULL) == AE_OK,
          "keeps the owner loop active during close cleanup");
    check(aeCreateFileEvent(second, other, AE_READABLE, unusedCallback, NULL) == AE_OK,
          "attaches the second listener");
    iocpLoopState *other_loop = WSIOCP_GetExistingSocketState(other)->loop;

    fdapi_socket saved_socket = socket;
    socket = failAcceptSocket;
    check(WSIOCP_EnsureAcceptQueued(fd) == -1, "records failure before attachment");
    socket = saved_socket;
    check(!WSIOCP_AcceptRearmPending(other_loop), "unattached failure cannot affect another loop");
    check(aeCreateFileEvent(first, fd, AE_READABLE, unusedCallback, NULL) == AE_OK,
          "attaches a listener with a pending retry");
    iocpLoopState *owner = WSIOCP_GetExistingSocketState(fd)->loop;
    check(owner != other_loop && WSIOCP_AcceptRearmPending(owner),
          "attachment accounts for the existing retry on its owner");

    aeEventLoop *third = aeCreateEventLoop(65536);
    check(third && WSIOCP_AcceptRearmPending(owner), "creating another loop preserves retries");
    if (third) aeDeleteEventLoop(third);
    socket = failAcceptSocket;
    int before = accept_attempts;
    aeProcessEvents(second, AE_FILE_EVENTS | AE_DONT_WAIT);
    check(accept_attempts == before, "another loop never retries this listener");
    aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
    check(accept_attempts == before + 1, "owner retries once on its first tick");
    ULONGLONG start = GetTickCount64();
    before = accept_attempts;
    for (int i = 0; i < 10; i++) aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
    if (GetTickCount64() - start < 80)
        check(accept_attempts == before, "transient accept failure does not spin");
    Sleep(110);
    aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
    check(accept_attempts > before, "accept retry resumes after its bounded delay");
    socket = saved_socket;

    check(WSIOCP_EnsureAcceptQueued(fd) == 0, "listener recovers after transient failure");
    check(!WSIOCP_AcceptRearmPending(owner), "successful rearm clears only its own counter");
    aeDeleteFileEvent(first, fd, AE_READABLE);
    close(fd);
    for (int i = 0; i < 1000 && WSIOCP_GetExistingSocketState(fd); i++) {
        aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
        Sleep(1);
    }
    check(!WSIOCP_GetExistingSocketState(fd), "close drains the retained AcceptEx owner");

    fd = listener();
    check(fd >= 0 && aeCreateFileEvent(first, fd, AE_READABLE, unusedCallback, NULL) == AE_OK,
          "attaches a listener for teardown");
    socket = failAcceptSocket;
    check(WSIOCP_EnsureAcceptQueued(fd) == -1, "teardown begins with a retry pending");
    socket = saved_socket;
    aeDeleteEventLoop(first);
    check(!WSIOCP_AcceptRearmPending(owner), "a retired loop cannot schedule retries");
    check(aeCreateFileEvent(second, fd, AE_READABLE, unusedCallback, NULL) == AE_ERR,
          "a retired completion port cannot be adopted by another loop");
    close(fd);
    close(guard);
    check(!WSIOCP_AcceptRearmPending(other_loop), "late close leaves the live loop counters intact");
    aeDeleteFileEvent(second, other, AE_READABLE);
    close(other);
    aeDeleteEventLoop(second);
}

#define WRITERS 70
static int writer_fds[WRITERS];
static int visited[WRITERS];
static int poll_calls;
static int recordBlockedWriters(struct pollfd *fds, nfds_t count, int timeout) {
    check(count <= 64 && timeout == 0, "writer retry uses a bounded nonblocking batch");
    poll_calls++;
    for (nfds_t i = 0; i < count; i++) {
        int found = 0;
        for (int j = 0; j < WRITERS; j++) {
            if (writer_fds[j] == fds[i].fd) { visited[j]++; found = 1; break; }
        }
        check(found, "writer batch contains only the owning loop's sockets");
        fds[i].revents = 0;
    }
    return 0;
}

static void writable(aeEventLoop *el, int fd, void *data, int mask) {
    (void)mask;
    (*(int *)data)++;
    aeDeleteFileEvent(el, fd, AE_WRITABLE);
}

static void testWriteRetry(void) {
    aeEventLoop *first = aeCreateEventLoop(65536);
    aeEventLoop *second = aeCreateEventLoop(65536);
    int pairs[WRITERS][2], callbacks = 0, count = 0;
    int small = 1024;
    char bytes[65536];
    memset(bytes, 'w', sizeof(bytes));
    memset(visited, 0, sizeof(visited));
    check(first && second, "creates writer event loops");
    if (!first || !second) return;
    for (; count < WRITERS; count++) {
        if (FDAPI_pipe_for_eventloop(pairs[count]) != 0) break;
        int fd = pairs[count][0];
        fcntl(fd, F_SETFL, O_NONBLOCK);
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, (char *)&small, sizeof(small));
        setsockopt(pairs[count][1], SOL_SOCKET, SO_RCVBUF, (char *)&small, sizeof(small));
        for (int attempt = 0; attempt < 1024 && FDAPI_IsSocketWritable(fd) > 0; attempt++) {
            if (write(fd, bytes, sizeof(bytes)) < 0 && errno != EWOULDBLOCK && errno != EAGAIN) break;
        }
        check(FDAPI_IsSocketWritable(fd) == 0, "native sender reaches backpressure");
        writer_fds[count] = fd;
        check(aeCreateFileEvent(first, fd, AE_WRITABLE, writable, &callbacks) == AE_OK,
              "registers a blocked writer");
    }
    check(count == WRITERS, "creates more blocked writers than one retry batch");
    iocpLoopState *owner = count ? WSIOCP_GetExistingSocketState(pairs[0][0])->loop : NULL;
    check(WSIOCP_WriteRearmPending(owner), "blocked writers belong to their event loop");
    fdapi_poll saved_poll = poll;
    poll = recordBlockedWriters;
    poll_calls = 0;
    aeProcessEvents(second, AE_FILE_EVENTS | AE_DONT_WAIT);
    check(poll_calls == 0, "unrelated loop never probes blocked writers");
    aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
    Sleep(15);
    aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
    poll = saved_poll;
    for (int i = 0; i < count; i++) check(visited[i] > 0, "round-robin retries reach every blocked writer");

    for (int i = 0; i < count; i++) close(pairs[i][1]);
    for (int attempt = 0; attempt < 2000 && callbacks < count; attempt++) {
        aeProcessEvents(first, AE_FILE_EVENTS | AE_DONT_WAIT);
        Sleep(1);
    }
    check(callbacks == count, "ready or failed writers each receive a cleanup callback");
    check(!WSIOCP_WriteRearmPending(owner), "completed writer retries leave no stale counter");
    for (int i = 0; i < count; i++) {
        aeDeleteFileEvent(first, pairs[i][0], AE_WRITABLE);
        close(pairs[i][0]);
    }
    aeDeleteEventLoop(first);
    aeDeleteEventLoop(second);
}

static int closing_fd;
static void closeBeforeDispatch(aeEventLoop *el) {
    aeSetAfterSleepProc(el, NULL);
    aeDeleteFileEvent(el, closing_fd, AE_WRITABLE);
    close(closing_fd);
}

static void testFiredOwnership(void) {
    int pair[2], callbacks = 0;
    aeEventLoop *el = aeCreateEventLoop(65536);
    check(el != NULL, "creates close-before-dispatch event loop");
    if (!el) return;
    int created = FDAPI_pipe_for_eventloop(pair);
    check(created == 0, "creates close-before-dispatch socket");
    if (created != 0) { aeDeleteEventLoop(el); return; }
    closing_fd = pair[0];
    check(aeCreateFileEvent(el, pair[0], AE_WRITABLE, writable, &callbacks) == AE_OK,
          "queues a readiness completion");
    aeSetAfterSleepProc(el, closeBeforeDispatch);
    aeProcessEvents(el, AE_FILE_EVENTS | AE_DONT_WAIT | AE_CALL_AFTER_SLEEP);
    check(callbacks == 0, "a retained event cannot dispatch a closed descriptor");
    check(!WSIOCP_GetExistingSocketState(pair[0]), "fired-event release finalizes the closed owner");
    close(pair[1]);
    aeDeleteEventLoop(el);
}

int win32_iocp_interop_test(void) {
    failures = 0;
    testAcceptRetry();
    testWriteRetry();
    testFiredOwnership();
    if (!failures) printf("IOCP loop isolation, retry fairness and ownership tests passed\n");
    return failures;
}
