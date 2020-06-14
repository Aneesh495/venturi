! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! RFC 8216 HTTP Live Streaming (HLS) multivariant master playlist
! and media playlist authoring with CMAF byte-range and fragment indexing.

USING: accessors arrays formatting kernel locals math math.functions
math.order math.parser sequences strings vectors venturi.common.types
venturi.common.utils ;
IN: venturi.manifests.hls

! Stream variant definition for HLS Multivariant Master Playlists.
TUPLE: hls-variant
    { bandwidth integer read-only }
    { average-bandwidth integer read-only }
    { width integer read-only }
    { height integer read-only }
    { frame-rate float read-only }
    { codecs string read-only }
    { audio-group string read-only }
    { uri string read-only } ;

: <hls-variant> ( bw avg-bw w h fps codecs audio-grp uri -- variant )
    hls-variant boa ;

! Builds an RFC 8216 HLS Multivariant Master Playlist (master.m3u8).
:: build-hls-master-playlist ( variants -- m3u8-string )
    V{ } clone :> lines
    "#EXTM3U" lines push
    "#EXT-X-VERSION:7" lines push
    "#EXT-X-INDEPENDENT-SEGMENTS" lines push
    "" lines push

    variants [
        :> v
        V{ } clone :> inf
        "#EXT-X-STREAM-INF:BANDWIDTH=" inf push
        v bandwidth>> number>string inf push

        v average-bandwidth>> zero? not [
            ",AVERAGE-BANDWIDTH=" inf push
            v average-bandwidth>> number>string inf push
        ] when

        v width>> 0 > v height>> 0 > and [
            ",RESOLUTION=" inf push
            v width>> number>string inf push
            "x" inf push
            v height>> number>string inf push
        ] when

        v frame-rate>> 0.0 > [
            ",FRAME-RATE=" inf push
            v frame-rate>> "%.3f" sprintf inf push
        ] when

        v codecs>> length 0 > [
            ",CODECS=\"" inf push
            v codecs>> inf push
            "\"" inf push
        ] when

        v audio-group>> length 0 > [
            ",AUDIO=\"" inf push
            v audio-group>> inf push
            "\"" inf push
        ] when

        inf concat lines push
        v uri>> lines push
    ] each

    lines "\n" join "\n" append ;

! Formats a single #EXTINF tag line with segment duration in seconds.
:: format-extinf-line ( segment -- line )
    segment segment-duration-seconds :> sec
    "#EXTINF:" sec "%.3f" sprintf append "," append ;

! Builds an RFC 8216 HLS VOD Media Playlist for completed streams.
:: build-hls-vod-playlist ( segments init-uri -- m3u8-string )
    V{ } clone :> lines
    "#EXTM3U" lines push
    "#EXT-X-VERSION:7" lines push
    "#EXT-X-PLAYLIST-TYPE:VOD" lines push

    0.0 :> max-dur!
    segments [
        segment-duration-seconds max-dur max max-dur!
    ] each

    max-dur ceiling >integer 1 max :> target-dur
    "#EXT-X-TARGETDURATION:" target-dur number>string append lines push
    "#EXT-X-MEDIA-SEQUENCE:1" lines push
    "#EXT-X-MAP:URI=\"" init-uri append "\"" append lines push
    "" lines push

    segments [
        :> seg
        seg format-extinf-line lines push
        seg uri>> lines push
    ] each

    "#EXT-X-ENDLIST" lines push
    lines "\n" join "\n" append ;

! Builds an RFC 8216 HLS Live Media Playlist maintaining a sliding window of recent fragments.
:: build-hls-live-playlist ( all-segments window-size init-uri -- m3u8-string )
    V{ } clone :> lines
    "#EXTM3U" lines push
    "#EXT-X-VERSION:7" lines push

    all-segments length :> total-count
    total-count window-size - 0 max :> start-idx
    total-count start-idx - :> kept-count
    start-idx total-count all-segments subseq-safe :> window-segments

    0.0 :> max-dur!
    window-segments [
        segment-duration-seconds max-dur max max-dur!
    ] each

    max-dur ceiling >integer 1 max :> target-dur
    "#EXT-X-TARGETDURATION:" target-dur number>string append lines push

    window-segments length 0 > [
        0 window-segments nth sequence>> :> seq-num
        "#EXT-X-MEDIA-SEQUENCE:" seq-num number>string append lines push
    ] [
        "#EXT-X-MEDIA-SEQUENCE:1" lines push
    ] if

    "#EXT-X-MAP:URI=\"" init-uri append "\"" append lines push
    "" lines push

    window-segments [
        :> seg
        seg format-extinf-line lines push
        seg uri>> lines push
    ] each

    lines "\n" join "\n" append ;
