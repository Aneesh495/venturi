! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! High-throughput binary slicing, 4CC atom identifier encoding/decoding,
! big-endian multi-byte appenders, and hex formatting utilities.

USING: arrays byte-arrays byte-vectors kernel locals math
math.bitwise math.functions math.order sequences strings ;
IN: venturi.common.utils

! Converts a 4-character string into a 32-bit unsigned FourCC integer.
:: string>4cc ( str -- val )
    0 :> acc!
    str 4 head [
        :> ch
        acc 8 shift ch + acc!
    ] each
    acc ;

! Converts a 32-bit unsigned FourCC integer into a 4-character string.
:: 4cc>string ( val -- str )
    { 24 16 8 0 } [ val swap neg shift 0xFF bitand ] "" map-as ;

! Reads a 16-bit big-endian unsigned integer from bytes at offset.
:: read-be16 ( bytes offset -- val )
    offset bytes nth 8 shift
    offset 1 + bytes nth + ;

! Reads a 24-bit big-endian unsigned integer from bytes at offset.
:: read-be24 ( bytes offset -- val )
    offset bytes nth 16 shift
    offset 1 + bytes nth 8 shift +
    offset 2 + bytes nth + ;

! Reads a 32-bit big-endian unsigned integer from bytes at offset.
:: read-be32 ( bytes offset -- val )
    offset bytes nth 24 shift
    offset 1 + bytes nth 16 shift +
    offset 2 + bytes nth 8 shift +
    offset 3 + bytes nth + ;

! Reads a 64-bit big-endian unsigned integer from bytes at offset.
:: read-be64 ( bytes offset -- val )
    bytes offset read-be32 32 shift
    bytes offset 4 + read-be32 + ;

! Reads a 16.16 fixed-point number as floating point.
:: read-fixed-16-16 ( bytes offset -- val )
    bytes offset read-be32 65536.0 / ;

! Reads an 8.8 fixed-point number as floating point.
:: read-fixed-8-8 ( bytes offset -- val )
    bytes offset read-be16 256.0 / ;

! Appends an 8-bit unsigned integer to a byte-vector.
:: push-u8 ( vec val -- )
    val 0xFF bitand vec push ;

! Appends a 16-bit big-endian unsigned integer to a byte-vector.
:: push-be16 ( vec val -- )
    val -8 shift 0xFF bitand vec push
    val 0xFF bitand vec push ;

! Appends a 24-bit big-endian unsigned integer to a byte-vector.
:: push-be24 ( vec val -- )
    val -16 shift 0xFF bitand vec push
    val -8 shift 0xFF bitand vec push
    val 0xFF bitand vec push ;

! Appends a 32-bit big-endian unsigned integer to a byte-vector.
:: push-be32 ( vec val -- )
    val -24 shift 0xFF bitand vec push
    val -16 shift 0xFF bitand vec push
    val -8 shift 0xFF bitand vec push
    val 0xFF bitand vec push ;

! Appends a 64-bit big-endian unsigned integer to a byte-vector.
:: push-be64 ( vec val -- )
    vec val -32 shift 0xFFFFFFFF bitand push-be32
    vec val 0xFFFFFFFF bitand push-be32 ;

! Appends a 16.16 fixed-point float to a byte-vector.
:: push-fixed-16-16 ( vec flt -- )
    vec flt 65536.0 * round >integer push-be32 ;

! Appends an 8.8 fixed-point float to a byte-vector.
:: push-fixed-8-8 ( vec flt -- )
    vec flt 256.0 * round >integer push-be16 ;

! Appends an entire byte sequence to a byte-vector.
:: push-bytes ( vec bytes -- )
    bytes [ vec push ] each ;

! Safe subseq that clamps bounds to sequence length.
:: subseq-safe ( from to seq -- sub )
    0 from max seq length min :> clamped-from
    clamped-from to max seq length min :> clamped-to
    clamped-from clamped-to seq subseq ;

! Copies bytes from src [src-from, src-to) into dst starting at dst-from.
:: copy-bytes ( src-from src-to src dst-from dst -- )
    src-from src-to src subseq-safe :> slice
    0 :> i!
    slice [
        dst-from i + dst set-nth
        i 1 + i!
    ] each ;

! Formats a byte-array into a hex string representation.
:: bytes>hex ( bytes -- str )
    "0123456789ABCDEF" :> hex-digits
    bytes [
        :> b
        b -4 shift 0xF bitand hex-digits nth
        b 0xF bitand hex-digits nth
        2array
    ] { } map-as concat >string ;

! Finds the index of a needle subsequence in a haystack starting at from-index.
:: find-subsequence-from ( haystack needle from-index -- idx/f )
    needle length :> n-len
    haystack length :> h-len
    h-len n-len - :> max-start
    from-index :> curr!
    f :> found!
    [ curr max-start <= found not and ] [
        curr curr n-len + haystack subseq needle = [
            curr found!
        ] [
            curr 1 + curr!
        ] if
    ] while
    found ;
