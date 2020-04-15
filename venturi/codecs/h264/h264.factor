! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ITU-T H.264 / ISO/IEC 14496-10 Advanced Video Coding (AVC) bitstream parser.
! Annex B start code scanning, emulation prevention byte extraction,
! and NAL unit classification.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise sequences vectors venturi.common.utils ;
IN: venturi.codecs.h264

! Canonical H.264 NAL Unit Types
CONSTANT: NAL_UNSPECIFIED 0
CONSTANT: NAL_NON_IDR     1  ! Coded slice of a non-IDR picture
CONSTANT: NAL_PARTITION_A 2  ! Coded slice data partition A
CONSTANT: NAL_PARTITION_B 3  ! Coded slice data partition B
CONSTANT: NAL_PARTITION_C 4  ! Coded slice data partition C
CONSTANT: NAL_IDR         5  ! Coded slice of an IDR picture (keyframe)
CONSTANT: NAL_SEI         6  ! Supplemental enhancement information
CONSTANT: NAL_SPS         7  ! Sequence parameter set
CONSTANT: NAL_PPS         8  ! Picture parameter set
CONSTANT: NAL_AUD         9  ! Access unit delimiter
CONSTANT: NAL_END_SEQ     10 ! End of sequence
CONSTANT: NAL_END_STREAM  11 ! End of stream
CONSTANT: NAL_FILLER      12 ! Filler data

! Unified NAL unit structure
TUPLE: nal-unit
    { type integer read-only }
    { ref-idc integer read-only }
    { data byte-array read-only }
    { rbsp byte-array read-only } ;

: <nal-unit> ( type ref-idc data rbsp -- nal )
    nal-unit boa ;

! Strips emulation prevention bytes (0x000003 -> 0x0000) from NAL unit body.
:: remove-emulation-prevention ( bytes -- rbsp )
    bytes length :> len
    len <byte-vector> :> out
    0 :> i!
    [ i len < ] [
        i len 3 - <= [
            i bytes nth 0 =
            i 1 + bytes nth 0 = and
            i 2 + bytes nth 3 = and [
                0 out push
                0 out push
                i 3 + i!
            ] [
                i bytes nth out push
                i 1 + i!
            ] if
        ] [
            i bytes nth out push
            i 1 + i!
        ] if
    ] while
    out >byte-array ;

! Parses 1-byte NAL unit header into type and ref-idc.
:: parse-nal-header ( byte -- nal-type nal-ref-idc )
    byte 0x1F bitand
    byte -5 shift 0x03 bitand ;

! Scans for the next Annex B start code prefix (0x000001 or 0x00000001) from offset.
:: find-annex-b-start ( bytes offset -- start-pos prefix-len/f )
    bytes length :> len
    offset :> i!
    f :> found-pos!
    f :> found-len!
    [ i len 3 - <= found-pos not and ] [
        i bytes nth 0 =
        i 1 + bytes nth 0 = and [
            i 2 + bytes nth 1 = [
                ! Found 3-byte prefix (0x000001)
                ! Check if preceded by another 0 for 4-byte prefix
                i 0 > [
                    i 1 - bytes nth 0 = [
                        i 1 - found-pos!
                        4 found-len!
                    ] [
                        i found-pos!
                        3 found-len!
                    ] if
                ] [
                    i found-pos!
                    3 found-len!
                ] if
            ] [
                i 2 + bytes nth 0 =
                i 3 + len < and [
                    i 3 + bytes nth 1 = [
                        i found-pos!
                        4 found-len!
                    ] when
                ] when
            ] if
        ] when
        i 1 + i!
    ] while
    found-pos found-len ;

! Demuxes an Annex B byte stream into discrete NAL units.
:: split-annex-b-nals ( bytes -- nals )
    V{ } clone :> nals
    bytes length :> len
    len 4 < [ nals ] [
        0 :> curr-off!
        [ curr-off len < ] [
            bytes curr-off find-annex-b-start :> ( start-pos prefix-len )
            start-pos [
                start-pos prefix-len + :> payload-start
                bytes payload-start find-annex-b-start :> ( next-start next-len )
                next-start [ next-start ] [ len ] if :> payload-end

                payload-end payload-start > [
                    payload-start payload-end bytes subseq-safe :> nal-data
                    nal-data 0 nth parse-nal-header :> ( n-type n-ref )
                    1 nal-data length nal-data subseq-safe remove-emulation-prevention :> rbsp
                    n-type n-ref nal-data rbsp <nal-unit> nals push
                ] when

                next-start [ next-start curr-off! ] [ len curr-off! ] if
            ] [
                len curr-off!
            ] if
        ] while
        nals
    ] if ;

! Determines if a NAL unit represents an IDR keyframe slice.
: keyframe-nal? ( nal -- ? )
    type>> NAL_IDR = ;

! Determines if a NAL unit represents a parameter set (SPS or PPS).
: parameter-set-nal? ( nal -- ? )
    type>> [ NAL_SPS = ] [ NAL_PPS = ] bi or ;
