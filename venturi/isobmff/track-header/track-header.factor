! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Parsers and declarative builders for Movie Header (mvhd), Track Header (tkhd),
! Media Header (mdhd), Handler Reference (hdlr), and Media Information (minf/vmhd/smhd) boxes.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise math.functions sequences strings venturi.common.utils
venturi.isobmff.box-reader venturi.isobmff.box-writer
venturi.isobmff.constants ;
IN: venturi.isobmff.track-header

! Decoded Movie Header attributes.
TUPLE: mvhd-info
    { timescale integer read-only }
    { duration integer read-only }
    { next-track-id integer read-only } ;

: <mvhd-info> ( timescale duration next-track-id -- info )
    mvhd-info boa ;

! Decoded Track Header attributes.
TUPLE: tkhd-info
    { track-id integer read-only }
    { duration integer read-only }
    { width float read-only }
    { height float read-only }
    { volume float read-only } ;

: <tkhd-info> ( track-id duration width height volume -- info )
    tkhd-info boa ;

! Decoded Media Header attributes.
TUPLE: mdhd-info
    { timescale integer read-only }
    { duration integer read-only }
    { language string read-only } ;

: <mdhd-info> ( timescale duration language -- info )
    mdhd-info boa ;

! Decoded Handler Reference attributes.
TUPLE: hdlr-info
    { handler-type integer read-only }
    { name string read-only } ;

: <hdlr-info> ( handler-type name -- info )
    hdlr-info boa ;

! Identity display transformation matrix (36 bytes: unity scale, zero shear).
:: build-identity-matrix ( -- bytes )
    36 <byte-vector> :> buf
    buf 0x00010000 push-be32  ! a: 1.0 (16.16)
    buf 0          push-be32  ! b: 0.0
    buf 0          push-be32  ! u: 0.0
    buf 0          push-be32  ! c: 0.0
    buf 0x00010000 push-be32  ! d: 1.0 (16.16)
    buf 0          push-be32  ! v: 0.0
    buf 0          push-be32  ! x: 0.0
    buf 0          push-be32  ! y: 0.0
    buf 0x40000000 push-be32  ! w: 1.0 (2.30)
    buf >byte-array ;

! Packs a 3-character ISO-639-2/T language code (for example "und" or "eng") into uint16.
:: pack-iso-language ( lang-str -- u16 )
    lang-str length 3 < [ 0x55C4 ] [ ! default "und"
        0 lang-str nth 0x60 - 0x1F bitand 10 shift
        1 lang-str nth 0x60 - 0x1F bitand 5 shift +
        2 lang-str nth 0x60 - 0x1F bitand +
    ] if ;

! Unpacks a uint16 ISO-639-2/T language code into a 3-character ASCII string.
:: unpack-iso-language ( u16 -- lang-str )
    u16 -10 shift 0x1F bitand 0x60 +
    u16 -5 shift 0x1F bitand 0x60 +
    u16 0x1F bitand 0x60 +
    3array >string ;

! Parses an mvhd FullBox payload.
:: parse-mvhd ( box -- info/f )
    box payload>> :> p
    p length 100 < [ f ] [
        0 p nth :> ver
        ver 1 = [
            p 20 read-be32 :> timescale
            p 24 read-be64 :> duration
            p 96 read-be32 :> next-id
            timescale duration next-id <mvhd-info>
        ] [
            p 12 read-be32 :> timescale
            p 16 read-be32 :> duration
            p 96 read-be32 :> next-id
            timescale duration next-id <mvhd-info>
        ] if
    ] if ;

! Parses a tkhd FullBox payload.
:: parse-tkhd ( box -- info/f )
    box payload>> :> p
    p length 84 < [ f ] [
        0 p nth :> ver
        ver 1 = [
            p 20 read-be32 :> track-id
            p 28 read-be64 :> duration
            p 44 read-fixed-8-8 :> volume
            p 76 read-fixed-16-16 :> width
            p 80 read-fixed-16-16 :> height
            track-id duration width height volume <tkhd-info>
        ] [
            p 12 read-be32 :> track-id
            p 20 read-be32 :> duration
            p 36 read-fixed-8-8 :> volume
            p 76 read-fixed-16-16 :> width
            p 80 read-fixed-16-16 :> height
            track-id duration width height volume <tkhd-info>
        ] if
    ] if ;

! Parses an mdhd FullBox payload.
:: parse-mdhd ( box -- info/f )
    box payload>> :> p
    p length 24 < [ f ] [
        0 p nth :> ver
        ver 1 = [
            p 20 read-be32 :> timescale
            p 24 read-be64 :> duration
            p 32 read-be16 unpack-iso-language :> lang
            timescale duration lang <mdhd-info>
        ] [
            p 12 read-be32 :> timescale
            p 16 read-be32 :> duration
            p 20 read-be16 unpack-iso-language :> lang
            timescale duration lang <mdhd-info>
        ] if
    ] if ;

! Parses an hdlr FullBox payload.
:: parse-hdlr ( box -- info/f )
    box payload>> :> p
    p length 24 < [ f ] [
        p 8 read-be32 :> h-type
        24 p length p subseq-safe :> name-bytes
        name-bytes >string :> name-str
        h-type name-str <hdlr-info>
    ] if ;

! Builds a Movie Header (mvhd) FullBox (version 0).
:: build-mvhd-box ( timescale duration next-track-id -- box-bytes )
    108 <byte-vector> :> p
    p 0 push-be32             ! creation_time = 0
    p 0 push-be32             ! modification_time = 0
    p timescale push-be32     ! timescale
    p duration push-be32      ! duration
    p 0x00010000 push-be32    ! rate = 1.0 (16.16)
    p 0x0100 push-be16        ! volume = 1.0 (8.8)
    p 10 <byte-array> push-bytes ! reserved
    p build-identity-matrix push-bytes ! matrix (36 bytes)
    p 24 <byte-array> push-bytes ! pre_defined (24 bytes)
    p next-track-id push-be32 ! next_track_id
    FOURCC_MVHD 0 0 p >byte-array serialize-full-box ;

! Builds a Track Header (tkhd) FullBox (version 0).
! flags: 0x000007 (Track_enabled, Track_in_movie, Track_in_preview)
:: build-tkhd-box ( track-id duration width height is-audio? -- box-bytes )
    84 <byte-vector> :> p
    p 0 push-be32             ! creation_time = 0
    p 0 push-be32             ! modification_time = 0
    p track-id push-be32      ! track_id
    p 0 push-be32             ! reserved
    p duration push-be32      ! duration
    p 8 <byte-array> push-bytes ! reserved
    p 0 push-be16             ! layer = 0
    p 0 push-be16             ! alternate_group = 0
    p is-audio? [ 0x0100 ] [ 0x0000 ] if push-be16 ! volume
    p 0 push-be16             ! reserved
    p build-identity-matrix push-bytes ! matrix
    p width push-fixed-16-16  ! track width (16.16)
    p height push-fixed-16-16 ! track height (16.16)
    FOURCC_TKHD 0 0x000007 p >byte-array serialize-full-box ;

! Builds a Media Header (mdhd) FullBox (version 0).
:: build-mdhd-box ( timescale duration lang-str -- box-bytes )
    24 <byte-vector> :> p
    p 0 push-be32             ! creation_time = 0
    p 0 push-be32             ! modification_time = 0
    p timescale push-be32     ! timescale
    p duration push-be32      ! duration
    p lang-str pack-iso-language push-be16 ! language
    p 0 push-be16             ! pre_defined = 0
    FOURCC_MDHD 0 0 p >byte-array serialize-full-box ;

! Builds a Handler Reference (hdlr) FullBox.
:: build-hdlr-box ( handler-type name-str -- box-bytes )
    name-str length 25 + <byte-vector> :> p
    p 0 push-be32             ! pre_defined = 0
    p handler-type push-be32  ! handler_type (e.g. 'vide', 'soun')
    p 12 <byte-array> push-bytes ! reserved
    p name-str >byte-array push-bytes
    p 0 push-u8               ! null terminator
    FOURCC_HDLR 0 0 p >byte-array serialize-full-box ;

! Builds a Video Media Header (vmhd) FullBox.
:: build-vmhd-box ( -- box-bytes )
    8 <byte-vector> :> p
    p 0 push-be16  ! graphicsmode = copy (0)
    p 0 push-be16  ! opcolor[0]
    p 0 push-be16  ! opcolor[1]
    p 0 push-be16  ! opcolor[2]
    FOURCC_VMHD 0 1 p >byte-array serialize-full-box ;

! Builds a Sound Media Header (smhd) FullBox.
:: build-smhd-box ( -- box-bytes )
    4 <byte-vector> :> p
    p 0 push-be16  ! balance = 0.0 (center)
    p 0 push-be16  ! reserved = 0
    FOURCC_SMHD 0 0 p >byte-array serialize-full-box ;

! Builds a Data Information (dinf) Box with a single self-contained url dref.
:: build-dinf-box ( -- box-bytes )
    ! url box with flag 0x000001 (in same file)
    B{ } FOURCC_URL 0 0x000001 rot serialize-full-box :> url-box
    url-box length 8 + <byte-vector> :> dref-payload
    dref-payload 1 push-be32  ! entry_count = 1
    dref-payload url-box push-bytes
    FOURCC_DREF 0 0 dref-payload >byte-array serialize-full-box :> dref-box
    FOURCC_DINF { dref-box } serialize-container-box ;
