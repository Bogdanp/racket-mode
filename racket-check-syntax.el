;;; racket-check-syntax.el -*- lexical-binding: t -*-

;; Copyright (c) 2013-2020 by Greg Hendershott.
;; Portions Copyright (C) 1985-1986, 1999-2013 Free Software Foundation, Inc.

;; Author: Greg Hendershott
;; URL: https://github.com/greghendershott/racket-mode

;; License:
;; This is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version. This is distributed in the hope that it will be
;; useful, but without any warranty; without even the implied warranty
;; of merchantability or fitness for a particular purpose. See the GNU
;; General Public License for more details. See
;; http://www.gnu.org/licenses/ for details.

;;; The general approach here:
;;;
;;; - Add 'help-echo and 'point-{entered left} text properties with
;;;   information supplied by the drracket/check-syntax module.
;;;
;;; - Refresh in an after-change hook, plus an idle-timer delay.
;;;
;;; - Point motion hooks add/remove temporarily overlays to highlight
;;;   defs and uses. (We can't draw GUI arrows as in Dr Racket.)
;;;
;;; - Use a header line so our information isn't "fighting" with other
;;;   things using the echo area.

(require 'racket-custom)
(require 'racket-repl)
(require 'racket-edit)
(require 'rx)

(defun racket--check-syntax-show-info (str)
  ;;(message "%s" (racket--only-first-line str))
  (setq-local header-line-format
              (format "%s" (racket--only-first-line str))))

(defun racket--only-first-line (str)
  (save-match-data
    (string-match (rx (group (* (not (any ?\n))))) str)
    (match-string 1 str)))

(defconst racket--check-syntax-overlay-name 'racket-check-syntax-overlay)

(defun racket--check-syntax-overlay-p (o)
  (eq (overlay-get o 'name)
      racket--check-syntax-overlay-name))

(defun racket--highlight (beg end face)
  (unless (cl-some #'racket--check-syntax-overlay-p
                   (overlays-in beg end))
    (let ((o (make-overlay beg end)))
      (overlay-put o 'name racket--check-syntax-overlay-name)
      (overlay-put o 'priority 100)
      (overlay-put o 'face face))))

(defun racket--unhighlight (beg end)
  (remove-overlays beg end racket--check-syntax-overlay-name))

(defun racket--unhighlight-all ()
  (racket--unhighlight (point-min) (point-max)))

(defun racket--non-empty-string-p (v)
  (and (stringp v)
       (not (string-match-p "\\`[ \t\n\r]*\\'" v)))) ;`string-blank-p'

(defun racket--point-entered (_old new)
  (pcase (get-text-property new 'help-echo)
    ((and s (pred racket--non-empty-string-p))
     (racket--check-syntax-show-info s)))
  (pcase (get-text-property new 'racket-check-syntax-def)
    ((and uses `((,beg ,_end) . ,_))
     (pcase (get-text-property beg 'racket-check-syntax-use)
       (`(,beg ,end)
        (racket--highlight beg end racket-check-syntax-def-face)))
     (dolist (use uses)
       (pcase use
         (`(,beg ,end)
          (racket--highlight beg end racket-check-syntax-use-face))))))
  (pcase (get-text-property new 'racket-check-syntax-use)
    (`(,beg ,end)
     (racket--highlight beg end racket-check-syntax-def-face)
     (dolist (use (get-text-property beg 'racket-check-syntax-def))
       (pcase use
         (`(,beg ,end)
          (racket--highlight beg end racket-check-syntax-use-face)))))))

(defun racket--point-left (old _new)
  (when (get-text-property old 'help-echo)
    (racket--check-syntax-show-info ""))
  (racket--unhighlight-all))

(defun racket-check-syntax-visit-definition ()
  "When point is on a use, go to its definition.

If check-syntax says the definition is local, go there. This
handles bindings in the current source file -- even bindings in
internal definition contexts, and even those that shadow other
bindings.

Otherwise defer to `racket-visit-definition'."
  (interactive)
  (pcase (get-text-property (point) 'racket-check-syntax-use)
    (`(,beg ,_end)
     (racket--push-loc)
     (goto-char beg))
    (_ (racket-visit-definition))))

(defun racket-check-syntax--forward-use (amt)
  "When point is on a use, go AMT uses forward. AMT may be negative.

Moving before/after the first/last use wraps around.

If point is instead on a definition, then go to its first use."
  (pcase (get-text-property (point) 'racket-check-syntax-use)
    (`(,beg ,_end)
     (pcase (get-text-property beg 'racket-check-syntax-def)
       (uses (let* ((pt (point))
                    (ix-this (cl-loop for ix from 0 to (1- (length uses))
                                      for use = (nth ix uses)
                                      when (and (<= (car use) pt) (< pt (cadr use)))
                                      return ix))
                    (ix-next (+ ix-this amt))
                    (ix-next (if (> amt 0)
                                 (if (>= ix-next (length uses)) 0 ix-next)
                               (if (< ix-next 0) (1- (length uses)) ix-next)))
                    (next (nth ix-next uses)))
               (goto-char (car next))))))
    (_ (pcase (get-text-property (point) 'racket-check-syntax-def)
         (`((,beg ,_end) . ,_) (goto-char beg))))))

(defun racket-check-syntax-next-use ()
  "When point is on a use, go to the next, sibling use."
  (interactive)
  (racket-check-syntax--forward-use 1))

(defun racket-check-syntax-previous-use ()
  "When point is on a use, go to the previous, sibling use."
  (interactive)
  (racket-check-syntax--forward-use -1))

(defun racket-check-syntax-rename ()
  "Rename a local definition and its uses in the current file."
  (interactive)
  ;; If we're on a def, get its uses. If we're on a use, get its def.
  (let* ((uses (get-text-property (point) 'racket-check-syntax-def))
         (def  (get-text-property (point) 'racket-check-syntax-use)))
    (unless (or uses def)
      (user-error "Can only rename local definitions"))
    ;; We got one, get the other.
    (let* ((uses (or uses (get-text-property (car def)   'racket-check-syntax-def)))
           (def  (or def  (get-text-property (caar uses) 'racket-check-syntax-use)))
           (locs (cons def uses))
           (old  (apply #'buffer-substring-no-properties def))
           (new  (read-from-minibuffer (format "Rename %s to: " old)))
           (marker-pairs (mapcar (lambda (loc)
                                   (let ((beg (make-marker))
                                         (end (make-marker)))
                                     (set-marker beg (nth 0 loc) (current-buffer))
                                     (set-marker end (nth 1 loc) (current-buffer))
                                     (list beg end)))
                                 locs))
           (point-marker (let ((m (make-marker)))
                           (set-marker m (point) (current-buffer)))))
      ;; Don't let our after-change hook run until all changes are
      ;; made, otherwise check-syntax will find a syntax error.
      (let ((inhibit-modification-hooks t))
        (dolist (marker-pair marker-pairs)
          (let ((beg (marker-position (nth 0 marker-pair)))
                (end (marker-position (nth 1 marker-pair))))
            (delete-region beg end)
            (goto-char beg)
            (insert new))))
      (goto-char (marker-position point-marker))
      (racket--check-syntax-annotate
       (lambda () (racket--point-entered nil (marker-position point-marker)))))))

(defun racket-check-syntax-next-definition ()
  (interactive)
  (let ((pos (next-single-property-change (point) 'racket-check-syntax-def)))
    (when pos
      (unless (get-text-property pos 'racket-check-syntax-def)
        (setq pos (next-single-property-change pos 'racket-check-syntax-def)))
      (and pos (goto-char pos)))))

(defun racket-check-syntax-previous-definition ()
  (interactive)
  (let ((pos (previous-single-property-change (point) 'racket-check-syntax-def)))
    (when pos
      (unless (get-text-property pos 'racket-check-syntax-def)
        (setq pos (previous-single-property-change pos 'racket-check-syntax-def)))
      (and pos (goto-char pos)))))

(defvar racket-check-syntax-control-c-hash-keymap
  (racket--easy-keymap-define
   '(("j" racket-check-syntax-next-definition)
     ("k" racket-check-syntax-previous-definition)
     ("n" racket-check-syntax-next-use)
     ("p" racket-check-syntax-previous-use)
     ("." racket-check-syntax-visit-definition)
     ("r" racket-check-syntax-rename))) )

;;;###autoload
(define-minor-mode racket-check-syntax-mode
  "A minor mode that annotates information supplied by drracket/check-syntax.

This minor mode is an optional enhancement to `racket-mode' edit
buffers. Like any minor mode, you can turn it on or off for a
specific buffer. If you always want to use it, put the following
code in your Emacs init file:

#+BEGIN_SRC elisp
    (require 'racket-check-syntax)
    (add-hook 'racket-mode-hook #'racket-check-syntax-mode)
#+END_SRC

Note: This mode won't do anything unless the Racket Mode back end
is running -- as a result of a `racket-run' or `racket-repl'
command. You need not run the buffer you are editing, just /some/
buffer.

When point is on a definition or use, related items are
highlighted using `racket-check-syntax-def-face' and
`racket-check-syntax-use-face' -- instead of drawing arrows as in
Dr Racket -- and \"mouse over\" information is displayed in the
header line.

You may also use commands to navigate among a definition and its
uses, or rename all of them.

\"M-.\" is rebound to `racket-check-syntax-visit-definition'.
This uses information provided by check-syntax for local
bindings, or else does the usual `racket-visit-definition' for
bindings imported by a `require` or module language.

When you edit the buffer, existing annotations are retained;
their positions are updated to reflect the edit. Annotations for
new or deleted text are not requested until after
`racket-check-syntax-after-change-refresh-delay' seconds. The
request is made asynchronously so that Emacs will not block --
the drracket/check-syntax analysis can take even tens of seconds
for even moderately complex source files. When the results are
ready, all annotations for the buffer are completely refreshed.

Tip: This follows the convention that a minor mode may only use a
prefix key consisting of C-c followed by a punctuation key. As a
result, `racket-check-syntax-control-c-hash-keymap' is bound to
\"C-c #\" by default. However, as an Emacs user, you are free to
rebind this to a more convenient prefix!

\\{racket-check-syntax-mode-map}
"
  :lighter " CheckSyntax"
  :keymap (racket--easy-keymap-define
           `(("C-c #" ,racket-check-syntax-control-c-hash-keymap)
             ("M-."   ,#'racket-check-syntax-visit-definition)))
  (unless (eq major-mode 'racket-mode)
    (setq racket-check-syntax-mode nil)
    (user-error "racket-check-syntax-mode only works with racket-mode buffers"))
  (setq-local header-line-format nil)
  (racket--check-syntax-clear)
  (remove-hook 'after-change-functions
               #'racket--check-syntax-after-change-hook
               t)
  (when racket-check-syntax-mode
    (racket--check-syntax-show-info "Waiting for initial check-syntax analysis...")
    (racket--check-syntax-annotate)
    (add-hook 'after-change-functions
              #'racket--check-syntax-after-change-hook
              t t)
    ;; In case REPL not live when they visit this file, but it becomes
    ;; live, later, annotate then.
    (add-hook 'racket--repl-after-live-hook
              #'racket--check-syntax-annotate)))

(defvar-local racket--check-syntax-timer nil)
(defun racket--check-syntax-after-change-hook (_beg _end _len)
  (when (timerp racket--check-syntax-timer)
    (cancel-timer racket--check-syntax-timer))
  (setq racket--check-syntax-timer
        (run-with-idle-timer racket-check-syntax-after-change-refresh-delay
                             nil ;no repeat
                             #'racket--check-syntax-annotate)))

(defun racket--check-syntax-annotate (&optional thunk)
  (when (racket--repl-live-p)
    (let ((buf (current-buffer)))
      (racket--cmd/async
       `(check-syntax ,(or (racket--buffer-file-name) (buffer-name))
                      ,(buffer-substring-no-properties (point-min) (point-max)))
       (lambda (response)
         (with-current-buffer buf
           (racket--check-syntax-show-info "")
           (pcase response
             (`(check-syntax-ok)
              (racket--check-syntax-clear))
             (`(check-syntax-ok . ,xs)
              (racket--check-syntax-clear)
              (racket--check-syntax-insert xs)
              (when thunk (funcall thunk)))
             (`(check-syntax-errors . ,xs)
              (racket--check-syntax-insert xs)))))))))

(defun racket--check-syntax-insert (xs)
  "Insert text properties. Convert integer positions to markers."
  (with-silent-modifications
    (overlay-recenter (point-max)) ;faster
    (dolist (x xs)
      (pcase x
        (`(,`error ,path ,beg ,end ,str)
         (when (equal path (racket--buffer-file-name))
           (let ((beg (copy-marker beg t))
                 (end (copy-marker end t)))
             (remove-text-properties beg
                                     end
                                     (list 'help-echo               nil
                                           'racket-check-syntax-def nil
                                           'racket-check-syntax-use nil
                                           'point-entered           nil
                                           'point-left              nil))
             (add-text-properties beg
                                  end
                                  (list 'face          'error
                                        'help-echo     str
                                        'point-entered #'racket--point-entered
                                        'point-left    #'racket--point-left))
             ;; Show immediately
             (racket--check-syntax-show-info str))))
        (`(,`info ,beg ,end ,str)
         (let ((beg (copy-marker beg t))
               (end (copy-marker end t)))
           (add-text-properties beg
                                end
                                (list 'help-echo     str
                                      'point-entered #'racket--point-entered
                                      'point-left    #'racket--point-left))))
        (`(,`def/uses ,def-beg ,def-end ,uses)
         (let ((def-beg (copy-marker def-beg t))
               (def-end (copy-marker def-end t))
               (uses    (mapcar (lambda (xs)
                                  (mapcar (lambda (x)
                                            (copy-marker x t))
                                          xs))
                                uses)))
          (add-text-properties def-beg
                               def-end
                               (list 'racket-check-syntax-def uses
                                     'point-entered #'racket--point-entered
                                     'point-left    #'racket--point-left))
          (dolist (use uses)
            (pcase-let* ((`(,use-beg ,use-end) use))
              (add-text-properties use-beg
                                   use-end
                                   (list 'racket-check-syntax-use (list def-beg
                                                                        def-end)
                                         'help-echo     "Defined locally"
                                         'point-entered #'racket--point-entered
                                         'point-left    #'racket--point-left))))))))
    ;; Make 'point-entered and 'point-left work in Emacs 25+. Note
    ;; that this is somewhat of a hack -- I spent a lot of time trying
    ;; to Do the Right Thing using the new cursor-sensor-mode, but
    ;; could not get it to work satisfactorily. See:
    ;; http://emacs.stackexchange.com/questions/29813/point-motion-strategy-for-emacs-25-and-older
    (setq-local inhibit-point-motion-hooks nil)))

(defun racket--check-syntax-clear ()
  (with-silent-modifications
    (remove-text-properties (point-min)
                            (point-max)
                            (list 'help-echo nil
                                  'racket-check-syntax-def nil
                                  'racket-check-syntax-use nil
                                  'point-entered nil
                                  'point-left nil))
    (racket--unhighlight-all)))

(provide 'racket-check-syntax)

;; racket-check-syntax.el ends here