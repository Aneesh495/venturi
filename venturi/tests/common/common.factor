! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit tests for common primitives: bitstream, exp-golomb, CRC, and utils.

USING: accessors byte-arrays byte-vectors io kernel locals math
sequences strings venturi.common.bitstream venturi.common.crc
venturi.common.exp-golomb venturi.common.types venturi.common.utils
venturi.tests.harness ;
IN: venturi.tests.common

:: run-bitstream-tests ( -- )
    "Testing Bitstream Reader and Writer..." print

    ! Test basic bit reader
    B{ 0xAA 0x55 } <bit-reader> :> r1
    r1 read-bit 1 "read 1st bit from 0xAA" test=
    r1 read-bit 0 "read 2nd bit from 0xAA" test=
    r1 6 read-bits 0x2A "read remaining 6 bits from 0xAA" test=
    r1 8 read-bits 0x55 "read 2nd byte 0x55" test=

    ! Test bit writer roundtrip
    <bit-writer> :> w1
    w1 0x7 3 write-bits
    w1 0x1 1 write-bits
    w1 0x2B 6 write-bits
    w1 0x3 6 write-bits
    w1 writer-bytes :> out-bytes
    out-bytes length 2 "writer emitted 2 bytes" test=
    0 out-bytes nth 0xFA "1st byte matches expected 0xFA" test=
    1 out-bytes nth 0xC3 "2nd byte matches expected 0xC3" test=

    ! Test peek and skip
    B{ 0x12 0x34 } <bit-reader> :> r2
    r2 8 peek-bits 0x12 "peek-bits matches 0x12" test=
    r2 8 read-bits 0x12 "read-bits after peek matches 0x12" test=
    r2 4 skip-bits
    r2 4 read-bits 0x4 "read after skip matches 0x4" test=

    ! Test align to byte
    B{ 0xFF 0xAA } <bit-reader> :> r3
    r3 3 read-bits drop
    r3 align-to-byte
    r3 8 read-bits 0xAA "align-to-byte correctly positioned to next byte" test=

    ! Test underflow
    B{ 0x01 } <bit-reader> :> r4
    [ r4 10 read-bits drop ] "bitstream underflow raises error" test-throws ;

:: run-exp-golomb-tests ( -- )
    "Testing Exponential-Golomb Coding..." print

    <bit-writer> :> w
    w 0 write-ue
    w 1 write-ue
    w 2 write-ue
    w 5 write-ue
    w 14 write-ue
    w 0 write-se
    w 1 write-se
    w -1 write-se
    w 2 write-se
    w -2 write-se
    w 15 write-se
    w -15 write-se

    w writer-bytes <bit-reader> :> r
    r read-ue 0 "ue(0) is 0" test=
    r read-ue 1 "ue(1) is 1" test=
    r read-ue 2 "ue(2) is 2" test=
    r read-ue 5 "ue(5) is 5" test=
    r read-ue 14 "ue(14) is 14" test=

    r read-se 0 "se(0) is 0" test=
    r read-se 1 "se(1) is 1" test=
    r read-se -1 "se(-1) is -1" test=
    r read-se 2 "se(2) is 2" test=
    r read-se -2 "se(-2) is -2" test=
    r read-se 15 "se(15) is 15" test=
    r read-se -15 "se(-15) is -15" test= ;

:: run-crc-tests ( -- )
    "Testing CRC Algorithms..." print

    "123456789" >byte-array :> test-bytes
    test-bytes crc32-ieee 0xCBF43926 "IEEE 802.3 CRC-32 for standard test vector" test=
    test-bytes crc32-mpeg2 0x0376E6E7 "MPEG-2 ISO/IEC 13818-1 CRC-32 for standard test vector" test=
    test-bytes crc16-ccitt 0x29B1 "CRC-16 CCITT for standard test vector" test=

    ! Verify trailing CRC property for MPEG-2
    13 <byte-vector> :> psi-buf
    psi-buf test-bytes push-bytes
    psi-buf 0x0376E6E7 push-be32
    psi-buf >byte-array verify-mpeg2-crc "verify-mpeg2-crc passes on compliant block" test-true ;

:: run-utils-and-types-tests ( -- )
    "Testing Utils and Types..." print

    "ftyp" string>4cc 0x66747970 "string>4cc for 'ftyp'" test=
    0x66747970 4cc>string "ftyp" "4cc>string for 0x66747970" test=

    "moov" string>4cc 0x6D6F6F76 "string>4cc for 'moov'" test=
    0x6D6F6F76 4cc>string "moov" "4cc>string for 0x6D6F6F76" test=

    B{ 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 } :> raw
    raw 0 read-be16 0x0102 "read-be16" test=
    raw 0 read-be24 0x010203 "read-be24" test=
    raw 0 read-be32 0x01020304 "read-be32" test=
    raw 0 read-be64 0x0102030405060708 "read-be64" test=

    0 4 raw subseq-safe B{ 0x01 0x02 0x03 0x04 } "subseq-safe normal" test=
    6 20 raw subseq-safe B{ 0x07 0x08 } "subseq-safe clamp high" test=

    B{ 0xDE 0xAD 0xBE 0xEF } bytes>hex "DEADBEEF" "bytes>hex formatting" test=

    ! Rational time and types
    100 1000 <rational-time> time>seconds 0.1 "rational-time time>seconds" test=
    90000 90000 1000 rescale-time 1000 "rescale-time from 90kHz to 1kHz" test=

    ! Sample flags and composition offset
    1 120 100 20 4096 1 B{ 0x00 } <media-sample> :> s1
    s1 keyframe? "sample 1 is keyframe" test-true
    s1 sample-composition-offset 20 "sample 1 composition offset is 20" test= ;

:: run-all-common-tests ( -- ? )
    init-test-harness
    run-bitstream-tests
    run-exp-golomb-tests
    run-crc-tests
    run-utils-and-types-tests
    "Common Primitives Suite" print-test-summary ;
