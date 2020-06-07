! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! End-to-end transmuxing pipeline connecting demuxers, bitstream parsers,
! temporal keyframe chunkers, and ISO/IEC 23000-19 CMAF fragment packaging.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.order math.parser sequences strings vectors venturi.codecs.aac
venturi.codecs.h264 venturi.codecs.h265 venturi.common.types
venturi.common.utils venturi.isobmff.movie-fragment
venturi.mpegts.demuxer venturi.packaging.cmaf
venturi.packaging.chunker venturi.packaging.timeline ;
IN: venturi.packaging.pipeline

! Transmuxing pipeline result container holding packaged init and media segments.
TUPLE: transmux-result
    { init-segment media-segment read-only }
    { media-segments array read-only }
    { tracks array read-only }
    { target-duration-seconds float read-only } ;

: <transmux-result> ( init segments tracks target-dur -- result )
    transmux-result boa ;

! Normalizes raw video track samples by extracting parameter sets and converting to AVC1/HEV1.
:: normalize-video-track ( v-track -- normalized-track )
    v-track samples>> :> raw-samples
    raw-samples length zero? [ v-track ] [
        v-track codec>> "avc1" = [
            ! H.264 video
            f :> sps-nal!
            f :> pps-nal!
            V{ } clone :> converted-samples

            raw-samples [
                :> s
                s data>> split-annex-b-nals :> nals
                nals [
                    :> n
                    n type>> NAL_SPS = [ n data>> sps-nal! ] when
                    n type>> NAL_PPS = [ n data>> pps-nal! ] when
                ] each

                s data>> annex-b>avc1-sample :> avc-data
                s track-id>> s pts>> s dts>> s duration>>
                avc-data length s flags>> avc-data <media-sample> converted-samples push
            ] each

            sps-nal pps-nal and [
                sps-nal pps-nal build-avcc-box :> avcc-box
                sps-nal parse-sps :> sps-meta
                sps-meta [
                    v-track sps-meta width>> >>width drop
                    v-track sps-meta height>> >>height drop
                ] when
                v-track avcc-box >>codec-private drop
            ] when

            v-track converted-samples >>samples drop
            v-track
        ] [
            v-track codec>> "hev1" = [
                ! H.265 video
                f :> vps-nal!
                f :> sps-nal!
                f :> pps-nal!
                V{ } clone :> converted-samples

                raw-samples [
                    :> s
                    s data>> split-hevc-annex-b-nals :> nals
                    nals [
                        :> n
                        n type>> NAL_HEVC_VPS = [ n data>> vps-nal! ] when
                        n type>> NAL_HEVC_SPS = [ n data>> sps-nal! ] when
                        n type>> NAL_HEVC_PPS = [ n data>> pps-nal! ] when
                    ] each

                    s data>> annex-b>hev1-sample :> hev-data
                    s track-id>> s pts>> s dts>> s duration>>
                    hev-data length s flags>> hev-data <media-sample> converted-samples push
                ] each

                vps-nal sps-nal and pps-nal and [
                    vps-nal sps-nal pps-nal build-hvcc-box :> hvcc-box
                    sps-nal length 2 > [
                        2 sps-nal length sps-nal subseq-safe remove-emulation-prevention parse-hevc-sps
                    ] [ f ] if :> h-sps
                    h-sps [
                        v-track h-sps width>> >>width drop
                        v-track h-sps height>> >>height drop
                    ] when
                    v-track hvcc-box >>codec-private drop
                ] when

                v-track converted-samples >>samples drop
                v-track
            ] [
                v-track
            ] if
        ] if
    ] if ;

! Normalizes raw audio track samples by synthesizing AudioSpecificConfig and stripping ADTS.
:: normalize-audio-track ( a-track -- normalized-track )
    a-track samples>> :> raw-samples
    raw-samples length zero? [ a-track ] [
        0 raw-samples nth data>> :> first-data
        first-data 0 parse-adts-frame :> adts
        adts [
            a-track adts sample-rate>> >>sample-rate drop
            a-track adts channels>> >>channels drop
            a-track
            adts profile>> adts sample-rate>> adts channels>>
            build-audio-specific-config build-esds-box >>codec-private drop

            ! Convert all samples to raw AAC payloads
            V{ } clone :> stripped-samples
            raw-samples [
                :> s
                s data>> 0 parse-adts-frame :> frame
                frame [
                    frame payload>> :> pl
                    s track-id>> s pts>> s dts>> s duration>>
                    pl length s flags>> pl <media-sample> stripped-samples push
                ] [
                    s stripped-samples push
                ] if
            ] each
            a-track stripped-samples >>samples drop
        ] when
        a-track
    ] if ;

! Packages tracks into a complete CMAF live or on-demand distribution bundle.
:: transmux-tracks-to-cmaf ( tracks target-duration-ms -- result )
    ! Partition into primary video and audio tracks
    f :> v-trk!
    f :> a-trk!
    tracks [
        :> trk
        trk type>> +video+ = [ trk v-trk! ] when
        trk type>> +audio+ = [ trk a-trk! ] when
    ] each

    v-trk [ v-trk normalize-video-track v-trk! ] when
    a-trk [ a-trk normalize-audio-track a-trk! ] when

    V{ } clone :> normalized-tracks
    v-trk [ v-trk normalized-tracks push ] when
    a-trk [ a-trk normalized-tracks push ] when

    ! Generate init.mp4
    normalized-tracks >array build-cmaf-init-segment :> init-bytes
    0 0 0 1000 t "init.mp4" init-bytes <media-segment> :> init-seg

    ! Chunk video and audio tracks
    v-trk a-trk target-duration-ms chunk-tracks :> chunks

    ! Package each chunk into styp + moof + mdat
    V{ } clone :> media-segments
    build-cmaf-styp-box :> styp-box

    chunks [
        :> chk
        chk sequence>> :> seq-num
        chk start-pts>> :> start-pts
        chk duration>> :> dur
        chk timescale>> :> tscale
        chk video-samples>> :> v-samps

        seq-num v-trk [ id>> ] [ 1 ] if* start-pts v-samps build-cmaf-segment :> fragment-bytes
        styp-box fragment-bytes append :> full-segment-data

        "segment_" seq-num number>string append ".m4s" append :> seg-uri
        seq-num start-pts dur tscale f seg-uri full-segment-data <media-segment> media-segments push
    ] each

    target-duration-ms 1000.0 / :> target-sec
    init-seg media-segments >array normalized-tracks >array target-sec <transmux-result> ;

! Demuxes an MPEG-2 Transport Stream byte array and transmuxes it directly into CMAF.
:: transmux-mpegts-to-cmaf ( ts-bytes target-duration-ms -- result )
    ts-bytes demux-mpegts :> tracks
    tracks target-duration-ms transmux-tracks-to-cmaf ;
