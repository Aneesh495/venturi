! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! 64-bit continuous media timeline coordinator and clock drift compensator.
! Resolves 33-bit broadcast PCR/PTS rollover (26.5h wrap), smooths jitter,
! and guarantees monotonic baseMediaDecodeTime progression for CMAF tfdt boxes.

USING: accessors arrays kernel locals math math.functions math.order
sequences venturi.common.types venturi.common.utils ;
IN: venturi.packaging.timeline

! Constant for 33-bit MPEG timestamp modulus (2^33 = 8589934592)
CONSTANT: PTS_MODULUS 8589934592
CONSTANT: PTS_HALF_MODULUS 4294967296
CONSTANT: DEFAULT_DISCONTINUITY_THRESHOLD 90000 ! 1 second at 90kHz

! Stateful continuous timeline tracker for a media stream.
TUPLE: media-timeline
    { timescale integer }
    { initial-pts object }          ! first seen raw timestamp or f
    { last-raw-pts integer }        ! previous raw timestamp
    { continuous-time integer }     ! monotonically accumulating ticks
    { rollover-count integer }      ! number of 33-bit wraps detected
    { discon-threshold integer } ;

: <media-timeline> ( timescale -- timeline )
    media-timeline new
        swap >>timescale
        f >>initial-pts
        0 >>last-raw-pts
        0 >>continuous-time
        0 >>rollover-count
        DEFAULT_DISCONTINUITY_THRESHOLD >>discon-threshold ;

! Checks if the delta between current and previous raw PTS exceeds discontinuity limit.
:: discontinuity? ( timeline raw-pts -- ? )
    timeline initial-pts>> [
        raw-pts timeline last-raw-pts>> - abs :> delta
        delta timeline discon-threshold>> >
        delta PTS_HALF_MODULUS - abs timeline discon-threshold>> > and
    ] [ f ] if ;

! Feeds a raw sample timestamp into the timeline, returning continuous 64-bit decode time.
:: advance-timeline ( timeline raw-pts sample-duration -- continuous-pts )
    timeline initial-pts>> [
        ! Check for 33-bit backwards rollover
        raw-pts timeline last-raw-pts>> <
        timeline last-raw-pts>> raw-pts - PTS_HALF_MODULUS > and [
            timeline timeline rollover-count>> 1 + >>rollover-count drop
        ] when

        ! Compute unwrapped 64-bit timestamp
        timeline rollover-count>> PTS_MODULUS * raw-pts + :> unwrapped-pts
        timeline initial-pts>> :> init-pts
        unwrapped-pts init-pts - :> delta-from-start

        ! Ensure strict monotonicity
        delta-from-start timeline continuous-time>> max :> monotonic-pts
        monotonic-pts timeline continuous-time>> :> pts-to-return

        timeline raw-pts >>last-raw-pts drop
        timeline monotonic-pts sample-duration + >>continuous-time drop
        pts-to-return
    ] [
        ! First timestamp initializes the base clock
        timeline raw-pts >>initial-pts drop
        timeline raw-pts >>last-raw-pts drop
        timeline sample-duration >>continuous-time drop
        0
    ] if ;

! Rescales all samples in an array from source timescale to destination timescale.
:: rescale-samples ( samples src-timescale dst-timescale -- rescaled )
    samples [
        :> s
        s pts>> src-timescale dst-timescale rescale-time :> new-pts
        s dts>> src-timescale dst-timescale rescale-time :> new-dts
        s duration>> src-timescale dst-timescale rescale-time :> new-dur
        s track-id>> new-pts new-dts new-dur s size>> s flags>> s data>> <media-sample>
    ] { } map-as ;
