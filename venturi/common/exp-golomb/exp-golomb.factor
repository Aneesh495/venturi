! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Exponential-Golomb variable-length entropy coding parser and serializer
! conforming to ITU-T H.264 / ISO-IEC 14496-10 and HEVC syntax specifications.

USING: accessors kernel locals math math.bitwise math.functions
sequences venturi.common.bitstream ;
IN: venturi.common.exp-golomb

:: read-ue ( reader -- val )
    0 :> leading-zeros!
    [ reader read-bit zero? ] [
        leading-zeros 1 + leading-zeros!
    ] while
    leading-zeros zero? [ 0 ] [
        reader leading-zeros read-bits :> info
        1 leading-zeros shift 1 - info +
    ] if ;

:: read-se ( reader -- val )
    reader read-ue :> k
    k 1 bitand 1 = [
        k 1 + 2 /i
    ] [
        k 2 /i neg
    ] if ;

:: read-te ( reader range -- val )
    range 1 <= [
        reader read-bit 1 = 0 1 ?
    ] [
        reader read-ue
    ] if ;

:: write-ue ( writer val -- )
    val 0 < [ "ue(v) value cannot be negative" throw ] when
    val 1 + :> temp
    temp log2 >integer :> m
    writer 0 m write-bits
    writer temp m 1 + write-bits ;

:: write-se ( writer val -- )
    val 0 <= [
        val neg 2 *
    ] [
        val 2 * 1 -
    ] if :> k
    writer k write-ue ;
