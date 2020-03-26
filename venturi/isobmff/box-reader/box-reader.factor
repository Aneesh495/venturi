! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Recursive ISO/IEC 14496-12 box header parser supporting 32-bit compact
! headers, 64-bit largesize extended headers, and deep container traversal.

USING: accessors byte-arrays kernel locals math math.order
sequences vectors venturi.common.utils venturi.isobmff.constants ;
IN: venturi.isobmff.box-reader

! Core MP4 box tuple representing an atom node in the ISOBMFF tree.
TUPLE: mp4-box
    { type integer read-only }
    { size integer read-only }
    { header-size integer read-only }
    { payload-offset integer read-only }
    { payload byte-array read-only }
    { children vector } ;

: <mp4-box> ( type size header-size offset payload -- box )
    V{ } clone mp4-box boa ;

! FullBox variant containing version (8-bit) and flags (24-bit).
TUPLE: full-box < mp4-box
    { version integer read-only }
    { flags integer read-only } ;

:: <full-box> ( type size header-size offset payload ver flg -- fbox )
    type size header-size offset payload V{ } clone ver flg full-box boa ;

! Returns true if the FourCC identifies a structural container atom.
:: container-box? ( fourcc -- ? )
    fourcc {
        0x6D6F6F76  ! moov
        0x7472616B  ! trak
        0x6D646961  ! mdia
        0x6D696E66  ! minf
        0x64696E66  ! dinf
        0x7374626C  ! stbl
        0x6D766578  ! mvex
        0x6D6F6F66  ! moof
        0x74726166  ! traf
    } member? ;

! Returns true if the FourCC identifies an ISO FullBox with version and flags.
:: full-box-type? ( fourcc -- ? )
    fourcc {
        0x6D766864  ! mvhd
        0x746B6864  ! tkhd
        0x6D646864  ! mdhd
        0x68646C72  ! hdlr
        0x766D6864  ! vmhd
        0x736D6864  ! smhd
        0x64726566  ! dref
        0x73747364  ! stsd
        0x73747473  ! stts
        0x63747473  ! ctts
        0x73747363  ! stsc
        0x7374737A  ! stsz
        0x73747A32  ! stz2
        0x7374636F  ! stco
        0x636F3634  ! co64
        0x73747373  ! stss
        0x73647470  ! sdtp
        0x6D656864  ! mehd
        0x74726578  ! trex
        0x6D666864  ! mfhd
        0x74666864  ! tfhd
        0x74666474  ! tfdt
        0x7472756E  ! trun
        0x73696478  ! sidx
        0x656D7367  ! emsg
    } member? ;

! Reads the box header from bytes at offset. Returns ( type size header-size ).
:: read-box-header ( bytes offset max-offset -- type size header-size )
    max-offset offset - :> rem-len
    rem-len 8 < [
        0 0 0
    ] [
        bytes offset read-be32 :> raw-size
        bytes offset 4 + read-be32 :> fourcc
        raw-size 1 = [
            rem-len 16 < [
                0 0 0
            ] [
                fourcc
                bytes offset 8 + read-be64
                16
            ] if
        ] [
            raw-size zero? [
                fourcc rem-len 8
            ] [
                fourcc raw-size 8
            ] if
        ] if
    ] if ;

DEFER: parse-boxes

! Parses a single box starting at offset. Returns ( box next-offset ).
:: parse-box ( bytes offset max-offset -- box/f next-offset )
    bytes offset max-offset read-box-header :> ( fourcc b-size h-size )
    h-size zero? [ f max-offset ] [
        offset b-size + :> next-off
        offset h-size + :> p-start
        next-off bytes length min :> p-end
        p-start p-end bytes subseq-safe :> payload

        fourcc full-box-type? [
            payload length 4 >= [
                0 payload nth :> ver
                payload 1 read-be24 :> flg
                fourcc b-size h-size p-start payload ver flg <full-box>
            ] [
                fourcc b-size h-size p-start payload <mp4-box>
            ] if
        ] [
            fourcc b-size h-size p-start payload <mp4-box>
        ] if :> box

        fourcc container-box? [
            box bytes p-start p-end parse-boxes >>children drop
        ] when

        box next-off
    ] if ;

! Recursively parses all consecutive boxes within the byte range [offset, max-offset).
:: parse-boxes ( bytes offset max-offset -- boxes )
    V{ } clone :> out
    offset :> curr!
    [ curr max-offset < ] [
        bytes curr max-offset parse-box :> ( b next-off )
        b [ b out push ] when
        next-off curr <= [ max-offset curr! ] [ next-off curr! ] if
    ] while
    out ;

! Searches immediate children of a box for the first match with target-type.
:: find-child-box ( box target-type -- child/f )
    box children>> [ type>> target-type = ] find nip ;

! Searches immediate children of a box for all matches with target-type.
:: find-child-boxes ( box target-type -- matching-children )
    box children>> [ type>> target-type = ] filter ;

! Traverses a hierarchical path of FourCC identifiers (for example { moov trak mdia minf stbl }).
:: find-box-path ( root-box path-seq -- target-box/f )
    root-box :> curr!
    path-seq [
        :> step-fourcc
        curr [
            curr step-fourcc find-child-box curr!
        ] when
    ] each
    curr ;
