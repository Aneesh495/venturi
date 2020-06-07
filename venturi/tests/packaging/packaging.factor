! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit test suite for CMAF track packaging, init.mp4 generation,
! keyframe-aligned temporal chunking, and 64-bit continuous timeline tracking.

USING: accessors arrays byte-arrays byte-vectors io kernel locals math
sequences strings venturi.common.types venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.box-writer
venturi.isobmff.constants venturi.packaging.cmaf
venturi.packaging.chunker venturi.packaging.pipeline
venturi.packaging.timeline venturi.tests.harness ;
IN: venturi.tests.packaging

:: test-cmaf-init-generation ( -- )
    "Testing CMAF Initialization Segment (init.mp4) Generation..." print

    ! Build synthetic video and audio tracks
    B{ 0x01 0x42 0xE0 0x1F 0xFF 0xE1 0x00 0x08 66 224 31 244 2 128 45 208 0x01 0x00 0x01 208 } :> dummy-avcc
    FOURCC_AVCC dummy-avcc serialize-box :> avcc-box

    B{ 0x00 0x00 0x00 0x00 0x03 0x16 0x00 0x01 0x00 0x04 0x0F 0x40 0x15 0x00 0x00 0x00 0x00 0x01 0xF4 0x00 0x00 0x01 0xF4 0x00 0x05 0x02 0x11 0x90 0x06 0x01 0x02 } :> dummy-esds
    FOURCC_ESDS dummy-esds serialize-box :> esds-box

    1 "avc1" 90000 1920 1080 avcc-box <video-track> :> v-trk
    2 "mp4a" 48000 48000 2 esds-box <audio-track> :> a-trk

    { v-trk a-trk } build-cmaf-init-segment :> init-bytes
    init-bytes length 0 > "init segment is non-empty" test-true

    ! Parse root boxes (must be ftyp and moov)
    init-bytes 0 init-bytes length parse-boxes :> root-boxes
    root-boxes length 2 "init segment contains exactly 2 root boxes" test=
    0 root-boxes nth type>> FOURCC_FTYP "first box is ftyp" test=
    1 root-boxes nth type>> FOURCC_MOOV "second box is moov" test=

    ! Inspect moov container
    1 root-boxes nth :> moov-box
    moov-box FOURCC_MVHD find-child-box f = not "moov contains mvhd" test-true
    moov-box FOURCC_MVEX find-child-box f = not "moov contains mvex" test-true

    ! Check trak children
    moov-box children>> [ type>> FOURCC_TRAK = ] filter :> trak-boxes
    trak-boxes length 2 "moov contains 2 trak boxes" test=

    ! Check mvex has 2 trex children
    moov-box FOURCC_MVEX find-child-box children>> [ type>> FOURCC_TREX = ] filter :> trex-boxes
    trex-boxes length 2 "mvex contains 2 trex boxes" test= ;

:: test-temporal-chunker ( -- )
    "Testing Temporal Keyframe Chunker..." print

    ! Build 90 video samples (3 seconds at 30 fps, 3000 ticks per frame at 90kHz)
    ! Keyframes at frame 0, 30, and 60
    V{ } clone :> v-samples
    90 [
        :> i
        i 3000 * :> pts
        i 30 mod zero? 1 0 ? :> flags
        1 pts pts 3000 1000 flags B{ 0x01 0x02 0x03 } <media-sample> v-samples push
    ] each-integer

    ! Build audio samples (1024 samples per frame at 48kHz = 21.33ms = 1920 ticks at 90kHz)
    V{ } clone :> a-samples
    140 [
        :> j
        j 1024 * :> a-pts
        2 a-pts a-pts 1024 200 1 B{ 0xAA 0xBB } <media-sample> a-samples push
    ] each-integer

    v-samples split-samples-into-gops :> gops
    gops length 3 "split 90 samples into 3 GOPs of 30 frames" test=

    1 "avc1" 90000 1920 1080 B{ } <video-track> :> v-trk
    v-trk v-samples >>samples drop
    2 "mp4a" 48000 48000 2 B{ } <audio-track> :> a-trk
    a-trk a-samples >>samples drop

    ! Target 1000 ms chunks
    v-trk a-trk 1000 chunk-tracks :> chunks
    chunks length 3 "chunked into 3 segments" test=
    0 chunks nth video-samples>> length 30 "chunk 0 has 30 video frames" test=
    1 chunks nth video-samples>> length 30 "chunk 1 has 30 video frames" test=
    2 chunks nth video-samples>> length 30 "chunk 2 has 30 video frames" test=
    0 chunks nth keyframe?>> "chunk 0 starts on keyframe" test-true
    1 chunks nth keyframe?>> "chunk 1 starts on keyframe" test-true
    2 chunks nth keyframe?>> "chunk 2 starts on keyframe" test-true ;

:: test-timeline-coordinator ( -- )
    "Testing 64-bit Timeline Coordinator..." print

    90000 <media-timeline> :> tl

    ! Initial timestamp 90000 (1 second), duration 3000
    tl 90000 3000 advance-timeline 0 "initial PTS normalizes to 0" test=
    tl 93000 3000 advance-timeline 3000 "second PTS advances by 3000" test=
    tl 96000 3000 advance-timeline 6000 "third PTS advances by 3000" test=

    ! Simulate 33-bit rollover (from near 2^33 to near 0)
    ! Last PTS at 8589930000, next PTS at 3000
    tl 8589930000 >>last-raw-pts drop
    tl 3000 3000 advance-timeline :> rolled-pts
    tl rollover-count>> 1 "detected 1 rollover event" test=
    rolled-pts 6000 >= "timeline advances monotonically across rollover" test-true

    ! Discontinuity detection
    tl 900000 discontinuity? "large timestamp jump detected as discontinuity" test-true
    tl 3030 discontinuity? "normal progression is not discontinuity" test-false ;

:: test-transmux-pipeline ( -- )
    "Testing Full CMAF Transmux Pipeline..." print

    ! Build video samples with Annex B NALs
    B{ 66 224 31 244 2 128 45 208 } :> sps-bytes
    B{ 208 } :> pps-bytes
    B{ 0x00 0x00 0x00 0x01 } sps-bytes append
    B{ 0x00 0x00 0x00 0x01 } append pps-bytes append
    B{ 0x00 0x00 0x00 0x01 0x65 0x11 0x22 0x33 } append :> idr-annex-b

    V{ } clone :> v-samples
    1 0 0 3000 idr-annex-b length 1 idr-annex-b <media-sample> v-samples push

    1 "avc1" 90000 0 0 B{ } <video-track> :> v-trk
    v-trk v-samples >>samples drop

    { v-trk } 2000 transmux-tracks-to-cmaf :> result
    result f = not "transmux result is non-f" test-true
    result init-segment>> f = not "result contains init segment" test-true
    result init-segment>> uri>> "init.mp4" "init segment URI is init.mp4" test=
    result init-segment>> is-init>> "is-init flag is true" test-true
    result media-segments>> length 1 "produced 1 media segment" test=

    0 result media-segments>> nth :> seg0
    seg0 uri>> "segment_1.m4s" "segment 0 URI is segment_1.m4s" test=
    seg0 is-init>> "segment 0 is-init is false" test-false

    ! Verify segment starts with styp box
    seg0 data>> 4 read-be32 FOURCC_STYP "segment begins with styp box" test= ;

:: run-all-packaging-tests ( -- ? )
    init-test-harness
    test-cmaf-init-generation
    test-temporal-chunker
    test-timeline-coordinator
    test-transmux-pipeline
    "CMAF Packaging & Chunker Test Suite" print-test-summary ;
