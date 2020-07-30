/*
 * Copyright (C) 2026 Aneesh Krishna.
 * See LICENSE for copyright and license details.
 *
 * bench_simd.c: Verification suite and microbenchmark for C99 SIMD fast-path.
 */

#include "venturi_simd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double get_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

int main(void) {
    printf("================================================================================\n");
    printf("                  VENTURI C99 SIMD / SWAR ACCELERATION TEST                     \n");
    printf("================================================================================\n");

    /* 1. Unit Verification of Annex B start code scanner */
    const uint8_t test_stream[] = {
        0x00, 0x00, 0x01, 0x67, 0x42, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x68, 0xCE,
        0x00, 0x00, 0x01, 0x65, 0x88, 0x84
    };
    size_t offsets[16];
    uint8_t prefix_lens[16];

    size_t found = venturi_scan_annexb(test_stream, sizeof(test_stream), offsets, prefix_lens, 16);
    if (found != 3) {
        fprintf(stderr, "[FAIL] Expected 3 NAL units, found %zu\n", found);
        return 1;
    }
    if (prefix_lens[0] != 3 || offsets[0] != 3 ||
        prefix_lens[1] != 4 || offsets[1] != 10 ||
        prefix_lens[2] != 3 || offsets[2] != 15) {
        fprintf(stderr, "[FAIL] Unexpected offset or prefix length\n");
        return 1;
    }
    printf("[PASS] Annex B NAL start code scanner verification: 3/3 matched\n");

    /* 2. Unit Verification of Emulation Prevention unescaping */
    const uint8_t escaped[] = { 0x67, 0x00, 0x00, 0x03, 0x01, 0x42, 0x00, 0x00, 0x03, 0x02 };
    uint8_t unescaped[32];
    size_t unescaped_len = venturi_unescape_emulation_prevention(escaped, sizeof(escaped), unescaped);
    if (unescaped_len != 8) {
        fprintf(stderr, "[FAIL] Expected unescaped length 8, got %zu\n", unescaped_len);
        return 1;
    }
    if (unescaped[3] != 0x01 || unescaped[7] != 0x02) {
        fprintf(stderr, "[FAIL] Unescaped byte mismatch\n");
        return 1;
    }
    printf("[PASS] Emulation prevention unescaping verification: clean\n");

    /* 3. Unit Verification of CRC32 */
    const char *crc_text = "123456789";
    uint32_t expected_crc = 0xCBF43926U;
    uint32_t actual_crc = venturi_crc32((const uint8_t*)crc_text, 9);
    if (actual_crc != expected_crc) {
        fprintf(stderr, "[FAIL] CRC32 expected 0x%08X, got 0x%08X\n", expected_crc, actual_crc);
        return 1;
    }
    printf("[PASS] IEEE 802.3 CRC-32 verification: 0x%08X\n", actual_crc);

    /* 4. High-Throughput Stress Benchmark (50 MB buffer) */
    size_t bench_size = 50 * 1024 * 1024;
    uint8_t *bench_buf = (uint8_t*)malloc(bench_size);
    if (!bench_buf) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }
    memset(bench_buf, 0xAA, bench_size);

    /* Interleave start codes every 1024 bytes */
    for (size_t pos = 0; pos + 4 < bench_size; pos += 1024) {
        bench_buf[pos] = 0x00;
        bench_buf[pos + 1] = 0x00;
        bench_buf[pos + 2] = 0x00;
        bench_buf[pos + 3] = 0x01;
    }

    size_t *bench_offsets = (size_t*)malloc(sizeof(size_t) * 100000);
    uint8_t *bench_prefixes = (uint8_t*)malloc(100000);

    double t0 = get_time_sec();
    size_t bench_found = venturi_scan_annexb(bench_buf, bench_size, bench_offsets, bench_prefixes, 100000);
    double t1 = get_time_sec();

    double elapsed = t1 - t0;
    double throughput_mb = (double)bench_size / (1024.0 * 1024.0) / elapsed;

    printf("\nThroughput Benchmark on 50 MB Payload:\n");
    printf("  NAL Units Scanned:  %zu\n", bench_found);
    printf("  Scan Latency:       %.2f ms\n", elapsed * 1000.0);
    printf("  Scan Throughput:    %.2f MB/sec (%.2f GB/sec)\n", throughput_mb, throughput_mb / 1024.0);
    printf("================================================================================\n");

    free(bench_buf);
    free(bench_offsets);
    free(bench_prefixes);
    return 0;
}
