! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Packetized Elementary Stream (PES) reassembler with 33-bit PTS and DTS
! timestamp recovery, header parsing, and multi-packet stream reconstitution.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise math.order sequences venturi.common.utils
venturi.mpegts.constants venturi.mpegts.packet ;
IN: venturi.mpegts.pes

! Decoded Packetized Elementary Stream packet with synchronized PTS/DTS.
TUPLE: pes-packet
    { stream-id integer read-only }
    { pts integer read-only }
    { dts integer read-only }
    { payload byte-array read-only } ;

: <pes-packet> ( stream-id pts dts payload -- pes )
    pes-packet boa ;

! Decodes a 33-bit PTS or DTS timestamp from 5 contiguous bytes conforming to ISO/IEC 13818-1.
:: decode-pes-timestamp ( bytes offset -- ts-33bit )
    offset bytes nth :> b0
    offset 1 + bytes read-be16 :> w1
    offset 3 + bytes read-be16 :> w2

    b0 0x0E bitand 29 shift
    w1 -1 shift 0x7FFF bitand 15 shift +
    w2 -1 shift 0x7FFF bitand + ;

! Parses a complete reassembled PES packet byte array.
:: parse-pes-packet ( pes-bytes -- pes/f )
    pes-bytes length 6 < [ f ] [
        0 pes-bytes read-be24 :> prefix
        prefix 0x000001 = not [ f ] [
            3 pes-bytes nth :> s-id
            4 pes-bytes read-be16 :> p-len

            ! Default PTS/DTS to 0
            0 :> pts!
            0 :> dts!
            6 :> payload-start!

            ! Check if PES packet has optional header (audio or video stream)
            s-id STREAM_ID_PROGRAM_STREAM_MAP = not
            s-id STREAM_ID_PADDING_STREAM = not
            s-id STREAM_ID_PRIVATE_STREAM_2 = not and and [
                pes-bytes length 9 >= [
                    7 pes-bytes nth :> flags2
                    8 pes-bytes nth :> header-data-len
                    9 header-data-len + :> p-start
                    p-start payload-start!

                    flags2 -6 shift 0x3 bitand :> pts-dts-flags

                    pts-dts-flags 2 = [  ! PTS only
                        pes-bytes length 14 >= [
                            pes-bytes 9 decode-pes-timestamp pts!
                            pts dts!
                        ] when
                    ] when

                    pts-dts-flags 3 = [  ! Both PTS and DTS
                        pes-bytes length 19 >= [
                            pes-bytes 9 decode-pes-timestamp pts!
                            pes-bytes 14 decode-pes-timestamp dts!
                        ] when
                    ] when
                ] when
            ] when

            payload-start pes-bytes length <= [
                payload-start pes-bytes length pes-bytes subseq-safe :> pl
                s-id pts dts pl <pes-packet>
            ] [ f ] if
        ] if
    ] if ;

! Stateful PES stream accumulator assembling fragments across consecutive TS packets.
TUPLE: pes-assembler
    { pid integer read-only }
    { stream-type integer read-only }
    { buffer byte-vector }
    { last-cc integer } ;

: <pes-assembler> ( pid stream-type -- assembler )
    65536 <byte-vector> 0 pes-assembler boa ;

! Feeds a single TS packet into the assembler.
! If PUSI is set and an ongoing buffer exists, completes and returns the previous PES.
:: feed-ts-packet ( assembler packet -- completed-pes/f )
    f :> completed!

    packet pusi>> [
        assembler buffer>> length zero? not [
            assembler buffer>> >byte-array parse-pes-packet completed!
            0 assembler buffer>> set-length
        ] when
    ] when

    packet payload>> length zero? not [
        assembler buffer>> packet payload>> push-bytes
    ] when

    completed ;

! Flushes any remaining bytes in the accumulator when stream ends.
:: flush-pes-assembler ( assembler -- final-pes/f )
    assembler buffer>> length zero? [ f ] [
        assembler buffer>> >byte-array parse-pes-packet
        0 assembler buffer>> set-length
    ] if ;
