! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! CLI command: benchmark
! High-stress throughput and latency benchmarking for bitstream parsing,
! box serialization, and end-to-end CMAF live transmuxing.

USING: accessors arrays byte-arrays byte-vectors formatting io kernel
locals math math.parser sequences strings system vectors venturi.codecs.h264
venturi.common.types venturi.common.utils venturi.isobmff.box-reader
venturi.isobmff.box-writer venturi.isobmff.constants
venturi.packaging.cmaf venturi.packaging.pipeline ;
IN: venturi.cli.benchmark

:: generate-synthetic-annexb-payload ( target-bytes -- bytes )
    V{ } clone :> buf
    [ buf length target-bytes < ] [
        ! Interleave 4-byte start codes with payload and emulation prevention
        buf 0 push-be32
        1 buf push
        0x65 buf push ! IDR slice header
        0 buf push
        0 buf push
        3 buf push ! Emulation prevention
        1 buf push
        ! 256 random-ish payload bytes
        256 [ 0xAA buf push ] times
    ] while
    buf >byte-array ;

:: benchmark-annexb-scanner ( -- )
    "Running Annex B Start-Code Scanner & Unescape Benchmark..." write flush
    10 1024 * 1024 * generate-synthetic-annexb-payload :> raw-payload

    nano-count :> t0
    raw-payload split-annex-b-nals :> nal-units
    nano-count :> t1

    t1 t0 - 1000000000.0 /f :> elapsed
    raw-payload length 1024 1024 * /f :> mb
    mb elapsed /f :> throughput

    " DONE" print
    "  Payload Size:       " write mb "%.2f" sprintf write " MB" print
    "  NAL Units Found:    " write nal-units length number>string print
    "  Elapsed Time:       " write elapsed 1000.0 * "%.2f" sprintf write " ms" print
    "  Scan Throughput:    " write throughput "%.2f" sprintf write " MB/sec" print ;

:: benchmark-box-writer ( -- )
    "Running ISOBMFF Box Serialization Benchmark..." write flush
    20000 :> iterations

    nano-count :> t0
    iterations [
        FOURCC_MOOF B{ 0 0 0 16 116 114 97 102 0 0 0 8 116 102 104 100 } serialize-box drop
    ] times
    nano-count :> t1

    t1 t0 - 1000000000.0 /f :> elapsed
    iterations elapsed /f :> rate

    " DONE" print
    "  Iterations:         " write iterations number>string write " box serializations" print
    "  Elapsed Time:       " write elapsed 1000.0 * "%.2f" sprintf write " ms" print
    "  Throughput:         " write rate "%.0f" sprintf write " ops/sec" print ;

:: benchmark-cmaf-pipeline ( -- )
    "Running End-to-End CMAF Transmuxing Pipeline Benchmark..." write flush

    ! Build synthetic 1080p60 stream (3000 frames = 50 seconds)
    V{ } clone :> samples
    3000 [
        :> i
        i 60 rem zero? [ 1 ] [ 0 ] if :> flags
        i 1500 * :> pts
        B{ 0x00 0x00 0x00 0x02 0x65 0x88 } :> dummy-data
        1 pts pts 1500 dummy-data length flags dummy-data <media-sample> samples push
    ] each-integer

    1 "avc1" 90000 1920 1080 B{ 0x01 } <video-track> :> v-trk
    v-trk samples >vector >>samples drop

    nano-count :> t0
    { v-trk } 2000 transmux-tracks-to-cmaf :> result
    nano-count :> t1

    t1 t0 - 1000000000.0 /f :> elapsed
    3000 elapsed /f :> fps
    50.0 elapsed /f :> rtf

    " DONE" print
    "  Input Video Stream: 3,000 frames @ 60 fps (50.000 sec)" print
    "  CMAF Fragments:     " write result media-segments>> length number>string write " fragments" print
    "  Elapsed Time:       " write elapsed 1000.0 * "%.2f" sprintf write " ms" print
    "  Processing Speed:   " write fps "%.1f" sprintf write " frames/sec" print
    "  Real-Time Factor:   " write rtf "%.1f" sprintf write "x real-time" print ;

:: run-benchmark-command ( -- )
    "================================================================================" print
    "                  VENTURI HIGH-THROUGHPUT ENGINE BENCHMARK                      " print
    "================================================================================" print
    benchmark-annexb-scanner
    "\n" write
    benchmark-box-writer
    "\n" write
    benchmark-cmaf-pipeline
    "================================================================================" print ;
