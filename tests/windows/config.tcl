if {$::tcl_platform(platform) eq "windows"} {
    start_server {tags {windows config external:skip tls:skip} overrides {
        io-threads 1
        io-threads-do-reads no
    }} {
        test {Windows accepts single-threaded client I/O settings} {
            assert_equal PONG [r ping]
            assert_equal 1 [lindex [r config get io-threads] 1]
            assert_equal {} [r config get io-threads-do-reads]
        }

        test {Windows CLI and benchmark work with executable ASLR} {
            set cli [list $::redis_cli_path -h [srv host] -p [srv port]]
            assert_equal PONG [string trim [exec {*}$cli ping]]
            assert_equal OK [string trim [exec {*}$cli set affinity-tool-smoke value]]
            assert_equal value [string trim [exec {*}$cli get affinity-tool-smoke]]

            r config resetstat
            set output [exec $::redis_benchmark_path \
                -h [srv host] -p [srv port] -q -n 200 -c 2 -P 4 -t set,get 2>@1]
            assert_match {*SET:*} $output
            assert_match {*GET:*} $output
            assert_match {calls=200,*,rejected_calls=0,failed_calls=0} [cmdrstat set r]
            assert_match {calls=200,*,rejected_calls=0,failed_calls=0} [cmdrstat get r]
        }
    }
}
