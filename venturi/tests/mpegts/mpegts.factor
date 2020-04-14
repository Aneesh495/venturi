! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Comprehensive test suite for MPEG-2 Transport Stream decoding,
! packet framing, PAT/PMT PSI tables, PES reassembly, and demuxing.

USING: accessors arrays byte-arrays byte-vectors hashtables io
kernel locals math math.order sequences sets strings venturi.common.crc
venturi.common.types venturi.common.utils venturi.mpegts.constants
venturi.mpegts.demuxer venturi.mpegts.packet venturi.mpegts.pes
venturi.mpegts.psi venturi.tests.harness ;
IN: venturi.tests.mpegts

! Helper to create a 188-byte buffer filled with a repeated byte
:: make-ts-packet ( pusi? pid cc payload -- packet-bytes )
    188 <byte-array> :> buf
    TS_SYNC_BYTE 0 buf set-nth
    payload length :> plen
    plen 184 < [
        pusi? 0x40 0 ? pid -8 shift 0x1F bitand bitor 1 buf set-nth
        pid 0xFF bitand 2 buf set-nth
        0x30 cc 0x0F bitand bitor 3 buf set-nth
        184 plen - :> af-len
        af-len 1 - 4 buf set-nth
        af-len 1 > [
            0 5 buf set-nth
            5 :> idx!
            [ idx 1 + 4 af-len + < ] [
                idx 1 + idx!
                0xFF idx buf set-nth
            ] while
        ] when
        0 plen payload 4 af-len + buf copy-bytes
    ] [
        pusi? 0x40 0 ? pid -8 shift 0x1F bitand bitor 1 buf set-nth
        pid 0xFF bitand 2 buf set-nth
        0x10 cc 0x0F bitand bitor 3 buf set-nth
        0 184 payload 4 buf copy-bytes
    ] if
    buf ;

:: make-ts-packet-with-af ( pusi? pid cc rai? pcr-val payload -- packet-bytes )
    188 <byte-array> :> buf
    TS_SYNC_BYTE 0 buf set-nth
    pusi? 0x40 0 ? pid -8 shift 0x1F bitand bitor 1 buf set-nth
    pid 0xFF bitand 2 buf set-nth
    0x30 cc 0x0F bitand bitor 3 buf set-nth ! 0x30 = adaptation field + payload
    ! Adaptation field length = 7 (flags + 6 bytes PCR)
    7 4 buf set-nth
    ! Flags: PCR flag (0x10) | (rai? 0x40 0 ?)
    0x10 rai? 0x40 0 ? bitor 5 buf set-nth
    ! PCR 33-bit base + 6 reserved + 9-bit ext
    pcr-val -25 shift 0xFF bitand 6 buf set-nth
    pcr-val -17 shift 0xFF bitand 7 buf set-nth
    pcr-val -9 shift 0xFF bitand 8 buf set-nth
    pcr-val -1 shift 0xFF bitand 9 buf set-nth
    pcr-val 1 shift 0x80 bitand 0x7E bitor 10 buf set-nth
    0 11 buf set-nth ! ext low
    ! Payload starts at offset 12
    payload length :> plen
    plen 176 min :> copy-len
    0 copy-len payload 12 buf copy-bytes
    buf ;

:: test-ts-packet-framing ( -- )
    "Testing TS Packet Framing..." print
    B{ 1 2 3 4 } :> payload
    t 0x0100 3 payload make-ts-packet :> pkt-bytes
    pkt-bytes parse-ts-packet :> pkt

    pkt f = not "parsed packet is not f" test-true
    pkt pusi>> "PUSI is true" test-true
    pkt pid>> 0x0100 "PID matches 0x0100" test=
    pkt continuity-counter>> 3 "CC is 3" test=
    pkt afc>> 3 "AFC is adaptation + payload (3)" test=
    pkt payload>> payload "payload matches" test=

    ! Test packet with adaptation field and PCR
    B{ 9 8 7 } :> af-payload
    f 0x0101 7 t 8541000 af-payload make-ts-packet-with-af :> af-pkt-bytes
    af-pkt-bytes parse-ts-packet :> af-pkt

    af-pkt pid>> 0x0101 "PID matches 0x0101" test=
    af-pkt afc>> 3 "AFC is adaptation + payload (3)" test=
    af-pkt random-access?>> "random-access flag is set" test-true
    af-pkt pcr>> f = not "PCR value decoded" test-true

    ! Rejects bad sync byte
    188 0xFF <array> >byte-array parse-ts-packet f "invalid sync byte rejected" test= ;

:: test-psi-pat-pmt ( -- )
    "Testing PSI PAT and PMT Parsers..." print
    ! Construct a standard single-program PAT packet
    188 0xFF <array> >byte-array :> pat-pkt
    TS_SYNC_BYTE 0 pat-pkt set-nth
    0x40 1 pat-pkt set-nth ! PUSI = 1, PID = 0
    0x00 2 pat-pkt set-nth
    0x10 3 pat-pkt set-nth ! payload only, cc = 0
    0x00 4 pat-pkt set-nth ! pointer field = 0

    B{
        0x00 0xB0 0x0D
        0x00 0x01
        0xC1
        0x00 0x00
        0x00 0x01 0xF0 0x00
    } :> pat-body

    pat-body crc32-mpeg2 :> pat-crc
    pat-body
    pat-crc -24 shift 0xFF bitand 1byte-array append
    pat-crc -16 shift 0xFF bitand 1byte-array append
    pat-crc -8 shift 0xFF bitand 1byte-array append
    pat-crc 0xFF bitand 1byte-array append :> pat-section

    0 pat-section length pat-section 5 pat-pkt copy-bytes

    pat-pkt parse-ts-packet :> parsed-pat-pkt
    parsed-pat-pkt parse-pat-packet :> entries

    entries length 1 "PAT has 1 program entry" test=
    0 entries nth program-number>> 1 "program number is 1" test=
    0 entries nth pmt-pid>> 0x1000 "PMT PID is 0x1000" test=

    ! Construct PMT packet for program 1
    188 0xFF <array> >byte-array :> pmt-pkt
    TS_SYNC_BYTE 0 pmt-pkt set-nth
    0x50 1 pmt-pkt set-nth ! PUSI = 1, PID = 0x1000
    0x00 2 pmt-pkt set-nth
    0x10 3 pmt-pkt set-nth ! cc = 0
    0x00 4 pmt-pkt set-nth ! pointer = 0

    B{
        0x02 0xB0 0x17
        0x00 0x01
        0xC1
        0x00 0x00
        0xE1 0x00
        0xF0 0x00
        0x1B 0xE1 0x00 0xF0 0x00
        0x0F 0xE1 0x01 0xF0 0x00
    } :> pmt-body

    pmt-body crc32-mpeg2 :> pmt-crc
    pmt-body
    pmt-crc -24 shift 0xFF bitand 1byte-array append
    pmt-crc -16 shift 0xFF bitand 1byte-array append
    pmt-crc -8 shift 0xFF bitand 1byte-array append
    pmt-crc 0xFF bitand 1byte-array append :> pmt-section

    0 pmt-section length pmt-section 5 pmt-pkt copy-bytes

    pmt-pkt parse-ts-packet :> parsed-pmt-pkt
    parsed-pmt-pkt 0x1000 parse-pmt-packet :> pmt-info

    pmt-info pcr-pid>> 0x0100 "PMT PCR PID is 0x0100" test=
    pmt-info streams>> length 2 "PMT defines 2 elementary streams" test=
    0 pmt-info streams>> nth stream-type>> STREAM_TYPE_H264 "stream 0 is H.264" test=
    0 pmt-info streams>> nth elementary-pid>> 0x0100 "stream 0 PID is 0x0100" test=
    1 pmt-info streams>> nth stream-type>> STREAM_TYPE_AAC_ADTS "stream 1 is AAC" test=
    1 pmt-info streams>> nth elementary-pid>> 0x0101 "stream 1 PID is 0x0101" test= ;

:: test-pes-reassembly ( -- )
    "Testing PES Reassembly..." print
    0x0100 STREAM_TYPE_H264 <pes-assembler> :> asm

    B{
        0x00 0x00 0x01 0xE0 0x00 0x00
        0x80 0x80 0x05
        0x21 0x00 0x05 0xBF 0x21
        0xDE 0xAD 0xBE 0xEF
    } :> pes-chunk-1

    t 0x0100 0 pes-chunk-1 make-ts-packet parse-ts-packet :> ts1
    asm ts1 feed-ts-packet :> res1
    res1 f "first packet returns f" test=

    B{ 0xCA 0xFE 0xBA 0xBE } :> pes-chunk-2
    f 0x0100 1 pes-chunk-2 make-ts-packet parse-ts-packet :> ts2
    asm ts2 feed-ts-packet :> res2
    res2 f "second packet returns f" test=

    asm flush-pes-assembler :> final-pes
    final-pes f = not "flushed PES is non-f" test-true
    final-pes stream-id>> 0xE0 "stream ID is 0xE0" test=
    final-pes pts>> 90000 "PTS is 90000" test=
    final-pes payload>> length 8 "reassembled payload length is 8" test=
    final-pes payload>> B{ 0xDE 0xAD 0xBE 0xEF 0xCA 0xFE 0xBA 0xBE } "payload content matches" test= ;

:: test-demux-mpegts ( -- )
    "Testing MPEG-TS Multi-Track Demuxer..." print
    188 0xFF <array> >byte-array :> pat-pkt
    TS_SYNC_BYTE 0 pat-pkt set-nth
    0x40 1 pat-pkt set-nth
    0x00 2 pat-pkt set-nth
    0x10 3 pat-pkt set-nth
    0x00 4 pat-pkt set-nth
    B{ 0x00 0xB0 0x0D 0x00 0x01 0xC1 0x00 0x00 0x00 0x01 0xF0 0x00 } :> pat-b
    pat-b crc32-mpeg2 :> pat-c
    pat-b
    pat-c -24 shift 0xFF bitand 1byte-array append
    pat-c -16 shift 0xFF bitand 1byte-array append
    pat-c -8 shift 0xFF bitand 1byte-array append
    pat-c 0xFF bitand 1byte-array append :> pat-s
    0 pat-s length pat-s 5 pat-pkt copy-bytes

    188 0xFF <array> >byte-array :> pmt-pkt
    TS_SYNC_BYTE 0 pmt-pkt set-nth
    0x50 1 pmt-pkt set-nth
    0x00 2 pmt-pkt set-nth
    0x10 3 pmt-pkt set-nth
    0x00 4 pmt-pkt set-nth
    B{
        0x02 0xB0 0x17 0x00 0x01 0xC1 0x00 0x00 0xE1 0x00 0xF0 0x00
        0x1B 0xE1 0x00 0xF0 0x00
        0x0F 0xE1 0x01 0xF0 0x00
    } :> pmt-b
    pmt-b crc32-mpeg2 :> pmt-c
    pmt-b
    pmt-c -24 shift 0xFF bitand 1byte-array append
    pmt-c -16 shift 0xFF bitand 1byte-array append
    pmt-c -8 shift 0xFF bitand 1byte-array append
    pmt-c 0xFF bitand 1byte-array append :> pmt-s
    0 pmt-s length pmt-s 5 pmt-pkt copy-bytes

    B{
        0x00 0x00 0x01 0xE0 0x00 0x00
        0x80 0x80 0x05
        0x21 0x00 0x05 0xBF 0x21
        0x00 0x00 0x00 0x01 0x67 0x42 0x00 0x1E
    } :> vid-pes
    t 0x0100 0 vid-pes make-ts-packet :> vid-pkt

    pat-pkt pmt-pkt append vid-pkt append :> ts-stream

    ts-stream demux-mpegts :> tracks
    tracks length 2 "demuxed 2 tracks" test=
    tracks [ id>> 0x0100 = ] filter :> v-trks
    v-trks length 1 "found 1 video track with PID 0x0100" test=
    0 v-trks nth samples>> length 1 "video track has 1 sample" test=
    0 v-trks nth samples>> 0 swap nth pts>> 90000 "sample PTS is 90000" test= ;

:: run-all-mpegts-tests ( -- ? )
    init-test-harness
    test-ts-packet-framing
    test-psi-pat-pmt
    test-pes-reassembly
    test-demux-mpegts
    "MPEG-2 Transport Stream Test Suite" print-test-summary ;
