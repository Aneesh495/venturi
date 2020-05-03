! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ISO/IEC 13818-7 / ISO/IEC 14496-3 Advanced Audio Coding (AAC) parser.
! ADTS framing, AudioSpecificConfig (ASC) generation, and MPEG-4 esds box authoring.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise sequences vectors venturi.common.bitstream
venturi.common.utils venturi.isobmff.box-writer
venturi.isobmff.constants ;
IN: venturi.codecs.aac

! Standard AAC sampling frequencies indexed 0 through 12
CONSTANT: AAC_SAMPLE_RATES {
    96000 88200 64000 48000 44100 32000
    24000 22050 16000 12000 11025 8000 7350
}

! Maps a sampling frequency integer to its 4-bit standard index.
:: sample-rate>index ( rate -- index )
    AAC_SAMPLE_RATES rate index [ 4 ] unless* ;

! Maps a 4-bit index to its sampling frequency in Hz.
:: index>sample-rate ( idx -- rate )
    idx 0 >= idx AAC_SAMPLE_RATES length < and [
        idx AAC_SAMPLE_RATES nth
    ] [ 44100 ] if ;

! Parsed ADTS Frame Header representation
TUPLE: adts-header
    { mpeg-version integer read-only }        ! 0 = MPEG-4, 1 = MPEG-2
    { protection-absent? boolean read-only }  ! t = no CRC (7 bytes), f = with CRC (9 bytes)
    { profile integer read-only }             ! 1 = AAC Main, 2 = AAC LC, 3 = AAC SSR
    { sample-rate-index integer read-only }   ! 0..12
    { sample-rate integer read-only }         ! in Hz
    { channels integer read-only }            ! 1..7
    { frame-length integer read-only }        ! total frame byte length including header
    { header-length integer read-only }       ! 7 or 9
    { payload byte-array read-only } ;

: <adts-header> ( mpeg-ver prot? prof sr-idx sr chan f-len h-len pl -- adts )
    adts-header boa ;

! Parses a single ADTS frame from bytes starting at offset.
:: parse-adts-frame ( bytes offset -- adts/f )
    offset 7 + bytes length <= [
        bytes offset read-be16 :> w0
        w0 -4 shift 0x0FFF bitand 0x0FFF = not [ f ] [
            w0 3 bit? 1 0 ? :> mpeg-ver
            w0 0 bit? :> prot-absent
            prot-absent 7 9 ? :> header-len

            offset 2 + bytes nth :> b2
            offset 3 + bytes nth :> b3
            offset 4 + bytes nth :> b4
            offset 5 + bytes nth :> b5

            b2 -6 shift 0x03 bitand 1 + :> profile
            b2 -2 shift 0x0F bitand :> sr-idx
            sr-idx index>sample-rate :> sr
            b2 1 bitand 2 shift b3 -6 shift 0x03 bitand bitor :> channels

            b3 0x03 bitand 11 shift
            b4 3 shift +
            b5 -5 shift 0x07 bitand + :> frame-len

            offset frame-len + bytes length <= frame-len header-len >= and [
                offset header-len + offset frame-len + bytes subseq-safe :> pl
                mpeg-ver prot-absent profile sr-idx sr channels frame-len header-len pl <adts-header>
            ] [ f ] if
        ] if
    ] [ f ] if ;

! Demuxes an ADTS stream buffer into a sequence of parsed adts-header structures.
:: split-adts-stream ( bytes -- frames )
    V{ } clone :> out
    0 :> off!
    bytes length :> len
    [ off 7 + len <= ] [
        bytes off parse-adts-frame :> frame
        frame [
            frame out push
            off frame frame-length>> + off!
        ] [
            off 1 + off!
        ] if
    ] while
    out ;

! Synthesizes a 2-byte ISO/IEC 14496-3 AudioSpecificConfig (ASC).
:: build-audio-specific-config ( aot sample-rate channels -- asc-bytes )
    sample-rate sample-rate>index :> sr-idx
    2 <byte-array> :> buf
    aot 0x1F bitand 3 shift sr-idx -1 shift 0x07 bitand bitor 0 buf set-nth
    sr-idx 0x01 bitand 7 shift channels 0x0F bitand 3 shift bitor 1 buf set-nth
    buf ;

! Parses a 2-byte AudioSpecificConfig into object type, sampling frequency, and channels.
:: parse-audio-specific-config ( asc-bytes -- aot sample-rate channels )
    asc-bytes length 2 < [ 2 44100 2 ] [
        0 asc-bytes nth :> b0
        1 asc-bytes nth :> b1
        b0 -3 shift 0x1F bitand :> aot
        b0 0x07 bitand 1 shift b1 -7 shift 0x01 bitand bitor :> sr-idx
        b1 -3 shift 0x0F bitand :> channels
        aot sr-idx index>sample-rate channels
    ] if ;

! Authors an ISO/IEC 14496-1 Elementary Stream Descriptor (esds) box for MP4 audio.
:: build-esds-box ( asc-bytes -- box-bytes )
    128 <byte-vector> :> buf

    ! FullBox header (version 0, flags 0)
    buf 0 push-be32

    ! ES_Descriptor (tag 0x03)
    buf 0x03 push-u8
    asc-bytes length 20 + :> es-len
    buf es-len push-u8
    buf 0x0001 push-be16 ! ES_ID = 1
    buf 0x00 push-u8     ! flags (streamDependence, URL, OCRstream = 0)

    ! DecoderConfigDescriptor (tag 0x04)
    buf 0x04 push-u8
    asc-bytes length 13 + :> dec-len
    buf dec-len push-u8
    buf 0x40 push-u8     ! objectTypeIndication = 0x40 (Audio ISO/IEC 14496-3)
    buf 0x15 push-u8     ! streamType = 5 (AudioStream) << 2 | 1
    buf 0x000000 push-be24 ! bufferSizeDB = 0
    buf 128000 push-be32 ! maxBitrate = 128 kbps
    buf 128000 push-be32 ! avgBitrate = 128 kbps

    ! DecoderSpecificInfo (tag 0x05)
    buf 0x05 push-u8
    buf asc-bytes length push-u8
    buf asc-bytes push-bytes

    ! SLConfigDescriptor (tag 0x06)
    buf 0x06 push-u8
    buf 1 push-u8
    buf 0x02 push-u8     ! predefined = 2 (reserved for MP4)

    FOURCC_ESDS buf >byte-array serialize-box ;
