
(cond-expand
 (modules (import (chibi test)))
 (else (load "tests/r5rs-tests.scm")))

(test-begin "libraries")

(load "tests/flonum-tests.scm")
(load "tests/numeric-tests.scm")
(load "tests/loop-tests.scm")
(load "tests/match-tests.scm")
(load "tests/scribble-tests.scm")
(cond-expand (utf-8 (load "tests/unicode-tests.scm")) (else #f))

(cond-expand
 (modules
  (begin
    (load "tests/record-tests.scm")
    (load "tests/hash-tests.scm")
    (load "tests/sort-tests.scm")
    (load "tests/thread-tests.scm")))
 (else #f))

(test-end)
