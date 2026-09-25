set defaults { appendonly {yes} appendfilename {appendonly.aof} aof-use-rdb-preamble {no} }
set server_path [tmpdir server.aof]
set aof_path "$server_path/appendonly.aof"

proc start_server_aof {overrides code} {
    upvar defaults defaults srv srv server_path server_path
    set config [concat $defaults $overrides]
    # The next server must replay the AOF, so do not remove it during teardown.
    start_server [list overrides $config keep_persistence true] $code
}

tags {"aof"} {
    # Specific test for a regression where internal buffers were not properly
    # cleaned after a child responsible for an AOF rewrite exited. This buffer
    # was subsequently appended to the new AOF, resulting in duplicate commands.
    start_server_aof [list dir $server_path] {
        set client [redis [srv host] [srv port] 0 $::tls]
        set bench_cmd [list | $::redis_benchmark_path -q -h [srv host] -p [srv port] -c 20 -n 20000 incr foo]
        set bench [open $bench_cmd "r+"]

        after 100

        # Benchmark should be running by now: start background rewrite
        $client bgrewriteaof

        # Read until benchmark pipe reaches EOF
        while {[string length [read $bench]] > 0} {}
        close $bench

        waitForBgrewriteaof $client

        # Check contents of foo
        assert_equal 20000 [$client get foo]
        $client close
    }

    # Restart server to replay AOF
    start_server_aof [list dir $server_path] {
        set client [redis [srv host] [srv port] 0 $::tls]
        wait_done_loading $client
        assert_equal 20000 [$client get foo]
        $client close
    }
}
