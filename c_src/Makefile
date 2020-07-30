# Copyright (C) 2026 Aneesh Krishna.
# See LICENSE for copyright and license details.
#
# Makefile for C99 SIMD fast-path shared library and benchmark binary.

CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -pedantic -std=c99 -fPIC
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    SHLIB_EXT := dylib
    SHLIB_FLAGS := -dynamiclib
else
    SHLIB_EXT := so
    SHLIB_FLAGS := -shared
endif

TARGET_LIB := libventuri_simd.$(SHLIB_EXT)
TARGET_BENCH := bench_simd

.PHONY: all clean test

all: $(TARGET_LIB) $(TARGET_BENCH)

$(TARGET_LIB): venturi_simd.c venturi_simd.h
	$(CC) $(CFLAGS) $(SHLIB_FLAGS) -o $@ venturi_simd.c

$(TARGET_BENCH): bench_simd.c venturi_simd.c venturi_simd.h
	$(CC) $(CFLAGS) -o $@ bench_simd.c venturi_simd.c

test: $(TARGET_BENCH)
	./$(TARGET_BENCH)

clean:
	rm -f $(TARGET_LIB) $(TARGET_BENCH) *.o
