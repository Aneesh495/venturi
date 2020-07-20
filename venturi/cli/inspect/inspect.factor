! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! CLI command: inspect
! Probes and outputs structural container telemetry, box hierarchies,
! and codec configurations for ISOBMFF and MPEG-2 TS media streams.

USING: accessors arrays formatting io io.encodings.binary io.files kernel
locals math math.parser sequences strings venturi.common.types
venturi.common.utils venturi.isobmff.box-reader venturi.isobmff.constants
venturi.isobmff.demuxer venturi.mpegts.demuxer ;
IN: venturi.cli.inspect

:: print-separator ( -- )
    "--------------------------------------------------------------------------------" print ;

:: inspect-isobmff ( bytes path -- )
    print-separator
    "VENTURI MEDIA CONTAINER INSPECTION: ISOBMFF / CMAF" print
    print-separator
    "File:        " write path print
    "File Size:   " write bytes length number>string write " bytes" print

    ! Parse root boxes
    bytes 0 bytes length parse-boxes :> root-boxes
    "Root Boxes:  " write root-boxes length number>string print
    root-boxes [
        :> b
        "  + Box [" write b type>> 4cc>string write "] offset=" write
        b offset>> number>string write " size=" write
        b size>> number>string print
    ] each

    ! Demux container tracks
    bytes demux-isobmff :> tracks
    "\nDetected Media Tracks: " write tracks length number>string print
    tracks [
        :> trk
        trk type>> +video+ = [
            "  [Track " write trk id>> number>string write "] Type: VIDEO" print
            "    Codec:      " write trk codec>> print
            "    Dimensions: " write trk width>> number>string write "x" write trk height>> number>string print
            "    Timescale:  " write trk timescale>> number>string write " Hz" print
            "    Duration:   " write trk duration>> number>string write " ticks (" write
            trk duration>> trk timescale>> /f "%.3f" sprintf write " sec)" print
            "    Samples:    " write trk samples>> length number>string print
        ] [
            "  [Track " write trk id>> number>string write "] Type: AUDIO" print
            "    Codec:      " write trk codec>> print
            "    Sample Rate:" write trk sample-rate>> number>string write " Hz" print
            "    Channels:   " write trk channels>> number>string print
            "    Timescale:  " write trk timescale>> number>string write " Hz" print
            "    Duration:   " write trk duration>> number>string write " ticks (" write
            trk duration>> trk timescale>> /f "%.3f" sprintf write " sec)" print
            "    Samples:    " write trk samples>> length number>string print
        ] if
    ] each
    print-separator ;

:: inspect-mpegts ( bytes path -- )
    print-separator
    "VENTURI MEDIA CONTAINER INSPECTION: MPEG-2 TRANSPORT STREAM" print
    print-separator
    "File:        " write path print
    "File Size:   " write bytes length number>string write " bytes" print
    "Packets:     " write bytes length 188 / >integer number>string print

    bytes demux-mpegts :> tracks
    "\nDemuxed Elementary Streams: " write tracks length number>string print
    tracks [
        :> trk
        trk type>> +video+ = [
            "  [Stream PID 0x" write trk id>> >hex write "] Type: VIDEO (AVC/H.264)" print
            "    Timescale:  " write trk timescale>> number>string write " Hz (90 kHz clock)" print
            "    Duration:   " write trk duration>> number>string write " ticks (" write
            trk duration>> trk timescale>> /f "%.3f" sprintf write " sec)" print
            "    Samples:    " write trk samples>> length number>string print
        ] [
            "  [Stream PID 0x" write trk id>> >hex write "] Type: AUDIO (AAC ADTS)" print
            "    Timescale:  " write trk timescale>> number>string write " Hz (90 kHz clock)" print
            "    Duration:   " write trk duration>> number>string write " ticks (" write
            trk duration>> trk timescale>> /f "%.3f" sprintf write " sec)" print
            "    Samples:    " write trk samples>> length number>string print
        ] if
    ] each
    print-separator ;

:: run-inspect-command ( path -- )
    path file-exists? [
        path binary file-contents :> bytes
        bytes length 8 >= [
            ! Check for ISOBMFF ftyp box at offset 4
            bytes 4 read-be32 FOURCC_FTYP = [
                bytes path inspect-isobmff
            ] [
                ! Check for MPEG-TS 0x47 sync byte
                0 bytes nth 0x47 = [
                    bytes path inspect-mpegts
                ] [
                    "Unknown or unsupported media container format." print
                ] if
            ] if
        ] [
            "File too small to be a valid media stream." print
        ] if
    ] [
        "Error: File not found: " write path print
    ] if ;
