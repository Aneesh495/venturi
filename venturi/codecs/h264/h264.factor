! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ITU-T H.264 / ISO/IEC 14496-10 Advanced Video Coding (AVC) bitstream parser.
! Annex B start code scanning, emulation prevention byte extraction,
! and NAL unit classification.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise sequences vectors venturi.common.bitstream
venturi.common.exp-golomb venturi.common.utils ;
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

! Sequence Parameter Set (SPS) extracted metadata
TUPLE: sps-info
    { profile-idc integer read-only }
    { profile-compat integer read-only }
    { level-idc integer read-only }
    { sps-id integer read-only }
    { width integer read-only }
    { height integer read-only }
    { frame-mbs-only? boolean read-only } ;

: <sps-info> ( prof-idc prof-compat lvl-idc sps-id w h mbs-only? -- sps )
    sps-info boa ;

! Picture Parameter Set (PPS) extracted metadata
TUPLE: pps-info
    { pps-id integer read-only }
    { sps-id integer read-only }
    { cabac? boolean read-only } ;

: <pps-info> ( pps-id sps-id cabac? -- pps )
    pps-info boa ;

! Parses an H.264 SPS raw byte sequence payload (RBSP).
:: parse-sps ( rbsp-bytes -- sps/f )
    rbsp-bytes length 3 < [ f ] [
        rbsp-bytes <bit-reader> :> reader
        reader 8 read-bits :> profile-idc
        reader 8 read-bits :> profile-compat
        reader 8 read-bits :> level-idc
        reader read-ue :> sps-id

        ! High profile extensions (FRExt)
        profile-idc { 100 110 122 244 44 83 86 118 128 138 139 134 135 } member? [
            reader read-ue :> chroma-format-idc
            chroma-format-idc 3 = [
                reader 1 read-bits drop ! separate_colour_plane_flag
            ] when
            reader read-ue drop ! bit_depth_luma_minus8
            reader read-ue drop ! bit_depth_chroma_minus8
            reader 1 read-bits drop ! qpprime_y_zero_transform_bypass_flag
            reader 1 read-bits 1 = [ ! seq_scaling_matrix_present_flag
                chroma-format-idc 3 = 12 8 ? [
                    reader 1 read-bits 1 = [
                        ! Skip scaling matrix coefficients
                        16 :> mat-size
                        8 :> last-scale!
                        8 :> next-scale!
                        0 :> j!
                        [ j mat-size < ] [
                            next-scale zero? not [
                                reader read-se :> delta-scale
                                last-scale delta-scale + 256 + 256 mod next-scale!
                            ] when
                            next-scale zero? [ last-scale ] [ next-scale ] if last-scale!
                            j 1 + j!
                        ] while
                    ] when
                ] times
            ] when
        ] when

        reader read-ue drop ! log2_max_frame_num_minus4
        reader read-ue :> pic-order-cnt-type
        pic-order-cnt-type 0 = [
            reader read-ue drop ! log2_max_pic_order_cnt_lsb_minus4
        ] [
            pic-order-cnt-type 1 = [
                reader 1 read-bits drop ! delta_pic_order_always_zero_flag
                reader read-se drop ! offset_for_non_ref_pic
                reader read-se drop ! offset_for_top_to_bottom_field
                reader read-ue :> num-ref-frames-in-pic-order-cnt-cycle
                num-ref-frames-in-pic-order-cnt-cycle [
                    reader read-se drop
                ] times
            ] when
        ] if

        reader read-ue drop ! max_num_ref_frames
        reader 1 read-bits drop ! gaps_in_frame_num_value_allowed_flag
        reader read-ue :> pic-width-in-mbs-minus1
        reader read-ue :> pic-height-in-map-units-minus1
        reader 1 read-bits 1 = :> frame-mbs-only?

        frame-mbs-only? not [
            reader 1 read-bits drop ! mb_adaptive_frame_field_flag
        ] when

        reader 1 read-bits drop ! direct_8x8_inference_flag

        0 :> crop-left!
        0 :> crop-right!
        0 :> crop-top!
        0 :> crop-bottom!

        reader 1 read-bits 1 = [ ! frame_cropping_flag
            reader read-ue crop-left!
            reader read-ue crop-right!
            reader read-ue crop-top!
            reader read-ue crop-bottom!
        ] when

        pic-width-in-mbs-minus1 1 + 16 * crop-left crop-right + 2 * - :> width
        pic-height-in-map-units-minus1 1 + 16 * frame-mbs-only? 1 2 ? * crop-top crop-bottom + 2 * - :> height

        profile-idc profile-compat level-idc sps-id width height frame-mbs-only? <sps-info>
    ] if ;

! Parses an H.264 PPS raw byte sequence payload (RBSP).
:: parse-pps ( rbsp-bytes -- pps/f )
    rbsp-bytes length zero? [ f ] [
        rbsp-bytes <bit-reader> :> reader
        reader read-ue :> pps-id
        reader read-ue :> sps-id
        reader 1 read-bits 1 = :> cabac?
        pps-id sps-id cabac? <pps-info>
    ] if ;
