! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! End-to-end integration test suite verifying the complete pipeline:
! synthetic MPEG-TS demuxing, CMAF packaging, dual-manifest authoring,
! and HTTP/1.1 media route dispatching with byte-range slicing.

USING: accessors arrays assocs byte-arrays byte-vectors hashtables
io kernel locals math math.order math.parser sequences strings
venturi.codecs.aac venturi.codecs.h264 venturi.common.crc
venturi.common.types venturi.common.utils venturi.isobmff.box-reader
venturi.isobmff.constants venturi.manifests.coordinator
venturi.mpegts.demuxer venturi.packaging.pipeline
venturi.server.handler venturi.server.live-stream
venturi.server.range-requests venturi.tests.harness ;
IN: venturi.tests.integration

:: make-synthetic-integration-ts ( -- ts-bytes )
    V{ } clone :> pkts

    ! Helper to push a 188-byte packet
    [ :> cc :> pusi? :> pid :> payload
        0x47 pkts push
        pusi? [ 0x40 ] [ 0x00 ] if pid -8 shift 0x1F bitand bitor pkts push
        pid 0xFF bitand pkts push
        0x10 cc 0x0F bitand bitor pkts push
        payload length 184 min :> copy-len
        pkts 0 copy-len payload subseq-safe push-bytes
        184 copy-len - [ 0xFF pkts push ] times
    ] :> push-pkt

    ! 1. PAT (PID 0)
    B{ 0x00 0xB0 0x0D 0x00 0x01 0xC1 0x00 0x00 0x00 0x01 0xF0 0x00 } :> pat-sec
    pat-sec crc32-mpeg2 :> pat-crc
    V{ 0 } clone :> pat-pl
    pat-pl pat-sec push-bytes
    pat-pl pat-crc push-be32
    pat-pl >byte-array 0 t 0 push-pkt call

    ! 2. PMT (PID 0x1000)
    B{ 0x02 0xB0 0x17 0x00 0x01 0xC1 0x00 0x00 0xE1 0x00 0xF0 0x00 0x1B 0xE1 0x00 0xF0 0x00 0x0F 0xE1 0x01 0xF0 0x00 } :> pmt-sec
    pmt-sec crc32-mpeg2 :> pmt-crc
    V{ 0 } clone :> pmt-pl
    pmt-pl pmt-sec push-bytes
    pmt-pl pmt-crc push-be32
    pmt-pl >byte-array 0x1000 t 0 push-pkt call

    ! 3. Video IDR frame (PID 0x0100)
    B{
        0x00 0x00 0x00 0x01 0x67 0x42 0xE0 0x1F 0xFF 0xE1 0x00 0x08 66 224 31 244 2 128 45 208
        0x00 0x00 0x00 0x01 0x68 0xCE 0x3C 0x80
        0x00 0x00 0x00 0x01 0x65 0x88 0x84 0x00 0x11 0x22 0x33 0x44
    } :> idr-annexb

    ! Video PES Header with PTS=0
    V{ 0x00 0x00 0x01 0xE0 0x00 0x00 0x80 0x80 0x05 0x21 0x00 0x01 0x00 0x01 } clone :> v-pes
    v-pes idr-annexb push-bytes
    v-pes >byte-array 0x0100 t 0 push-pkt call

    ! 4. Audio ADTS frame (PID 0x0101)
    B{ 0xFF 0xF1 0x50 0x80 0x03 0xFF 0xFC 0xAA 0xBB 0xCC 0xDD } :> adts-frame
    V{ 0x00 0x00 0x01 0xC0 0x00 0x00 0x80 0x80 0x05 0x21 0x00 0x01 0x00 0x01 } clone :> a-pes
    a-pes adts-frame push-bytes
    a-pes >byte-array 0x0101 t 0 push-pkt call

    pkts >byte-array ;

:: test-end-to-end-pipeline ( -- )
    "Testing Full End-to-End Transmux, Packaging & Edge HTTP Dispatch..." print

    make-synthetic-integration-ts :> ts-bytes
    ts-bytes length 0 > "synthetic TS stream generated" test-true

    ! Step 1: Demux TS stream
    ts-bytes demux-mpegts :> tracks
    tracks length 2 = "demuxed exactly 2 tracks (video and audio)" test-true

    ! Step 2: Transmux to CMAF
    tracks 2000 transmux-tracks-to-cmaf :> result
    result init-segment>> data>> length 0 > "init.mp4 is non-empty" test-true
    result media-segments>> length 0 > "produced at least 1 media segment" test-true

    ! Step 3: Author synchronized HLS and DASH manifests
    result f coordinate-manifests :> bundle
    "#EXTM3U" bundle hls-master>> subseq? "master playlist contains #EXTM3U" test-true
    "#EXT-X-TARGETDURATION" bundle hls-media>> subseq? "media playlist contains target duration" test-true
    "<MPD" bundle dash-mpd>> subseq? "dash manifest contains root MPD" test-true

    ! Step 4: Map bundle to file hashtable and dispatch HTTP edge requests
    bundle bundle-file-map :> files

    ! Test GET /master.m3u8
    "GET /master.m3u8 HTTP/1.1\r\nHost: localhost\r\n" B{ } parse-http-request :> req-master
    req-master files f dispatch-media-request :> resp-master
    resp-master status-code>> 200 "GET /master.m3u8 returns 200 OK" test=

    ! Test GET /init.mp4 with RFC 7233 Byte Range (0-31 = first 32 bytes)
    "GET /init.mp4 HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-31\r\n" B{ } parse-http-request :> req-init-rng
    req-init-rng files f dispatch-media-request :> resp-init-rng
    resp-init-rng status-code>> 206 "GET /init.mp4 with Range returns 206 Partial Content" test=
    resp-init-rng body>> length 32 "Range response body length is 32 bytes" test=

    ! Verify that the first 4 bytes of slice are ftyp box size
    resp-init-rng body>> 4 read-be32 FOURCC_FTYP "init slice begins with ftyp FourCC" test= ;

:: run-integration-tests ( -- )
    init-test-harness
    test-end-to-end-pipeline
    "Venturi End-to-End Transmuxing & Edge Streaming Integration Test Suite" print-test-summary drop ;

MAIN: run-integration-tests
