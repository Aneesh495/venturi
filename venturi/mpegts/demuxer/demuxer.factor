! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! End-to-end MPEG-2 Transport Stream continuous demuxer, assembling PAT, PMT,
! and synchronized elementary video and audio tracks from broadcast byte feeds.

USING: accessors arrays assocs byte-arrays byte-vectors hashtables kernel
locals math math.order sequences sets vectors venturi.common.types
venturi.common.utils venturi.mpegts.constants venturi.mpegts.packet
venturi.mpegts.pes venturi.mpegts.psi ;
IN: venturi.mpegts.demuxer

! Demuxes an entire MPEG-2 Transport Stream buffer into unified media-track structures.
:: demux-mpegts ( ts-bytes -- tracks )
    ts-bytes parse-ts-packets :> packets
    packets length zero? [ { } ] [
        ! Step 1: Discover PMT PID from PAT
        f :> pmt-pid!
        packets [
            dup pid>> PID_PAT = [
                parse-pat-packet :> pat-entries
                pat-entries length zero? not [
                    0 pat-entries nth pmt-pid>> pmt-pid!
                ] when
            ] [ drop ] if
        ] each

        pmt-pid [
            ! Step 2: Discover Elementary Streams from PMT
            f :> pmt-info!
            packets [
                dup pid>> pmt-pid = [
                    pmt-pid parse-pmt-packet :> parsed-pmt
                    parsed-pmt [ parsed-pmt pmt-info! ] when
                ] [ drop ] if
            ] each

            pmt-info [
                ! Step 3: Setup PES assemblers and tracks for discovered streams
                H{ } clone :> assemblers
                H{ } clone :> stream-tracks

                pmt-info streams>> [
                    :> s
                    s stream-type>> :> s-type
                    s elementary-pid>> :> e-pid

                    e-pid s-type <pes-assembler> e-pid assemblers set-at

                    s-type STREAM_TYPE_H264 = [
                        e-pid "avc1" 90000 0 0 B{ } <video-track> e-pid stream-tracks set-at
                    ] [
                        s-type STREAM_TYPE_H265 = [
                            e-pid "hev1" 90000 0 0 B{ } <video-track> e-pid stream-tracks set-at
                        ] [
                            s-type STREAM_TYPE_AAC_ADTS = [
                                e-pid "mp4a" 90000 48000 2 B{ } <audio-track> e-pid stream-tracks set-at
                            ] when
                        ] if
                    ] if
                ] each

                ! Step 4: Stream demuxing loop feeding packets to assemblers
                packets [
                    :> pkt
                    pkt pid>> :> pid
                    pid assemblers at :> asm
                    pid stream-tracks at :> trk

                    asm trk and [
                        asm pkt feed-ts-packet :> completed-pes
                        completed-pes [
                            completed-pes payload>> length :> p-sz
                            p-sz 0 > [
                                ! Infer keyframe from random_access or start
                                pkt random-access?>> 1 0 ? :> flags
                                pid completed-pes pts>> completed-pes dts>> 3000 p-sz flags
                                completed-pes payload>> <media-sample> trk add-sample
                            ] when
                        ] when
                    ] when
                ] each

                ! Step 5: Flush any remaining fragments
                assemblers [
                    :> asm :> pid
                    pid stream-tracks at :> trk
                    trk [
                        asm flush-pes-assembler :> final-pes
                        final-pes [
                            final-pes payload>> length :> p-sz
                            p-sz 0 > [
                                pid final-pes pts>> final-pes dts>> 3000 p-sz 0
                                final-pes payload>> <media-sample> trk add-sample
                            ] when
                        ] when
                    ] when
                ] assoc-each

                stream-tracks values >array
            ] [ { } ] if
        ] [ { } ] if
    ] if ;
