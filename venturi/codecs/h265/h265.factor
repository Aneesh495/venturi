! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! ITU-T H.265 / ISO/IEC 23008-2 High Efficiency Video Coding (HEVC) parser.
! Two-byte NAL unit headers, parameter set decoders (VPS, SPS, PPS),
! and ISO/IEC 14496-15 hvcC box generation.

USING: accessors arrays byte-arrays byte-vectors kernel locals math
math.bitwise math.order sequences vectors venturi.codecs.h264
venturi.common.bitstream venturi.common.exp-golomb
venturi.common.utils venturi.isobmff.box-writer
venturi.isobmff.constants ;
IN: venturi.codecs.h265

! Canonical HEVC NAL Unit Types
CONSTANT: NAL_HEVC_TRAIL_N    0
CONSTANT: NAL_HEVC_TRAIL_R    1
CONSTANT: NAL_HEVC_TSA_N      2
CONSTANT: NAL_HEVC_TSA_R      3
CONSTANT: NAL_HEVC_STSA_N     4
CONSTANT: NAL_HEVC_STSA_R     5
CONSTANT: NAL_HEVC_RADL_N     6
CONSTANT: NAL_HEVC_RADL_R     7
CONSTANT: NAL_HEVC_RASL_N     8
CONSTANT: NAL_HEVC_RASL_R     9
CONSTANT: NAL_HEVC_IDR_W_RADL 19 ! IDR with RADL
CONSTANT: NAL_HEVC_IDR_N_LP   20 ! IDR without LP
CONSTANT: NAL_HEVC_CRA_NUT    21 ! Clean Random Access
CONSTANT: NAL_HEVC_VPS        32 ! Video Parameter Set
CONSTANT: NAL_HEVC_SPS        33 ! Sequence Parameter Set
CONSTANT: NAL_HEVC_PPS        34 ! Picture Parameter Set
CONSTANT: NAL_HEVC_AUD        35 ! Access Unit Delimiter
CONSTANT: NAL_HEVC_EOS        36 ! End of Sequence
CONSTANT: NAL_HEVC_EOB        37 ! End of Bitstream
CONSTANT: NAL_HEVC_FD_NUT     38 ! Filler Data
CONSTANT: NAL_HEVC_PREFIX_SEI 39 ! Supplemental Enhancement Information

! Unified HEVC NAL unit structure
TUPLE: hevc-nal-unit
    { type integer read-only }
    { layer-id integer read-only }
    { temporal-id integer read-only }
    { data byte-array read-only }
    { rbsp byte-array read-only } ;

: <hevc-nal-unit> ( type layer-id temporal-id data rbsp -- hevc-nal )
    hevc-nal-unit boa ;

! Parses 2-byte HEVC NAL unit header into type, layer ID, and temporal ID.
:: parse-hevc-header ( b0 b1 -- type layer-id temporal-id )
    b0 -1 shift 0x3F bitand :> nal-type
    b0 0x01 bitand 5 shift b1 -3 shift 0x1F bitand bitor :> layer-id
    b1 0x07 bitand 1 - 0 max :> temporal-id
    nal-type layer-id temporal-id ;

! Scans and splits Annex B byte stream into discrete HEVC NAL units.
:: split-hevc-annex-b-nals ( bytes -- nals )
    V{ } clone :> nals
    bytes length :> len
    len 5 < [ nals ] [
        0 :> curr-off!
        [ curr-off len < ] [
            bytes curr-off find-annex-b-start :> ( start-pos prefix-len )
            start-pos [
                start-pos prefix-len + :> payload-start
                bytes payload-start find-annex-b-start :> ( next-start next-len )
                next-start [ next-start ] [ len ] if :> payload-end

                payload-end payload-start > [
                    payload-start payload-end bytes subseq-safe :> nal-data
                    nal-data length 2 >= [
                        nal-data 0 nth nal-data 1 nth parse-hevc-header :> ( n-type n-layer n-temp )
                        2 nal-data length nal-data subseq-safe remove-emulation-prevention :> rbsp
                        n-type n-layer n-temp nal-data rbsp <hevc-nal-unit> nals push
                    ] when
                ] when

                next-start [ next-start curr-off! ] [ len curr-off! ] if
            ] [
                len curr-off!
            ] if
        ] while
        nals
    ] if ;

! Determines if an HEVC NAL unit represents a keyframe (IDR or CRA).
: hevc-keyframe? ( nal -- ? )
    type>> { NAL_HEVC_IDR_W_RADL NAL_HEVC_IDR_N_LP NAL_HEVC_CRA_NUT } member? ;

! Determines if an HEVC NAL unit is a parameter set (VPS, SPS, or PPS).
: hevc-parameter-set? ( nal -- ? )
    type>> { NAL_HEVC_VPS NAL_HEVC_SPS NAL_HEVC_PPS } member? ;

! HEVC SPS metadata representation
TUPLE: hevc-sps-info
    { vps-id integer read-only }
    { sps-id integer read-only }
    { profile-idc integer read-only }
    { level-idc integer read-only }
    { width integer read-only }
    { height integer read-only }
    { bit-depth integer read-only } ;

: <hevc-sps-info> ( vps-id sps-id profile-idc level-idc width height bit-depth -- info )
    hevc-sps-info boa ;

! Parses an HEVC SPS raw byte sequence payload.
:: parse-hevc-sps ( rbsp-bytes -- sps/f )
    rbsp-bytes length 16 < [ f ] [
        rbsp-bytes <bit-reader> :> reader
        reader 4 read-bits :> vps-id
        reader 3 read-bits :> max-sub-layers-minus1
        reader 1 read-bits drop ! temporal_id_nesting_flag

        ! profile_tier_level
        reader 2 read-bits drop ! general_profile_space
        reader 1 read-bits drop ! general_tier_flag
        reader 5 read-bits :> profile-idc
        reader 32 read-bits drop ! general_profile_compatibility_flags
        reader 48 read-bits drop ! general_constraint_indicator_flags
        reader 8 read-bits :> level-idc

        ! Sub-layer profile flags if max_sub_layers_minus1 > 0
        max-sub-layers-minus1 [
            reader 2 read-bits drop
        ] times

        max-sub-layers-minus1 8 < [
            8 max-sub-layers-minus1 - 2 * [ reader 1 read-bits drop ] times
        ] when

        reader read-ue :> sps-id
        reader read-ue :> chroma-format-idc
        chroma-format-idc 3 = [
            reader 1 read-bits drop ! separate_colour_plane_flag
        ] when

        reader read-ue :> pic-width
        reader read-ue :> pic-height

        0 :> conf-left!
        0 :> conf-right!
        0 :> conf-top!
        0 :> conf-bottom!

        reader 1 read-bits 1 = [ ! conformance_window_flag
            reader read-ue conf-left!
            reader read-ue conf-right!
            reader read-ue conf-top!
            reader read-ue conf-bottom!
        ] when

        reader read-ue :> bit-depth-luma-minus8
        reader read-ue drop ! bit_depth_chroma_minus8

        pic-width conf-left conf-right + 2 * - :> width
        pic-height conf-top conf-bottom + 2 * - :> height
        bit-depth-luma-minus8 8 + :> bit-depth

        vps-id sps-id profile-idc level-idc width height bit-depth <hevc-sps-info>
    ] if ;

! Synthesizes an ISO/IEC 14496-15 HEVCDecoderConfigurationRecord (hvcC).
:: build-hvcc-record ( vps-nal-bytes sps-nal-bytes pps-nal-bytes -- hvcc-bytes )
    1024 <byte-vector> :> buf
    sps-nal-bytes length 2 > [
        2 sps-nal-bytes length sps-nal-bytes subseq-safe remove-emulation-prevention parse-hevc-sps
    ] [ f ] if :> sps

    sps [
        sps profile-idc>> :> p-idc
        sps level-idc>> :> l-idc

        buf 1 push-u8          ! configurationVersion = 1
        buf p-idc push-u8      ! general_profile_space(2) | general_tier_flag(1) | profile_idc(5)
        buf 0x60000000 push-be32 ! general_profile_compatibility_flags
        buf 0x0000 push-be16   ! constraint indicator flags high
        buf 0x00000000 push-be32 ! constraint indicator flags low
        buf l-idc push-u8      ! general_level_idc
        buf 0xF000 push-be16   ! min_spatial_segmentation_idc (4 bits reserved 1111)
        buf 0xFC push-u8       ! parallelismType (6 bits reserved 111111 | 00)
        buf 0xFD push-u8       ! chromaFormat (6 bits reserved 111111 | 01 = 4:2:0)
        buf 0xF8 push-u8       ! bitDepthLumaMinus8 (5 bits reserved 11111 | 000 = 8bit)
        buf 0xF8 push-u8       ! bitDepthChromaMinus8
        buf 0 push-be16        ! avgFrameRate = 0
        buf 0x0F push-u8       ! constantFrameRate(2) | numTemporalLayers(3) | temporalIdNested(1) | lengthSizeMinusOne(2) = 0b00001111
        buf 3 push-u8          ! numOfArrays = 3 (VPS, SPS, PPS)

        ! Array 1: VPS (NAL_HEVC_VPS = 32)
        buf 0x80 NAL_HEVC_VPS bitor push-u8 ! array_completeness = 1 | nal_unit_type = 32
        buf 1 push-be16                     ! numNalus = 1
        buf vps-nal-bytes length push-be16
        buf vps-nal-bytes push-bytes

        ! Array 2: SPS (NAL_HEVC_SPS = 33)
        buf 0x80 NAL_HEVC_SPS bitor push-u8 ! array_completeness = 1 | nal_unit_type = 33
        buf 1 push-be16                     ! numNalus = 1
        buf sps-nal-bytes length push-be16
        buf sps-nal-bytes push-bytes

        ! Array 3: PPS (NAL_HEVC_PPS = 34)
        buf 0x80 NAL_HEVC_PPS bitor push-u8 ! array_completeness = 1 | nal_unit_type = 34
        buf 1 push-be16                     ! numNalus = 1
        buf pps-nal-bytes length push-be16
        buf pps-nal-bytes push-bytes
    ] [
        ! Fallback minimal configuration
        buf 1 push-u8
        buf 1 push-u8
        buf 0x60000000 push-be32
        buf 0x0000 push-be16
        buf 0x00000000 push-be32
        buf 93 push-u8
        buf 0xF000 push-be16
        buf 0xFC push-u8
        buf 0xFD push-u8
        buf 0xF8 push-u8
        buf 0xF8 push-u8
        buf 0 push-be16
        buf 0x0F push-u8
        buf 3 push-u8

        buf 0xA0 push-u8
        buf 1 push-be16
        buf vps-nal-bytes length push-be16
        buf vps-nal-bytes push-bytes

        buf 0xA1 push-u8
        buf 1 push-be16
        buf sps-nal-bytes length push-be16
        buf sps-nal-bytes push-bytes

        buf 0xA2 push-u8
        buf 1 push-be16
        buf pps-nal-bytes length push-be16
        buf pps-nal-bytes push-bytes
    ] if
    buf >byte-array ;

! Wraps an HEVCDecoderConfigurationRecord inside an hvcC ISOBMFF box.
:: build-hvcc-box ( vps-nal-bytes sps-nal-bytes pps-nal-bytes -- box-bytes )
    vps-nal-bytes sps-nal-bytes pps-nal-bytes build-hvcc-record :> rec
    FOURCC_HVCC rec serialize-box ;

! Converts an HEVC Annex B byte buffer into 4-byte length-prefixed HEV1 sample format.
:: annex-b>hev1-sample ( annex-b-bytes -- hev1-bytes )
    annex-b-bytes split-hevc-annex-b-nals :> nals
    annex-b-bytes length 16 + <byte-vector> :> buf
    nals [
        :> n
        n type>> NAL_HEVC_AUD = not [
            buf n data>> length push-be32
            buf n data>> push-bytes
        ] when
    ] each
    buf >byte-array ;
