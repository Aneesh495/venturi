! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit test suite for RFC 8216 HLS master/media playlist generators,
! ISO/IEC 23009-1 DASH MPD XML authoring, and dual-manifest coordinator.

USING: accessors arrays assocs byte-arrays io kernel locals math
math.parser sequences strings venturi.common.types
venturi.manifests.coordinator venturi.manifests.dash venturi.manifests.hls
venturi.packaging.pipeline venturi.tests.harness ;
IN: venturi.tests.manifests

:: test-hls-master-authoring ( -- )
    "Testing RFC 8216 HLS Multivariant Master Playlist Generation..." print

    4500000 4000000 1920 1080 30.0 "avc1.640028,mp4a.40.2" "audio" "v1080p/stream.m3u8" <hls-variant> :> v1
    2500000 2200000 1280 720 30.0 "avc1.4d401f,mp4a.40.2" "audio" "v720p/stream.m3u8" <hls-variant> :> v2
    800000 700000 640 360 30.0 "avc1.42e01e,mp4a.40.2" "audio" "v360p/stream.m3u8" <hls-variant> :> v3

    { v1 v2 v3 } build-hls-master-playlist :> master

    "#EXTM3U" master subseq? "master starts with #EXTM3U" test-true
    "#EXT-X-VERSION:7" master subseq? "master declares version 7" test-true
    "#EXT-X-INDEPENDENT-SEGMENTS" master subseq? "master declares independent segments" test-true
    "BANDWIDTH=4500000" master subseq? "1080p bandwidth is present" test-true
    "RESOLUTION=1920x1080" master subseq? "1080p resolution is present" test-true
    "FRAME-RATE=30.000" master subseq? "framerate is formatted" test-true
    "v1080p/stream.m3u8" master subseq? "1080p URI is present" test-true
    "BANDWIDTH=2500000" master subseq? "720p bandwidth is present" test-true
    "v720p/stream.m3u8" master subseq? "720p URI is present" test-true
    "v360p/stream.m3u8" master subseq? "360p URI is present" test-true ;

:: make-dummy-segment ( seq-num start-pts dur-pts timescale -- seg )
    seq-num
    start-pts
    dur-pts
    timescale
    f
    "chunk-" seq-num >integer number>string append ".m4s" append
    B{ 0x00 0x00 0x00 0x18 0x6D 0x6F 0x6F 0x66 0x00 0x00 0x00 0x08 0x6D 0x64 0x61 0x74 }
    <media-segment> ;

:: test-hls-vod-media-playlist ( -- )
    "Testing RFC 8216 HLS VOD Media Playlist Generation..." print

    1 0 180000 90000 make-dummy-segment :> s1
    2 180000 180000 90000 make-dummy-segment :> s2
    3 360000 180000 90000 make-dummy-segment :> s3

    { s1 s2 s3 } "init.mp4" build-hls-vod-playlist :> vod

    "#EXTM3U" vod subseq? "vod starts with #EXTM3U" test-true
    "#EXT-X-PLAYLIST-TYPE:VOD" vod subseq? "playlist type is VOD" test-true
    "#EXT-X-TARGETDURATION:2" vod subseq? "target duration is 2s" test-true
    "#EXT-X-MAP:URI=\"init.mp4\"" vod subseq? "init map tag is present" test-true
    "#EXTINF:2.000," vod subseq? "extinf duration is 2.000" test-true
    "chunk-1.m4s" vod subseq? "chunk-1 URI is present" test-true
    "chunk-2.m4s" vod subseq? "chunk-2 URI is present" test-true
    "chunk-3.m4s" vod subseq? "chunk-3 URI is present" test-true
    "#EXT-X-ENDLIST" vod subseq? "VOD concludes with #EXT-X-ENDLIST" test-true ;

:: test-hls-live-sliding-window ( -- )
    "Testing HLS Live Sliding Window Media Playlist Generation..." print

    1 0 180000 90000 make-dummy-segment :> s1
    2 180000 180000 90000 make-dummy-segment :> s2
    3 360000 180000 90000 make-dummy-segment :> s3
    4 540000 180000 90000 make-dummy-segment :> s4
    5 720000 180000 90000 make-dummy-segment :> s5
    6 900000 180000 90000 make-dummy-segment :> s6
    7 1080000 180000 90000 make-dummy-segment :> s7

    ! Window size of 4 over 7 segments: media sequence should be 4 (1 + 7 - 4 = 4)
    { s1 s2 s3 s4 s5 s6 s7 } 4 "init.mp4" build-hls-live-playlist :> live

    "#EXTM3U" live subseq? "live starts with #EXTM3U" test-true
    "#EXT-X-PLAYLIST-TYPE:VOD" live subseq? not "live playlist omits VOD tag" test-true
    "#EXT-X-MEDIA-SEQUENCE:4" live subseq? "media sequence is 4" test-true
    "chunk-1.m4s" live subseq? not "chunk-1 is pruned from live window" test-true
    "chunk-3.m4s" live subseq? not "chunk-3 is pruned from live window" test-true
    "chunk-4.m4s" live subseq? "chunk-4 is present in live window" test-true
    "chunk-5.m4s" live subseq? "chunk-5 is present in live window" test-true
    "chunk-6.m4s" live subseq? "chunk-6 is present in live window" test-true
    "chunk-7.m4s" live subseq? "chunk-7 is present in live window" test-true
    "#EXT-X-ENDLIST" live subseq? not "live playlist omits #EXT-X-ENDLIST" test-true ;

:: test-dash-mpd-authoring ( -- )
    "Testing ISO/IEC 23009-1 DASH MPD Authoring..." print

    1 "avc1" 90000 1920 1080 B{ 0x01 } <video-track> :> v-trk
    2 "mp4a" 48000 48000 2 B{ 0x02 } <audio-track> :> a-trk

    1 0 180000 90000 make-dummy-segment :> s1
    2 180000 180000 90000 make-dummy-segment :> s2
    3 360000 180000 90000 make-dummy-segment :> s3

    ! VOD MPD
    { v-trk a-trk } { s1 s2 s3 } f build-dash-mpd :> vod-mpd
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" vod-mpd subseq? "mpd has xml declaration" test-true
    "<MPD xmlns=\"urn:mpeg:dash:schema:mpd:2011\"" vod-mpd subseq? "mpd has schema urn" test-true
    "type=\"static\"" vod-mpd subseq? "vod mpd is static" test-true
    "mediaPresentationDuration=\"PT6.000S\"" vod-mpd subseq? "vod duration is 6s" test-true
    "contentType=\"video\"" vod-mpd subseq? "contains video adaptation set" test-true
    "contentType=\"audio\"" vod-mpd subseq? "contains audio adaptation set" test-true
    "width=\"1920\" height=\"1080\"" vod-mpd subseq? "video dimensions in representation" test-true
    "<SegmentTimeline>" vod-mpd subseq? "timeline present in mpd" test-true
    "<S t=\"0\" d=\"180000\" r=\"2\" />" vod-mpd subseq? "segments run-length compressed" test-true

    ! Live MPD
    { v-trk a-trk } { s1 s2 s3 } t build-dash-mpd :> live-mpd
    "type=\"dynamic\"" live-mpd subseq? "live mpd is dynamic" test-true
    "timeShiftBufferDepth=\"PT60.0S\"" live-mpd subseq? "live mpd specifies timeshift buffer" test-true ;

:: test-manifest-coordinator-and-bundle ( -- )
    "Testing Synchronous Dual-Manifest Coordinator & Asset Map..." print

    1 "avc1" 90000 1920 1080 B{ 0x01 } <video-track> :> v-trk
    0 0 0 90000 t "init.mp4" B{ 0x11 0x22 0x33 0x44 } <media-segment> :> init-seg
    1 0 180000 90000 make-dummy-segment :> s1
    2 180000 180000 90000 make-dummy-segment :> s2

    init-seg { s1 s2 } { v-trk } 360000 <transmux-result> :> result

    result f coordinate-manifests :> bundle
    bundle hls-master>> length 0 > "bundle hls-master is non-empty" test-true
    bundle hls-media>> length 0 > "bundle hls-media is non-empty" test-true
    bundle dash-mpd>> length 0 > "bundle dash-mpd is non-empty" test-true
    bundle is-live?>> f = "bundle is-live is false" test-true

    bundle bundle-file-map :> files
    "master.m3u8" files key? "file map has master.m3u8" test-true
    "stream.m3u8" files key? "file map has stream.m3u8" test-true
    "manifest.mpd" files key? "file map has manifest.mpd" test-true
    "init.mp4" files key? "file map has init.mp4" test-true
    "chunk-1.m4s" files key? "file map has chunk-1.m4s" test-true
    "chunk-2.m4s" files key? "file map has chunk-2.m4s" test-true

    ! Live rolling update
    3 360000 180000 90000 make-dummy-segment :> s3
    bundle s3 2 update-live-manifests :> live-bundle
    live-bundle is-live?>> t = "updated bundle is live" test-true
    live-bundle media-segments>> length 3 "updated bundle has 3 segments" test= ;

:: run-manifest-tests ( -- )
    init-test-harness
    test-hls-master-authoring
    test-hls-vod-media-playlist
    test-hls-live-sliding-window
    test-dash-mpd-authoring
    test-manifest-coordinator-and-bundle
    "Venturi Manifest & Playlist Authoring Test Suite" print-test-summary drop ;

MAIN: run-manifest-tests
