! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! 188-byte ISO/IEC 13818-1 MPEG-2 Transport Stream packet parser,
! PCR clock recovery, continuity tracking, and stream synchronization.

USING: accessors arrays byte-arrays kernel locals math math.bitwise
sequences vectors venturi.common.utils venturi.mpegts.constants ;
IN: venturi.mpegts.packet

! Decoded MPEG-2 Transport Stream packet representation.
TUPLE: ts-packet
    { tei boolean read-only }                ! transport error indicator
    { pusi boolean read-only }               ! payload unit start indicator
    { priority boolean read-only }           ! transport priority
    { pid integer read-only }                ! 13-bit packet identifier
    { scrambling integer read-only }         ! scrambling control
    { afc integer read-only }                ! adaptation field control
    { continuity-counter integer read-only } ! 4-bit cyclic counter
    { random-access? boolean read-only }     ! keyframe indicator from adaptation
    { pcr object read-only }                 ! 27MHz recovered clock or f
    { payload byte-array read-only } ;

: <ts-packet> ( tei pusi priority pid scrambling afc cc ra? pcr payload -- packet )
    ts-packet boa ;

! Searches a byte buffer for a valid 188-byte periodic sync byte sequence.
:: find-ts-sync-offset ( bytes from-offset -- sync-offset/f )
    from-offset :> curr!
    f :> found-offset!
    bytes length TS_PACKET_SIZE 2 * - :> max-search
    [ curr max-search <= found-offset not and ] [
        curr bytes nth TS_SYNC_BYTE = [
            curr TS_PACKET_SIZE + bytes nth TS_SYNC_BYTE = [
                curr TS_PACKET_SIZE 2 * + bytes nth TS_SYNC_BYTE = [
                    curr found-offset!
                ] when
            ] when
        ] when
        curr 1 + curr!
    ] while
    found-offset ;

! Parses a single 188-byte MPEG-2 Transport Stream packet.
:: parse-ts-packet ( packet-bytes -- ts-packet/f )
    packet-bytes length TS_PACKET_SIZE < [ f ] [
        0 packet-bytes nth TS_SYNC_BYTE = not [ f ] [
            1 packet-bytes nth :> b1
            2 packet-bytes nth :> b2
            3 packet-bytes nth :> b3

            b1 7 bit? :> tei
            b1 6 bit? :> pusi
            b1 5 bit? :> priority
            b1 0x1F bitand 8 shift b2 + :> pid

            b3 -6 shift 0x3 bitand :> scrambling
            b3 -4 shift 0x3 bitand :> afc
            b3 0xF bitand :> cc

            tei [ f ] [
                4 :> payload-start!
                f :> random-access?!
                f :> pcr-val!

                ! Check adaptation field
                afc 2 bitand zero? not [
                    payload-start packet-bytes length < [
                        payload-start packet-bytes nth :> adapt-len
                        payload-start 1 + payload-start!

                        adapt-len 0 > payload-start packet-bytes length <= and [
                            payload-start packet-bytes nth :> adapt-flags
                            adapt-flags 6 bit? random-access?!

                            ! Check PCR flag (bit 4)
                            adapt-flags 4 bit? [
                                adapt-len 6 >= [
                                    payload-start 1 + :> pcr-off
                                    packet-bytes pcr-off read-be32 :> pcr-hi
                                    packet-bytes pcr-off 4 + read-be16 :> pcr-lo
                                    pcr-hi 1 shift pcr-lo -15 shift 1 bitand + :> pcr-base
                                    pcr-lo 0x1FF bitand :> pcr-ext
                                    pcr-base 300 * pcr-ext + pcr-val!
                                ] when
                            ] when

                            payload-start adapt-len + payload-start!
                        ] when
                    ] when
                ] when

                ! Extract payload
                afc 1 bitand zero? not payload-start TS_PACKET_SIZE <= and [
                    payload-start TS_PACKET_SIZE packet-bytes subseq-safe :> pl
                    tei pusi priority pid scrambling afc cc random-access? pcr-val pl <ts-packet>
                ] [
                    tei pusi priority pid scrambling afc cc random-access? pcr-val B{ } <ts-packet>
                ] if
            ] if
        ] if
    ] if ;

! Parses all aligned 188-byte packets from a contiguous byte buffer.
:: parse-ts-packets ( bytes -- packets )
    V{ } clone :> out
    0 :> off!
    bytes length TS_PACKET_SIZE - :> max-off
    [ off max-off <= ] [
        off off TS_PACKET_SIZE + bytes subseq-safe parse-ts-packet :> pkt
        pkt [ pkt out push ] when
        off TS_PACKET_SIZE + off!
    ] while
    out ;
