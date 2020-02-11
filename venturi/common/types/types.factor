! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Canonical data models and type definitions for media streams,
! rational timestamps, elementary samples, track layouts, and segments.

USING: accessors byte-arrays kernel locals math math.functions sequences
strings vectors ;
IN: venturi.common.types

! Track media type singletons.
SYMBOLS: +video+ +audio+ +metadata+ ;

! Rational timestamp representation (numerator ticks and denominator timescale).
TUPLE: rational-time
    { num integer read-only }
    { den integer read-only } ;

: <rational-time> ( num den -- rational-time )
    dup zero? [ "timescale denominator cannot be zero" throw ] when
    rational-time boa ;

: time>seconds ( rational-time -- seconds )
    [ num>> ] [ den>> ] bi / >float ;

:: rescale-time ( num src-den dst-den -- new-num )
    src-den zero? [ "source timescale denominator cannot be zero" throw ] when
    num dst-den * src-den /i ;

! Media sample encapsulation representing a discrete encoded frame or packet.
! flags bitmask:
!   bit 0 (0x01): sync-sample (keyframe / IDR)
!   bit 1 (0x02): disposable sample
!   bit 2 (0x04): has-redundancy
TUPLE: media-sample
    { track-id integer read-only }
    { pts integer read-only }
    { dts integer read-only }
    { duration integer read-only }
    { size integer read-only }
    { flags integer read-only }
    { data byte-array read-only } ;

: <media-sample> ( track-id pts dts duration size flags data -- media-sample )
    media-sample boa ;

: keyframe? ( media-sample -- ? )
    flags>> 1 bitand 1 = ;

: sample-composition-offset ( media-sample -- offset )
    [ pts>> ] [ dts>> ] bi - ;

! Unified media track descriptor encompassing video, audio, and metadata tracks.
TUPLE: media-track
    { id integer }
    { type object }           ! +video+, +audio+, or +metadata+
    { codec string }          ! fourcc string (for example "avc1", "mp4a")
    { timescale integer }     ! clock rate (for example 90000, 48000)
    { duration integer }      ! total duration in track timescale ticks
    { width integer }         ! video frame pixel width
    { height integer }        ! video frame pixel height
    { sample-rate integer }   ! audio sampling frequency (for example 44100, 48000)
    { channels integer }      ! audio channel count (for example 1, 2, 6)
    { codec-private byte-array } ! extradata / config record
    { samples vector } ;

: <video-track> ( id codec timescale width height codec-private -- track )
    media-track new
        swap >>codec-private
        swap >>height
        swap >>width
        swap >>timescale
        swap >>codec
        swap >>id
        +video+ >>type
        0 >>duration
        0 >>sample-rate
        0 >>channels
        V{ } clone >>samples ;

: <audio-track> ( id codec timescale sample-rate channels codec-private -- track )
    media-track new
        swap >>codec-private
        swap >>channels
        swap >>sample-rate
        swap >>timescale
        swap >>codec
        swap >>id
        +audio+ >>type
        0 >>duration
        0 >>width
        0 >>height
        V{ } clone >>samples ;

: track-duration-seconds ( media-track -- seconds )
    [ duration>> ] [ timescale>> ] bi
    dup zero? [ 2drop 0.0 ] [ / >float ] if ;

: add-sample ( sample track -- )
    [ samples>> push ]
    [ [ duration>> ] [ duration>> ] bi* + >>duration drop ] 2bi ;

! Packaged media segment representation for HLS and DASH distribution.
TUPLE: media-segment
    { sequence integer read-only }
    { start-time integer read-only }
    { duration integer read-only }
    { timescale integer read-only }
    { is-init boolean read-only }
    { uri string read-only }
    { data byte-array read-only } ;

: <media-segment> ( seq start dur timescale is-init uri data -- segment )
    media-segment boa ;

: segment-duration-seconds ( media-segment -- seconds )
    [ duration>> ] [ timescale>> ] bi
    dup zero? [ 2drop 0.0 ] [ / >float ] if ;

! Group of Pictures metadata tracking keyframe cadence and duration.
TUPLE: gop-info
    { start-pts integer read-only }
    { sample-count integer read-only }
    { duration integer read-only }
    { closed? boolean read-only } ;

: <gop-info> ( start-pts sample-count duration closed? -- gop-info )
    gop-info boa ;
