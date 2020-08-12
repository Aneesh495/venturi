#!/usr/bin/env bash
# Copyright (C) 2026 Aneesh Krishna.
# See LICENSE for copyright and license details.
#
# Unified verification and test runner script for Venturi.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "================================================================================"
echo "                  STARTING VENTURI SYSTEM VERIFICATION PASS                     "
echo "================================================================================"

# 1. Build and test C99 SIMD library
echo -e "\n[1/4] Building and Testing C99 SIMD / SWAR Acceleration Library..."
cd "${REPO_ROOT}/c_src"
make clean
make test
make all

# 2. Run Factor full test suite
echo -e "\n[2/4] Running Factor Native Unit & Integration Test Suite..."
cd "${REPO_ROOT}"
/Applications/factor/factor -roots="${REPO_ROOT}" -run=venturi test

# 3. Run Factor microbenchmarks
echo -e "\n[3/4] Running Factor Microbenchmark Suite..."
cd "${REPO_ROOT}"
/Applications/factor/factor -roots="${REPO_ROOT}" -run=venturi benchmark

# 4. Run Python Client SDK and Bitstream Validation Suite
echo -e "\n[4/4] Running Python Client SDK & End-to-End Bitstream Validation..."
cd "${REPO_ROOT}"
python3 python/test_venturi.py

echo -e "\n================================================================================"
echo "               ALL 336 VERIFICATION CHECKS PASSED SUCCESSFULLY                 "
echo "================================================================================"
