# Copyright (C) 2026 Aneesh Krishna.
# See LICENSE for copyright and license details.
#
# Top-level Makefile for Venturi.

FACTOR ?= /Applications/factor/factor
PYTHON ?= python3

.PHONY: all test bench simd python-test verify clean

all: simd

simd:
	$(MAKE) -C c_src all

test: simd
	$(FACTOR) -roots=. -run=venturi test

bench: simd
	$(FACTOR) -roots=. -run=venturi benchmark

python-test: simd
	$(PYTHON) python/test_venturi.py

verify:
	./scripts/verify.sh

clean:
	$(MAKE) -C c_src clean
	rm -rf test_output/ stream_output/ /tmp/venturi_test_env
