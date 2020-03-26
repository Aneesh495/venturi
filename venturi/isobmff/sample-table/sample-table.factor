! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Indexer and run-length expander for Sample Table boxes: Time-to-Sample (stts),
! Composition Time (ctts), Sync Sample (stss), Sample-to-Chunk (stsc), and Sample Size (stsz).

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.order sequences sets vectors venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.box-writer
venturi.isobmff.constants ;
IN: venturi.isobmff.sample-table

! STSC entry tuple: first-chunk (1-based), samples-per-chunk, sample-desc-index.
TUPLE: stsc-entry
    { first-chunk integer read-only }
    { samples-per-chunk integer read-only }
    { desc-index integer read-only } ;

: <stsc-entry> ( chunk count desc -- entry )
    stsc-entry boa ;

! Parses an stts FullBox into a sequence of sample durations (ticks).
:: parse-stts ( box -- durations )
    box payload>> :> p
    p length 8 < [ { } ] [
        p 4 read-be32 :> entry-count
        V{ } clone :> out
        8 :> off!
        entry-count <iota> [
            drop
            off p length 8 - <= [
                p off read-be32 :> count
                p off 4 + read-be32 :> delta
                count <iota> [ drop delta out push ] each
                off 8 + off!
            ] when
        ] each
        out >array
    ] if ;

! Parses a ctts FullBox into a sequence of composition time offsets.
:: parse-ctts ( box -- offsets )
    box payload>> :> p
    p length 8 < [ { } ] [
        p 4 read-be32 :> entry-count
        V{ } clone :> out
        8 :> off!
        entry-count <iota> [
            drop
            off p length 8 - <= [
                p off read-be32 :> count
                p off 4 + read-be32 :> delta
                count <iota> [ drop delta out push ] each
                off 8 + off!
            ] when
        ] each
        out >array
    ] if ;

! Parses an stss FullBox into a set of 1-based keyframe sample numbers.
:: parse-stss ( box -- sync-set )
    box payload>> :> p
    p length 8 < [ HS{ } clone ] [
        p 4 read-be32 :> entry-count
        HS{ } clone :> out
        8 :> off!
        entry-count <iota> [
            drop
            off p length 4 - <= [
                p off read-be32 out adjoin
                off 4 + off!
            ] when
        ] each
        out
    ] if ;

! Parses an stsc FullBox into a vector of stsc-entry tuples.
:: parse-stsc ( box -- entries )
    box payload>> :> p
    p length 8 < [ V{ } clone ] [
        p 4 read-be32 :> entry-count
        entry-count <vector> :> out
        8 :> off!
        entry-count <iota> [
            drop
            off p length 12 - <= [
                p off read-be32 :> first-c
                p off 4 + read-be32 :> s-count
                p off 8 + read-be32 :> d-idx
                first-c s-count d-idx <stsc-entry> out push
                off 12 + off!
            ] when
        ] each
        out
    ] if ;

! Parses an stsz FullBox into a sequence of individual sample sizes in bytes.
:: parse-stsz ( box -- sizes )
    box payload>> :> p
    p length 12 < [ { } ] [
        p 4 read-be32 :> uniform-size
        p 8 read-be32 :> sample-count
        uniform-size zero? [
            sample-count 0 <array> :> out
            12 :> off!
            sample-count <iota> [
                :> i
                off p length 4 - <= [
                    p off read-be32 i out set-nth
                    off 4 + off!
                ] when
            ] each
            out
        ] [
            sample-count <iota> [ drop uniform-size ] { } map-as
        ] if
    ] if ;

! Builds an stts box by run-length compressing consecutive sample durations.
:: build-stts-box ( durations -- box-bytes )
    durations length zero? [
        8 <byte-vector> :> p
        p 0 push-be32  ! entry_count = 0
        FOURCC_STTS 0 0 p >byte-array serialize-full-box
    ] [
        V{ } clone :> runs
        0 durations nth :> curr-delta!
        1 :> curr-count!
        durations 1 tail [
            :> d
            d curr-delta = [
                curr-count 1 + curr-count!
            ] [
                curr-count curr-delta 2array runs push
                d curr-delta!
                1 curr-count!
            ] if
        ] each
        curr-count curr-delta 2array runs push

        runs length 8 * 4 + <byte-vector> :> p
        p runs length push-be32
        runs [
            :> run
            p 0 run nth push-be32
            p 1 run nth push-be32
        ] each
        FOURCC_STTS 0 0 p >byte-array serialize-full-box
    ] if ;

! Builds a ctts box by run-length compressing composition time offsets.
:: build-ctts-box ( offsets -- box-bytes )
    offsets length zero? [
        8 <byte-vector> :> p
        p 0 push-be32
        FOURCC_CTTS 0 0 p >byte-array serialize-full-box
    ] [
        V{ } clone :> runs
        0 offsets nth :> curr-delta!
        1 :> curr-count!
        offsets 1 tail [
            :> d
            d curr-delta = [
                curr-count 1 + curr-count!
            ] [
                curr-count curr-delta 2array runs push
                d curr-delta!
                1 curr-count!
            ] if
        ] each
        curr-count curr-delta 2array runs push

        runs length 8 * 4 + <byte-vector> :> p
        p runs length push-be32
        runs [
            :> run
            p 0 run nth push-be32
            p 1 run nth push-be32
        ] each
        FOURCC_CTTS 0 0 p >byte-array serialize-full-box
    ] if ;

! Builds an stss sync sample box from 1-based keyframe sample indices.
:: build-stss-box ( sync-indices -- box-bytes )
    sync-indices length 4 * 4 + <byte-vector> :> p
    p sync-indices length push-be32
    sync-indices [ p swap push-be32 ] each
    FOURCC_STSS 0 0 p >byte-array serialize-full-box ;

! Builds an stsc box from stsc-entry tuples.
:: build-stsc-box ( stsc-entries -- box-bytes )
    stsc-entries length 12 * 4 + <byte-vector> :> p
    p stsc-entries length push-be32
    stsc-entries [
        :> entry
        p entry first-chunk>> push-be32
        p entry samples-per-chunk>> push-be32
        p entry desc-index>> push-be32
    ] each
    FOURCC_STSC 0 0 p >byte-array serialize-full-box ;

! Builds an stsz sample size box from sample byte sizes.
:: build-stsz-box ( sizes -- box-bytes )
    sizes length 4 * 8 + <byte-vector> :> p
    p 0 push-be32  ! sample_size = 0 (variable sizes)
    p sizes length push-be32
    sizes [ p swap push-be32 ] each
    FOURCC_STSZ 0 0 p >byte-array serialize-full-box ;
