! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Keyframe-aligned temporal chunking engine for adaptive media streaming.
! Enforces closed GOP boundaries, synchronizes video and audio sample intervals,
! and partitions continuous tracks into CMAF fragments.

USING: accessors arrays byte-arrays kernel locals math math.order
sequences vectors venturi.common.types venturi.common.utils ;
IN: venturi.packaging.chunker

! Discrete temporal media chunk bundling video and audio samples for one segment.
TUPLE: media-chunk
    { sequence integer read-only }
    { start-pts integer read-only }
    { duration integer read-only }
    { timescale integer read-only }
    { video-samples array read-only }
    { audio-samples array read-only }
    { keyframe? boolean read-only } ;

: <media-chunk> ( seq start dur timescale v-samples a-samples kf? -- chunk )
    media-chunk boa ;

! Partitions video samples into contiguous Groups of Pictures (GOPs).
:: split-samples-into-gops ( video-samples -- gop-sample-arrays )
    V{ } clone :> gops
    V{ } clone :> current-gop!

    video-samples [
        :> s
        s keyframe? [
            current-gop length zero? not [
                current-gop >array gops push
                V{ } clone current-gop!
            ] when
        ] when
        s current-gop push
    ] each

    current-gop length zero? not [
        current-gop >array gops push
    ] when

    gops >array ;

! Chunks video and audio tracks into synchronized keyframe-aligned segments.
:: chunk-tracks ( video-track audio-track target-duration-ms -- chunks )
    V{ } clone :> chunks
    video-track samples>> :> v-samples
    audio-track [ samples>> ] [ { } ] if* :> a-samples

    v-samples length zero? [ chunks >array ] [
        video-track timescale>> :> v-timescale
        audio-track [ timescale>> ] [ v-timescale ] if* :> a-timescale
        target-duration-ms v-timescale * 1000 /i :> target-ticks

        0 :> seq!
        0 :> a-idx!
        V{ } clone :> cur-v!
        0 :> cur-dur!
        0 v-samples nth pts>> :> cur-start-pts!

        v-samples [
            :> s
            ! If sample is a keyframe and we have accumulated enough duration, emit chunk
            s keyframe? cur-v length zero? not and cur-dur target-ticks >= and [
                ! Extract audio samples that fall within [cur-start-pts, cur-start-pts + cur-dur)
                V{ } clone :> cur-a
                cur-start-pts v-timescale 1000 rescale-time :> chunk-start-ms
                cur-dur v-timescale 1000 rescale-time :> chunk-dur-ms
                chunk-start-ms chunk-dur-ms + :> chunk-end-ms
                f :> stop!

                [ a-idx a-samples length < stop not and ] [
                    a-idx a-samples nth :> a-s
                    a-s pts>> a-timescale 1000 rescale-time :> a-ms
                    a-ms chunk-end-ms < [
                        a-s cur-a push
                        a-idx 1 + a-idx!
                    ] [
                        t stop!
                    ] if
                ] while

                seq 1 + seq!
                seq cur-start-pts cur-dur v-timescale
                cur-v >array cur-a >array t <media-chunk> chunks push

                V{ } clone cur-v!
                0 cur-dur!
                s pts>> cur-start-pts!
            ] when

            s cur-v push
            cur-dur s duration>> + cur-dur!
        ] each

        ! Flush remaining samples as final chunk
        cur-v length zero? not [
            V{ } clone :> final-a
            [ a-idx a-samples length < ] [
                a-idx a-samples nth final-a push
                a-idx 1 + a-idx!
            ] while

            seq 1 + seq!
            seq cur-start-pts cur-dur v-timescale
            cur-v >array final-a >array t <media-chunk> chunks push
        ] when

        chunks >array
    ] if ;
