! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Factor FFI bindings for C99 SIMD fast-path acceleration library.
! Provides zero-copy Annex B NAL scanning and CRC-32 calculation.

USING: alien alien.c-types alien.libraries alien.syntax
combinators continuations kernel locals math sequences system venturi.common.crc ;
IN: venturi.codecs.simd

<<
"venturi_simd" {
    { [ os macos? ] [ "c_src/libventuri_simd.dylib" ] }
    { [ os unix? ]  [ "c_src/libventuri_simd.so" ] }
    { [ os windows? ] [ "c_src/venturi_simd.dll" ] }
} cond [ cdecl add-library ] when*
>>

LIBRARY: venturi_simd

FUNCTION: size_t venturi_scan_annexb ( void* data, size_t len, void* offsets, void* prefix_lens, size_t max_offsets )
FUNCTION: size_t venturi_unescape_emulation_prevention ( void* src, size_t src_len, void* dst )
FUNCTION: uint32_t venturi_crc32 ( void* data, size_t len )

! High-level wrapper computing CRC-32 via SIMD C library with native Factor fallback.
:: fast-crc32 ( byte-arr -- crc )
    [ byte-arr byte-arr length venturi_crc32 ]
    [ drop byte-arr crc32-ieee ] recover ;
