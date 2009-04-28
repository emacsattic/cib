;;; cib.el --- Complete into Buffer for Emacs
;; Copyright (c) 1999 Carsten Dominik

;; Author: Carsten Dominik <dominik@astro.uva.nl>
;; Version: 0.1
;; Keywords: extensions

;; This file not part of the GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;---------------------------------------------------------------------------

;;; Commentary:

;; This program provides a function to complete strings in a buffer.
;; In many programming modes this functionality is bound to M-<TAB>.
;; For example, in `emacs-lisp-mode', you can complete symbols in this
;; way.  AUCTeX uses in-buffer completion to complete macros, labels
;; and may other things.
;;
;; cib.el provides a simple interface for such in-buffer completion
;; and does the work about finding out if the completion is unique,
;; inserting partial completions, displaying the list of completions
;; etc.  It is a programming interface, sort of a `completing-read'
;; for in-buffer completion.  The only entry point is `cib-complete'
;; which takes the string to be completed and a completion table as
;; mandatory arguments.
;;
;; cib.el overcomes a number of shortcomings which AFAIK are present
;; in the available in-buffer completion implementations in Emacs.
;;
;; 1. It restores the window configuration (to get rid of the
;;    *Completions* window) after a successful completion.
;;    "Successful" means any of these:
;;    - The entered string is already complete and unique.
;;    - There is a unique completion (which gets inserted).
;;    - The user selects a completion in the *Completions* buffer.
;;    - The entered string is complete but not unique, and the user
;;      asks for completion twice.  So if you enter "AB" and table
;;      contains "AB" and "ABC", the first completion attempt displays
;;      the list of completions, the second restores the window
;;      configuration.
;;
;; 2. A hook form can be specified which will be evaluated after
;;    successful completion.
;;
;; 3. For a long list of completions, calling the completion function
;;    repeatedly causes the *Completions* window to scroll.
;;
;; 4. Completions can be sorted and uniquified before display.
;;
;; 5. Case-insensitive completion works properly.
;;
;;    a) To do case-insensitive completion, your code will bind
;;       `completion-ignore-case' to a non-nil value in the completion
;;       function.  This does the right thing for finding and
;;       displaying possible completions.  However, selecting a
;;       completion with the mouse used to fail in such cases because
;;       the dynamic binding of `completion-ignore-case' is no longer
;;       present when the mouse selects a completion.  `cib-complete'
;;       installs a wrapper around the `choose-completion' functions
;;       which binds `completion-ignore-case' to the correct value.
;;
;;    b) You can make the partial string in the buffer determine
;;       dynamically the case of the completed string, to help users
;;       with different case preferences.  See the variable
;;       `cib-adaptive-case'.
;;
;; 6. Works on both Emacs and XEmacs .
;;

;;; Examples:
;;  ========
;;
;; Here is an example on how to use this function to implement
;; symbol completion in FORTRAN mode.  FORTRAN is a case-insensitive
;; language, so this example uses `cib-adaptive-case'.
;; `fortran-symbol-table' is assumed to contain the symbols.
;;
;; (defun fortran-complete ()
;;   "Complete a FORTRAN symbol at point."
;;   ;; Find the beginning of the string to complete, bind variables
;;   (let ((beg (save-excursion (skip-chars-backwards "a-zA-Z_") (point)))
;;         (completion-ignore-case t)
;;         (cib-adaptive-case t)
;;         (cib-sort-completions t)
;;         (cib-uniquify-completions t))
;;     (cib-complete beg fortran-symbol-table)))
;; (define-key fortran-mode-map [(meta tab)] fortran-complete)
;;
;; -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -
;;
;; Here is AUCTeX's `TeX-complete-symbol', rewritten to use `cib-complete'.
;; Uses the FINAL arg of `cib-complete' to insert closing parenthesis.
;;
;; (defun TeX-complete-symbol ()
;;   "Perform completion on TeX/LaTeX symbol preceding point."
;;   (interactive "*")
;;   (let ((list TeX-complete-list)
;;         entry)
;;     (while list
;;       (setq entry (car list)
;;             list (cdr list))
;;       (if (TeX-looking-at-backward (car entry) 250)
;;           (setq list nil)))
;;     (if (numberp (nth 1 entry))
;;         (let* ((sub (nth 1 entry))
;;                (close (nth 3 entry))
;;                (close-form `(or (looking-at ,close) (insert ,close)))
;;                (begin (match-beginning sub))
;;                (cib-error (format "Can't find completion for \"%s\""
;;                                   (match-string 0)))
;;                (list (funcall (nth 2 entry))))
;;           (cib-complete begin list nil close-form))
;;       (funcall (nth 1 entry)))))
;;
;; -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -
;;
;; `lisp-complete-symbol' from lisp.el, rewritten to use `cib-complete'.
;; Uses the DISPLAY-FILTER are to attatch " <f>" to functions.
;; The XEmacs version of that function could be written similarily.
;;
;; (defun lisp-complete-symbol ()
;;   "Perform completion on Lisp symbol preceding point."
;;   (interactive)
;;   (let* ((end (point))
;;          (buffer-syntax (syntax-table))
;;          (beg (unwind-protect
;;                   (save-excursion
;;                     (set-syntax-table emacs-lisp-mode-syntax-table)
;;                     (backward-sexp 1)
;;                     (while (= (char-syntax (following-char)) ?\')
;;                       (forward-char 1))
;;                     (point))
;;                 (set-syntax-table buffer-syntax)))
;;          (predicate
;;           (if (eq (char-after (1- beg)) ?\()
;;               'fboundp
;;             (function (lambda (sym)
;;                         (or (boundp sym) (fboundp sym)
;;                             (symbol-plist sym))))))
;;          (display-filter
;;           (if (eq predicate 'fboundp)
;;               nil
;;             (function (lambda (list)
;;                         (mapcar (lambda (x) (if (fboundp (intern x))
;;                                                 (list x " <f>")
;;                                               x))
;;                                 list)))))
;;          (completion-fixup-function
;;           (function (lambda ()
;;                       (if (save-excursion
;;                             (goto-char (max (point-min) (- (point) 4)))
;;                             (looking-at " <f>"))
;;                           (forward-char -4))))))
;;     (cib-complete beg obarray predicate nil display-filter)))
;;
;;---------------------------------------------------------------------------
;;
;; Bugs:
;;
;; - Maybe it would be cleaner to use `advice' to install the wrapper
;;   around the `choose-completon' functions for Emacs.  Right now we
;;   replace the keymap in the completions buffer with our own - kind
;;   of a hack.  The XEmacs interface is OK the way it is.
;;
;;---------------------------------------------------------------------------

;;; Code:

(eval-when-compile (require 'cl))

;; Public variables.  Lisp programmers may want to bind some of these
;; around the call to `cib-complete'.  See also `completion-ignore-case'.

(defvar cib-restore-window-configuration t
  "Non-nil means, try to restore window configuration after completion.")

(defvar cib-sort-completions nil
  "Non-nil means, sort completions before displaying.
Set this when you expect long completion list and TABLE is not sorted.")

(defvar cib-uniquify-completions nil
  "Non-nil means, remove double entries in completion list before displaying.
Set this only if the completion table contains double entries.")

(defvar cib-adaptive-case nil
  "*Non-nil means, the case of completions will be derived from context.
A lower-case string will be completed in lower case.  For any other string
the case of the completion will be as in the completion table.
When this variable is nil, the completion table casing always applies.
It is only useful to set this variable when `completion-ignore-case'
is also non-nil.")

(defvar cib-error "Can't find completion for \"%s\""
  "Format for error message when no completions are found.")

;; Internal variables, and the code.

(defconst cib-mark (make-marker)
  "The marker pointing to the beginning of the completion which
changed the window configuration.")

(defvar cib-begin nil
  "The most recent value of begin.")

(defvar cib-ignore-case nil
  "The value of `completion-ignore-case' when `cib-complete' was last called.")

(defvar cib-success-form nil
  "The value of the FINAL parameter to the last `cib-complete' call.")

(defvar cib-window-configuration nil
  "Window configuration before `cib-complete' last displayed *Completions*.")

;;;###autoload
(defun cib-complete (part table &optional predicate final
                          display-filter message
                          &rest args)
  "Complete PART right here in the buffer at point.
PART is the string to complete.  It must be a buffer substring ending
at point, or the buffer position where the string starts.
TABLE lists the completions.  It can be an alist, an obarray or a function,
as usual.  See `try-completion' and `all-completions'.
PREDICATE is called with each possible completion and should return t
if the item is acceptable.

After a successful completion, FINAL will executed:  A string will be
inserted, a list evaluated and a symbol have its function binding called.

Before displaying a list of possible completions, the list is processed
through DISPLAY-FILTER.  After displaying the list, MESSAGE will be echoed.

Any remaining ARGS will be passed on to `display-completion-list'.

The function respects the setting of `completion-ignore-case'.  See also
the variables `cib-adaptive-case', `cib-sort-completions', and
`cib-uniquify-completions'.

After a successful completion, the *Completions* window is removed and
the old window configuration restored."

  (if (and (get-buffer-window "*Completions*" 'visible)
           (eq (car-safe last-command) 'cib-display-completion-list))
      ;; Scroll the completions window
      (progn
        (setq this-command last-command)
        (cib-scroll (cdr-safe last-command)))

    (setq cib-ignore-case completion-ignore-case ; remember for callback
          cib-success-form final)                ; remember for hook

    ;; Work on the completion
    (if (integerp part) (setq part (buffer-substring part (point))))
    (let* ((beg (- (point) (length part)))
           (down (and cib-adaptive-case
                      (not (string= "" part))
                      (equal part (downcase part))))
           (fold (and completion-ignore-case (not down)))
           completion dcompletion all)
      (setq cib-begin beg
            completion (try-completion part table predicate)
            dcompletion (if (stringp completion) (downcase completion)))
      (cond
       ((null completion)
        (error "Can't find completion for \"%s\"" part))
       ((and (not (equal (downcase part) dcompletion))
             (not (eq t completion)))
        ;; Insert a partial completion
        (backward-delete-char (length part))
        (insert (if down dcompletion completion))
        (if (cib-unique completion table predicate)
            (cib-after-success beg)))
       ((cib-unique completion table predicate)
        (cib-after-success beg)
        (message "%s is complete" part))
       (t
        (message "Making completion list...")
        (setq all (or all (all-completions part table predicate))
              ;; complete means here: complete but not unique
              complete (= (length part) (apply 'min (mapcar 'length all))))
        (if down
            (setq all (mapcar 'downcase all)))
        (if cib-uniquify-completions
            (setq all (cib-uniquify-string-list all fold)))
        (if cib-sort-completions
            (setq all (cib-sort-string-list all fold)))
        (if display-filter
            (setq all (funcall display-filter all)))
        (apply 'cib-display-completion-list all beg complete message args))))))

(defun cib-unique (completion table predicate)
  "Is COMPLETION eq t, or a unique completion in TABLE/PREDICATE?"
  (or (eq t completion)
      (eq t (try-completion completion table predicate))
      (and cib-uniquify-completions
           (= 1 (length (cib-uniquify-string-list
                         (all-completions completion table predicate)
                         completion-ignore-case))))))

(defun cib-uniquify-string-list (list &optional fold-case)
  "Uniquify LIST of strings.  FOLD-CASE means to fold case for comparisons."
  (let (nlist seen x dx)
    (if fold-case
        (while list
          (setq x (pop list) dx (downcase x))
          (unless (member dx seen)
            (push x nlist)
            (push dx seen)))
      (while list
        (or (member (setq x (pop list)) nlist)
            (push x nlist))))
    (nreverse nlist)))

(defun cib-sort-string-list (list &optional fold-case)
  "Sort LIST of strings.  FOLD-CASE means to fold case for comparisons."
  (sort list (if fold-case
                 (function (lambda (a b) (string< (downcase a) (downcase b))))
               'string<)))

(defun cib-scroll (&optional complete)
  "Scroll the completion window."
  (let ((cwin (get-buffer-window "*Completions*" 'visible))
        (win (selected-window)))
    (unwind-protect
        (progn
          (select-window cwin)
          (condition-case nil
              (scroll-up)
            (error (if complete
                       (progn
                         (select-window win)
                         (cib-after-success cib-begin))
                     (set-window-start cwin (point-min))))))
      (select-window win))))

(defun cib-display-completion-list (list beg complete &optional message)
  "Display the completions in LIST and echo MESSAGE."
  (unless (and (get-buffer-window "*Completions*")
               (cib-local-value 'cib-completion-p "*Completions*"))
    ;; No cib *Completions* buffer visible yet - store window configuration
    (move-marker cib-mark beg)
    (setq cib-window-configuration (current-window-configuration)))

  (if (featurep 'xemacs)
      (cib-display-completion-list-xemacs list)
    (cib-display-completion-list-emacs list))

  ;; Store a special value in `this-command'.  When `cib-complete'
  ;; finds this in `last-command', it will scroll the *Completions* buffer.
  (setq this-command (cons 'cib-display-completion-list complete))

  ;; Mark the completions buffer as created by cib
  (cib-set-local 'cib-completion-p t "*Completions*")

  (message (or message "Making completion list...done")))

(defun cib-choose (function &rest args)
  "Call FUNCTION with ARGS as a wrapped completion chooser."
  (let ((completion-ignore-case cib-ignore-case))
    (apply function args))
  (cib-after-success 'force))

(defun cib-after-success (verify)
  "Restore window configuration and run the hook."
  (if (or (eq verify 'force)                                    ; force
          (and
           (get-buffer-window "*Completions*")                  ; visible
           (cib-local-value 'cib-completion-p "*Completions*")  ; cib-buffer
           (eq (marker-buffer cib-mark) (current-buffer))       ; buffer OK
           (equal (marker-position cib-mark) verify)))          ; pos OK
      (cib-restore-window-configuration))
  (move-marker cib-mark nil)
  (setq cib-window-configuration nil)
  (cond ((stringp cib-success-form) (insert cib-success-form))
        ((consp cib-success-form) (eval cib-success-form))
        ((and (symbolp cib-success-form) (fboundp cib-success-form))
         (funcall cib-success-form)))
  (setq cib-success-form nil))

(defun cib-restore-window-configuration ()
  "Restore the window configuration before cib-complete displayed completions."
  (interactive)
  (if (and cib-restore-window-configuration
           cib-window-configuration)
      (set-window-configuration cib-window-configuration)))

(defun cib-set-local (var value &optional buffer)
  "Set the buffer-local value of VAR in BUFFER to VALUE."
  (save-excursion
    (set-buffer (or buffer (current-buffer)))
    (set (make-local-variable var) value)))

(defun cib-local-value (var &optional buffer)
  "Return the value of VAR in BUFFER, but only if VAR is local to BUFFER."
  (save-excursion
    (set-buffer (or buffer (current-buffer)))
    (and (local-variable-p var (current-buffer))
         (symbol-value var))))

;; In XEmacs, we use :activate-callback to install the wrapper

(defun cib-display-completion-list-xemacs (list)
  (with-output-to-temp-buffer "*Completions*"
    (display-completion-list list :activate-callback
                             'cib-default-choose-completion)))

(defun cib-default-choose-completion (&rest args)
  "Execute `default-choose-completion' and run the success hook."
  (apply 'cib-choose 'default-choose-completion args))

;; In Emacs we replace the keymap in the *Completions* buffer

(defvar cib-completion-map nil
  "Keymap for completion-list-mode with cib-complete.")

(defun cib-display-completion-list-emacs (list)
  "Display completion list and install the choose wrappers."
  (with-output-to-temp-buffer "*Completions*"
    (display-completion-list list))
  (save-excursion
    (set-buffer "*Completions*")
    (use-local-map
     (or cib-completion-map
         (setq cib-completion-map
               (cib-make-modified-completion-map (current-local-map)))))))

(defun cib-make-modified-completion-map (old-map)
  "Replace `choose-completion' and `mouse-choose-completion' in OLD-MAP."
  (let ((new-map (copy-keymap old-map)))
    (substitute-key-definition
     'choose-completion 'cib-choose-completion new-map)
    (substitute-key-definition
     'mouse-choose-completion 'cib-mouse-choose-completion new-map)
    new-map))

(defun cib-choose-completion (&rest args)
  "Choose the completion that point is in or next to."
  (interactive)
  (apply 'cib-choose 'choose-completion args))

(defun cib-mouse-choose-completion (&rest args)
  "Click on an alternative in the `*Completions*' buffer to choose it."
  (interactive "e")
  (apply 'cib-choose 'mouse-choose-completion args))

;;; cib.el ends here
