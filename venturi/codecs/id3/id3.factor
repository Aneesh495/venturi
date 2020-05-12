! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ID3v2.4 / ID3v2.3 timed metadata tag generator and parser for HTTP Live Streaming.
! Synchsafe integer encoding, custom TXXX frames, and Apple HLS PRIV timestamp tags.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise math.order sequences strings vectors venturi.common.utils ;
IN: venturi.codecs.id3

! Encodes a 28-bit unsigned integer into 4 synchsafe bytes (bit 7 zeroed in each byte).
:: encode-synchsafe ( val -- bytes )
    4 <byte-array> :> buf
    val -21 shift 0x7F bitand 0 buf set-nth
    val -14 shift 0x7F bitand 1 buf set-nth
    val -7 shift 0x7F bitand 2 buf set-nth
    val 0x7F bitand 3 buf set-nth
    buf ;

! Decodes a 28-bit unsigned integer from 4 synchsafe bytes.
:: decode-synchsafe ( bytes offset -- val )
    offset bytes nth 0x7F bitand 21 shift
    offset 1 + bytes nth 0x7F bitand 14 shift +
    offset 2 + bytes nth 0x7F bitand 7 shift +
    offset 3 + bytes nth 0x7F bitand + ;

! Generic ID3v2 frame representation
TUPLE: id3-frame
    { id string read-only }
    { data byte-array read-only } ;

: <id3-frame> ( id data -- frame )
    id3-frame boa ;

! Builds a text information frame (for example TIT2, TPE1, or user text TXXX).
:: build-id3-txxx-frame ( desc val -- frame-bytes )
    128 <byte-vector> :> buf
    buf "TXXX" >byte-array push-bytes

    ! Payload: encoding (0x03 = UTF-8) + desc + 0x00 + val
    128 <byte-vector> :> payload
    payload 0x03 push-u8
    payload desc >byte-array push-bytes
    payload 0x00 push-u8
    payload val >byte-array push-bytes

    buf payload length encode-synchsafe push-bytes
    buf 0 push-be16 ! flags = 0
    buf payload >byte-array push-bytes
    buf >byte-array ;

! Builds an ID3v2 PRIV (private) frame.
:: build-id3-priv-frame ( owner payload-bytes -- frame-bytes )
    128 <byte-vector> :> buf
    buf "PRIV" >byte-array push-bytes

    128 <byte-vector> :> payload
    payload owner >byte-array push-bytes
    payload 0x00 push-u8
    payload payload-bytes push-bytes

    buf payload length encode-synchsafe push-bytes
    buf 0 push-be16 ! flags = 0
    buf payload >byte-array push-bytes
    buf >byte-array ;

! Builds a standardized Apple HLS transport stream timestamp ID3 tag for PES alignment.
:: build-hls-timestamp-id3 ( pts-90khz -- tag-bytes )
    8 <byte-vector> :> pcr-buf
    pcr-buf pts-90khz push-be64
    "com.apple.streaming.transportStreamTimestamp" pcr-buf >byte-array build-id3-priv-frame :> priv-frame
    { priv-frame } :> frames

    ! Wrap in ID3v2.4 header
    1024 <byte-vector> :> tag-buf
    tag-buf "ID3" >byte-array push-bytes
    tag-buf 0x04 push-u8 ! ID3v2.4
    tag-buf 0x00 push-u8 ! revision
    tag-buf 0x00 push-u8 ! flags = 0

    tag-buf priv-frame length encode-synchsafe push-bytes
    tag-buf priv-frame push-bytes
    tag-buf >byte-array ;

! Assembles an ID3v2.4 tag containing multiple pre-encoded frame byte arrays.
:: build-id3v2-tag ( frame-byte-arrays -- tag-bytes )
    1024 <byte-vector> :> buf
    0 :> total-frames-len!
    frame-byte-arrays [ length total-frames-len + total-frames-len! ] each

    buf "ID3" >byte-array push-bytes
    buf 0x04 push-u8
    buf 0x00 push-u8
    buf 0x00 push-u8
    buf total-frames-len encode-synchsafe push-bytes
    frame-byte-arrays [ :> f-bytes buf f-bytes push-bytes ] each
    buf >byte-array ;

! Parses an ID3v2 tag buffer and returns an array of id3-frame tuples.
:: parse-id3v2-tag ( tag-bytes -- frames )
    V{ } clone :> out
    tag-bytes length 10 < [ out ] [
        0 3 tag-bytes subseq-safe >string "ID3" = not [ out ] [
            tag-bytes 6 decode-synchsafe :> tag-size
            10 :> off!
            tag-size 10 + tag-bytes length min :> max-off

            [ off 10 + max-off <= ] [
                off off 4 + tag-bytes subseq-safe >string :> frame-id
                0 frame-id nth 0 = [
                    max-off off! ! padding reached
                ] [
                    tag-bytes off 4 + decode-synchsafe :> frame-len
                    off 10 + :> data-start
                    data-start frame-len + max-off min :> data-end

                    data-end data-start > [
                        data-start data-end tag-bytes subseq-safe :> f-data
                        frame-id f-data <id3-frame> out push
                        data-end off!
                    ] [
                        max-off off!
                    ] if
                ] if
            ] while
            out
        ] if
    ] if ;
