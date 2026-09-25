/* Exercise the production Sentinel adapter with the bundled hiredis. */
#include "server.h"
#include "async.h"
#include "async_private.h"
#include "Win32_Interop/win32_wsiocp.h"
#include "Win32_Interop/Win32_Error.h"

#undef serverLog
#define serverLog(...) ((void)0)

static int sentinel_test_fail_mask;

static int sentinelTestCreateEvent(aeEventLoop *loop, int fd, int mask,
                                   aeFileProc *proc, void *data) {
    if (mask & sentinel_test_fail_mask) {
        errno = ENOBUFS;
        return AE_ERR;
    }
    return aeCreateFileEvent(loop, fd, mask, proc, data);
}

/* The build extracts the adapter block from src/sentinel.c verbatim. Inject
 * failures at its event-registration boundary and keep hiredis unchanged. */
#define aeCreateFileEvent sentinelTestCreateEvent
#include "sentinel-adapter.inc"
#undef aeCreateFileEvent
#undef serverLog

static int sentinel_test_failures;
typedef struct sentinelTestResult {
    int cleaned;
    int disconnected;
    int disconnect_status;
    int replies;
} sentinelTestResult;

static void sentinelTestCheck(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: Sentinel adapter %s\n", message);
        sentinel_test_failures++;
    }
}

static void sentinelTestCleanup(void *data) {
    sentinelTestResult *result = data;
    result->cleaned++;
}

static void sentinelTestDisconnect(const redisAsyncContext *ac, int status) {
    sentinelTestResult *result = ac->data;
    result->disconnected++;
    result->disconnect_status = status;
}

static void sentinelTestReply(redisAsyncContext *ac, void *reply, void *data) {
    ((void)ac);
    sentinelTestResult *result = data;
    if (reply) result->replies++;
}

static redisAsyncContext *sentinelTestContext(aeEventLoop *loop, int pair[2],
                                             sentinelTestResult *result) {
    if (FDAPI_pipe_for_eventloop(pair) != 0) return NULL;
    redisOptions options = {0};
    options.type = REDIS_CONN_USERFD;
    options.endpoint.fd = pair[0];
    redisAsyncContext *ac = redisAsyncConnectWithOptions(&options);
    if (!ac) {
        close(pair[0]);
        close(pair[1]);
        return NULL;
    }
    ac->c.flags |= REDIS_CONNECTED;
    ac->data = result;
    ac->dataCleanup = sentinelTestCleanup;
    redisAsyncSetDisconnectCallback(ac, sentinelTestDisconnect);
    if (redisAeAttach(loop, ac) != C_OK) {
        redisAsyncFree(ac);
        close(pair[1]);
        return NULL;
    }
    return ac;
}

static void sentinelTestDrain(aeEventLoop *loop, int fd) {
    for (int i = 0; i < 1000 && WSIOCP_GetExistingSocketState(fd); i++) {
        aeProcessEvents(loop, AE_ALL_EVENTS | AE_DONT_WAIT);
        Sleep(1);
    }
    sentinelTestCheck(WSIOCP_GetExistingSocketState(fd) == NULL,
                      "drains closed socket operations");
}

static void sentinelTestRegistrationFailure(aeEventLoop *loop, int mask,
                                            int cleanup_before_timer) {
    int pair[2];
    sentinelTestResult result = {0};
    redisAsyncContext *ac = sentinelTestContext(loop, pair, &result);
    sentinelTestCheck(ac != NULL, "creates a native hiredis context");
    if (!ac) return;
    redisAeEvents *events = ac->ev.data;
    if (mask == AE_READABLE) redisAeAddWrite(events);
    else redisAeAddRead(events);

    sentinel_test_fail_mask = mask;
    if (mask == AE_READABLE) redisAeAddRead(events);
    else redisAeAddWrite(events);
    sentinel_test_fail_mask = 0;
    sentinelTestCheck(result.cleaned == 0,
                      "keeps hiredis alive until registration returns");
    if (result.cleaned == 0) {
        sentinelTestCheck(ac->c.err == REDIS_ERR_IO &&
                          aeGetFileEvents(loop, pair[0]) == AE_NONE,
                          "records the I/O failure and removes subscriptions");
        sentinelTestCheck(redisAsyncCommand(ac, NULL, NULL, "PING") == REDIS_ERR,
                          "rejects commands after a failed registration");
        if (cleanup_before_timer) {
            redisAsyncFree(ac);
        } else {
            events->callback_refs++;
            aeProcessEvents(loop, AE_TIME_EVENTS | AE_DONT_WAIT);
            sentinelTestCheck(result.cleaned == 0,
                              "defers cleanup during a nested callback");
            events->callback_refs--;
        }
        for (int i = 0; i < 100 && result.cleaned == 0; i++) {
            aeProcessEvents(loop, AE_TIME_EVENTS | AE_DONT_WAIT);
            Sleep(1);
        }
        sentinelTestCheck(result.cleaned == 1 && result.disconnected == 1,
                          "cleans up and disconnects exactly once");
        if (!cleanup_before_timer)
            sentinelTestCheck(result.disconnect_status == REDIS_ERR,
                              "reports an error disconnect");
    }
    close(pair[1]);
    sentinelTestDrain(loop, pair[0]);
    aeProcessEvents(loop, AE_TIME_EVENTS | AE_DONT_WAIT);
    sentinelTestCheck(result.cleaned == 1, "cancels obsolete cleanup timers");
}

static ssize_t sentinelTestNoNewBytes(redisContext *context, char *buf,
                                     size_t size) {
    ((void)context); ((void)buf); ((void)size);
    return 0;
}

static ssize_t sentinelTestBlockedWrite(int fd, const void *buf, size_t size) {
    ((void)fd); ((void)buf); ((void)size);
    errno = EAGAIN;
    return -1;
}

static void sentinelTestWriteRetry(aeEventLoop *loop) {
    int pair[2];
    sentinelTestResult result = {0};
    redisAsyncContext *ac = sentinelTestContext(loop, pair, &result);
    sentinelTestCheck(ac != NULL, "creates a context for a blocked write");
    if (!ac) return;
    redisAeEvents *events = ac->ev.data;
    sentinelTestCheck(redisAsyncCommand(ac, sentinelTestReply, &result,
                                        "PING") == REDIS_OK,
                      "queues a command before write backpressure");
    fdapi_write saved_write = write;
    write = sentinelTestBlockedWrite;
    redisAeWriteEvent(loop, pair[0], events, AE_WRITABLE);
    write = saved_write;
    sentinelTestCheck(result.cleaned == 0,
                      "keeps a temporarily blocked hiredis write alive");
    if (result.cleaned == 0) {
        sentinelTestCheck(ac->c.err == 0 && events->writing &&
                          (aeGetFileEvents(loop, pair[0]) & AE_WRITABLE),
                          "retains the command and its write subscription");
        redisAeWriteEvent(loop, pair[0], events, AE_WRITABLE);
        sentinelTestCheck(result.cleaned == 0 && !events->writing,
                          "flushes the queued command on the next writable event");
        if (result.cleaned == 0) redisAsyncFree(ac);
    }
    close(pair[1]);
    sentinelTestDrain(loop, pair[0]);
}

static void sentinelTestHiredisReadFailure(aeEventLoop *loop) {
    int pair[2];
    sentinelTestResult result = {0};
    redisAsyncContext *ac = sentinelTestContext(loop, pair, &result);
    sentinelTestCheck(ac != NULL, "creates a context for read dispatch");
    if (!ac) return;
    redisAeEvents *events = ac->ev.data;
    sentinelTestCheck(redisAsyncCommand(ac, sentinelTestReply, &result,
                                        "PING") == REDIS_OK,
                      "queues a command through the real hiredis adapter");
    redisAeWriteEvent(loop, pair[0], events, AE_WRITABLE);
    redisAeDelRead(events);
    redisContextFuncs funcs = *ac->c.funcs;
    funcs.read = sentinelTestNoNewBytes;
    ac->c.funcs = &funcs;
    sentinelTestCheck(redisReaderFeed(ac->c.reader, "+PONG\r\n", 7) == REDIS_OK,
                      "stages a reply for hiredis callback processing");
    sentinel_test_fail_mask = AE_READABLE;
    redisAeReadEvent(loop, pair[0], events, AE_READABLE);
    sentinel_test_fail_mask = 0;
    for (int i = 0; i < 100 && result.cleaned == 0; i++) {
        aeProcessEvents(loop, AE_TIME_EVENTS | AE_DONT_WAIT);
        Sleep(1);
    }
    sentinelTestCheck(result.cleaned == 1 && result.disconnected == 1,
                      "survives registration failure inside hiredis read dispatch");
    close(pair[1]);
    sentinelTestDrain(loop, pair[0]);
}

static void sentinelTestGuard(aeEventLoop *loop, int fd, void *data, int mask) {
    ((void)loop); ((void)fd); ((void)data); ((void)mask);
    sentinelTestCheck(0, "does not dispatch an idle guard socket");
}

int win32_sentinel_interop_test(void) {
    aeEventLoop *loop = aeCreateEventLoop(65536);
    int guard[2];
    sentinelTestCheck(loop != NULL, "creates an owning event loop");
    if (!loop) return sentinel_test_failures;
    if (FDAPI_pipe_for_eventloop(guard) != 0) {
        sentinelTestCheck(0, "creates a drain guard socket");
        aeDeleteEventLoop(loop);
        return sentinel_test_failures;
    }
    sentinelTestCheck(aeCreateFileEvent(loop, guard[0], AE_READABLE,
                                       sentinelTestGuard, NULL) == AE_OK,
                      "keeps completion draining active during cleanup");
    sentinelTestRegistrationFailure(loop, AE_READABLE, 0);
    sentinelTestRegistrationFailure(loop, AE_WRITABLE, 0);
    sentinelTestRegistrationFailure(loop, AE_READABLE, 1);
    sentinelTestRegistrationFailure(loop, AE_WRITABLE, 1);
    sentinelTestWriteRetry(loop);
    sentinelTestHiredisReadFailure(loop);
    aeDeleteFileEvent(loop, guard[0], AE_READABLE);
    close(guard[0]);
    close(guard[1]);
    aeProcessEvents(loop, AE_ALL_EVENTS | AE_DONT_WAIT);
    aeDeleteEventLoop(loop);
    if (!sentinel_test_failures)
        printf("Sentinel hiredis registration and deferred cleanup tests passed\n");
    return sentinel_test_failures;
}
