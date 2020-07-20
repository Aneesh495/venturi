! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! CLI command: package
! Packages input media streams into CMAF fragments and coordinated HLS/DASH manifests.

USING: accessors arrays assocs formatting io io.directories
io.encodings.binary io.files kernel locals math math.parser sequences
strings venturi.common.types venturi.common.utils
venturi.isobmff.constants venturi.isobmff.demuxer
venturi.manifests.coordinator venturi.mpegts.demuxer
venturi.packaging.pipeline ;
IN: venturi.cli.package

:: print-package-header ( in-path out-dir dur is-live? -- )
    "--------------------------------------------------------------------------------" print
    "VENTURI MEDIA PACKAGER: CMAF / HLS / DASH" print
    "--------------------------------------------------------------------------------" print
    "Source Input:       " write in-path print
    "Destination:        " write out-dir print
    "Target Chunk Dur:   " write dur number>string write " sec" print
    "Stream Profile:     " write is-live? [ "LIVE (sliding window)" ] [ "VOD (complete catalog)" ] if print
    "--------------------------------------------------------------------------------" print ;

:: run-package-command ( in-path out-dir dur is-live? -- )
    in-path file-exists? [
        in-path out-dir dur is-live? print-package-header

        in-path binary file-contents :> in-bytes
        out-dir make-directories

        ! Demux based on container format
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
            "Transmuxing tracks into CMAF fragments..." print
            tracks dur 1000 * >integer transmux-tracks-to-cmaf :> result

            "Authoring synchronized HLS and DASH manifests..." print
            result is-live? coordinate-manifests :> bundle
            bundle bundle-file-map :> file-map

            "Writing output assets to disk..." print
            file-map [
                :> data :> filename
                out-dir "/" append filename append :> dest-file
                data dest-file binary set-file-contents
                "  -> Wrote " write dest-file write " (" write data length number>string write " bytes)" print
            ] assoc-each

            "--------------------------------------------------------------------------------" print
            "Packaging completed successfully." print
            "Total Segments:     " write result media-segments>> length number>string print
            "Total Duration:     " write result media-segments>> [ segment-duration-seconds ] map-sum "%.3f" sprintf write " sec" print
            "--------------------------------------------------------------------------------" print
        ] [
            "Error: Unable to demux any valid media tracks from source." print
        ] if
    ] [
        "Error: Source file does not exist: " write in-path print
    ] if ;
