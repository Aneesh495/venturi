! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! High-level monolithic ISOBMFF / MP4 demuxer parsing movie atom hierarchies,
! extracting track configurations, and slicing contiguous media samples.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
sequences sets vectors venturi.common.types venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.chunk-offset
venturi.isobmff.constants venturi.isobmff.sample-table
venturi.isobmff.track-header ;
IN: venturi.isobmff.demuxer

! Parses an stsd sample description entry (avc1 or mp4a).
:: parse-sample-entry ( stsd-box -- codec width height rate channels config )
    stsd-box payload>> :> p
    p length 16 < [
        "undf" 0 0 0 0 B{ }
    ] [
        ! Skip 4 bytes (version+flags) + 4 bytes entry_count
        8 :> off
        off p length 8 - <= [
            p off 4 + read-be32 4cc>string :> codec-str
            p off 4 + read-be32 :> codec-fourcc

            codec-fourcc FOURCC_AVC1 = [
                p off 32 + read-be16 :> w
                p off 34 + read-be16 :> h
                ! Search for avcC atom inside entry
                f :> avcc-cfg!
                off 86 + :> sub-off!
                [ sub-off p length 8 - <= avcc-cfg not and ] [
                    p sub-off read-be32 :> atom-sz
                    p sub-off 4 + read-be32 :> atom-type
                    atom-type FOURCC_AVCC = [
                        sub-off 8 + sub-off atom-sz + p subseq-safe avcc-cfg!
                    ] when
                    atom-sz zero? [ p length sub-off! ] [ sub-off atom-sz + sub-off! ] if
                ] while
                codec-str w h 0 0 avcc-cfg [ B{ } ] unless*
            ] [
                codec-fourcc FOURCC_MP4A = [
                    p off 24 + read-be16 :> channels
                    p off 32 + read-be16 :> rate
                    ! Search for esds atom inside entry
                    f :> esds-cfg!
                    off 36 + :> sub-off!
                    [ sub-off p length 8 - <= esds-cfg not and ] [
                        p sub-off read-be32 :> atom-sz
                        p sub-off 4 + read-be32 :> atom-type
                        atom-type FOURCC_ESDS = [
                            sub-off 8 + sub-off atom-sz + p subseq-safe esds-cfg!
                        ] when
                        atom-sz zero? [ p length sub-off! ] [ sub-off atom-sz + sub-off! ] if
                    ] while
                    codec-str 0 0 rate channels esds-cfg [ B{ } ] unless*
                ] [
                    codec-str 0 0 0 0 B{ }
                ] if
            ] if
        ] [
            "undf" 0 0 0 0 B{ }
        ] if
    ] if ;

! Parses a single trak box into a populated media-track instance.
:: parse-trak-box ( trak-box file-bytes -- track/f )
    trak-box FOURCC_TKHD find-child-box [ parse-tkhd ] [ f ] if* :> tkhd
    trak-box { FOURCC_MDIA } find-box-path :> mdia
    mdia [
        mdia FOURCC_MDHD find-child-box [ parse-mdhd ] [ f ] if* :> mdhd
        mdia FOURCC_HDLR find-child-box [ parse-hdlr ] [ f ] if* :> hdlr
        mdia { FOURCC_MINF FOURCC_STBL } find-box-path :> stbl

        tkhd mdhd and hdlr and stbl and [
            stbl FOURCC_STTS find-child-box [ parse-stts ] [ { } ] if* :> durations
            stbl FOURCC_CTTS find-child-box [ parse-ctts ] [ { } ] if* :> ctts-offsets
            stbl FOURCC_STSS find-child-box [ parse-stss ] [ HS{ } clone ] if* :> sync-set
            stbl FOURCC_STSC find-child-box [ parse-stsc ] [ V{ } clone ] if* :> stsc-entries
            stbl FOURCC_STSZ find-child-box [ parse-stsz ] [ { } ] if* :> sample-sizes

            stbl FOURCC_STCO find-child-box [ parse-stco ] [
                stbl FOURCC_CO64 find-child-box [ parse-co64 ] [ { } ] if*
            ] if* :> chunk-offsets

            stbl FOURCC_STSD find-child-box [
                parse-sample-entry
            ] [
                "undf" 0 0 0 0 B{ }
            ] if* :> ( codec-str width height rate channels config-record )

            ! Resolve file offsets for all samples
            chunk-offsets stsc-entries sample-sizes resolve-sample-file-offsets :> file-offsets

            ! Determine track type
            hdlr handler-type>> :> h-type
            h-type HANDLER_VIDE = :> is-video?
            h-type HANDLER_SOUN = :> is-audio?

            tkhd track-id>> :> trk-id
            mdhd timescale>> :> trk-timescale

            is-video? [
                trk-id codec-str trk-timescale width height config-record <video-track>
            ] [
                is-audio? [
                    trk-id codec-str trk-timescale rate channels config-record <audio-track>
                ] [
                    trk-id codec-str trk-timescale width height config-record <video-track>
                ] if
            ] if :> track

            ! Slices samples from file-bytes
            0 :> curr-dts!
            sample-sizes length :> total-samples
            total-samples <iota> [
                :> s-idx
                s-idx 1 + :> sample-num  ! 1-based index

                s-idx file-offsets length < [
                    file-offsets s-idx nth :> s-off
                    sample-sizes s-idx nth :> s-sz
                    s-off s-off s-sz + file-bytes subseq-safe :> s-data

                    s-idx durations length < [
                        durations s-idx nth
                    ] [ 0 ] if :> s-dur

                    s-idx ctts-offsets length < [
                        ctts-offsets s-idx nth
                    ] [ 0 ] if :> s-ctts

                    curr-dts s-ctts + :> s-pts

                    ! Check keyframe: if stss absent, all samples are sync samples (e.g. audio)
                    sync-set cardinality zero? [
                        t
                    ] [
                        sample-num sync-set in?
                    ] if :> is-sync?

                    trk-id s-pts curr-dts s-dur s-sz
                    is-sync? 1 0 ?
                    s-data <media-sample> track add-sample

                    curr-dts s-dur + curr-dts!
                ] when
            ] each

            track
        ] [ f ] if
    ] [ f ] if* ;

! High-level demuxer parsing an entire monolithic MP4 file into media-track descriptors.
:: demux-isobmff ( file-bytes -- tracks )
    file-bytes 0 file-bytes length parse-boxes :> root-boxes
    root-boxes FOURCC_MOOV find-child-box :> moov
    moov [
        moov FOURCC_TRAK find-child-boxes :> trak-boxes
        trak-boxes [
            file-bytes parse-trak-box
        ] { } map-as [ ] filter
    ] [
        { }
    ] if ;
