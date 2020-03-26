! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Resolvers and builders for 32-bit Chunk Offset (stco) and 64-bit Chunk
! Large Offset (co64) boxes, computing absolute sample file locations.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
sequences vectors venturi.common.utils venturi.isobmff.box-reader
venturi.isobmff.box-writer venturi.isobmff.constants
venturi.isobmff.sample-table ;
IN: venturi.isobmff.chunk-offset

! Parses an stco 32-bit Chunk Offset FullBox.
:: parse-stco ( box -- offsets )
    box payload>> :> p
    p length 8 < [ { } ] [
        p 4 read-be32 :> entry-count
        entry-count 0 <array> :> out
        8 :> off!
        entry-count <iota> [
            :> i
            off p length 4 - <= [
                p off read-be32 i out set-nth
                off 4 + off!
            ] when
        ] each
        out
    ] if ;

! Parses a co64 64-bit Chunk Large Offset FullBox.
:: parse-co64 ( box -- offsets )
    box payload>> :> p
    p length 8 < [ { } ] [
        p 4 read-be32 :> entry-count
        entry-count 0 <array> :> out
        8 :> off!
        entry-count <iota> [
            :> i
            off p length 8 - <= [
                p off read-be64 i out set-nth
                off 8 + off!
            ] when
        ] each
        out
    ] if ;

! Resolves the absolute byte offset of every sample across all chunks.
:: resolve-sample-file-offsets ( chunk-offsets stsc-entries sample-sizes -- sample-offsets )
    chunk-offsets length :> total-chunks
    V{ } clone :> out
    0 :> global-sample-idx!
    0 :> stsc-idx!

    total-chunks <iota> [
        :> c-idx
        c-idx 1 + :> chunk-num

        ! Advance stsc-idx if next entry applies
        [
            stsc-idx 1 + stsc-entries length < [
                stsc-idx 1 + stsc-entries nth first-chunk>> chunk-num <=
            ] [ f ] if
        ] [
            stsc-idx 1 + stsc-idx!
        ] while

        stsc-idx stsc-entries nth samples-per-chunk>> :> samples-in-chunk
        c-idx chunk-offsets nth :> curr-chunk-offset!

        samples-in-chunk <iota> [
            drop
            global-sample-idx sample-sizes length < [
                curr-chunk-offset out push
                global-sample-idx sample-sizes nth :> s-sz
                curr-chunk-offset s-sz + curr-chunk-offset!
                global-sample-idx 1 + global-sample-idx!
            ] when
        ] each
    ] each
    out >array ;

! Builds a 32-bit stco chunk offset box.
:: build-stco-box ( chunk-offsets -- box-bytes )
    chunk-offsets length 4 * 4 + <byte-vector> :> p
    p chunk-offsets length push-be32
    chunk-offsets [ p swap push-be32 ] each
    FOURCC_STCO 0 0 p >byte-array serialize-full-box ;

! Builds a 64-bit co64 chunk large offset box.
:: build-co64-box ( chunk-offsets -- box-bytes )
    chunk-offsets length 8 * 4 + <byte-vector> :> p
    p chunk-offsets length push-be32
    chunk-offsets [ p swap push-be64 ] each
    FOURCC_CO64 0 0 p >byte-array serialize-full-box ;
