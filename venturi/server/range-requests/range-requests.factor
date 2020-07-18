! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! RFC 7233 Range Requests and 206 Partial Content handling for CMAF byte-range indexing.

USING: accessors arrays formatting kernel locals math math.order
math.parser sequences splitting strings venturi.common.utils ;
IN: venturi.server.range-requests

! Verified byte range within a content payload of known total length.
TUPLE: byte-range
    { start-byte integer read-only }
    { end-byte integer read-only }
    { total-length integer read-only } ;

: <byte-range> ( start end total -- range )
    byte-range boa ;

! Returns the byte count requested by this range.
: range-length ( byte-range -- len )
    [ end-byte>> ] [ start-byte>> ] bi - 1 + ;

! Formats the RFC 7233 Content-Range header value (e.g. "bytes 0-499/12345").
:: format-content-range ( byte-range -- str )
    "bytes "
    byte-range start-byte>> number>string append
    "-" append
    byte-range end-byte>> number>string append
    "/" append
    byte-range total-length>> number>string append ;

! Parses an RFC 7233 Range header value into a byte-range instance.
! Returns f if the header is malformed or the requested range cannot be satisfied.
:: parse-range-header ( header-str total-len -- byte-range/f )
    header-str "bytes=" head? [
        header-str 6 tail :> spec
        "-" spec subseq? [
            spec "-" split-subseq :> parts
            parts length 2 = [
                0 parts nth :> p0
                1 parts nth :> p1

                p0 length 0 > p1 length 0 > and [
                    ! Standard range: bytes=start-end
                    p0 string>number :> s
                    p1 string>number :> e
                    s [
                        e [
                            s 0 >= e total-len < and s e <= and [
                                s e total-len <byte-range>
                            ] [ f ] if
                        ] [ f ] if
                    ] [ f ] if
                ] [
                    p0 length 0 > p1 length zero? and [
                        ! Open-ended range: bytes=start-
                        p0 string>number :> s
                        s [
                            s 0 >= s total-len < and [
                                s total-len 1 - total-len <byte-range>
                            ] [ f ] if
                        ] [ f ] if
                    ] [
                        p0 length zero? p1 length 0 > and [
                            ! Suffix range: bytes=-suffix
                            p1 string>number :> suffix-len
                            suffix-len [
                                suffix-len 0 > [
                                    total-len suffix-len - 0 max :> s
                                    s total-len 1 - total-len <byte-range>
                                ] [ f ] if
                            ] [ f ] if
                        ] [ f ] if
                    ] if
                ] if
            ] [ f ] if
        ] [ f ] if
    ] [ f ] if ;

! Extracts a slice of the given byte array matching the byte-range boundaries.
:: slice-by-range ( data byte-range -- subseq )
    byte-range start-byte>>
    byte-range end-byte>> 1 +
    data subseq-safe ;
