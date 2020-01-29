! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! High-performance table-driven CRC-32 (IEEE 802.3 and MPEG-2 ISO/IEC 13818-1)
! and CRC-16 generators for bitstream validation and PSI section integrity.

USING: arrays byte-arrays kernel locals math math.bitwise
namespaces sequences ;
IN: venturi.common.crc

<PRIVATE

:: make-crc32-ieee-table ( -- table )
    256 0 <array> :> tbl
    256 <iota> [
        :> i
        i :> c!
        8 <iota> [
            drop
            c 1 bitand 1 = [
                c -1 shift 0xEDB88320 bitxor c!
            ] [
                c -1 shift c!
            ] if
        ] each
        c i tbl set-nth
    ] each
    tbl ;

:: make-crc32-mpeg2-table ( -- table )
    256 0 <array> :> tbl
    256 <iota> [
        :> i
        i 24 shift :> c!
        8 <iota> [
            drop
            c 31 bit? [
                c 1 shift 0xFFFFFFFF bitand 0x04C11DB7 bitxor c!
            ] [
                c 1 shift 0xFFFFFFFF bitand c!
            ] if
        ] each
        c i tbl set-nth
    ] each
    tbl ;

:: make-crc16-ccitt-table ( -- table )
    256 0 <array> :> tbl
    256 <iota> [
        :> i
        i 8 shift :> c!
        8 <iota> [
            drop
            c 15 bit? [
                c 1 shift 0xFFFF bitand 0x1021 bitxor c!
            ] [
                c 1 shift 0xFFFF bitand c!
            ] if
        ] each
        c i tbl set-nth
    ] each
    tbl ;

SYMBOL: ieee-table
SYMBOL: mpeg2-table
SYMBOL: ccitt-table

ieee-table  [ make-crc32-ieee-table ] initialize
mpeg2-table [ make-crc32-mpeg2-table ] initialize
ccitt-table [ make-crc16-ccitt-table ] initialize

PRIVATE>

! Computes IEEE 802.3 CRC-32 (LSB-first, polynomial 0xEDB88320).
:: crc32-ieee ( bytes -- crc )
    0xFFFFFFFF :> c!
    ieee-table get-global :> tbl
    bytes [
        :> b
        c 0xFF bitand b bitxor :> idx
        idx tbl nth :> table-val
        c -8 shift table-val bitxor c!
    ] each
    c 0xFFFFFFFF bitxor ;

! Computes ISO/IEC 13818-1 MPEG-2 CRC-32 (MSB-first, polynomial 0x04C11DB7).
:: crc32-mpeg2 ( bytes -- crc )
    0xFFFFFFFF :> c!
    mpeg2-table get-global :> tbl
    bytes [
        :> b
        c -24 shift 0xFF bitand b bitxor :> idx
        idx tbl nth :> table-val
        c 8 shift 0xFFFFFFFF bitand table-val bitxor c!
    ] each
    c ;

! Computes CRC-16 CCITT (polynomial 0x1021).
:: crc16-ccitt ( bytes -- crc )
    0xFFFF :> c!
    ccitt-table get-global :> tbl
    bytes [
        :> b
        c -8 shift 0xFF bitand b bitxor :> idx
        idx tbl nth :> table-val
        c 8 shift 0xFFFF bitand table-val bitxor c!
    ] each
    c ;

! Verifies an MPEG-2 PSI section whose final 4 bytes are the big-endian CRC.
! A valid section evaluates to 0x00000000 when the CRC bytes are included.
:: verify-mpeg2-crc ( bytes -- ? )
    bytes crc32-mpeg2 zero? ;
