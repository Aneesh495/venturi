! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Venturi: High-Throughput Streaming Media Transmuxer, Live Segmented Packager,
! and Adaptive Edge Delivery Engine.
! Main CLI entrypoint and command router.

USING: accessors arrays command-line formatting io kernel locals math
math.parser namespaces sequences strings venturi.cli.benchmark
venturi.cli.inspect venturi.cli.package venturi.cli.serve
venturi.tests.codecs venturi.tests.common venturi.tests.isobmff
venturi.tests.manifests venturi.tests.mpegts venturi.tests.packaging
venturi.tests.server ;
IN: venturi

:: print-usage ( -- )
    "================================================================================" print
    "                               VENTURI CLI ENGINE                               " print
    "================================================================================" print
    "Usage: factor -roots=. -run=venturi <command> [options...]\n" print
    "Commands:" print
    "  inspect <file>                Deeply inspect ISOBMFF or MPEG-2 TS container metadata" print
    "  package <file> <out-dir>      Transmux and package stream into CMAF and HLS/DASH" print
    "  serve   <path> [port]         Serve packaged catalog or live stream over HTTP/1.1" print
    "  benchmark                     Run engine microbenchmarks across scanner and packager" print
    "  test                          Run full verification test suite across all subsystems" print
    "  help                          Display this usage guide" print
    "================================================================================" print ;

:: run-all-tests ( -- )
    "================================================================================" print
    "                   VENTURI FULL SUITE VERIFICATION PASS                         " print
    "================================================================================" print
    run-all-common-tests drop
    run-all-isobmff-tests drop
    run-all-mpegts-tests drop
    run-all-codecs-tests drop
    run-all-packaging-tests drop
    run-manifest-tests
    run-server-tests
    "All test suites executed successfully." print ;

:: venturi-main ( -- )
    command-line get :> args
    args length zero? [
        print-usage
    ] [
        0 args nth :> cmd
        cmd "inspect" = [
            args length 1 > [
                1 args nth run-inspect-command
            ] [
                "Error: inspect requires an input file path." print
            ] if
        ] [
            cmd "package" = [
                args length 2 > [
                    1 args nth :> in-path
                    2 args nth :> out-dir
                    args length 3 > [ 3 args nth string>number ] [ 2.0 ] if :> dur
                    args "--live" swap member? :> is-live?
                    in-path out-dir dur is-live? run-package-command
                ] [
                    "Error: package requires <input-file> and <output-dir>." print
                ] if
            ] [
                cmd "serve" = [
                    args length 1 > [
                        1 args nth :> target-path
                        args length 2 > [ 2 args nth string>number ] [ 8080 ] if :> port
                        args "--live" swap member? :> is-live?
                        target-path port is-live? run-serve-command
                    ] [
                        "Error: serve requires a directory or media file path." print
                    ] if
                ] [
                    cmd "benchmark" = [
                        run-benchmark-command
                    ] [
                        cmd "test" = [
                            run-all-tests
                        ] [
                            cmd "help" = cmd "--help" = or cmd "-h" = or [
                                print-usage
                            ] [
                                "Unknown command: " write cmd print
                                print-usage
                            ] if
                        ] if
                    ] if
                ] if
            ] if
        ] if
    ] if ;

MAIN: venturi-main
