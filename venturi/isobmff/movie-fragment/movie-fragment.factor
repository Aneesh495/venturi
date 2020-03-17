! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Fragmented MP4 (fMP4 / CMAF) box builders: Movie Fragment (moof),
! Track Fragment (traf), Track Fragment Header (tfhd), 64-bit Base Media
! Decode Time (tfdt), Track Fragment Run (trun), and Movie Extends (mvex/trex).

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise sequences vectors venturi.common.types venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.box-writer
venturi.isobmff.constants ;
IN: venturi.isobmff.movie-fragment

! Builds a Track Extends (trex) FullBox for the initialization segment (mvex).
:: build-trex-box ( track-id -- box-bytes )
    20 <byte-vector> :> p
    p track-id push-be32                     ! track_id
    p 1 push-be32                            ! default_sample_description_index = 1
    p 0 push-be32                            ! default_sample_duration = 0
    p 0 push-be32                            ! default_sample_size = 0
    p SAMPLE_FLAG_NON_SYNC push-be32         ! default_sample_flags
    FOURCC_TREX 0 0 p >byte-array serialize-full-box ;

! Builds a Movie Extends (mvex) Box wrapping trex boxes for all tracks.
:: build-mvex-box ( track-ids -- box-bytes )
    track-ids [ build-trex-box ] { } map-as :> trex-boxes
    FOURCC_MVEX trex-boxes serialize-container-box ;

! Builds a Movie Fragment Header (mfhd) FullBox with a sequence number.
:: build-mfhd-box ( sequence-num -- box-bytes )
    4 <byte-vector> :> p
    p sequence-num push-be32
    FOURCC_MFHD 0 0 p >byte-array serialize-full-box ;

! Parses an mfhd FullBox extracting its sequence number.
:: parse-mfhd ( box -- seq-num/f )
    box payload>> :> p
    p length 8 < [ f ] [
        p 4 read-be32
    ] if ;

! Builds a Track Fragment Header (tfhd) FullBox.
! Flags:
!   0x020000: default-base-is-moof
!   0x000020: default-sample-flags-present
:: build-tfhd-box ( track-id default-flags -- box-bytes )
    8 <byte-vector> :> p
    p track-id push-be32
    p default-flags push-be32
    0x020020 :> flags
    FOURCC_TFHD 0 flags p >byte-array serialize-full-box ;

! Parses a tfhd FullBox extracting track_id.
:: parse-tfhd ( box -- track-id/f )
    box payload>> :> p
    p length 8 < [ f ] [
        p 4 read-be32
    ] if ;

! Builds a Track Fragment Base Media Decode Time (tfdt) FullBox (version 1: 64-bit).
:: build-tfdt-box ( base-decode-time -- box-bytes )
    8 <byte-vector> :> p
    p base-decode-time push-be64
    FOURCC_TFDT 1 0 p >byte-array serialize-full-box ;

! Parses a tfdt FullBox extracting baseMediaDecodeTime (supporting version 0 and 1).
:: parse-tfdt ( box -- decode-time/f )
    box payload>> :> p
    p length 8 < [ f ] [
        p 0 nth :> ver
        ver 1 = [
            p length 12 < [ f ] [ p 4 read-be64 ] if
        ] [
            p 4 read-be32
        ] if
    ] if ;

! Builds a Track Fragment Run (trun) FullBox for a sequence of samples.
! Flags:
!   0x000001: data-offset-present
!   0x000004: first-sample-flags-present (if keyframe)
!   0x000100: sample-duration-present
!   0x000200: sample-size-present
!   0x000800: sample-composition-time-offsets-present
:: build-trun-box ( samples data-offset has-composition-offset? -- box-bytes )
    samples length zero? [
        8 <byte-vector> :> p
        p 0 push-be32
        FOURCC_TRUN 0 0 p >byte-array serialize-full-box
    ] [
        samples 0 nth keyframe? :> first-is-keyframe?

        0x000301 :> base-flags!  ! data-offset (0x1) + duration (0x100) + size (0x200)
        first-is-keyframe? [
            base-flags 0x000004 bitor base-flags!
        ] when
        has-composition-offset? [
            base-flags 0x000800 bitor base-flags!
        ] when

        samples length :> s-count
        4 4 + :> fixed-head!
        first-is-keyframe? [ fixed-head 4 + fixed-head! ] when
        8 :> per-sample!
        has-composition-offset? [ per-sample 4 + per-sample! ] when
        fixed-head s-count per-sample * + <byte-vector> :> p

        p s-count push-be32
        p data-offset push-be32
        first-is-keyframe? [
            p SAMPLE_FLAG_SYNC_KEYFRAME push-be32
        ] when

        samples [
            :> sample
            p sample duration>> push-be32
            p sample size>> push-be32
            has-composition-offset? [
                p sample sample-composition-offset push-be32
            ] when
        ] each

        FOURCC_TRUN 0 base-flags p >byte-array serialize-full-box
    ] if ;

! Parses a trun box and reconstructs media-sample tuples.
:: parse-trun-samples ( trun-box track-id base-decode-time mdat-bytes -- samples )
    trun-box payload>> :> p
    p length 8 < [ V{ } clone ] [
        p 1 read-be24 :> flags
        p 4 read-be32 :> sample-count
        8 :> off!
        0 :> data-offset!

        flags 0x000001 bitand zero? not [
            p off read-be32 data-offset!
            off 4 + off!
        ] when

        0 :> first-sample-flags!
        flags 0x000004 bitand zero? not [
            p off read-be32 first-sample-flags!
            off 4 + off!
        ] when

        sample-count <vector> :> out
        base-decode-time :> curr-dts!
        0 :> curr-mdat-idx!

        sample-count <iota> [
            :> s-idx
            off p length < [
                0 :> s-dur!
                flags 0x000100 bitand zero? not [
                    p off read-be32 s-dur!
                    off 4 + off!
                ] when

                0 :> s-sz!
                flags 0x000200 bitand zero? not [
                    p off read-be32 s-sz!
                    off 4 + off!
                ] when

                0 :> s-flags!
                s-idx zero? first-sample-flags zero? not and [
                    first-sample-flags s-flags!
                ] [
                    flags 0x000400 bitand zero? not [
                        p off read-be32 s-flags!
                        off 4 + off!
                    ] when
                ] if

                0 :> s-ctts!
                flags 0x000800 bitand zero? not [
                    p off read-be32 s-ctts!
                    off 4 + off!
                ] when

                curr-mdat-idx curr-mdat-idx s-sz + mdat-bytes subseq-safe :> s-data
                curr-dts s-ctts + :> s-pts

                track-id s-pts curr-dts s-dur s-sz
                s-flags SAMPLE_FLAG_SYNC_KEYFRAME = 1 0 ?
                s-data <media-sample> out push

                curr-dts s-dur + curr-dts!
                curr-mdat-idx s-sz + curr-mdat-idx!
            ] when
        ] each
        out
    ] if ;

! Builds a complete Track Fragment (traf) container box.
:: build-traf-box ( track-id base-decode-time samples data-offset has-composition-offset? -- box-bytes )
    track-id SAMPLE_FLAG_NON_SYNC build-tfhd-box :> tfhd
    base-decode-time build-tfdt-box :> tfdt
    samples data-offset has-composition-offset? build-trun-box :> trun
    FOURCC_TRAF { tfhd tfdt trun } serialize-container-box ;

! Calculates the exact moof container byte size before final data-offset patching.
:: estimate-moof-size ( sequence-num track-id base-decode-time samples has-composition-offset? -- size )
    0 :> dummy-data-offset
    sequence-num build-mfhd-box length :> mfhd-len
    track-id base-decode-time samples dummy-data-offset has-composition-offset? build-traf-box length :> traf-len
    mfhd-len traf-len + 8 + ;

! Synthesizes a CMAF Media Segment (.m4s) consisting of a moof box followed by an mdat box.
:: build-cmaf-segment ( sequence-num track-id base-decode-time samples -- segment-bytes )
    samples [ sample-composition-offset zero? not ] any? :> has-ctts?

    ! Phase 1: Estimate moof size to determine mdat start
    sequence-num track-id base-decode-time samples has-ctts? estimate-moof-size :> estimated-moof-sz
    estimated-moof-sz 8 + :> accurate-data-offset

    ! Phase 2: Build final traf with exact data-offset
    sequence-num build-mfhd-box :> mfhd-box
    track-id base-decode-time samples accurate-data-offset has-ctts? build-traf-box :> traf-box
    FOURCC_MOOF { mfhd-box traf-box } serialize-container-box :> moof-box

    ! Phase 3: Assemble sample payloads into contiguous mdat box
    samples [ size>> ] map-sum :> total-sample-bytes
    total-sample-bytes <byte-vector> :> mdat-payload
    samples [ data>> mdat-payload push-bytes ] each
    mdat-payload >byte-array build-mdat-box :> mdat-box

    ! Concatenate moof and mdat
    moof-box length mdat-box length + <byte-vector> :> seg-buf
    seg-buf moof-box push-bytes
    seg-buf mdat-box push-bytes
    seg-buf >byte-array ;
