! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Synchronous dual-manifest coordinator binding HLS and DASH to shared CMAF fragments.
! Atomic live window sliding, multi-format synchronization, and unified edge asset dispatch.

USING: accessors arrays assocs byte-arrays hashtables kernel locals math
sequences strings vectors venturi.common.types venturi.manifests.dash
venturi.manifests.hls venturi.packaging.pipeline ;
IN: venturi.manifests.coordinator

! Bundled multi-protocol manifest package for edge distribution.
TUPLE: manifest-bundle
    { hls-master string read-only }
    { hls-media string read-only }
    { dash-mpd string read-only }
    { init-segment media-segment read-only }
    { media-segments array read-only }
    { tracks array read-only }
    { is-live? boolean read-only } ;

: <manifest-bundle> ( master media mpd init segs trks live? -- bundle )
    manifest-bundle boa ;

! Coordinates and authors dual HLS and DASH manifests from a transmux result.
:: coordinate-manifests ( result is-live? -- bundle )
    result tracks>> :> trks
    result media-segments>> :> segs
    result init-segment>> :> init-seg

    ! HLS Master Playlist
    V{ } clone :> variants
    trks [
        :> trk
        trk type>> +video+ = [
            4500000 4000000 trk width>> trk height>> 30.0 "avc1.640028" "" "stream.m3u8"
            <hls-variant> variants push
        ] when
    ] each

    variants length zero? [
        2500000 2000000 1280 720 30.0 "avc1.4d401f" "" "stream.m3u8"
        <hls-variant> variants push
    ] when

    variants >array build-hls-master-playlist :> hls-master

    ! HLS Media Playlist
    is-live? [
        segs 6 init-seg uri>> build-hls-live-playlist
    ] [
        segs init-seg uri>> build-hls-vod-playlist
    ] if :> hls-media

    ! DASH MPD
    trks segs is-live? build-dash-mpd :> dash-mpd

    hls-master hls-media dash-mpd init-seg segs trks is-live? <manifest-bundle> ;

! Updates a live manifest bundle upon arrival of a newly packaged segment.
:: update-live-manifests ( bundle new-segment window-size -- updated-bundle )
    bundle media-segments>> new-segment suffix :> updated-segs
    bundle init-segment>> uri>> :> init-uri

    updated-segs window-size init-uri build-hls-live-playlist :> new-hls
    bundle tracks>> updated-segs t build-dash-mpd :> new-mpd

    bundle hls-master>> new-hls new-mpd bundle init-segment>>
    updated-segs bundle tracks>> t <manifest-bundle> ;

! Maps all manifest files and media segments into a path-to-bytes lookup hashtable.
:: bundle-file-map ( bundle -- files-hash )
    H{ } clone :> files
    bundle hls-master>> >byte-array "master.m3u8" files set-at
    bundle hls-media>> >byte-array "stream.m3u8" files set-at
    bundle dash-mpd>> >byte-array "manifest.mpd" files set-at

    bundle init-segment>> :> init-seg
    init-seg data>> init-seg uri>> files set-at

    bundle media-segments>> [
        :> seg
        seg data>> seg uri>> files set-at
    ] each

    files ;
