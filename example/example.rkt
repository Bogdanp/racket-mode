#lang racket

(for/fold ([str ""])
          ([ss '("a" "b" "c")])
  (string-append str ss))

(require xml)
(provide valid-bucket-name?)

(define (function foo)
  #t)
(define a-var 10)

(define/contract (f2 x)
  (any/c . -> . any)
  #t)

(define-values (1st-var 2nd-var) (values 1 2))

;; Following should be `lambda' not `lambda':
(lambda (x) #t)

;; Single line comment

#|

Multi-line
comment

|#

#;(sexpr comment)

(define (a-function x #:keyword [y 0])
  (define foo0 'symbol) ; ()
  [define foo1 'symbol] ; []
  {define foo2 'symbol} ; {}
  (and (append (car '(1 2 3))))
  (regexp-match? #rx"foobar" "foobar")
  (regexp-match? #px"foobar" "foobar")
  (define a 1)
  (let ([a "foo"]
        [b "bar"])
    (displayln b))
  (let* ([a "foo"]
         [b "bar"])
    (displayln b))
  (let-values ([(a b) (values 1 2)])
    #t)
  (for/list ([x (in-list (list 1 2 (list 3 4)))])
      (cond
       [(pair? x) (car x)]
       [else x])))

(define (foo)
  (let ([x 10])
    #t)

  (let ([x 1]
        [y 2])
    #t)

  (define 1/2-the-way 0)
  (define less-than-1/2 0)

  ;; Self-eval examples
  (values
   1/2-the-way                            ;should NOT be self-eval
   less-than-1/2                          ;should NOT be self-eval
   +inf.0
   -inf.0
   +nan.0
   #t
   #f
   1
   1.0
   1/2
   -1/2
   #b100
   #o123
   #d123
   #x7f7f
   'symbol
   '|symbol with spaces|
   'symbol-with-no-alpha/numeric-chars
   #\c
   #\space
   #\newline

   ;; Literal number examples
   
   ;; #b
   #b1.1
   #b-1.1
   #b1e1
   #b0/1
   #b1/1
   #b1e-1
   #b101
   
   ;; #d
   #d-1.23
   #d1.123
   #d1e3
   #d1e-22
   #d1/2
   #d-1/2
   #d1
   #d-1

   ;; No # reader prefix -- same as #d
   -1.23
   1.123
   1e3
   1e-22
   1/2
   -1/2
   1
   -1

   ;; #e
   #e-1.23
   #e1.123
   #e1e3
   #e1e-22
   #e1
   #e-1
   #e1/2
   #e-1/2

   ;; #i always float
   #i-1.23
   #i1.123
   #i1e3
   #i1e-22
   #i1/2
   #i-1/2
   #i1
   #i-1

   ;; #o
   #o777.777
   #o-777.777
   #o777e777
   #o777e-777
   #o3/7
   #o-3/7
   #o777
   #o-777

   ;; #x
   #x-f.f
   #xf.f
   #x-f
   #xf
   ))

(define/contract (valid-bucket-name? s #:keyword [dns-compliant? #t])
  ((string?) (#:keyword boolean?) . ->* . boolean?)
  (cond
   [dns-compliant?
    (and (<= 3 (string-length s)) (<= (string-length s) 63)
         (not (regexp-match #px"\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}" s))
         (for/and ([s (regexp-split #rx"\\." s)])
           (define (valid-first-or-last? c)
             (or (char-lower-case? (string-ref s 0))
                 (char-numeric? (string-ref s 0))))
           (define (valid-mid? c)
             (or (valid-first-or-last? c)
                 (equal? c #\-)))
           (define len (string-length s))
           (and (< 0 len)
                (valid-first-or-last? (string-ref s 0))
                (valid-first-or-last? (string-ref s (sub1 len)))
                (or (<= len 2)
                    (for/and ([c (substring s 1 (sub1 len))])
                      (valid-mid? c))))))]
   [else
    (and (<= (string-length s) 255)
         (for/and ([c s])
           (or (char-numeric? c)
               (char-lower-case? c)
               (char-upper-case? c)
               (equal? c #\.)
               (equal? c #\-)
               (equal? c #\_))))]))

;; Silly test submodule example that always fails (to test output).
(module+ test
  (require rackunit)
  (check-true #f))

(displayln "I'm running!")