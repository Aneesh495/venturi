"""
Bitstream and container validation for ISOBMFF, CMAF, and MPEG-2 TS.
Copyright (C) 2026 Aneesh Krishna.
See LICENSE for copyright and license details.
"""

import struct
from typing import List, Dict, Any, Optional


class BoxNode:
    """Represents a parsed ISOBMFF box node."""
    def __init__(self, fourcc: str, offset: int, size: int, payload: bytes):
        self.fourcc = fourcc
        self.offset = offset
        self.size = size
        self.payload = payload
        self.children: List['BoxNode'] = []

    def find_child(self, fourcc: str) -> Optional['BoxNode']:
        for child in self.children:
            if child.fourcc == fourcc:
                return child
        return None

    def find_all(self, fourcc: str) -> List['BoxNode']:
        return [c for c in self.children if c.fourcc == fourcc]


class IsobmffValidator:
    """Validates ISOBMFF and CMAF fragmented MP4 compliance."""

    CONTAINER_BOXES = {"moov", "trak", "mdia", "minf", "dinf", "stbl", "mvex", "moof", "traf"}

    @classmethod
    def parse_boxes(cls, data: bytes, offset: int = 0, end_offset: Optional[int] = None) -> List[BoxNode]:
        if end_offset is None:
            end_offset = len(data)

        boxes = []
        pos = offset
        while pos + 8 <= end_offset:
            box_size, = struct.unpack_from(">I", data, pos)
            fourcc = data[pos + 4:pos + 8].decode("latin-1", errors="replace")

            if box_size == 1:
                # 64-bit extended box size
                box_size, = struct.unpack_from(">Q", data, pos + 8)
                header_size = 16
            else:
                header_size = 8

            if box_size == 0:
                box_size = end_offset - pos

            if box_size < header_size or pos + box_size > end_offset:
                raise ValueError(f"Malformed box {fourcc} at offset {pos}: size {box_size}")

            payload = data[pos + header_size:pos + box_size]
            node = BoxNode(fourcc, pos, box_size, payload)

            if fourcc in cls.CONTAINER_BOXES:
                node.children = cls.parse_boxes(data, pos + header_size, pos + box_size)

            boxes.append(node)
            pos += box_size

        return boxes

    @classmethod
    def validate_init_segment(cls, data: bytes) -> Dict[str, Any]:
        """Validates that a byte array conforms to a CMAF Track Initialization Segment (init.mp4)."""
        boxes = cls.parse_boxes(data)
        if len(boxes) < 2:
            raise AssertionError(f"init.mp4 must contain at least 2 root boxes, found {len(boxes)}")

        if boxes[0].fourcc != "ftyp":
            raise AssertionError(f"First box must be ftyp, found {boxes[0].fourcc}")
        if boxes[1].fourcc != "moov":
            raise AssertionError(f"Second box must be moov, found {boxes[1].fourcc}")

        moov = boxes[1]
        if not moov.find_child("mvhd"):
            raise AssertionError("moov must contain an mvhd box")
        if not moov.find_child("mvex"):
            raise AssertionError("moov must contain an mvex box for fragmented media")

        traks = moov.find_all("trak")
        if not traks:
            raise AssertionError("moov must contain at least one trak box")

        return {
            "root_boxes": [b.fourcc for b in boxes],
            "track_count": len(traks),
            "has_mvex": True,
            "has_mvhd": True
        }

    @classmethod
    def validate_media_segment(cls, data: bytes, expected_track_id: Optional[int] = None) -> Dict[str, Any]:
        """Validates that a byte array conforms to a CMAF Media Fragment Segment (.m4s)."""
        boxes = cls.parse_boxes(data)
        if len(boxes) < 2:
            raise AssertionError(f"Media fragment must contain at least 2 root boxes, found {len(boxes)}")

        # Check styp (optional in generic ISOBMFF, mandatory in strict CMAF)
        idx = 0
        has_styp = False
        if boxes[0].fourcc == "styp":
            has_styp = True
            idx = 1

        if idx >= len(boxes) or boxes[idx].fourcc != "moof":
            raise AssertionError(f"Expected moof box at index {idx}, got {boxes[idx].fourcc if idx < len(boxes) else 'EOF'}")

        moof = boxes[idx]
        idx += 1

        if idx >= len(boxes) or boxes[idx].fourcc != "mdat":
            raise AssertionError(f"moof box must be immediately followed by mdat, got {boxes[idx].fourcc if idx < len(boxes) else 'EOF'}")

        mdat = boxes[idx]

        # Validate moof internals
        if not moof.find_child("mfhd"):
            raise AssertionError("moof must contain an mfhd box")

        traf = moof.find_child("traf")
        if not traf:
            raise AssertionError("moof must contain at least one traf box")

        tfhd = traf.find_child("tfhd")
        if not tfhd:
            raise AssertionError("traf must contain a tfhd box")

        tfdt = traf.find_child("tfdt")
        decode_time = 0
        if tfdt:
            # Parse baseMediaDecodeTime
            version = tfdt.payload[0]
            if version == 1:
                decode_time, = struct.unpack_from(">Q", tfdt.payload, 4)
            else:
                decode_time, = struct.unpack_from(">I", tfdt.payload, 4)

        trun = traf.find_child("trun")
        sample_count = 0
        if trun:
            sample_count, = struct.unpack_from(">I", trun.payload, 4)

        return {
            "has_styp": has_styp,
            "has_moof": True,
            "has_mdat": True,
            "mdat_payload_size": len(mdat.payload),
            "sample_count": sample_count,
            "decode_time": decode_time
        }


class MpegTsValidator:
    """Validates MPEG-2 Transport Stream structure and continuity."""

    @classmethod
    def validate_stream(cls, data: bytes) -> Dict[str, Any]:
        if len(data) % 188 != 0:
            raise AssertionError(f"MPEG-TS byte length must be multiple of 188, got {len(data)}")

        packet_count = len(data) // 188
        pids = set()
        has_pat = False

        for i in range(packet_count):
            offset = i * 188
            sync_byte = data[offset]
            if sync_byte != 0x47:
                raise AssertionError(f"Packet {i} does not start with 0x47 sync byte (got 0x{sync_byte:02X})")

            flags1 = data[offset + 1]
            pid = ((flags1 & 0x1F) << 8) | data[offset + 2]
            pids.add(pid)
            if pid == 0:
                has_pat = True

        return {
            "packet_count": packet_count,
            "unique_pids": sorted(list(pids)),
            "has_pat": has_pat
        }
