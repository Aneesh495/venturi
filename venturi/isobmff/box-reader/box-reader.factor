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

: <full-box> ( type size header-size offset payload ver flg -- fbox )
    [ <mp4-box> ] 2dip full-box boa ;

! Returns true if the FourCC identifies a structural container atom.
:: container-box? ( fourcc -- ? )
    fourcc {
        FOURCC_MOOV
        FOURCC_TRAK
        FOURCC_MDIA
        FOURCC_MINF
        FOURCC_DINF
        FOURCC_STBL
        FOURCC_MVEX
        FOURCC_MOOF
        FOURCC_TRAF
    } member? ;

! Returns true if the FourCC identifies an ISO FullBox with version and flags.
:: full-box-type? ( fourcc -- ? )
    fourcc {
        FOURCC_MVHD
        FOURCC_TKHD
        FOURCC_MDHD
        FOURCC_HDLR
        FOURCC_VMHD
        FOURCC_SMHD
        FOURCC_DREF
        FOURCC_STSD
        FOURCC_STTS
        FOURCC_CTTS
        FOURCC_STSC
        FOURCC_STSZ
        FOURCC_STZ2
        FOURCC_STCO
        FOURCC_CO64
        FOURCC_STSS
        FOURCC_SDTP
        FOURCC_MEHD
        FOURCC_TREX
        FOURCC_MFHD
        FOURCC_TFHD
        FOURCC_TFDT
        FOURCC_TRUN
        FOURCC_SIDX
        FOURCC_EMSG
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
                payload 0 nth :> ver
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
    f :> found!
    box children>> [
        dup type>> target-type = [
            found! drop
        ] [
            drop
        ] if
    ] each
    found ;

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
