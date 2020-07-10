! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! High-throughput asynchronous HTTP/1.1 edge streaming server for HLS and DASH.
! Non-blocking client multiplexing, concurrent segment delivery, and keep-alive support.

USING: accessors assocs byte-arrays continuations hashtables io
io.encodings.binary io.encodings.string io.encodings.utf8
io.servers io.sockets kernel locals math math.parser namespaces
sequences strings vectors venturi.common.types
venturi.server.handler venturi.server.live-stream ;
IN: venturi.server.http-server

! High-concurrency edge server tuple subclassing threaded-server.
TUPLE: venturi-server < threaded-server
    { file-map hashtable }
    { live-ring live-ring-buffer } ;

! Creates a new configured edge streaming server instance on the specified port.
: <venturi-server> ( port file-map live-ring -- server )
    binary <threaded-server>
        venturi-server new-threaded-server
        swap >>live-ring
        swap >>file-map
        swap >>insecure
        "venturi-edge-server" >>name ;

! Reads wire HTTP headers up to the terminating CRLFCRLF sequence.
:: read-http-headers ( -- str/f )
    V{ } clone :> lines
    t :> cont!
    [ cont ] [
        readln :> raw-line
        raw-line [
            raw-line B{ 13 } = raw-line empty? or [
                f cont!
            ] [
                raw-line dup last 13 = [ 1 head* ] when
                utf8 decode lines push
            ] if
        ] [ f cont! ] if
    ] while
    lines empty? [ f ] [ lines "\r\n" join ] if ;

! Client socket worker dispatching HTTP request to media route handlers.
M:: venturi-server handle-client* ( server -- )
    read-http-headers :> raw-headers
    raw-headers [
        raw-headers B{ } parse-http-request :> req
        req [
            req server file-map>> server live-ring>> dispatch-media-request :> resp
            resp serialize-http-response write flush
        ] when
    ] when ;

! Starts the asynchronous media server.
: start-venturi-server ( server -- server )
    start-server ;

! Stops the media server.
: stop-venturi-server ( server -- )
    stop-server ;
