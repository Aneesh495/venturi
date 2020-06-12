! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! RFC 8216 HTTP Live Streaming (HLS) multivariant master playlist
! and media playlist authoring with CMAF byte-range and fragment indexing.

USING: accessors arrays formatting kernel locals math math.functions
math.order math.parser sequences strings vectors venturi.common.types ;
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
