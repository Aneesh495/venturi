! Copyright (C) 2026 Aneesh Krishna.
! See LICENSE for copyright and license details.
!
! Zero-dependency lightweight unit test runner and assertion framework.

USING: accessors continuations io kernel locals math namespaces
prettyprint sequences strings ;
IN: venturi.tests.harness

SYMBOL: total-tests
SYMBOL: passed-tests
SYMBOL: failed-tests

: init-test-harness ( -- )
    0 total-tests set-global
    0 passed-tests set-global
    0 failed-tests set-global ;

init-test-harness

:: test= ( actual expected msg -- )
    total-tests get-global 1 + total-tests set-global
    expected actual = [
        passed-tests get-global 1 + passed-tests set-global
        "  [PASS] " write msg print
    ] [
        failed-tests get-global 1 + failed-tests set-global
        "  [FAIL] " write msg print
        "         Expected: " write expected .
        "         Actual:   " write actual .
    ] if ;

: test-true ( actual msg -- )
    t swap test= ; inline

: test-false ( actual msg -- )
    f swap test= ; inline

:: test-throws ( quot msg -- )
    total-tests get-global 1 + total-tests set-global
    [ quot call( -- ) f ] [ drop t ] recover [
        passed-tests get-global 1 + passed-tests set-global
        "  [PASS] " write msg write " (threw as expected)" print
    ] [
        failed-tests get-global 1 + failed-tests set-global
        "  [FAIL] " write msg write " (expected exception but none thrown)" print
    ] if ;

:: print-test-summary ( suite-name -- ? )
    "\n=======================================================\n" write
    "Test Suite: " write suite-name print
    "Total:  " write total-tests get-global .
    "Passed: " write passed-tests get-global .
    "Failed: " write failed-tests get-global .
    "=======================================================\n\n" write
    failed-tests get-global zero? ;
