! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit test suite for RFC 7233 byte-range parsing, live segment ring buffer,
! HTTP request parsing, response serialization, and media route dispatching.

USING: accessors arrays assocs byte-arrays byte-vectors hashtables
io kernel locals math math.parser sequences strings
venturi.common.types venturi.server.handler venturi.server.live-stream
venturi.server.range-requests venturi.tests.harness ;
IN: venturi.tests.server

:: test-byte-range-requests ( -- )
    "Testing RFC 7233 Range Request Parser and Slicer..." print

    ! Standard closed range: bytes=0-499 on length 1000
    "bytes=0-499" 1000 parse-range-header :> r1
    r1 f = not "range 0-499 parsed successfully" test-true
    r1 start-byte>> 0 "range start is 0" test=
    r1 end-byte>> 499 "range end is 499" test=
    r1 range-length 500 "range length is 500" test=
    r1 format-content-range "bytes 0-499/1000" "content-range formatted correctly" test=

    ! Open-ended range: bytes=500- on length 1000
    "bytes=500-" 1000 parse-range-header :> r2
    r2 start-byte>> 500 "range start is 500" test=
    r2 end-byte>> 999 "range end is 999" test=
    r2 range-length 500 "range length is 500" test=

    ! Suffix range: bytes=-250 on length 1000
    "bytes=-250" 1000 parse-range-header :> r3
    r3 start-byte>> 750 "suffix range start is 750" test=
    r3 end-byte>> 999 "suffix range end is 999" test=
    r3 range-length 250 "suffix range length is 250" test=

    ! Unsatisfiable range: beyond bounds
    "bytes=1200-1500" 1000 parse-range-header f = "out of bounds range returns f" test-true
    "bytes=600-400" 1000 parse-range-header f = "inverted range returns f" test-true
    "malformed" 1000 parse-range-header f = "malformed range returns f" test-true

    ! Slicing byte array
    B{ 10 20 30 40 50 60 70 80 90 100 } :> sample-bytes
    "bytes=2-5" 10 parse-range-header :> slice-rng
    sample-bytes slice-rng slice-by-range :> sliced
    sliced B{ 30 40 50 60 } "slice-by-range extracts exact subseq" test= ;

:: make-test-segment ( seq-num uri data-len -- seg )
    seq-num
    0
    180000
    90000
    f
    uri
    data-len <byte-array>
    <media-segment> ;

:: test-live-ring-buffer ( -- )
    "Testing High-Concurrency In-Memory Live Segment Ring Buffer..." print

    3 <live-ring-buffer> :> ring
    ring live-segment-count 0 "new ring buffer is empty" test=

    0 0 0 90000 t "init.mp4" B{ 1 2 3 4 } <media-segment> :> init-seg
    init-seg ring set-init-segment
    "init.mp4" ring get-live-segment f = not "init segment retrievable from ring" test-true

    1 "chunk-1.m4s" 100 make-test-segment :> s1
    2 "chunk-2.m4s" 100 make-test-segment :> s2
    3 "chunk-3.m4s" 100 make-test-segment :> s3

    s1 ring push-live-segment
    s2 ring push-live-segment
    s3 ring push-live-segment

    ring live-segment-count 3 "ring buffer contains 3 segments" test=
    ring live-sequence-range :> ( min-seq max-seq )
    min-seq 1 "min sequence is 1" test=
    max-seq 3 "max sequence is 3" test=

    "chunk-1.m4s" ring get-live-segment f = not "chunk-1 present before eviction" test-true

    ! Push segment 4: capacity 3 exceeded, chunk-1 must be evicted
    4 "chunk-4.m4s" 100 make-test-segment :> s4
    s4 ring push-live-segment

    ring live-segment-count 3 "ring buffer maintains capacity 3" test=
    ring live-sequence-range :> ( min2 max2 )
    min2 2 "min sequence rolled to 2" test=
    max2 4 "max sequence rolled to 4" test=

    "chunk-1.m4s" ring get-live-segment f = "chunk-1 evicted from ring" test-true
    "chunk-4.m4s" ring get-live-segment f = not "chunk-4 present in ring" test-true

    ! Sliding window slice
    ring 2 current-live-window :> win
    win length 2 "current live window returns requested 2 segments" test=
    0 win nth sequence>> 3 "first in window is seq 3" test=
    1 win nth sequence>> 4 "second in window is seq 4" test= ;

:: test-http-parser-and-dispatcher ( -- )
    "Testing HTTP 1.1 Parser, Serializer, and Route Dispatcher..." print

    "master.m3u8" mime-type-for-path "application/vnd.apple.mpegurl" "m3u8 MIME type" test=
    "manifest.mpd" mime-type-for-path "application/dash+xml" "mpd MIME type" test=
    "chunk-1.m4s" mime-type-for-path "video/iso.segment" "m4s MIME type" test=
    "init.mp4" mime-type-for-path "video/mp4" "mp4 MIME type" test=

    ! Parse HTTP Request
    "GET /stream.m3u8?session=123 HTTP/1.1\r\nHost: localhost:8080\r\nRange: bytes=0-199\r\nAccept: */*\r\n"
    B{ } parse-http-request :> req

    req f = not "request parsed successfully" test-true
    req method>> "GET" "parsed method is GET" test=
    req path>> "/stream.m3u8" "parsed path is /stream.m3u8" test=
    req query>> "session=123" "parsed query parameter" test=
    "host" req headers>> key? "header host present" test-true
    "range" req headers>> key? "header range present" test-true

    ! Media dispatch against static files
    H{ } clone :> files
    "#EXTM3U\n#EXT-X-VERSION:7\n" >byte-array "stream.m3u8" files set-at
    B{ 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 } "chunk-1.m4s" files set-at

    ! GET full resource
    "GET /stream.m3u8 HTTP/1.1\r\nHost: localhost\r\n" B{ } parse-http-request :> req-vod
    req-vod files f dispatch-media-request :> resp-vod
    resp-vod status-code>> 200 "GET stream.m3u8 status is 200" test=
    "application/vnd.apple.mpegurl" resp-vod headers>> "Content-Type" swap at "Content-Type matches" test=

    ! HEAD resource
    "HEAD /stream.m3u8 HTTP/1.1\r\nHost: localhost\r\n" B{ } parse-http-request :> req-head
    req-head files f dispatch-media-request :> resp-head
    resp-head status-code>> 200 "HEAD stream.m3u8 status is 200" test=
    resp-head body>> length 0 "HEAD response body is empty" test=

    ! GET Byte-Range (206 Partial Content)
    "GET /chunk-1.m4s HTTP/1.1\r\nHost: localhost\r\nRange: bytes=2-7\r\n" B{ } parse-http-request :> req-rng
    req-rng files f dispatch-media-request :> resp-rng
    resp-rng status-code>> 206 "Range request status is 206" test=
    resp-rng body>> B{ 2 3 4 5 6 7 } "Range request body matches exact slice" test=
    "bytes 2-7/16" resp-rng headers>> "Content-Range" swap at "Content-Range header present" test=

    ! 404 Not Found
    "GET /nonexistent.m4s HTTP/1.1\r\nHost: localhost\r\n" B{ } parse-http-request :> req-404
    req-404 files f dispatch-media-request :> resp-404
    resp-404 status-code>> 404 "Non-existent asset returns 404" test=

    ! CORS OPTIONS preflight
    "OPTIONS /stream.m3u8 HTTP/1.1\r\nHost: localhost\r\n" B{ } parse-http-request :> req-opt
    req-opt files f dispatch-media-request :> resp-opt
    resp-opt status-code>> 204 "OPTIONS returns 204" test=
    "*" resp-opt headers>> "Access-Control-Allow-Origin" swap at "CORS allow-origin present" test=

    ! Serialize HTTP response
    resp-vod serialize-http-response :> wire-bytes
    wire-bytes length 0 > "serialized HTTP response is non-empty" test-true
    "HTTP/1.1 200 OK\r\n" wire-bytes >string subseq? "wire response begins with HTTP/1.1 200 OK" test-true ;

:: run-server-tests ( -- )
    init-test-harness
    test-byte-range-requests
    test-live-ring-buffer
    test-http-parser-and-dispatcher
    "Venturi HTTP Edge Server & Live Buffer Test Suite" print-test-summary drop ;

MAIN: run-server-tests
