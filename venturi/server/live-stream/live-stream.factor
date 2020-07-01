! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! High-concurrency in-memory live segment ring buffer for low-latency CMAF streaming.
! Atomic live window sliding, fast URI lookup, and thread-safe segment eviction.

USING: accessors arrays assocs concurrency.locks hashtables
kernel locals math math.order sequences strings vectors
venturi.common.types venturi.common.utils ;
IN: venturi.server.live-stream

! Ring buffer storing active live media segments bounded by capacity.
TUPLE: live-ring-buffer
    { capacity integer read-only }
    { segments vector }
    { segment-map hashtable }
    { init-segment media-segment }
    { lock lock } ;

: <live-ring-buffer> ( capacity -- ring )
    V{ } clone
    H{ } clone
    f
    <lock>
    live-ring-buffer boa ;

! Registers the shared CMAF initialization segment (init.mp4).
:: set-init-segment ( segment ring -- )
    ring lock>> [
        segment ring init-segment<<
        segment segment uri>> ring segment-map>> set-at
    ] with-lock ;

! Appends a newly transmuxed live media segment into the ring buffer.
! Automatically evicts the oldest segment when capacity is exceeded.
:: push-live-segment ( segment ring -- )
    ring lock>> [
        segment ring segments>> push
        segment segment uri>> ring segment-map>> set-at

        [ ring segments>> length ring capacity>> > ] [
            0 ring segments>> nth :> oldest
            oldest uri>> ring segment-map>> delete-at
            0 1 ring segments>> delete-slice
        ] while
    ] with-lock ;

! Retrieves a media segment by URI if present in the active live window.
:: get-live-segment ( uri ring -- segment/f )
    ring lock>> [
        uri ring segment-map>> ?at [ drop f ] unless
    ] with-lock ;

! Returns the most recent N media segments in presentation order.
:: current-live-window ( ring window-size -- segments-array )
    ring lock>> [
        ring segments>> :> segs
        segs length window-size min :> count
        segs length count - :> start-idx
        start-idx segs length segs subseq-safe >array
    ] with-lock ;

! Returns the minimum and maximum sequence numbers currently held in buffer.
:: live-sequence-range ( ring -- min-seq max-seq )
    ring lock>> [
        ring segments>> :> segs
        segs length zero? [
            0 0
        ] [
            0 segs nth sequence>>
            segs last sequence>>
        ] if
    ] with-lock ;

! Returns total count of live media segments currently buffered.
:: live-segment-count ( ring -- n )
    ring lock>> [
        ring segments>> length
    ] with-lock ;
