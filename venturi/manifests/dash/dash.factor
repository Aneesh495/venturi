! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ISO/IEC 23009-1 Dynamic Adaptive Streaming over HTTP (DASH) XML MPD manifest generator.
! SegmentTemplate, SegmentTimeline run-length compression, and dual VoD/Live authoring.

USING: accessors arrays formatting kernel locals math math.functions
math.order math.parser sequences strings vectors venturi.common.types ;
IN: venturi.manifests.dash

! Converts a duration in floating-point seconds to an ISO 8601 duration string (PT...S).
:: seconds>iso8601-duration ( seconds -- str )
    "PT" seconds "%.3f" sprintf append "S" append ;

! Compresses segments into run-length encoded <S> elements within a <SegmentTimeline>.
:: build-segment-timeline ( segments -- timeline-xml-lines )
    V{ } clone :> lines
    segments length zero? [ lines ] [
        "        <SegmentTimeline>" lines push

        0 :> i!
        [ i segments length < ] [
            i segments nth :> first-seg
            first-seg start-time>> :> start-t
            first-seg duration>> :> dur
            0 :> r!

            ! Count repeats of equal duration
            i 1 + :> next-i!
            [
                next-i segments length < [
                    next-i segments nth duration>> dur =
                ] [ f ] if
            ] [
                r 1 + r!
                next-i 1 + next-i!
            ] while

            V{ } clone :> s-elem
            "          <S t=\"" s-elem push
            start-t number>string s-elem push
            "\" d=\"" s-elem push
            dur number>string s-elem push
            "\"" s-elem push

            r 0 > [
                " r=\"" s-elem push
                r number>string s-elem push
                "\"" s-elem push
            ] when

            " />" s-elem push
            s-elem concat lines push

            next-i i!
        ] while

        "        </SegmentTimeline>" lines push
        lines
    ] if ;

! Authors a complete ISO/IEC 23009-1 DASH Media Presentation Description (MPD).
:: build-dash-mpd ( tracks segments is-live? -- mpd-xml )
    V{ } clone :> lines
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" lines push

    ! MPD root tag
    0.0 :> total-sec!
    segments [ segment-duration-seconds total-sec + total-sec! ] each

    V{ } clone :> mpd-tag
    "<MPD xmlns=\"urn:mpeg:dash:schema:mpd:2011\"" mpd-tag push
    " profiles=\"urn:mpeg:dash:profile:isoff-live:2011,urn:com:dashif:ingest:2017\"" mpd-tag push
    is-live? [
        " type=\"dynamic\" minBufferTime=\"PT2.0S\"" mpd-tag push
        " timeShiftBufferDepth=\"PT60.0S\"" mpd-tag push
    ] [
        " type=\"static\"" mpd-tag push
        " mediaPresentationDuration=\"" mpd-tag push
        total-sec seconds>iso8601-duration mpd-tag push
        "\" minBufferTime=\"PT2.0S\"" mpd-tag push
    ] if
    ">" mpd-tag push
    mpd-tag concat lines push

    "<Period id=\"1\" start=\"PT0.0S\">" lines push

    ! AdaptationSet for each track
    tracks [
        :> trk
        trk type>> +video+ = :> is-video?
        trk id>> :> trk-id
        trk timescale>> :> tscale

        V{ } clone :> adapt-tag
        "  <AdaptationSet id=\"" adapt-tag push
        trk-id number>string adapt-tag push
        "\" contentType=\"" adapt-tag push
        is-video? "video" "audio" ? adapt-tag push
        "\" mimeType=\"" adapt-tag push
        is-video? "video/mp4" "audio/mp4" ? adapt-tag push
        "\" segmentAlignment=\"true\" startWithSAP=\"1\">" adapt-tag push
        adapt-tag concat lines push

        ! SegmentTemplate
        V{ } clone :> templ-tag
        "    <SegmentTemplate timescale=\"" templ-tag push
        tscale number>string templ-tag push
        "\" initialization=\"init.mp4\" media=\"segment_$Number$.m4s\" startNumber=\"1\">" templ-tag push
        templ-tag concat lines push

        segments build-segment-timeline [ lines push ] each
        "    </SegmentTemplate>" lines push

        ! Representation
        V{ } clone :> rep-tag
        "    <Representation id=\"" rep-tag push
        is-video? "video_" "audio_" ? rep-tag push
        trk-id number>string rep-tag push
        "\" bandwidth=\"" rep-tag push
        is-video? "4500000" "128000" ? rep-tag push
        "\"" rep-tag push

        is-video? [
            " width=\"" rep-tag push
            trk width>> number>string rep-tag push
            "\" height=\"" rep-tag push
            trk height>> number>string rep-tag push
            "\" frameRate=\"30/1\" />" rep-tag push
            rep-tag concat lines push
        ] [
            " audioSamplingRate=\"" rep-tag push
            trk sample-rate>> number>string rep-tag push
            "\">" rep-tag push
            rep-tag concat lines push
            "      <AudioChannelConfiguration schemeIdUri=\"urn:mpeg:dash:23003:3:audio_channel_configuration:2011\" value=\""
            trk channels>> number>string append "\" />" append lines push
            "    </Representation>" lines push
        ] if

        "  </AdaptationSet>" lines push
    ] each

    "</Period>" lines push
    "</MPD>" lines push

    lines "\n" join "\n" append ;
