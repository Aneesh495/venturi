! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Standalone high-throughput benchmarking suite for bitstream scanning,
! MPEG-TS demuxing, CMAF packaging, and HTTP edge dispatch latency.

USING: accessors arrays assocs byte-arrays byte-vectors formatting
hashtables io kernel locals math math.order math.parser sequences
strings system vectors venturi.cli.benchmark venturi.codecs.h264
venturi.common.types venturi.common.utils venturi.isobmff.box-writer
venturi.isobmff.constants venturi.manifests.coordinator
venturi.mpegts.demuxer venturi.packaging.pipeline
venturi.server.handler venturi.tests.integration ;
IN: benchmarks.bench-suite

:: benchmark-http-dispatcher ( -- )
    "Running HTTP Edge Route Dispatcher & Slicer Benchmark..." write flush
    100000 :> iterations

    ! Build synthetic bundle and file map
    H{ } clone :> files
    1024 <byte-array> "init.mp4" files set-at
    65536 <byte-array> "segment_1.m4s" files set-at
    "#EXTM3U\n#EXT-X-VERSION:7\n" >byte-array "stream.m3u8" files set-at

    "GET /segment_1.m4s HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-1023\r\n"
    B{ } parse-http-request :> req

    nano-count :> t0
    iterations [
        req files f dispatch-media-request serialize-http-response drop
    ] times
    nano-count :> t1

    t1 t0 - 1000000000.0 /f :> elapsed
    iterations elapsed /f :> rps
    elapsed iterations /f 1000000.0 * :> us-per-req

    " DONE" print
    "  Requests Processed: " write iterations number>string write " HTTP requests" print
    "  Elapsed Time:       " write elapsed 1000.0 * "%.2f" sprintf write " ms" print
    "  Throughput:         " write rps "%.0f" sprintf write " req/sec" print
    "  Mean Latency:       " write us-per-req "%.2f" sprintf write " microseconds/req" print ;

:: run-comprehensive-benchmarks ( -- )
    "================================================================================" print
    "                 VENTURI FULL PERFORMANCE & STRESS BENCHMARK                     " print
    "================================================================================" print
    run-benchmark-command
    "\n" write
    benchmark-http-dispatcher
    "================================================================================" print ;

MAIN: run-comprehensive-benchmarks
