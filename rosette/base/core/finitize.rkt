#lang racket

(require racket/syntax 
         "term.rkt" "real.rkt" "bitvector.rkt" "bool.rkt" 
         "polymorphic.rkt" "merge.rkt")

(provide finitize)

; The finitize procedure takes as input a list of terms, in any combination of theories, 
; and encodes those terms in the theory of bitvectors (BV), representing integers and reals 
; as bitvectors of length bw. The optional bw argument, if provided, specifies 
; the bitwidth to be used for finitization of integer and real operation 
; (current-bitwidth by default).
;
; The procedure produces a map from input terms, and their subterms, to 
; their corresponding BV finitizations.  Terms that are already in BV 
; finitize to themselves.
(define (finitize terms [bw (current-bitwidth)])
  (let ([env (make-hash)])
    (for ([t terms])
      (enc t env))
    env))

; The enc procedure takes a value (a term or a literal), 
; and an environment (a hash-map from terms to their QF_BV encoding), and returns  
; a QF_BV term representing that value in the given environment.  If it 
; cannot produce an encoding for the given value, an error is thrown. 
; The environment will be modified (if needed) to include an encoding for 
; the given value and all of its subexpressions (if any).
(define (enc v env)
  (or (hash-ref env v #f)
      (hash-ref! env v 
                 (match v
                   [(? expression?) (enc-expr v env)]
                   [(? constant?)   (enc-const v env)]
                   [_               (enc-lit v env)]))))

; TODO:  use unsafe ops for encoding.
(define (enc-expr v env)
  (match v
    [(expression (== @=) x y)         (@bveq (enc x env) (enc y env))]
    [(expression (== @<) x y)         (@bvslt (enc x env) (enc y env))]
    [(expression (== @<=) x y)        (@bvsle (enc x env) (enc y env))]
    [(expression (== @-) x)           (@bvneg (enc x env))]
    [(expression (== @+) xs ...)      (apply @bvadd (for/list ([x xs]) (enc x env)))]
    [(expression (== @*) xs ...)      (apply @bvmul (for/list ([x xs]) (enc x env)))]
    [(expression (== @/) x y)         (@bvsdiv (enc x env) (enc y env))]
    [(expression (== @quotient) x y)  (@bvsdiv (enc x env) (enc y env))]
    [(expression (== @remainder) x y) (@bvsrem (enc x env) (enc y env))]
    [(expression (== @modulo) x y)    (@bvsmod (enc x env) (enc y env))]
    [(expression (== @int?) _)        #t]
    [(expression (== @abs) x) 
     (let ([e (enc x env)])
       (merge (@bvslt e (bv 0 (get-type e))) (@bvneg e) e))]
    [(expression (or (== @integer->real) (== @real->integer)) x _) 
     (enc x env)]
    [(expression (== @integer->bitvector) v (bitvector sz))
     (convert (enc v env) (current-bitwidth) sz @sign-extend)]
    [(expression (== @bitvector->natural) (and v (app get-type (bitvector sz))))
     (convert (enc v env) sz (current-bitwidth) @zero-extend)]
    [(expression (== @bitvector->integer) (and v (app get-type (bitvector sz))))
     (convert (enc v env) sz (current-bitwidth) @sign-extend)]
    [(expression (== ite) a b c)
     (merge (enc a env) (enc b env) (enc c env))]
    ((expression (== ite*) gvs ...)
     (apply merge* 
            (for/list ([gv gvs]) 
              (cons (enc (guarded-test gv) env) (enc (guarded-value gv) env)))))                  
    [(expression op x)     
     (op (enc x env))]
    [(expression op x y)   
     (op (enc x env) (enc y env))]
    [(expression op xs ...) 
     (apply op (for/list ([x xs]) (enc x env)))]))
    
(define (enc-const v env)
  (match v
    [(constant (or id (cons id _)) (or (== @integer?) (== @real?)))
     (constant (format-id id "~a" (gensym (term-e v)) #:source id)
               (bitvector (current-bitwidth)))]
    [_ v]))
                              
(define (enc-lit v env)
  (match v 
    [(? real?) (bv v (current-bitwidth))]
    [_ v]))

(define (convert v src tgt @extend)
  (cond [(= src tgt) v]
        [(> src tgt) (@extract (- tgt 1) 0 v)]
        [else        (@extend v (bitvector tgt))]))
