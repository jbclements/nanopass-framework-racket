#lang racket
;;; Copyright (c) 2000-2013 Dipanwita Sarkar, Andrew W. Keep, R. Kent Dybvig, Oscar Waddell
;;; See the accompanying file Copyright for detatils

;;; AWK - TODO - Once the meta-parser can handle language passes that match
;;;              a single variable.
;;;       FIXME - For Ikarus, I needed to use "dots" instead of the ".."
;;;               because Ikarus sees .. as a syntax error, even when it is
;;;               exported as an auxiliary keyword.

;;; Time-stamp: <2000-01-10 12:29:38 kemillik>
;;; (time-stamp generated by emacs:  Type M-x time-stamp anywhere to update)

;;; syncase is a pattern matcher where patterns are quoted or
;;; quasiquoted expressions, or symbols. Unquoted symbols denote
;;; pattern variables.  All quoted things must match precisely. 
;;; Also, there is a symbol ".." that may be used to allow repetitions
;;; of the preceeding pattern.  Any pattern variables within are bound
;;; to a list of matches.  ".." may be nested.
;;; Below is the canonical example of "let" 

;;; [`(let ([,var ,rhs] ..) ,body0 ,body1 ..)
;;;  (guard (for-all symbol? var) (no-duplicates? var))
;;;  `((lambda ,var ,body0 ,@body1) ,@rhs)]

;;; For the pattern to match, the optional guard requires its
;;; arguments to be true.  The guard also uses the pattern
;;; variables.

;;; We have added three obvious new forms: synlambda, synlet, and
;;; synlet*.  Finally, we have added a very useful operation,
;;; make-double-collector-over-list, whose description follows from the
;;; very simple code  below.
;;; Here are some descriptive examples of each of the new special forms.

;;;> (define foo
;;;    (synlambda `((if ,exp0 ,exp1) ,env)
;;;      (guard (number? exp1))
;;;      `(,env (if ,exp0 ,exp1 0))))
;;;> (foo '(if 1 2) 'anenv)
;;;(anenv (if 1 2 0))

;;;> (synlet ([`(if ,exp0 ,exp1)
;;;            (guard (number? exp0))
;;;            '(if 0 1)])
;;;    `(if ,exp1, exp0))
;;;(if 1 0)

;;;> (synlet ([`(if ,x ,y ,z) '(if 1 2 3)]
;;;	      [`(if ,a then ,b else ,c) '(if 1 then 2 else 3)]
;;;	      [`(when ,u ,w) (guard (number? u) (number? w) (= u w))
;;;	       '(when 1 1)])
;;;    (list x y z a b c a b))
;;; (1 2 3 1 2 3 1 2)

;;;> (synlet* ([`(if ,exp0 ,exp1) (guard (number? exp0)) '(if 0 1)]
;;;            [`(if ,x ,y ,exp2) `(if ,exp0 ,exp1 5)])
;;;    `(if ,exp0 ,y ,exp2))
;;;(if 0 1 5)

(provide syncase)

(define-syntax syncase
  (syntax-rules ()
    [(_ Exp (Clause ...) ...) 
     (let ([x Exp])
       (call/cc
         (lambda (succeed)
           (pm:c start x succeed Clause ...)
           ...
           (error 'syncase "No match for ~s" x))))])) 
  
(define-syntax pm:c
  (syntax-rules (guard start finish)
    [(pm:c start V Succ Pattern (guard Exp ...) Body0 Body ...)
     (pm:parse start Pattern 
       (pm:c finish V
         (when (and Exp ...)
           (Succ (begin Body0 Body ...)))))]
    [(pm:c finish V Body Pattern UsedFormals)
     (pm:find-dup UsedFormals
       (cont (Dup) 
         (pm:error "Duplicate patvar ~s in pattern ~s" Dup Pattern))
       (cont () (pm V Pattern Body)))] 
    [(_ start V Succ Pattern Body0 Body ...)
     (pm:c start V Succ Pattern (guard) Body0 Body ...)]
    [(_ start V Succ Pattern)
     (pm:error "Missing body for pattern ~s" Pattern)])) 
  
(define-syntax pm:parse ;; returns parsed thing + used formals
  (syntax-rules (dots quasiquote quote unquote start)
    [(pm:parse start () K) (pm:ak K (null) ())]
    [(pm:parse start (unquote X) K) (pm:ak K (formal X) (X))]
    [(pm:parse start (A . D) K) (pm:parseqq start (A . D) K)]
    [(pm:parse start X K) (pm:ak K (keyword X) ())]))
  
(define-syntax pm:parseqq;; returns parsed thing + used formals
  (lambda (x)
    (syntax-case x (unquote start dothead dottail dottemps pairhead pairtail)
      [(pm:parseqq start (unquote ()) K) #'(pm:error "Bad variable: ~s" ())]
      [(pm:parseqq start (unquote (quasiquote X)) K) #'(pm:parseqq start X K)]
      [(pm:parseqq start (unquote (X . Y)) K)
       #'(pm:error "Bad variable: ~s" (X . Y))]
      [(pm:parseqq start (unquote #(X ...)) K)
       #'(pm:error "Bad variable: ~s" #(X ...))]
      [(pm:parseqq start (unquote X) K) #'(pm:ak K (formal X) (X))]
      [(pm:parseqq start (X dots . Y) K) 
       (eq? (syntax->datum #'dots) '...)
       #'(pm:parseqq start X (pm:parseqq dothead Y K))]
      [(pm:parseqq dothead Y K Xpat Xformals)
       #'(pm:parseqq^ start Y () ()
           (pm:parseqq dottail Xpat Xformals K))]
      [(pm:parseqq dottail Xpat Xformals K Yrevpat Yformals)
       #'(pm:gen-temps Xformals ()
           (pm:parseqq dottemps Xpat Yrevpat Xformals Yformals K))]
      [(pm:parseqq dottemps Xpat Yrevpat (Xformal ...) (Yformal ...) K Xtemps)
       #'(pm:ak K (dots (Xformal ...) Xtemps Xpat Yrevpat)
           (Xformal ... Yformal ...))] 
      [(pm:parseqq start (X . Y) K)
       #'(pm:parseqq start X (pm:parseqq pairhead Y K))]
      [(pm:parseqq pairhead Y K Xpat Xformals)
       #'(pm:parseqq start Y (pm:parseqq pairtail Xpat Xformals K))]
      [(pm:parseqq pairtail Xpat (Xformal ...) K Ypat (Yformal ...))
       #'(pm:ak K (pair Xpat Ypat) (Xformal ... Yformal ...))]
      [(pm:parseqq start X K) #'(pm:ak K (keyword X) ())])))
  
(define-syntax pm:parseqq^;; returns list-of parsed thing + used formals
  (syntax-rules (dots start pairhead)
    [(pm:parseqq^ start () Acc Used K) (pm:ak K Acc ())]
    [(pm:parseqq^ start (dots . Y) Acc Used K)
     (pm:error "Illegal continuation of list pattern beyond dots: ~s" Y)]
    [(pm:parseqq^ start (X . Y) Acc Used K)
     (pm:parseqq start X (pm:parseqq^ pairhead Y Acc Used K))]
    [(pm:parseqq^ pairhead Y Acc (Used ...) K Xpat (Xformal ...))
     (pm:parseqq^ start Y (Xpat . Acc) (Used ... Xformal ...) K)] 
    [(pm:parseqq^ start X Acc Used K) (pm:error "Bad pattern ~s" X)])) 
  
(define-syntax pm
  (syntax-rules (keyword formal dots null pair)
    [(pm V (keyword K) Body) (when (eqv? V 'K) Body)]
    [(pm V (formal F) Body) (let ((F V)) Body)]
    [(pm V (dots Dformals DTemps DPat (PostPat ...)) Body)
     (when (list? V) 
       (let ((rev (reverse V)))
         (pm:help rev (PostPat ...) Dformals DTemps DPat Body)))]
    [(pm V (null) Body) (when (null? V) Body)]
    [(pm V (pair P0 P1) Body) 
     (when (pair? V) 
       (let ((X (car V)) (Y (cdr V))) 
         (pm X P0 (pm Y P1 Body))))])) 
  
(define-syntax pm:help
  (syntax-rules ()
    [(pm:help V () (DFormal ...) (DTemp ...) DPat Body)
     (let f ((ls V) (DTemp '()) ...)
       (if (null? ls)
           (let ((DFormal DTemp) ...) Body)
           (let ((X (car ls)) (Y (cdr ls)))
             (pm X DPat
               (f Y (cons DFormal DTemp) ...)))))]
    [(pm:help V (Post0 PostPat ...) DFormals DTemps DPat Body)
     (when (pair? V) 
       (let ((X (car V)) (Y (cdr V)))
         (pm X Post0 
           (pm:help Y (PostPat ...) DFormals DTemps DPat Body))))])) 
  
(define-syntax pm:error
  (syntax-rules ()
    [(pm:error X ...) (error 'syncase 'X ...)])) 
  
(define-syntax pm:eq?
  (syntax-rules ()
    [(_ A B SK FK) ; b should be an identifier
     (let-syntax ([f (syntax-rules (B)
                       [(f B _SK _FK) (pm:ak _SK)]
                       [(f nonB _SK _FK) (pm:ak _FK)])])
       (f A SK FK))])) 
  
(define-syntax pm:member?
  (syntax-rules ()
    [(pm:member? A () SK FK) (pm:ak FK)]
    [(pm:member? A (Id0 . Ids) SK FK) 
     (pm:eq? A Id0 SK (cont () (pm:member? A Ids SK FK)))])) 
  
(define-syntax pm:find-dup
  (syntax-rules ()
    [(pm:find-dup () SK FK) (pm:ak FK)]
    [(pm:find-dup (X . Y) SK FK) 
     (pm:member? X Y 
       (cont () (pm:ak SK X)) (cont () (pm:find-dup Y SK FK)))])) 
  
(define-syntax pm:gen-temps
  (syntax-rules ()
    [(_ () Acc K) (pm:ak K Acc)]
    [(_ (X . Y) Acc K) (pm:gen-temps Y (temp . Acc) K)])) 
  
;;; ------------------------------
;;; Continuation representation and stuff 
(define-syntax cont ; broken for non-nullary case
  (syntax-rules ()
    [(_ () Body) Body]
    [(_ (Var ...) Body Exp ...)
     (let-syntax ([f (syntax-rules ()
                       [(_ Var ...) Body])])
       (f Exp ...))])) 
  
(define-syntax pm:ak
  (syntax-rules ()
    [(_ (X Y ...) Z ...) (X Y ... Z ...)])) 
  
;;; ------------------------------ 
;;; tests 
  
;(define exp0
;  '(syncase '((a) (b) (c d))
;     ((,zz ,ww) ((,zz .. ,ww) ..)
;      zz))) 
  
;(define test
;  (lambda (x)
;    (pretty-print x)
;    (pretty-print (eval x))
;    (newline)))
;
;(define test0 (lambda () (test exp0)))
  
;;; There are three additional special forms, which should be obvious.  
(define-syntax synlambda
  (syntax-rules (guard)
    [(_ pat (guard g ...) body0 body1 ...)
     (lambda (x)
       (syncase x
         [pat (guard g ...) (begin body0 body1 ...)]))]
    [(_ pat body0 body1 ...)
     (lambda (x)
       (syncase x
         [pat (begin body0 body1 ...)]))])) 
  
(define-syntax synlet
  (syntax-rules (guard)
    [(_ ([pat (guard g) rhs] ...) body0 body1 ...)
     ((synlambda `(,pat ...) 
        (guard (and g ...)) body0 body1 ...) `(,rhs ...))]
    [(_ ([pat rhs] ...) body0 body1 ...)
     ((synlambda `(,pat ...) body0 body1 ...) `(,rhs ...))]
    [(_ stuff ...) (synlet-all-guarded () stuff ...)])) 
  
(define-syntax synlet-all-guarded
  (syntax-rules (guard)
    [(_ (x ...) () body0 body1 ...) (synlet (x ...) body0 body1 ...)]
    [(_ (x ...) ([pat (guard g0 g1 g2 ...) rhs] decl ...) body0 body1 ...)
     (synlet-all-guarded (x ... [pat (guard (and g0 g1 g2 ...)) rhs])
       (decl ...) body0 body1 ...)]
    [(_ (x ...) ([pat rhs] decl ...) body0 body1 ...)
     (synlet-all-guarded (x ... [pat (guard #t) rhs])
       (decl ...) body0 body1 ...)]
    [(_ (x ...) ([pat] decl ...) body0 body1 ...)
     (pm:error "synlet missing right-hand-side for pattern: ~s" pat)]
    [(_ () (decl ...)) (pm:error "synlet missing body")])) 
  
(define-syntax synlet*
  (syntax-rules ()
    [(_ (dec) body0 body1 ...) (synlet (dec) body0 body1 ...)]
    [(_ (dec0 decl ...) body0 body1 ...)
     (synlet (dec0) (synlet* (decl ...) body0 body1 ...))])) 
  
(define make-double-collector-over-list
  (lambda (constructor1 base1 constructor2 base2)
    (letrec ((loop42 (lambda args
                       (unless (= (length args) 2)
                         (error 'syncase "Invalid rhs expression"))
                       (let ([f (car args)] [arg (cadr args)])
                         (cond
                           [(null? arg) `(,base1 ,base2)]
                           [else
                            (synlet ([`(,x ,y) (f (car arg))]
                                     [`(,x* ,y*) (loop42 f (cdr arg))])
                              `(,(constructor1 x x*)
                                 ,(constructor2 y y*)))])))))
      loop42)))