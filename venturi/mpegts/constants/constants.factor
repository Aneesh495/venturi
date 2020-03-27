! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Canonical ISO/IEC 13818-1 MPEG-2 Transport Stream packet constants,
! PID reservations, stream type identifiers, and PES stream IDs.

USING: kernel math ;
IN: venturi.mpegts.constants

CONSTANT: TS_PACKET_SIZE 188
CONSTANT: TS_SYNC_BYTE   0x47

! Reserved Transport Stream Packet Identifiers (PIDs)
CONSTANT: PID_PAT  0x0000  ! Program Association Table
CONSTANT: PID_CAT  0x0001  ! Conditional Access Table
CONSTANT: PID_TSDT 0x0002  ! Transport Stream Description Table
CONSTANT: PID_NULL 0x1FFF  ! Null Packet Padding

! Elementary Stream Types (ISO/IEC 13818-1 and ITU-T specifications)
CONSTANT: STREAM_TYPE_MPEG1_VIDEO 0x01
CONSTANT: STREAM_TYPE_MPEG2_VIDEO 0x02
CONSTANT: STREAM_TYPE_MPEG1_AUDIO 0x03
CONSTANT: STREAM_TYPE_MPEG2_AUDIO 0x04
CONSTANT: STREAM_TYPE_AAC_ADTS    0x0F  ! AAC audio with ADTS framing
CONSTANT: STREAM_TYPE_H264        0x1B  ! AVC / H.264 video
CONSTANT: STREAM_TYPE_H265        0x24  ! HEVC / H.265 video
CONSTANT: STREAM_TYPE_AC3         0x81  ! Dolby Digital AC-3 audio

! Program Specific Information (PSI) Table Identifiers
CONSTANT: TABLE_ID_PAT 0x00
CONSTANT: TABLE_ID_PMT 0x02

! Packetized Elementary Stream (PES) Stream ID ranges
CONSTANT: STREAM_ID_PROGRAM_STREAM_MAP 0xBC
CONSTANT: STREAM_ID_PRIVATE_STREAM_1   0xBD
CONSTANT: STREAM_ID_PADDING_STREAM     0xBE
CONSTANT: STREAM_ID_PRIVATE_STREAM_2   0xBF
CONSTANT: STREAM_ID_AUDIO_BASE         0xC0  ! 0xC0 .. 0xDF
CONSTANT: STREAM_ID_VIDEO_BASE         0xE0  ! 0xE0 .. 0xEF

! Adaptation Field Control flags (bits 5-4 of byte 3)
CONSTANT: ADAPTATION_PAYLOAD_ONLY 1  ! 0b01
CONSTANT: ADAPTATION_FIELD_ONLY   2  ! 0b10
CONSTANT: ADAPTATION_BOTH         3  ! 0b11
