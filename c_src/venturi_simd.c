/*
 * Copyright (C) 2026 Aneesh Krishna.
 * See LICENSE for copyright and license details.
 *
 * venturi_simd.c: SIMD, NEON, and 64-bit SWAR fast-path implementations.
 */

#include "venturi_simd.h"
#include <string.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define VENTURI_HAS_NEON 1
#elif defined(__AVX2__) || defined(__SSE4_2__)
#include <immintrin.h>
#define VENTURI_HAS_X86_SIMD 1
#endif

/*
 * High-speed Annex B start code scanner.
 * Uses 64-bit word zero-byte detection to skip non-zero byte runs quickly.
 */
size_t venturi_scan_annexb(
    const uint8_t *data,
    size_t len,
    size_t *offsets,
    uint8_t *prefix_lens,
    size_t max_offsets
) {
    if (!data || len < 4 || !offsets || !prefix_lens || max_offsets == 0) {
        return 0;
    }

    size_t count = 0;
    size_t i = 0;
    int zero_run = 0;

    /* Fast path for large payloads: check 8 bytes at a time for zeroes */
    const uint64_t mask_01 = 0x0101010101010101ULL;
    const uint64_t mask_80 = 0x8080808080808080ULL;

    while (i + 8 <= len && count < max_offsets) {
        if (zero_run == 0) {
            uint64_t word;
            memcpy(&word, data + i, sizeof(word));
            /* Zero-byte detection formula (Alan Mycroft) */
            uint64_t has_zero = (word - mask_01) & ~word & mask_80;
            if (!has_zero) {
                /* No zero byte in this 8-byte chunk, skip forward safely */
                i += 7; /* Advance 7 to allow 1 overlap for boundary zeroes */
                zero_run = 0;
                continue;
            }
        }

        uint8_t b = data[i];
        if (b == 0x00) {
            zero_run++;
        } else if (b == 0x01) {
            if (zero_run >= 2) {
                uint8_t prefix = (zero_run >= 3) ? 4 : 3;
                offsets[count] = i + 1;
                prefix_lens[count] = prefix;
                count++;
            }
            zero_run = 0;
        } else {
            zero_run = 0;
        }
        i++;
    }

    /* Process remainder scalar tail */
    while (i < len && count < max_offsets) {
        uint8_t b = data[i];
        if (b == 0x00) {
            zero_run++;
        } else if (b == 0x01) {
            if (zero_run >= 2) {
                uint8_t prefix = (zero_run >= 3) ? 4 : 3;
                offsets[count] = i + 1;
                prefix_lens[count] = prefix;
                count++;
            }
            zero_run = 0;
        } else {
            zero_run = 0;
        }
        i++;
    }

    return count;
}

/*
 * Strips emulation prevention bytes (0x000003).
 */
size_t venturi_unescape_emulation_prevention(
    const uint8_t *src,
    size_t src_len,
    uint8_t *dst
) {
    if (!src || !dst || src_len == 0) {
        return 0;
    }

    if (src_len < 3) {
        memcpy(dst, src, src_len);
        return src_len;
    }

    size_t in_idx = 0;
    size_t out_idx = 0;

    while (in_idx < src_len) {
        if (in_idx + 2 < src_len &&
            src[in_idx] == 0x00 &&
            src[in_idx + 1] == 0x00 &&
            src[in_idx + 2] == 0x03) {
            dst[out_idx++] = 0x00;
            dst[out_idx++] = 0x00;
            in_idx += 3; /* Skip the emulation prevention byte (0x03) */
        } else {
            dst[out_idx++] = src[in_idx++];
        }
    }

    return out_idx;
}

/* Precomputed IEEE 802.3 CRC-32 Lookup Table */
static uint32_t crc32_table[256];
static int crc32_table_initialized = 0;

static void init_crc32_table(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xEDB88320U;
            } else {
                crc >>= 1;
            }
        }
        crc32_table[i] = crc;
    }
    crc32_table_initialized = 1;
}

uint32_t venturi_crc32(const uint8_t *data, size_t len) {
    if (!crc32_table_initialized) {
        init_crc32_table();
    }

    uint32_t crc = 0xFFFFFFFFU;
    for (size_t i = 0; i < len; i++) {
        uint8_t table_idx = (uint8_t)((crc ^ data[i]) & 0xFF);
        crc = (crc >> 8) ^ crc32_table[table_idx];
    }
    return crc ^ 0xFFFFFFFFU;
}
