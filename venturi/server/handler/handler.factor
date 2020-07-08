! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! HTTP request parsing, response serialization, MIME resolution,
! and media route dispatching with RFC 7233 byte-range support.

USING: accessors arrays assocs byte-arrays byte-vectors formatting
hashtables kernel locals math math.order math.parser sequences
splitting strings unicode venturi.common.types venturi.common.utils
venturi.server.live-stream venturi.server.range-requests ;
IN: venturi.server.handler

! Inbound HTTP 1.1 request data model.
TUPLE: http-request
    { method string read-only }
    { path string read-only }
    { query string read-only }
    { headers hashtable read-only }
    { body byte-array read-only } ;

: <http-request> ( method path query headers body -- req )
    http-request boa ;

! Outbound HTTP 1.1 response data model.
TUPLE: http-response
    { status-code integer read-only }
    { status-text string read-only }
    { headers hashtable read-only }
    { body byte-array read-only } ;

: <http-response> ( status-code status-text headers body -- resp )
    http-response boa ;

! Maps a resource file path extension to an RFC-compliant MIME content type.
:: mime-type-for-path ( path -- mime-type )
    path ".m3u8" tail? [
        "application/vnd.apple.mpegurl"
    ] [
        path ".mpd" tail? [
            "application/dash+xml"
        ] [
            path ".mp4" tail? [
                "video/mp4"
            ] [
                path ".m4s" tail? [
                    "video/iso.segment"
                ] [
                    path ".ts" tail? [
                        "video/mp2t"
                    ] [
                        path ".xml" tail? [
                            "application/xml"
                        ] [
                            path ".json" tail? [
                                "application/json"
                            ] [
                                "application/octet-stream"
                            ] if
                        ] if
                    ] if
                ] if
            ] if
        ] if
    ] if ;

! Parses raw HTTP header text into an http-request tuple.
:: parse-http-request ( raw-header-str raw-body -- req/f )
    "\r\n" raw-header-str split-subseq :> lines
    lines length zero? [ f ] [
        0 lines nth " " split-subseq :> req-line
        req-line length 3 >= [
            0 req-line nth >upper :> method
            1 req-line nth :> full-path

            "?" full-path split-subseq :> path-parts
            0 path-parts nth :> raw-path
            path-parts length 1 > [ 1 path-parts nth ] [ "" ] if :> query

            ! Parse headers into lowercase hashtable
            H{ } clone :> hdr-table
            lines 1 tail [
                :> line
                ": " line split-subseq :> kv
                kv length 2 = [
                    0 kv nth >lower :> k
                    1 kv nth :> v
                    v k hdr-table set-at
                ] when
            ] each

            method raw-path query hdr-table raw-body <http-request>
        ] [ f ] if
    ] if ;

! Constructs standard 200 OK response with CORS and Byte-Range support headers.
:: <response-200> ( content-type body -- resp )
    H{ } clone :> hdrs
    content-type "Content-Type" hdrs set-at
    body length number>string "Content-Length" hdrs set-at
    "bytes" "Accept-Ranges" hdrs set-at
    "*" "Access-Control-Allow-Origin" hdrs set-at
    "GET, HEAD, OPTIONS" "Access-Control-Allow-Methods" hdrs set-at
    "Range, Accept-Encoding, Origin" "Access-Control-Allow-Headers" hdrs set-at
    "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
    200 "OK" hdrs body <http-response> ;

! Constructs 206 Partial Content response with Content-Range header.
:: <response-206> ( content-type body byte-range -- resp )
    H{ } clone :> hdrs
    content-type "Content-Type" hdrs set-at
    body length number>string "Content-Length" hdrs set-at
    byte-range format-content-range "Content-Range" hdrs set-at
    "bytes" "Accept-Ranges" hdrs set-at
    "*" "Access-Control-Allow-Origin" hdrs set-at
    "GET, HEAD, OPTIONS" "Access-Control-Allow-Methods" hdrs set-at
    "Range, Accept-Encoding, Origin" "Access-Control-Allow-Headers" hdrs set-at
    "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
    206 "Partial Content" hdrs body <http-response> ;

! Constructs 404 Not Found response.
:: <response-404> ( missing-path -- resp )
    H{ } clone :> hdrs
    "text/plain" "Content-Type" hdrs set-at
    "*" "Access-Control-Allow-Origin" hdrs set-at
    "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
    "404 Not Found: " missing-path append "\n" append >byte-array :> b
    b length number>string "Content-Length" hdrs set-at
    404 "Not Found" hdrs b <http-response> ;

! Constructs 416 Range Not Satisfiable response.
:: <response-416> ( total-len -- resp )
    H{ } clone :> hdrs
    "bytes */" total-len number>string append "Content-Range" hdrs set-at
    "*" "Access-Control-Allow-Origin" hdrs set-at
    "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
    "0" "Content-Length" hdrs set-at
    416 "Range Not Satisfiable" hdrs B{ } <http-response> ;

! Constructs 204 No Content response for CORS preflight OPTIONS requests.
:: <response-options> ( -- resp )
    H{ } clone :> hdrs
    "*" "Access-Control-Allow-Origin" hdrs set-at
    "GET, HEAD, OPTIONS" "Access-Control-Allow-Methods" hdrs set-at
    "Range, Accept-Encoding, Origin" "Access-Control-Allow-Headers" hdrs set-at
    "86400" "Access-Control-Max-Age" hdrs set-at
    "0" "Content-Length" hdrs set-at
    "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
    204 "No Content" hdrs B{ } <http-response> ;

! Serializes an http-response tuple into an HTTP/1.1 wire protocol byte-array.
:: serialize-http-response ( resp -- wire-bytes )
    V{ } clone :> parts
    "HTTP/1.1 " parts push
    resp status-code>> number>string parts push
    " " parts push
    resp status-text>> parts push
    "\r\n" parts push

    resp headers>> [
        :> v :> k
        k parts push
        ": " parts push
        v parts push
        "\r\n" parts push
    ] assoc-each

    "\r\n" parts push
    parts concat >byte-array :> header-bytes

    header-bytes resp body>> append ;

! Resolves an incoming HTTP media request against static bundle and live ring buffer.
:: dispatch-media-request ( request file-map live-ring -- response )
    request method>> :> method

    method "OPTIONS" = [
        <response-options>
    ] [
        method "GET" = method "HEAD" = or [
            request path>> :> raw-path
            raw-path "/" head? [ raw-path 1 tail ] [ raw-path ] if :> clean-path

            ! Locate asset payload: check static file-map first, then live ring buffer
            f :> payload!
            clean-path file-map ?at [ payload! drop ] [
                live-ring [
                    clean-path live-ring get-live-segment [
                        data>> payload!
                    ] when*
                ] when
            ] if

            payload [
                clean-path mime-type-for-path :> ctype
                payload length :> total-len

                ! Check for Range header
                "range" request headers>> ?at :> ( range-hdr range-found? )

                range-found? [
                    range-hdr total-len parse-range-header :> byte-rng
                    byte-rng [
                        payload byte-rng slice-by-range :> slice-data
                        method "HEAD" = [
                            ctype B{ } byte-rng <response-206>
                        ] [
                            ctype slice-data byte-rng <response-206>
                        ] if
                    ] [
                        total-len <response-416>
                    ] if
                ] [
                    method "HEAD" = [
                        ctype B{ } <response-200>
                    ] [
                        ctype payload <response-200>
                    ] if
                ] if
            ] [
                clean-path <response-404>
            ] if
        ] [
            H{ } clone :> hdrs
            "0" "Content-Length" hdrs set-at
            "Venturi/1.0.0 (Factor)" "Server" hdrs set-at
            405 "Method Not Allowed" hdrs B{ } <http-response>
        ] if
    ] if ;
