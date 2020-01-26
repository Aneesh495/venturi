! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Arbitrary-width bitstream reader and writer with bit-level cursor navigation,
! big-endian bit ordering, and byte-boundary alignment primitives.

USING: accessors byte-arrays byte-vectors kernel locals math
math.bitwise math.order sequences ;
IN: venturi.common.bitstream

! Bitstream reader with bit-level cursor indexing into a contiguous byte-array.
TUPLE: bit-reader
    { data byte-array read-only }
    { bit-pos integer }
    { bit-length integer read-only } ;

: <bit-reader> ( byte-array -- reader )
    dup length 8 *
    0 swap bit-reader boa ;

: bits-remaining ( reader -- n )
    [ bit-length>> ] [ bit-pos>> ] bi - 0 max ;

ERROR: bitstream-underflow requested remaining ;

:: check-bits-available ( reader n -- )
    reader bits-remaining n < [
        n reader bits-remaining bitstream-underflow
    ] when ;

:: read-bit ( reader -- bit )
    reader 1 check-bits-available
    reader data>> :> d
    reader bit-pos>> :> pos
    pos -3 shift :> byte-idx
    pos 7 bitand :> bit-idx
    byte-idx d nth :> b
    b 7 bit-idx - bit? 1 0 ? :> bit-val
    reader pos 1 + >>bit-pos drop
    bit-val ;

:: read-bits ( reader n -- val )
    n zero? [ 0 ] [
        reader n check-bits-available
        0 :> acc!
        n <iota> [
            drop
            acc 1 shift reader read-bit + acc!
        ] each
        acc
    ] if ;

:: peek-bits ( reader n -- val )
    reader bit-pos>> :> saved-pos
    reader n read-bits :> res
    reader saved-pos >>bit-pos drop
    res ;

:: skip-bits ( reader n -- )
    reader n check-bits-available
    reader reader bit-pos>> n + >>bit-pos drop ;

: byte-aligned? ( reader -- ? )
    bit-pos>> 7 bitand zero? ;

:: align-to-byte ( reader -- )
    reader bit-pos>> 7 bitand :> rem
    rem zero? [ ] [
        reader 8 rem - skip-bits
    ] if ;

:: read-bytes ( reader n -- bytes )
    n <byte-array> :> out
    n <iota> [
        :> i
        reader 8 read-bits i out set-nth
    ] each
    out ;

! Arbitrary-width bitstream writer accumulating into a dynamic byte-vector.
TUPLE: bit-writer
    { buffer byte-vector }
    { current-byte integer }
    { bits-in-byte integer } ;

: <bit-writer> ( -- writer )
    1024 <byte-vector> 0 0 bit-writer boa ;

:: write-bit ( writer bit -- )
    bit 1 bitand :> b
    writer writer current-byte>> 1 shift b + >>current-byte drop
    writer bits-in-byte>> 1 + :> cnt
    cnt 8 = [
        writer current-byte>> writer buffer>> push
        writer 0 >>current-byte drop
        writer 0 >>bits-in-byte drop
    ] [
        writer cnt >>bits-in-byte drop
    ] if ;

:: write-bits ( writer val n -- )
    n zero? [ ] [
        n <iota> <reversed> [
            :> shift-amt
            val shift-amt bit? 1 0 ? :> bit
            writer bit write-bit
        ] each
    ] if ;

:: flush-byte ( writer -- )
    writer bits-in-byte>> :> bits
    bits zero? [ ] [
        8 bits - :> pad
        writer writer current-byte>> pad shift >>current-byte drop
        writer current-byte>> writer buffer>> push
        writer 0 >>current-byte drop
        writer 0 >>bits-in-byte drop
    ] if ;

:: write-bytes ( writer byte-array -- )
    writer flush-byte
    byte-array [ writer buffer>> push ] each ;

:: writer-bytes ( writer -- byte-array )
    writer flush-byte
    writer buffer>> >byte-array ;
