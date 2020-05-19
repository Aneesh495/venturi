! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ISO/IEC 23000-19 Common Media Application Format (CMAF) track packager.
! Initialization segment generator (init.mp4), Movie Extends (mvex/trex) authoring,
! and ISO/IEC 14496-12 visual and audio sample description synthesizer.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.order sequences vectors venturi.codecs.aac venturi.codecs.h264
venturi.codecs.h265 venturi.common.types venturi.common.utils
venturi.isobmff.box-writer venturi.isobmff.constants
venturi.isobmff.track-header ;
IN: venturi.packaging.cmaf

! Builds an ISO/IEC 14496-12 File Type (ftyp) box.
:: build-ftyp-box ( major-brand minor-ver compatible-brands -- ftyp-bytes )
    compatible-brands length 4 * 8 + <byte-vector> :> buf
    buf major-brand push-be32
    buf minor-ver push-be32
    compatible-brands [ :> b buf b push-be32 ] each
    FOURCC_FTYP buf >byte-array serialize-box ;

! Builds a Segment Type (styp) box for CMAF media segments.
:: build-styp-box ( major-brand minor-ver compatible-brands -- styp-bytes )
    compatible-brands length 4 * 8 + <byte-vector> :> buf
    buf major-brand push-be32
    buf minor-ver push-be32
    compatible-brands [ :> b buf b push-be32 ] each
    FOURCC_STYP buf >byte-array serialize-box ;

! Default CMAF File Type box (major 'cmfc', brands cmfc, iso6, isom, mp41).
: build-cmaf-ftyp-box ( -- ftyp-bytes )
    0x636D6663 0 { 0x636D6663 0x69736F36 0x69736F6D 0x6D703431 } build-ftyp-box ;

! Default CMAF Segment Type box (major 'cmfs', brands cmfs, iso6, msdh).
: build-cmaf-styp-box ( -- styp-bytes )
    0x636D6673 0 { 0x636D6673 0x69736F36 0x6D736468 } build-styp-box ;

! Builds an ISO/IEC 14496-12 Video Media Header (vmhd) box.
: build-vmhd-box ( -- vmhd-bytes )
    FOURCC_VMHD 0 1 B{ 0 0 0 0 0 0 0 0 } serialize-full-box ;

! Builds an ISO/IEC 14496-12 Sound Media Header (smhd) box.
: build-smhd-box ( -- smhd-bytes )
    FOURCC_SMHD 0 0 B{ 0 0 0 0 } serialize-full-box ;

! Builds an ISO/IEC 14496-12 Data Information (dinf) box containing local self-ref dref.
:: build-dinf-box ( -- dinf-bytes )
    FOURCC_URL 0 1 B{ } serialize-full-box :> url-box
    16 <byte-vector> :> dref-payload
    dref-payload 1 push-be32 ! entry_count = 1
    dref-payload url-box push-bytes
    FOURCC_DREF 0 0 dref-payload >byte-array serialize-full-box :> dref-box
    FOURCC_DINF { dref-box } serialize-container-box ;

! Builds an ISO/IEC 14496-12 VisualSampleEntry (78 bytes) with child configuration box.
:: build-visual-sample-entry ( fourcc width height config-box -- entry-bytes )
    128 config-box length + <byte-vector> :> buf
    buf 0 push-be32 ! reserved 4 bytes
    buf 0 push-be16 ! reserved 2 bytes
    buf 1 push-be16 ! data_reference_index = 1
    buf 0 push-be16 ! pre_defined = 0
    buf 0 push-be16 ! reserved = 0
    buf 0 push-be32 ! pre_defined[0] = 0
    buf 0 push-be32 ! pre_defined[1] = 0
    buf 0 push-be32 ! pre_defined[2] = 0
    buf width push-be16
    buf height push-be16
    buf 0x00480000 push-be32 ! horizresolution = 72 dpi (16.16)
    buf 0x00480000 push-be32 ! vertresolution = 72 dpi (16.16)
    buf 0 push-be32 ! reserved = 0
    buf 1 push-be16 ! frame_count = 1
    32 [ buf 0 push-u8 ] times ! compressorname (32 bytes nulls)
    buf 0x0018 push-be16 ! depth = 24 bpp
    buf 0xFFFF push-be16 ! pre_defined = -1
    buf config-box push-bytes
    fourcc buf >byte-array serialize-box ;

! Builds an ISO/IEC 14496-12 AudioSampleEntry (28 bytes) with child esds box.
:: build-audio-sample-entry ( fourcc channels sample-rate esds-box -- entry-bytes )
    64 esds-box length + <byte-vector> :> buf
    buf 0 push-be32 ! reserved 4 bytes
    buf 0 push-be16 ! reserved 2 bytes
    buf 1 push-be16 ! data_reference_index = 1
    buf 0 push-be32 ! reserved[0] = 0
    buf 0 push-be32 ! reserved[1] = 0
    buf channels push-be16
    buf 16 push-be16 ! samplesize = 16 bits
    buf 0 push-be16 ! pre_defined = 0
    buf 0 push-be16 ! reserved = 0
    buf sample-rate 16 shift push-be32 ! samplerate (16.16)
    buf esds-box push-bytes
    fourcc buf >byte-array serialize-box ;

! Builds an empty ISO/IEC 14496-12 Sample Table (stbl) container for fragmented media.
:: build-fragmented-stbl-box ( sample-entry-box -- stbl-bytes )
    16 sample-entry-box length + <byte-vector> :> stsd-payload
    stsd-payload 1 push-be32 ! entry_count = 1
    stsd-payload sample-entry-box push-bytes
    FOURCC_STSD 0 0 stsd-payload >byte-array serialize-full-box :> stsd-box

    FOURCC_STTS 0 0 B{ 0 0 0 0 } serialize-full-box :> stts-box
    FOURCC_STSC 0 0 B{ 0 0 0 0 } serialize-full-box :> stsc-box
    FOURCC_STSZ 0 0 B{ 0 0 0 0 0 0 0 0 } serialize-full-box :> stsz-box
    FOURCC_STCO 0 0 B{ 0 0 0 0 } serialize-full-box :> stco-box

    FOURCC_STBL { stsd-box stts-box stsc-box stsz-box stco-box } serialize-container-box ;

! Builds an ISO/IEC 14496-12 Track Extends (trex) box for fragmented playback.
:: build-trex-box ( track-id -- trex-bytes )
    32 <byte-vector> :> buf
    buf track-id push-be32
    buf 1 push-be32 ! default_sample_description_index = 1
    buf 0 push-be32 ! default_sample_duration = 0
    buf 0 push-be32 ! default_sample_size = 0
    buf 0 push-be32 ! default_sample_flags = 0
    FOURCC_TREX 0 0 buf >byte-array serialize-full-box ;

! Builds an ISO/IEC 14496-12 Movie Extends Header (mehd) box for overall duration declaration.
:: build-mehd-box ( duration-64bit -- mehd-bytes )
    8 <byte-vector> :> buf
    buf duration-64bit push-be64
    FOURCC_MEHD 1 0 buf >byte-array serialize-full-box ;

! Builds an ISO/IEC 14496-12 Movie Extends (mvex) box containing trex boxes for each track.
:: build-mvex-box ( tracks -- mvex-bytes )
    tracks [ id>> build-trex-box ] { } map-as :> trex-boxes
    FOURCC_MVEX trex-boxes serialize-container-box ;

! Builds an ISO/IEC 14496-12 Movie Extends (mvex) box with explicit mehd duration.
:: build-mvex-box-with-duration ( tracks total-duration -- mvex-bytes )
    tracks [ id>> build-trex-box ] { } map-as :> trex-boxes
    total-duration build-mehd-box :> mehd-box
    V{ mehd-box } clone :> children
    trex-boxes [ :> t-box children t-box push ] each
    FOURCC_MVEX children >array serialize-container-box ;

! Builds an ISO/IEC 14496-12 Media (minf) box for video or audio.
:: build-minf-box ( is-video? sample-entry-box -- minf-bytes )
    is-video? [ build-vmhd-box ] [ build-smhd-box ] if :> header-box
    build-dinf-box :> dinf-box
    sample-entry-box build-fragmented-stbl-box :> stbl-box
    FOURCC_MINF { header-box dinf-box stbl-box } serialize-container-box ;

! Builds an ISO/IEC 14496-12 Track (trak) container box for an initialization segment.
:: build-cmaf-trak-box ( track -- trak-bytes )
    track type>> +video+ = :> is-video?
    track timescale>> :> timescale

    ! tkhd
    track id>> 0 track width>> >float track height>> >float build-tkhd-box :> tkhd-box

    ! mdhd
    timescale 0 "und" build-mdhd-box :> mdhd-box

    ! hdlr
    is-video? [ HANDLER_VIDE "VideoHandler" ] [ HANDLER_SOUN "SoundHandler" ] if
    build-hdlr-box :> hdlr-box

    ! stsd sample entry
    is-video? [
        track codec>> "hev1" = track codec>> "hvc1" = or [
            FOURCC_HEV1 track width>> track height>> track codec-private>>
            build-visual-sample-entry
        ] [
            FOURCC_AVC1 track width>> track height>> track codec-private>>
            build-visual-sample-entry
        ] if
    ] [
        FOURCC_MP4A track channels>> track sample-rate>> track codec-private>>
        build-audio-sample-entry
    ] if :> sample-entry

    ! minf
    is-video? sample-entry build-minf-box :> minf-box

    ! mdia
    FOURCC_MDIA { mdhd-box hdlr-box minf-box } serialize-container-box :> mdia-box

    ! trak
    FOURCC_TRAK { tkhd-box mdia-box } serialize-container-box ;

! Generates a complete, standard-compliant CMAF Track Initialization Segment (init.mp4).
:: build-cmaf-init-segment ( tracks -- init-bytes )
    build-cmaf-ftyp-box :> ftyp-box

    ! mvhd
    1000 0 1 tracks [ id>> ] [ max ] each 1 + build-mvhd-box :> mvhd-box

    ! trak boxes
    tracks [ build-cmaf-trak-box ] { } map-as :> trak-boxes

    ! mvex box
    tracks build-mvex-box :> mvex-box

    ! moov
    V{ mvhd-box } clone :> moov-children
    trak-boxes [ :> trk-box moov-children trk-box push ] each
    moov-children mvex-box push

    FOURCC_MOOV moov-children >array serialize-container-box :> moov-box

    ftyp-box moov-box append ;
