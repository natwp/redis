/* Exercise the Redis 6.2 connection callbacks with native FDAPI sockets. */
#include "server.h"
#include "Win32_Interop/win32_wsiocp.h"

struct redisServer server;
static int fail_read, fail_write, read_rearms, write_rearms;
static int connected_callbacks, error_callbacks, failures;

static int testRearmRead(int fd) {
    read_rearms++;
    if (fail_read) { errno = ENOBUFS; return -1; }
    return WSIOCP_QueueNextRead(fd);
}

static int testRearmWrite(int fd) {
    write_rearms++;
    if (fail_write) { errno = ENOBUFS; return -1; }
    return WSIOCP_QueueWriteReady(fd);
}

/* Compile the production callbacks with deterministic rearm failures. The
 * backend still creates, owns, cancels, and drains the real socket operations. */
#define WSIOCP_QueueNextRead testRearmRead
#define WSIOCP_QueueWriteReady testRearmWrite
#include "../../src/connection.c"
#undef WSIOCP_QueueNextRead
#undef WSIOCP_QueueWriteReady

static void check(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: 6.2 connection %s\n", message);
        failures++;
    }
}

static void observe(connection *conn) {
    if (conn->state == CONN_STATE_ERROR) error_callbacks++;
    else if (conn->state == CONN_STATE_CONNECTED) connected_callbacks++;
}

static void closeInCallback(connection *conn) {
    connected_callbacks++;
    connClose(conn);
}

static void guardCallback(aeEventLoop *el, int fd, void *data, int mask) {
    (void)el; (void)fd; (void)data; (void)mask;
    check(0, "does not dispatch an idle guard socket");
}

static void drainClosed(int fd) {
    for (int i = 0; i < 1000 && WSIOCP_GetExistingSocketState(fd); i++) {
        aeProcessEvents(server.el, AE_FILE_EVENTS | AE_DONT_WAIT);
        Sleep(1);
    }
    check(WSIOCP_GetExistingSocketState(fd) == NULL,
          "drains completions after connection cleanup");
}

static connection *pairConnection(int pair[2]) {
    if (FDAPI_pipe_for_eventloop(pair) != 0) return NULL;
    connection *conn = connCreateAcceptedSocket(pair[0]);
    conn->state = CONN_STATE_CONNECTED;
    connected_callbacks = error_callbacks = 0;
    return conn;
}

static void testRearmFailure(int mask, int barrier) {
    int pair[2];
    connection *conn = pairConnection(pair);
    check(conn != NULL, "creates a connection for rearm failure");
    if (conn == NULL) return;
    check(connSocketSetReadHandler(conn, observe) == C_OK,
          "registers a read callback");
    check(connSocketSetWriteHandler(conn, observe, barrier) == C_OK,
          "registers a write callback");
    fail_read = (mask & AE_READABLE) &&
                (!barrier || !(mask & AE_WRITABLE));
    fail_write = !fail_read;
    connSocketEventHandler(server.el, pair[0], conn, mask);
    fail_read = fail_write = 0;
    check(connected_callbacks == 1 && error_callbacks == 1,
          "delivers one cleanup callback after the rearm fails");
    check(conn->state == CONN_STATE_ERROR && conn->last_errno == ENOBUFS,
          "preserves the failed rearm error");
    char byte = 'x';
    check(connRead(conn, &byte, 1) == -1 && errno == ENOBUFS,
          "makes cleanup reads report the rearm error");
    check(connWrite(conn, &byte, 1) == -1 && errno == ENOBUFS,
          "makes cleanup writes report the rearm error");
    check(aeGetFileEvents(server.el, pair[0]) == AE_NONE,
          "removes both subscriptions on rearm failure");
    connClose(conn);
    drainClosed(pair[0]);
    close(pair[1]);
}

static void testConnectError(void) {
    int pair[2];
    connection *conn = pairConnection(pair);
    check(conn != NULL, "creates a connection for a deferred connect error");
    if (conn == NULL) return;
    conn->state = CONN_STATE_CONNECTING;
    conn->conn_handler = observe;
    check(aeCreateFileEvent(server.el, pair[0], AE_WRITABLE,
                           connSocketEventHandler, conn) == AE_OK,
          "registers the connecting callback");
    WSIOCP_SetDeferredError(pair[0], ECONNREFUSED);
    connSocketEventHandler(server.el, pair[0], conn, AE_WRITABLE);
    check(error_callbacks == 1 && connected_callbacks == 0 &&
          conn->last_errno == ECONNREFUSED,
          "reports a failed completion even when SO_ERROR has cleared");
    check(WSIOCP_TakeDeferredError(pair[0]) == 0,
          "consumes a deferred connect error once");
    connClose(conn);
    drainClosed(pair[0]);
    close(pair[1]);
}

static void testCallbackCloseAndBarrier(void) {
    int pair[2];
    connection *conn = pairConnection(pair);
    check(conn != NULL, "creates a callback-close connection");
    if (conn == NULL) return;
    check(connSocketSetWriteHandler(conn, observe, 0) == C_OK &&
          connSocketSetWriteHandler(conn, observe, 1) == C_OK &&
          (aeGetFileEvents(server.el, pair[0]) & AE_BARRIER),
          "updates a write barrier when its callback is unchanged");
    check(connSocketSetWriteHandler(conn, observe, 0) == C_OK &&
          !(aeGetFileEvents(server.el, pair[0]) & AE_BARRIER),
          "clears a write barrier without replacing the callback");
    check(connSocketSetReadHandler(conn, closeInCallback) == C_OK,
          "registers a callback that closes its own connection");
    int before = read_rearms;
    connSocketEventHandler(server.el, pair[0], conn, AE_READABLE);
    check(connected_callbacks == 1 && read_rearms == before,
          "does not rearm or access a connection closed by its callback");
    drainClosed(pair[0]);
    close(pair[1]);
}

int win32_connection_interop_test(void) {
    int guard[2];
    server.el = aeCreateEventLoop(65536);
    check(server.el != NULL, "creates an owning event loop");
    if (server.el == NULL) return failures;
    if (FDAPI_pipe_for_eventloop(guard) != 0) {
        check(0, "creates a cleanup guard socket");
        aeDeleteEventLoop(server.el);
        return failures;
    }
    check(aeCreateFileEvent(server.el, guard[0], AE_READABLE,
                           guardCallback, NULL) == AE_OK,
          "keeps the loop active while cancelled operations drain");
    testRearmFailure(AE_READABLE, 0);
    testRearmFailure(AE_READABLE, 1);
    testRearmFailure(AE_WRITABLE, 0);
    testRearmFailure(AE_READABLE | AE_WRITABLE, 0);
    testRearmFailure(AE_READABLE | AE_WRITABLE, 1);
    testConnectError();
    testCallbackCloseAndBarrier();
    aeDeleteFileEvent(server.el, guard[0], AE_READABLE);
    close(guard[0]);
    close(guard[1]);
    aeProcessEvents(server.el, AE_ALL_EVENTS | AE_DONT_WAIT);
    aeDeleteEventLoop(server.el);
    server.el = NULL;
    if (!failures) printf("Redis 6.2 connection rearm and callback ownership tests passed\n");
    return failures;
}
