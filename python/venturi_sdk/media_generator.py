"""
Synthetic Media Stream Generator for MPEG-2 TS and Annex B bitstreams.
Copyright (C) 2026 Aneesh Krishna.
See LICENSE for copyright and license details.
"""

import struct


class SyntheticMediaGenerator:
    """Generates specification-compliant synthetic media bitstreams for testing."""

    @staticmethod
    def generate_h264_sps() -> bytes:
        """Returns a valid 1080p Baseline SPS NAL unit (Annex B format)."""
        return bytes([
            0x00, 0x00, 0x00, 0x01,  # 4-byte start code
            0x67, 0x42, 0xC0, 0x28,  # SPS header, profile 66, level 4.0
            0xD9, 0x00, 0x78, 0x02,
            0x27, 0xE5, 0x84, 0x00,
            0x00, 0x03, 0x00, 0x04,  # Includes emulation prevention byte (0x03)
            0x00, 0x00, 0x03, 0x00,
            0xF0, 0x3C, 0x60, 0xC9, 0x20
        ])

    @staticmethod
    def generate_h264_pps() -> bytes:
        """Returns a valid PPS NAL unit (Annex B format)."""
        return bytes([
            0x00, 0x00, 0x00, 0x01,  # 4-byte start code
            0x68, 0xCE, 0x3C, 0x80
        ])

    @staticmethod
    def generate_h264_idr_slice(frame_num: int = 0) -> bytes:
        """Returns a synthetic IDR slice NAL unit (Annex B format)."""
        prefix = bytes([0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00])
        payload = bytes([(frame_num + i) & 0xFF for i in range(256)])
        return prefix + payload

    @staticmethod
    def generate_h264_non_idr_slice(frame_num: int) -> bytes:
        """Returns a synthetic non-IDR P-slice NAL unit (Annex B format)."""
        prefix = bytes([0x00, 0x00, 0x01, 0x41, 0x9A, 0x00])
        payload = bytes([(frame_num * 3 + i) & 0xFF for i in range(128)])
        return prefix + payload

    @staticmethod
    def generate_aac_adts_frame(frame_num: int, sample_rate_idx: int = 4, channels: int = 2) -> bytes:
        """
        Synthesizes a 7-byte ADTS header followed by raw AAC payload.
        Sample rate index 4 corresponds to 44,100 Hz.
        """
        payload_len = 120
        frame_len = 7 + payload_len

        # ADTS Header (7 bytes)
        # Byte 0: syncword 0xFF
        b0 = 0xFF
        # Byte 1: syncword high (0xF), ID=0 (MPEG-4), layer=00, protection_absent=1
        b1 = 0xF1
        # Byte 2: profile=01 (AAC-LC), sample_rate_idx (4 bits), private=0, channels high bit (1 bit)
        b2 = (0x01 << 6) | ((sample_rate_idx & 0x0F) << 2) | ((channels >> 2) & 0x01)
        # Byte 3: channels low 2 bits, orig=0, home=0, copyright=0, copyright_start=0, frame_len high 2 bits
        b3 = ((channels & 0x03) << 6) | ((frame_len >> 11) & 0x03)
        # Byte 4: frame_len middle 8 bits
        b4 = (frame_len >> 3) & 0xFF
        # Byte 5: frame_len low 3 bits, buffer_fullness high 5 bits (0x7FF = VBR)
        b5 = ((frame_len & 0x07) << 5) | 0x1F
        # Byte 6: buffer_fullness low 6 bits, raw_data_blocks=0
        b6 = 0xFC

        header = bytes([b0, b1, b2, b3, b4, b5, b6])
        payload = bytes([(frame_num + j * 7) & 0xFF for j in range(payload_len)])
        return header + payload

    @classmethod
    def generate_synthetic_mpegts(cls, num_video_frames: int = 60, keyframe_interval: int = 30) -> bytes:
        """
        Synthesizes an MPEG-2 Transport Stream file with PAT, PMT, PCR, Video PES, and Audio PES.
        Contains exactly num_video_frames frames at 30 fps (90 kHz clock increment 3000).
        """
        packets = bytearray()
        cc_pat = 0
        cc_pmt = 0
        cc_video = 0
        cc_audio = 0

        video_pid = 0x0100
        audio_pid = 0x0101
        pmt_pid = 0x1000

        def build_ts_packet(pid: int, payload_unit_start: bool, cc: int, payload: bytes) -> bytes:
            pkt = bytearray(188)
            pkt[0] = 0x47  # Sync byte
            flags1 = (1 if payload_unit_start else 0) << 6
            flags1 |= (pid >> 8) & 0x1F
            pkt[1] = flags1
            pkt[2] = pid & 0xFF
            pkt[3] = 0x10 | (cc & 0x0F)  # Adaptation: payload only (0x10), CC

            # Copy payload up to 184 bytes
            copy_len = min(len(payload), 184)
            pkt[4:4 + copy_len] = payload[:copy_len]
            # Pad remaining bytes with 0xFF
            for k in range(4 + copy_len, 188):
                pkt[k] = 0xFF
            return bytes(pkt)

        def encode_pts(pts: int) -> bytes:
            b0 = 0x21 | (((pts >> 30) & 0x07) << 1)
            p1 = (pts >> 15) & 0x7FFF
            b1 = (p1 >> 7) & 0xFF
            b2 = ((p1 & 0x7F) << 1) | 0x01
            p2 = pts & 0x7FFF
            b3 = (p2 >> 7) & 0xFF
            b4 = ((p2 & 0x7F) << 1) | 0x01
            return bytes([b0, b1, b2, b3, b4])

        def crc32_mpeg2(data: bytes) -> int:
            crc = 0xFFFFFFFF
            for b in data:
                crc ^= (b << 24)
                for _ in range(8):
                    if crc & 0x80000000:
                        crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
                    else:
                        crc = (crc << 1) & 0xFFFFFFFF
            return crc

        # PAT packet (PID 0)
        pat_section = bytes([
            0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00,
            0x00, 0x01, 0xF0, 0x00  # Program 1 -> PMT PID 0x1000
        ])
        pat_crc = struct.pack(">I", crc32_mpeg2(pat_section))
        pat_payload = bytes([0x00]) + pat_section + pat_crc
        packets.extend(build_ts_packet(0, True, cc_pat, pat_payload))
        cc_pat = (cc_pat + 1) & 0x0F

        # PMT packet (PID 0x1000)
        pmt_section = bytes([
            0x02, 0xB0, 0x17, 0x00, 0x01, 0xC1, 0x00, 0x00,
            0xE1, 0x00, 0xF0, 0x00,  # PCR PID 0x0100
            0x1B, 0xE1, 0x00, 0xF0, 0x00,  # Stream 1: H.264 (0x1B), PID 0x0100
            0x0F, 0xE1, 0x01, 0xF0, 0x00   # Stream 2: AAC (0x0F), PID 0x0101
        ])
        pmt_crc = struct.pack(">I", crc32_mpeg2(pmt_section))
        pmt_payload = bytes([0x00]) + pmt_section + pmt_crc
        packets.extend(build_ts_packet(pmt_pid, True, cc_pmt, pmt_payload))
        cc_pmt = (cc_pmt + 1) & 0x0F

        # Video & Audio frames
        for frame_idx in range(num_video_frames):
            pts = frame_idx * 3000
            is_keyframe = (frame_idx % keyframe_interval == 0)

            # Build PES packet for video
            nal_data = bytearray()
            if is_keyframe:
                nal_data.extend(cls.generate_h264_sps())
                nal_data.extend(cls.generate_h264_pps())
                nal_data.extend(cls.generate_h264_idr_slice(frame_idx))
            else:
                nal_data.extend(cls.generate_h264_non_idr_slice(frame_idx))

            pes_header = bytearray([
                0x00, 0x00, 0x01, 0xE0,  # Video stream ID 0xE0
                0x00, 0x00,              # Length (unbounded)
                0x80, 0x80,              # PTS only
                0x05                     # Header data length
            ])
            pes_header.extend(encode_pts(pts))
            video_pes = bytes(pes_header + nal_data)

            # Chunk video PES across TS packets
            v_offset = 0
            while v_offset < len(video_pes):
                is_start = (v_offset == 0)
                chunk = video_pes[v_offset:v_offset + 184]
                packets.extend(build_ts_packet(video_pid, is_start, cc_video, chunk))
                cc_video = (cc_video + 1) & 0x0F
                v_offset += 184

            # Audio frame
            audio_frame = cls.generate_aac_adts_frame(frame_idx)
            audio_pes_hdr = bytearray([
                0x00, 0x00, 0x01, 0xC0,  # Audio stream ID 0xC0
                0x00, 0x00,
                0x80, 0x80,
                0x05
            ])
            audio_pes_hdr.extend(encode_pts(pts))
            audio_pes = bytes(audio_pes_hdr + audio_frame)

            a_offset = 0
            while a_offset < len(audio_pes):
                is_start = (a_offset == 0)
                chunk = audio_pes[a_offset:a_offset + 184]
                packets.extend(build_ts_packet(audio_pid, is_start, cc_audio, chunk))
                cc_audio = (cc_audio + 1) & 0x0F
                a_offset += 184

        return bytes(packets)
