#!/usr/bin/env python3
"""
Venturi Python Test Runner & End-to-End Transmuxing Verification Suite.
Copyright (C) 2026 Aneesh Krishna.
See LICENSE for copyright and license details.
"""

import os
import shutil
import subprocess
import sys
from venturi_sdk import SyntheticMediaGenerator, IsobmffValidator, MpegTsValidator


def run_synthetic_generator_tests():
    print("Testing Synthetic Media Generator & MPEG-TS Stream Creation...")
    sps = SyntheticMediaGenerator.generate_h264_sps()
    assert len(sps) > 10, "SPS length must be > 10 bytes"
    assert sps[:4] == bytes([0, 0, 0, 1]), "SPS must start with 4-byte Annex B prefix"

    pps = SyntheticMediaGenerator.generate_h264_pps()
    assert len(pps) == 8, f"PPS length expected 8, got {len(pps)}"

    aac = SyntheticMediaGenerator.generate_aac_adts_frame(0)
    assert len(aac) == 127, f"ADTS frame expected 127, got {len(aac)}"
    assert aac[0] == 0xFF and (aac[1] & 0xF0) == 0xF0, "ADTS syncword must be 0xFFF"

    ts_data = SyntheticMediaGenerator.generate_synthetic_mpegts(num_video_frames=60, keyframe_interval=30)
    assert len(ts_data) > 0, "MPEG-TS data must not be empty"
    assert len(ts_data) % 188 == 0, "MPEG-TS data must be multiple of 188"

    ts_info = MpegTsValidator.validate_stream(ts_data)
    assert ts_info["has_pat"], "Stream must contain PAT"
    assert len(ts_info["unique_pids"]) >= 3, "Stream must contain PAT, PMT, and video/audio PIDs"
    print(f"  [PASS] Synthesized MPEG-TS stream: {ts_info['packet_count']} packets, PIDs {ts_info['unique_pids']}")


def run_isobmff_validator_tests():
    print("Testing ISOBMFF Box Parsing and Structure Validator...")
    # Synthetic minimal init segment: ftyp (16 bytes) + moov (minimal container)
    ftyp = bytes([
        0x00, 0x00, 0x00, 0x10,
        0x66, 0x74, 0x79, 0x70,  # "ftyp"
        0x63, 0x6D, 0x61, 0x66,  # "cmaf"
        0x00, 0x00, 0x00, 0x01
    ])
    mvhd = bytes([0x00, 0x00, 0x00, 0x18, 0x6D, 0x76, 0x68, 0x64] + [0] * 16)
    mvex = bytes([0x00, 0x00, 0x00, 0x08, 0x6D, 0x76, 0x65, 0x78])
    trak = bytes([0x00, 0x00, 0x00, 0x08, 0x74, 0x72, 0x61, 0x6B])
    moov_payload = mvhd + mvex + trak
    moov = bytes([0x00, 0x00, 0x00, 8 + len(moov_payload), 0x6D, 0x6F, 0x6F, 0x76]) + moov_payload

    init_bytes = ftyp + moov
    res = IsobmffValidator.validate_init_segment(init_bytes)
    assert res["has_mvhd"] and res["has_mvex"] and res["track_count"] == 1
    print("  [PASS] ISOBMFF Track Initialization Segment (init.mp4) validation passed")

    # Synthetic media fragment: styp + moof (with mfhd, traf, tfhd) + mdat
    styp = bytes([0x00, 0x00, 0x00, 0x10, 0x73, 0x74, 0x79, 0x70, 0x63, 0x6D, 0x66, 0x32, 0, 0, 0, 1])
    mfhd = bytes([0x00, 0x00, 0x00, 0x10, 0x6D, 0x66, 0x68, 0x64, 0, 0, 0, 0, 0, 0, 0, 1])
    tfhd = bytes([0x00, 0x00, 0x00, 0x10, 0x74, 0x66, 0x68, 0x64, 0, 0, 0, 0, 0, 0, 0, 1])
    traf = bytes([0x00, 0x00, 0x00, 8 + len(tfhd), 0x74, 0x72, 0x61, 0x66]) + tfhd
    moof_payload = mfhd + traf
    moof = bytes([0x00, 0x00, 0x00, 8 + len(moof_payload), 0x6D, 0x6F, 0x6F, 0x66]) + moof_payload
    mdat_payload = bytes([0xDE, 0xAD, 0xBE, 0xEF])
    mdat = bytes([0x00, 0x00, 0x00, 8 + len(mdat_payload), 0x6D, 0x64, 0x61, 0x74]) + mdat_payload

    frag_bytes = styp + moof + mdat
    frag_res = IsobmffValidator.validate_media_segment(frag_bytes)
    assert frag_res["has_styp"] and frag_res["has_moof"] and frag_res["has_mdat"]
    assert frag_res["mdat_payload_size"] == 4
    print("  [PASS] CMAF Media Fragment Segment (.m4s) validation passed")


def run_end_to_end_transmux_verification():
    print("\nRunning End-to-End Transmuxing Verification with Factor Engine...")
    test_dir = "/tmp/venturi_test_env"
    if os.path.exists(test_dir):
        shutil.rmtree(test_dir)
    os.makedirs(test_dir, exist_ok=True)

    input_ts = os.path.join(test_dir, "stream.ts")
    output_dir = os.path.join(test_dir, "packaged")

    print(f"  * Synthesizing broadcast-compliant MPEG-TS stream (60 frames, 2.0s)...")
    ts_bytes = SyntheticMediaGenerator.generate_synthetic_mpegts(num_video_frames=60, keyframe_interval=30)
    with open(input_ts, "wb") as f:
        f.write(ts_bytes)
    print(f"  * Wrote {len(ts_bytes)} bytes to {input_ts}")

    # Invoke Factor packager CLI
    factor_bin = "/Applications/factor/factor"
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    cmd = [
        factor_bin,
        f"-roots={repo_root}",
        "-run=venturi",
        "package",
        input_ts,
        output_dir,
        "1.0"
    ]

    print(f"  * Invoking Factor engine: {' '.join(cmd)}")
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=repo_root)
    if proc.returncode != 0:
        print(f"Factor stderr:\n{proc.stderr}")
        print(f"Factor stdout:\n{proc.stdout}")
        raise RuntimeError(f"Factor packaging command failed with code {proc.returncode}")

    print(f"  * Factor execution succeeded. Output summary:\n{proc.stdout}")

    # Verify generated assets on disk
    expected_files = ["init.mp4", "master.m3u8", "stream.m3u8", "manifest.mpd"]
    for fname in expected_files:
        fpath = os.path.join(output_dir, fname)
        assert os.path.exists(fpath), f"Expected asset missing: {fname}"
        assert os.path.getsize(fpath) > 0, f"Asset is empty: {fname}"
        print(f"  [PASS] Verified asset exists: {fname} ({os.path.getsize(fpath)} bytes)")

    # Validate init.mp4 box structure
    with open(os.path.join(output_dir, "init.mp4"), "rb") as f:
        init_data = f.read()
    init_res = IsobmffValidator.validate_init_segment(init_data)
    print(f"  [PASS] init.mp4 box structure validated: {init_res}")

    # Validate media fragments (.m4s)
    m4s_files = [f for f in os.listdir(output_dir) if f.endswith(".m4s")]
    assert len(m4s_files) >= 1, f"Expected at least 1 .m4s fragment, found {len(m4s_files)}"
    for m4s in sorted(m4s_files):
        fpath = os.path.join(output_dir, m4s)
        with open(fpath, "rb") as f:
            seg_data = f.read()
        seg_res = IsobmffValidator.validate_media_segment(seg_data)
        print(f"  [PASS] Verified fragment {m4s}: decode_time={seg_res['decode_time']}, mdat_bytes={seg_res['mdat_payload_size']}")

    print("\n=======================================================")
    print("ALL PYTHON SDK AND BITSTREAM VALIDATION TESTS PASSED")
    print("=======================================================")


if __name__ == "__main__":
    run_synthetic_generator_tests()
    run_isobmff_validator_tests()
    run_end_to_end_transmux_verification()
