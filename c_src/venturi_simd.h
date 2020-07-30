/*
 * Copyright (C) 2026 Aneesh Krishna.
 * See LICENSE for copyright and license details.
 *
 * venturi_simd.h: High-throughput SIMD and SWAR accelerated primitives
 * for Annex B start-code scanning, emulation prevention unescaping, and CRC32.
 */

#ifndef VENTURI_SIMD_H
#define VENTURI_SIMD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Scans a raw byte buffer for H.264/H.265 Annex B start codes (0x000001 and 0x00000001).
 * Populates offsets array with the start byte index of each NAL unit (excluding prefix),
 * and prefix_lens array with the prefix length (3 or 4).
 * Returns the total number of NAL units found, up to max_offsets.
 */
size_t venturi_scan_annexb(
    const uint8_t *data,
    size_t len,
    size_t *offsets,
    uint8_t *prefix_lens,
    size_t max_offsets
);

/*
 * Strips emulation prevention bytes (0x000003 -> 0x0000) from an Annex B NAL unit.
 * Writes output RBSP bytes to dst (dst buffer must be at least src_len bytes).
 * Returns the total number of unescaped bytes written to dst.
 */
size_t venturi_unescape_emulation_prevention(
    const uint8_t *src,
    size_t src_len,
    uint8_t *dst
);

/*
 * Computes IEEE 802.3 CRC-32 using slice-by-8 parallel table lookups.
 * Fully compatible with standard MPEG-2 PSI and ISOBMFF CRC32.
 */
uint32_t venturi_crc32(
    const uint8_t *data,
    size_t len
);

#ifdef __cplusplus
}
#endif

#endif /* VENTURI_SIMD_H */
