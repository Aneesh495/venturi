! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! CLI command: serve
! Launches an edge HTTP streaming server dispatching HLS, DASH, and CMAF fragments.

USING: accessors arrays assocs formatting hashtables io io.directories
io.encodings.binary io.files io.files.info io.files.types io.servers kernel locals math
math.parser sequences strings venturi.common.types venturi.common.utils
venturi.isobmff.constants venturi.isobmff.demuxer
venturi.manifests.coordinator venturi.mpegts.demuxer
venturi.packaging.pipeline venturi.server.http-server
venturi.server.live-stream ;
IN: venturi.cli.serve

:: print-server-banner ( port is-live? -- )
    "================================================================================" print
    "                     VENTURI HIGH-PERFORMANCE EDGE STREAMER                     " print
    "================================================================================" print
    "Listening on:       http://0.0.0.0:" write port number>string print
    "Profile:            " write is-live? [ "LIVE EDGE (low-latency ring)" ] [ "VOD CATALOG (byte-range indexing)" ] if print
    "CORS Preflight:     Enabled (*)" print
    "RFC 7233 Ranges:    Enabled (Accept-Ranges: bytes)" print
    "" print
    "Streaming Endpoints:" print
    "  * HLS Multivariant: http://localhost:" write port number>string write "/master.m3u8" print
    "  * HLS Stream:       http://localhost:" write port number>string write "/stream.m3u8" print
    "  * DASH MPD XML:     http://localhost:" write port number>string write "/manifest.mpd" print
    "================================================================================" print ;

:: load-directory-files ( dir-path -- file-map )
    H{ } clone :> files
    dir-path directory-entries [
        :> entry
        entry type>> +regular-file+ = [
            entry name>> :> fname
            dir-path "/" append fname append binary file-contents :> b
            b fname files set-at
        ] when
    ] each
    files ;

:: run-serve-command ( target-path port is-live? -- )
    target-path file-exists? [
        target-path directory? [
            target-path load-directory-files :> files
            f :> live-ring
            port is-live? print-server-banner
            port files live-ring <venturi-server> start-venturi-server drop
        ] [
            ! Transmux input file on the fly and serve
            target-path binary file-contents :> in-bytes
            f :> tracks!
            in-bytes length 8 >= [
                in-bytes 4 read-be32 FOURCC_FTYP = [
                    in-bytes demux-isobmff tracks!
                ] [
                    0 in-bytes nth 0x47 = [
                        in-bytes demux-mpegts tracks!
                    ] when
                ] if
            ] when

            tracks [
                "Transmuxing media stream for edge delivery..." print
                tracks 2000 transmux-tracks-to-cmaf :> result
                result is-live? coordinate-manifests :> bundle
                bundle bundle-file-map :> files

                is-live? [
                    10 <live-ring-buffer> :> ring
                    bundle init-segment>> ring set-init-segment
                    bundle media-segments>> [ ring push-live-segment ] each
                    ring
                ] [ f ] if :> live-ring

                port is-live? print-server-banner
                port files live-ring <venturi-server> start-venturi-server drop
            ] [
                "Error: Failed to demux media tracks from source file." print
            ] if
        ] if
    ] [
        "Error: Path does not exist: " write target-path print
    ] if ;
