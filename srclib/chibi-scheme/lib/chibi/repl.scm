;; repl.scm - friendlier repl with line editing and signal handling
;; Copyright (c) 2011 Alex Shinn.  All rights reserved.
;; BSD-style license: http://synthcode.com/license.txt

;;> A user-friendly REPL with line editing and signal handling.
;;> The default REPL provided by chibi-scheme is very minimal,
;;> meant primarily to be small and work on any platform.  This
;;> module provides an advanced REPL that handles vt100 line
;;> editing and signal handling, so that C-c will interrupt a
;;> computation and bring you back to the REPL prompt.  To use
;;> this repl, run
;;> @command{chibi-scheme -mchibi.repl -e'(repl)'}
;;> from the command line or within Emacs.

(define (with-signal-handler sig handler thunk)
  (let ((old-handler #f))
    (dynamic-wind
      (lambda () (set! old-handler (set-signal-action! sig handler)))
      thunk
      (lambda () (set-signal-action! sig old-handler)))))

(define (warn msg . args)
  (let ((out (current-error-port)))
    (display msg out)
    (for-each (lambda (x) (write-char #\space out) (write x out)) args)
    (newline out)))

(define (write-to-string x)
  (call-with-output-string (lambda (out) (write x out))))

(define (buffer-complete-sexp? buf)
  (guard (exn (else #f))
    (call-with-input-string (buffer->string buf)
      (lambda (in)
        (let lp () (if (not (eof-object? (read/ss in))) (lp)))))
    #t))

(define module? vector?)
(define (module-env mod) (vector-ref mod 1))

;;> Runs an interactive REPL.  Repeatedly displays a prompt,
;;> then Reads an expression, Evaluates the expression, Prints
;;> the result then Loops.  Terminates when the end of input is
;;> reached or the @scheme|{@exit}| command is given.
;;>
;;> Basic Emacs-style line editing with persistent history
;;> completion is provided.  C-c can be used to interrupt the
;;> current computation and drop back to the prompt.  The
;;> following keyword arguments customize the REPL:
;;>
;;> @itemlist[
;;> @item{@scheme{in:} - the input port (default @scheme{(current-input-port)})}
;;> @item{@scheme{out:} - the output port (default @scheme{(current-output-port)})}
;;> @item{@scheme{module:} - the initial module (default @scheme{(interaction-environment)})}
;;> @item{@scheme{escape:} - the command escape character (default @scheme|{#\@}|)}
;;> @item{@scheme{history:} - the initial command history}
;;> @item{@scheme{history-file:} - the file to save history to (default ~/.chibi-repl-history)}
;;> ]
;;>
;;> REPL commands in the style of @hyperlink["http://s48.org/"]{Scheme48}
;;> are available to control out-of-band properties.  By default a command
;;> is written as an identifier beginning with an "@" character (which
;;> would not be a portable identifier), but this can be customized with
;;> the @scheme{escape:} keyword.  The following commands are available:
;;>
;;> @itemlist[
;;> @item{@scheme|{@in [<module>]}| - switch to @var{<module>}, or the @scheme{interaction-environment} if @var{<module>} is not specified}
;;> @item{@scheme|{@config <expr>}| - evaluate @var{<expr>} in the @scheme{(config)} module}
;;> @item{@scheme|{@config-module-is <module>}| - switch the config module to @var{<module>}}
;;> @item{@scheme|{@exit}| - exit the REPL}
;;> ]

(define (repl . o)
  (let* ((in (cond ((memq 'in: o) => cadr) (else (current-input-port))))
         (out (cond ((memq 'out: o) => cadr) (else (current-output-port))))
         (escape (cond ((memq 'escape: o) => cadr) (else #\@)))
         (module (cond ((memq 'module: o) => cadr) (else #f)))
         (env (if module
                  (module-env
                   (if (module? module)
                       module
                       (eval `(load-module ',module) *config-env*)))
                  (interaction-environment)))
         (history-file
          (cond ((memq 'history-file: o) => cadr)
                (else (string-append (get-environment-variable "HOME")
                                     "/.chibi-repl-history"))))
         (history
          (cond ((memq 'history: o) => cadr)
                (else
                 (or (guard (exn (else #f))
                      (list->history
                       (call-with-input-file history-file read)))
                     (make-history)))))
         (raw? (cond ((memq 'raw?: o) => cadr)
                     (else (member (get-environment-variable "TERM")
                                   '("emacs" "dumb"))))))
    (let lp ((module module) (env env) (config-env *config-env*))
      (let* ((prompt
              (string-append (if module (write-to-string module) "") "> "))
             (line
              (cond
               (raw?
                (display prompt out)
                (flush-output out)
                (read-line in))
               (else
                (edit-line in out
                 'prompt: prompt
                 'history: history
                 'complete?: buffer-complete-sexp?)))))
        (cond
         ((or (not line) (eof-object? line)))
         ((equal? line "") (lp module env config-env))
         (else
          (history-commit! history line)
          (cond
           ((and (> (string-length line) 0) (eqv? escape (string-ref line 0)))
            (let meta ((env env)
                       (line (substring line 1 (string-length line)))
                       (continue lp))
              (define (fail msg . args)
                (apply warn msg args)
                (continue module env config-env))
              (call-with-input-string line
               (lambda (in)
                 (let ((op (read/ss in)))
                   (case op
                     ((in)
                      (let ((name (read/ss in)))
                        (cond
                         ((eof-object? name)
                          (continue #f (interaction-environment) config-env))
                         ((eval `(load-module ',name) config-env)
                          => (lambda (m)
                               (continue name (module-env m) config-env)))
                         (else
                          (fail "couldn't find module:" name)))))
                     ((config)
                      (let ((expr (read/ss in)))
                        (cond
                         ((and
                           (symbol? expr)
                           (eqv? escape (string-ref (symbol->string expr) 0)))
                          (meta config-env
                                (substring line 6 (string-length line))
                                (lambda _ (continue module env config-env))))
                         (else
                          (eval expr config-env)
                          (continue module env config-env)))))
                     ((config-module-is)
                      (let ((name (read/ss in)))
                        (cond
                         ((eval `(load-module ',name) config-env)
                          => (lambda (m) (lp module env (module-env m))))
                         (else
                          (fail "couldn't find module:" name)))))
                     ((exit))
                     (else
                      (fail "unknown repl command:" op))))))))
           (else
            (guard
             (exn
              (else (print-exception exn (current-error-port))))
             (let* ((expr (call-with-input-string line read/ss))
                    (thread
                     (make-thread
                      (lambda ()
                        (guard
                         (exn
                          (else (print-exception exn (current-error-port))))
                         (let ((res (eval expr env)))
                           (cond
                            ((not (eq? res (if #f #f)))
                             (write/ss res)
                             (newline)))))))))
               (with-signal-handler
                signal/interrupt
                (lambda (n)
                  (display "Interrupt\n" (current-error-port))
                  (thread-terminate! thread))
                (lambda () (thread-join! (thread-start! thread))))))
            (lp module env config-env)))))))
    (if history-file
        (call-with-output-file history-file
          (lambda (out) (write (history->list history) out))))))
