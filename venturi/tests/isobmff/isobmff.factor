! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit test suite for ISOBMFF box serialization, atom parsing,
! sample table run-length decoding, and CMAF fragmented MP4 assembly.

USING: accessors arrays byte-arrays byte-vectors io kernel locals math
sequences sets vectors venturi.common.types venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.box-writer
venturi.isobmff.chunk-offset venturi.isobmff.constants
venturi.isobmff.movie-fragment venturi.isobmff.sample-table
venturi.isobmff.track-header venturi.tests.harness ;
IN: venturi.tests.isobmff

:: test-box-reader-writer ( -- )
    "Testing Box Reader and Writer..." print

    ! Basic box serialization and parsing
    B{ 0x11 0x22 0x33 0x44 } :> payload
    FOURCC_FREE payload serialize-box :> free-box-bytes
    free-box-bytes length 12 "free box has length 12" test=
    free-box-bytes 0 read-be32 12 "free box size is 12" test=
    free-box-bytes 4 read-be32 FOURCC_FREE "free box type is FOURCC_FREE" test=

    free-box-bytes 0 free-box-bytes length parse-box :> ( b1 next-off1 )
    next-off1 12 "parsed next offset is 12" test=
    b1 type>> FOURCC_FREE "parsed type is FOURCC_FREE" test=
    b1 size>> 12 "parsed size is 12" test=
    b1 payload>> payload "parsed payload matches original" test=

    ! FullBox serialization and parsing
    FOURCC_MVHD 1 0x000007 payload serialize-full-box :> mvhd-bytes
    mvhd-bytes length 16 "mvhd full box has length 16" test=
    mvhd-bytes 0 mvhd-bytes length parse-box :> ( b2 next-off2 )
    next-off2 16 "next offset is 16" test=
    b2 version>> 1 "full box version is 1" test=
    b2 flags>> 0x000007 "full box flags match 0x000007" test=

    ! Nested container box parsing
    FOURCC_MOOV { free-box-bytes mvhd-bytes } serialize-container-box :> moov-bytes
    moov-bytes 0 moov-bytes length parse-box :> ( moov-box next-moov )
    moov-box children>> length 2 "moov has 2 children" test=
    moov-box FOURCC_FREE find-child-box [ type>> ] [ 0 ] if* FOURCC_FREE "found child FREE" test=
    moov-box FOURCC_MVHD find-child-box [ version>> ] [ 0 ] if* 1 "found child MVHD with version 1" test= ;

:: test-header-builders-and-parsers ( -- )
    "Testing Header Builders and Parsers..." print

    ! mvhd
    1000 60000 2 build-mvhd-box :> mvhd-bytes
    mvhd-bytes 0 mvhd-bytes length parse-box drop parse-mvhd :> mvhd-info
    mvhd-info timescale>> 1000 "mvhd timescale is 1000" test=
    mvhd-info duration>> 60000 "mvhd duration is 60000" test=
    mvhd-info next-track-id>> 2 "mvhd next track id is 2" test=

    ! tkhd
    1 60000 1920.0 1080.0 f build-tkhd-box :> tkhd-bytes
    tkhd-bytes 0 tkhd-bytes length parse-box drop parse-tkhd :> tkhd-info
    tkhd-info track-id>> 1 "tkhd track id is 1" test=
    tkhd-info duration>> 60000 "tkhd duration is 60000" test=
    tkhd-info width>> 1920.0 "tkhd width is 1920.0" test=
    tkhd-info height>> 1080.0 "tkhd height is 1080.0" test=

    ! mdhd
    90000 5400000 "eng" build-mdhd-box :> mdhd-bytes
    mdhd-bytes 0 mdhd-bytes length parse-box drop parse-mdhd :> mdhd-info
    mdhd-info timescale>> 90000 "mdhd timescale is 90000" test=
    mdhd-info duration>> 5400000 "mdhd duration is 5400000" test=
    mdhd-info language>> "eng" "mdhd language is 'eng'" test=

    ! hdlr
    HANDLER_VIDE "VideoHandler" build-hdlr-box :> hdlr-bytes
    hdlr-bytes 0 hdlr-bytes length parse-box drop parse-hdlr :> hdlr-info
    hdlr-info handler-type>> HANDLER_VIDE "hdlr handler type is HANDLER_VIDE" test=
    hdlr-info name>> "VideoHandler" head? "hdlr name contains 'VideoHandler'" test-true ;

:: test-sample-tables ( -- )
    "Testing Sample Tables and Offsets..." print

    ! stts runlength compression and expansion
    { 3000 3000 3000 3000 6000 6000 } :> original-durations
    original-durations build-stts-box :> stts-bytes
    stts-bytes 0 stts-bytes length parse-box drop parse-stts :> parsed-durations
    parsed-durations original-durations "stts durations roundtrip exactly" test=

    ! ctts composition offsets
    { 0 1000 2000 1000 0 } :> original-offsets
    original-offsets build-ctts-box :> ctts-bytes
    ctts-bytes 0 ctts-bytes length parse-box drop parse-ctts :> parsed-offsets
    parsed-offsets original-offsets "ctts offsets roundtrip exactly" test=

    ! stss sync sample set
    { 1 25 50 } :> sync-indices
    sync-indices build-stss-box :> stss-bytes
    stss-bytes 0 stss-bytes length parse-box drop parse-stss :> sync-set
    1 sync-set in? "sample 1 in sync-set" test-true
    25 sync-set in? "sample 25 in sync-set" test-true
    10 sync-set in? "sample 10 not in sync-set" test-false

    ! stsz sample sizes
    { 4000 1200 800 1500 950 } :> original-sizes
    original-sizes build-stsz-box :> stsz-bytes
    stsz-bytes 0 stsz-bytes length parse-box drop parse-stsz :> parsed-sizes
    parsed-sizes original-sizes "stsz sizes roundtrip exactly" test=

    ! stsc and chunk offset calculation
    { 1000 5000 } :> chunk-offsets
    1 2 1 <stsc-entry> 2 3 1 <stsc-entry> 2array :> stsc-entries
    { 500 600 700 800 900 } :> sample-sizes
    chunk-offsets stsc-entries sample-sizes resolve-sample-file-offsets :> calculated-offsets
    calculated-offsets length 5 "resolved 5 sample offsets" test=
    0 calculated-offsets nth 1000 "sample 1 offset is 1000" test=
    1 calculated-offsets nth 1500 "sample 2 offset is 1500 (1000 + 500)" test=
    2 calculated-offsets nth 5000 "sample 3 offset is 5000 (chunk 2 start)" test=
    3 calculated-offsets nth 5700 "sample 4 offset is 5700 (5000 + 700)" test=
    4 calculated-offsets nth 6500 "sample 5 offset is 6500 (5700 + 800)" test= ;

:: test-cmaf-fragment-pipeline ( -- )
    "Testing CMAF Fragment Assembly..." print

    ! Build a sequence of synthetic video samples
    V{ } clone :> samples
    1 0 0 3000 100 1 B{ 0x01 0x02 0x03 0x04 } <media-sample> samples push
    1 3000 3000 3000 80 0 B{ 0x05 0x06 0x07 } <media-sample> samples push
    1 6000 6000 3000 90 0 B{ 0x08 0x09 } <media-sample> samples push

    ! Assemble into CMAF media segment
    1 1 0 samples build-cmaf-segment :> segment-bytes
    segment-bytes length 0 > "segment-bytes is non-empty" test-true

    ! Parse root boxes of segment
    segment-bytes 0 segment-bytes length parse-boxes :> root-boxes
    root-boxes length 2 "segment contains exactly moof and mdat" test=
    0 root-boxes nth type>> FOURCC_MOOF "first box is MOOF" test=
    1 root-boxes nth type>> FOURCC_MDAT "second box is MDAT" test=

    ! Parse moof children
    0 root-boxes nth :> moof-box
    moof-box FOURCC_MFHD find-child-box parse-mfhd 1 "mfhd sequence number is 1" test=
    moof-box { 0x74726166 0x74666864 } find-box-path parse-tfhd 1 "tfhd track id is 1" test=
    moof-box { 0x74726166 0x74666474 } find-box-path parse-tfdt 0 "tfdt base decode time is 0" test=

    ! Reconstruct samples from segment
    1 root-boxes nth payload>> :> mdat-payload
    moof-box { 0x74726166 0x7472756E } find-box-path 1 0 mdat-payload parse-trun-samples :> recovered-samples
    recovered-samples length 3 "recovered exactly 3 samples" test=
    0 recovered-samples nth keyframe? "sample 0 is keyframe" test-true
    1 recovered-samples nth keyframe? "sample 1 is non-keyframe" test-false
    0 recovered-samples nth size>> 100 "sample 0 size is 100" test=
    1 recovered-samples nth size>> 80 "sample 1 size is 80" test=
    2 recovered-samples nth size>> 90 "sample 2 size is 90" test= ;

:: run-all-isobmff-tests ( -- ? )
    init-test-harness
    test-box-reader-writer
    test-header-builders-and-parsers
    test-sample-tables
    test-cmaf-fragment-pipeline
    "ISOBMFF Engine Suite" print-test-summary ;
