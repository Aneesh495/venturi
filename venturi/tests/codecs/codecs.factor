! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Unit test suite for H.264, H.265 / HEVC, AAC ADTS, and ID3v2 bitstream parsers,
! parameter set decoders, and container configuration record builders.

USING: accessors arrays byte-arrays byte-vectors io kernel locals
math sequences strings venturi.codecs.aac venturi.codecs.h264
venturi.codecs.h265 venturi.codecs.id3 venturi.common.bitstream
venturi.common.utils venturi.isobmff.constants venturi.tests.harness ;
IN: venturi.tests.codecs

:: test-h264-scanner-and-emulation ( -- )
    "Testing H.264 Scanner and Emulation Prevention..." print

    ! Emulation prevention removal
    B{ 0x00 0x00 0x03 0x01 0x00 0x00 0x03 0x02 0x05 } :> ep-bytes
    ep-bytes remove-emulation-prevention :> rbsp
    rbsp B{ 0x00 0x00 0x01 0x00 0x00 0x02 0x05 } "emulation prevention bytes stripped" test=

    ! Annex B start code detection
    B{ 0xFF 0x00 0x00 0x01 0x67 0x42 0x00 0x00 0x00 0x01 0x68 } :> stream-bytes
    stream-bytes 0 find-annex-b-start :> ( s1 l1 )
    s1 1 "first start code offset is 1" test=
    l1 3 "first prefix length is 3" test=

    stream-bytes 4 find-annex-b-start :> ( s2 l2 )
    s2 6 "second start code offset is 6" test=
    l2 4 "second prefix length is 4" test=

    ! Split Annex B NALs
    stream-bytes split-annex-b-nals :> nals
    nals length 2 "split into 2 NAL units" test=
    0 nals nth type>> NAL_SPS "NAL 0 is SPS (type 7)" test=
    1 nals nth type>> NAL_PPS "NAL 1 is PPS (type 8)" test=
    0 nals nth parameter-set-nal? "NAL 0 is parameter set" test-true
    0 nals nth keyframe-nal? "NAL 0 is not keyframe" test-false ;

:: test-h264-sps-pps-avcc ( -- )
    "Testing H.264 SPS, PPS, and avcC Builder..." print

    ! 1280x720 Baseline SPS
    B{ 66 224 31 244 2 128 45 208 } :> sps-bytes
    sps-bytes parse-sps :> sps
    sps f = not "parsed SPS is non-f" test-true
    sps width>> 1280 "SPS width is 1280" test=
    sps height>> 720 "SPS height is 720" test=
    sps profile-idc>> 66 "SPS profile is 66 (Baseline)" test=
    sps level-idc>> 31 "SPS level is 31" test=

    ! PPS test vector
    B{ 208 } :> pps-bytes
    pps-bytes parse-pps :> pps
    pps f = not "parsed PPS is non-f" test-true
    pps pps-id>> 0 "PPS ID is 0" test=
    pps sps-id>> 0 "PPS SPS ID is 0" test=

    ! Build and parse avcC record
    sps-bytes pps-bytes build-avcc-record :> avcc-rec
    0 avcc-rec nth 1 "avcC configurationVersion is 1" test=
    1 avcc-rec nth 66 "avcC profile indication is 66" test=
    3 avcc-rec nth 31 "avcC level indication is 31" test=

    avcc-rec parse-avcc-record :> ( recovered-sps recovered-pps )
    recovered-sps length 1 "recovered 1 SPS from avcC" test=
    recovered-pps length 1 "recovered 1 PPS from avcC" test=
    0 recovered-sps nth sps-bytes "recovered SPS matches original" test=
    0 recovered-pps nth pps-bytes "recovered PPS matches original" test=

    ! Annex B to AVC1 length-prefixed conversion
    B{ 0x00 0x00 0x00 0x01 0x65 0xAA 0xBB 0xCC } :> idr-annex-b
    idr-annex-b annex-b>avc1-sample :> avc1-sample
    avc1-sample length 8 "AVC1 sample length is 8 (4 len + 4 data)" test=
    avc1-sample 0 read-be32 4 "AVC1 sample length prefix is 4" test= ;

:: test-hevc-codecs ( -- )
    "Testing H.265 / HEVC NALs, SPS, and hvcC..." print

    ! 2-byte HEVC NAL header parsing
    ! IDR slice (type 19): 19 << 1 = 38 (0x26), layer 0, temp 1 (temp_id_plus1 = 2) -> 0x26 0x02
    0x26 0x02 parse-hevc-header :> ( idr-t idr-l idr-temp )
    idr-t NAL_HEVC_IDR_W_RADL "HEVC IDR type is 19" test=
    idr-l 0 "layer ID is 0" test=
    idr-temp 1 "temporal ID is 1" test=

    ! 1920x1080 Main Profile HEVC SPS
    B{ 1 1 96 0 0 0 0 0 0 0 0 0 93 160 3 192 128 16 229 192 } :> hevc-sps-bytes
    hevc-sps-bytes parse-hevc-sps :> h-sps
    h-sps f = not "parsed HEVC SPS is non-f" test-true
    h-sps width>> 1920 "HEVC SPS width is 1920" test=
    h-sps height>> 1080 "HEVC SPS height is 1080" test=
    h-sps bit-depth>> 8 "HEVC SPS bit depth is 8" test=
    h-sps level-idc>> 93 "HEVC SPS level IDC is 93" test=

    ! HEVC parameter set and keyframe detection
    B{ 0x00 0x00 0x00 0x01 0x26 0x01 0xFF } :> hevc-idr-annex-b
    hevc-idr-annex-b split-hevc-annex-b-nals :> h-nals
    h-nals length 1 "split 1 HEVC NAL" test=
    0 h-nals nth hevc-keyframe? "HEVC NAL is keyframe" test-true
    0 h-nals nth hevc-parameter-set? "HEVC NAL is not parameter set" test-false

    ! hvcC box authoring
    B{ 0x40 0x01 0x0C 0x01 } :> dummy-vps
    B{ 0x42 0x01 0x01 } :> dummy-sps
    B{ 0x44 0x01 } :> dummy-pps
    dummy-vps dummy-sps dummy-pps build-hvcc-box :> hvcc-box
    hvcc-box 4 read-be32 FOURCC_HVCC "hvcc box type is FOURCC_HVCC" test= ;

:: test-aac-adts-and-asc ( -- )
    "Testing AAC ADTS and AudioSpecificConfig..." print

    ! Sample rate lookup
    48000 sample-rate>index 3 "48000 Hz maps to index 3" test=
    44100 sample-rate>index 4 "44100 Hz maps to index 4" test=
    3 index>sample-rate 48000 "index 3 maps to 48000 Hz" test=
    4 index>sample-rate 44100 "index 4 maps to 44100 Hz" test=

    ! AudioSpecificConfig roundtrip
    2 48000 2 build-audio-specific-config :> asc-48k
    asc-48k length 2 "ASC length is 2 bytes" test=
    asc-48k parse-audio-specific-config :> ( aot-rec sr-rec chan-rec )
    aot-rec 2 "recovered AOT is 2 (AAC-LC)" test=
    sr-rec 48000 "recovered sample rate is 48000" test=
    chan-rec 2 "recovered channel count is 2 (stereo)" test=

    ! Synthetic ADTS frame parsing
    ! syncword = 0xFFF, mpeg-4 (ID=0), layer=0, protection_absent=1
    ! profile = 1 (AAC-LC -> stored as 1, profile_ObjectType=1), sr_idx = 3 (48kHz), channels = 2
    ! frame_length = 7 (header) + 4 (payload) = 11 (0x00B)
    ! Byte 0: 0xFF
    ! Byte 1: 0xF1 (0xFF0 | 0b0001)
    ! Byte 2: 0x4C (0b01001100 -> profile=1, sr=3, ch_hi=0)
    ! Byte 3: 0x80 (0b10000000 -> ch_lo=2, fl_hi=0)
    ! Byte 4: 0x16 (fl = 11 -> (11 >> 3) & 0xFF = 1? wait: 11 = 0x00B = 0000 0000 01011. fl << 5 = 0x160 -> b4 = 0x01, b5 = 0x60)
    ! Let's build ADTS frame using bit-writer to be 100% compliant
    <bit-writer> :> w
    w 0xFFF 12 write-bits
    w 0 1 write-bits   ! ID = 0 (MPEG-4)
    w 0 2 write-bits   ! layer = 0
    w 1 1 write-bits   ! protection_absent = 1
    w 1 2 write-bits   ! profile = 1 (LC)
    w 3 4 write-bits   ! sr_idx = 3 (48kHz)
    w 0 1 write-bits   ! private = 0
    w 2 3 write-bits   ! channels = 2
    w 0 1 write-bits   ! orig = 0
    w 0 1 write-bits   ! home = 0
    w 0 1 write-bits   ! copyright = 0
    w 0 1 write-bits   ! copyright_start = 0
    w 11 13 write-bits ! frame_length = 11
    w 0x7FF 11 write-bits ! fullness
    w 0 2 write-bits   ! num_blocks = 0
    w writer-bytes :> adts-hdr
    B{ 0xDE 0xAD 0xBE 0xEF } :> raw-audio
    adts-hdr raw-audio append :> complete-adts

    complete-adts 0 parse-adts-frame :> parsed-adts
    parsed-adts f = not "parsed ADTS is non-f" test-true
    parsed-adts profile>> 2 "ADTS profile is 2 (AAC-LC)" test=
    parsed-adts sample-rate>> 48000 "ADTS sample rate is 48000" test=
    parsed-adts channels>> 2 "ADTS channels is 2" test=
    parsed-adts frame-length>> 11 "ADTS frame length is 11" test=
    parsed-adts payload>> raw-audio "ADTS extracted payload matches" test=

    ! esds box
    asc-48k build-esds-box :> esds-box
    esds-box 4 read-be32 FOURCC_ESDS "esds box type is FOURCC_ESDS" test= ;

:: test-id3-metadata ( -- )
    "Testing ID3v2 Metadata Tagging..." print

    ! Synchsafe integer encoding/decoding
    1234567 encode-synchsafe :> ss-bytes
    ss-bytes 0 decode-synchsafe 1234567 "synchsafe integer roundtrip" test=

    ! TXXX frame creation
    "program_date_time" "2026-11-14T12:00:00Z" build-id3-txxx-frame :> txxx-bytes
    0 4 txxx-bytes subseq-safe >string "TXXX" "txxx frame ID is TXXX" test=

    ! Apple HLS PRIV timestamp tag
    8541000 build-hls-timestamp-id3 :> id3-tag
    0 3 id3-tag subseq-safe >string "ID3" "id3 identifier is ID3" test=
    3 id3-tag nth 4 "id3 major version is 4" test=

    ! Parse ID3 tag
    id3-tag parse-id3v2-tag :> frames
    frames length 1 "parsed 1 ID3 frame" test=
    0 frames nth id>> "PRIV" "frame ID is PRIV" test= ;

:: run-all-codecs-tests ( -- ? )
    init-test-harness
    test-h264-scanner-and-emulation
    test-h264-sps-pps-avcc
    test-hevc-codecs
    test-aac-adts-and-asc
    test-id3-metadata
    "Codecs & Bitstream Test Suite" print-test-summary ;
