;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Convert a chess game to/from PGN notation
;;
;; $Revision$

(require 'chess-game)
(require 'chess-pos)
(require 'chess-algebraic)
(require 'chess-fen)

(defvar chess-pgn-fill-column 60)

(chess-message-catalog 'english
  '((pgn-read-error  . "Error reading move: %s")
    (pgn-parse-error . "Error parsing PGN syntax")))

(defun chess-pgn-read-plies (game position &optional top-level)
  (let ((plies (list t)) prevpos done)
    (while (not (or done (eobp)))
      (cond
       ((looking-at "[1-9][0-9]*\\.[. ]*")
	(goto-char (match-end 0)))
       ((looking-at chess-algebraic-regexp)
	(goto-char (match-end 0))
	(setq prevpos position)
	(let* ((move (match-string 0))
	       (ply (chess-algebraic-to-ply position (match-string 0))))
	  (unless ply
	    (chess-error 'pgn-read-error move))
	  (setq position (chess-ply-next-pos ply))
	  (nconc plies (list ply))))
       ((and top-level
	     (looking-at "\\(\\*\\|1-0\\|0-1\\|1/2-1/2\\)"))
	(goto-char (match-end 0))
	(chess-game-set-tag game "Result" (match-string-no-properties 0))
	(nconc plies (list (chess-ply-create
			    (chess-ply-next-pos (car (last plies))))))
	(setq done t))
       ((looking-at "{")
	(forward-char)
	(let ((begin (point)))
	  (search-forward "}")
	  (forward-char)
	  (chess-pos-add-annotation prevpos (buffer-substring-no-properties
					     begin (- (point) 2)))))
       ((looking-at "(")
	(forward-char)
	(skip-chars-forward " \t\n")
	(chess-pos-add-annotation
	 prevpos (chess-pgn-read-plies game (chess-pos-copy prevpos))))
       ((and (not top-level)
	     (looking-at ")"))
	(forward-char)
	(setq done t))
       (t (chess-error 'pgn-parse-error)))
      (skip-chars-forward " \t\n"))
    (cdr plies)))

(defun chess-pgn-to-game (&optional string)
  "Convert PGN notation at point into a chess game."
  (if string
      (with-temp-buffer
	(insert string)
	(chess-parse-pgn))
    (chess-parse-pgn)))

(defun chess-parse-pgn ()
  (when (search-forward "[" nil t)
    (let ((game (chess-game-create)))
      (setcar game nil)
      (backward-char)
      (while (looking-at "^\\s-*\\[\\(\\S-+\\)\\s-+\\(\".+?\"\\)\\][ \t\n]+")
	(chess-game-set-tag game (match-string-no-properties 1)
			    (read (match-string-no-properties 2)))
	(goto-char (match-end 0)))
      (let ((fen (chess-game-tag game "FEN")))
	(chess-game-set-plies
	 game (or (chess-pgn-read-plies
		   game (if fen
			    (chess-fen-to-pos fen)
			  (chess-pos-copy chess-starting-position)) t)
		  ;; set the starting position to the FEN string
		  (list (chess-ply-create (if fen
					      (chess-fen-to-pos fen)
					    chess-starting-position))))))
      game)))

(defun chess-pgn-insert-annotations (game index ply)
  (dolist (ann (chess-pos-annotations (chess-ply-pos ply)))
    (if (stringp ann)
	(insert "\n{" ann "}")
      (assert (listp ann))
      (chess-pgn-insert-plies game index ann))))

(defun chess-pgn-insert-plies (game index plies &optional
				     for-black indented no-annotations)
  "NYI: Still have to implement INDENTED argument."
  (while plies
    (unless for-black
      (when (chess-ply-changes (car plies))
	(if (> (current-column) chess-pgn-fill-column)
	    (insert ?\n))
	(insert (format "%d. %s" index (chess-ply-to-algebraic (car plies))))
	(unless no-annotations
	  (chess-pgn-insert-annotations game index (car plies))))
      (setq plies (cdr plies) index (1+ index)))
    (when plies
      (when (chess-ply-changes (car plies))
	(when for-black
	  (if (> (current-column) chess-pgn-fill-column)
	      (insert ?\n))
	  (insert (format "%d. ..." index))
	  (setq for-black nil))
	(insert (format " %s" (chess-ply-to-algebraic (car plies))))
	(unless no-annotations
	  (chess-pgn-insert-annotations game index (car plies))))
      (setq plies (cdr plies)))
    (if plies
	(insert ? ))))

(defvar chess-pgn-tag-order
  '("Event" "Site" "Date" "Round"
    "White" "WhiteElo" "Black" "BlackElo"
    "Result" "TimeControl"))

(defun chess-game-to-pgn (game &optional indented to-string)
  "Convert a chess GAME to PGN notation.
If INDENTED is non-nil, indent the move texts."
  (if to-string
      (with-temp-buffer
	(chess-insert-pgn game indented)
	(buffer-string))
    (chess-insert-pgn game indented)))

(defun chess-insert-pgn (game &optional indented)
  (let ((fen (chess-game-tag game "FEN"))
	(first-pos (chess-ply-pos (chess-game-ply game 0))))
    (when (and fen (not (equal fen (chess-pos-to-fen first-pos))))
      (chess-game-del-tag game "FEN")
      (setq fen nil))
    (if (and (not fen)
	     (not (equal chess-starting-position first-pos)))
	(chess-game-set-tag game "FEN" (chess-pos-to-fen first-pos))))
  (dolist (tag (sort (copy-alist (chess-game-tags game))
		     (function
		      (lambda (left right)
			(setq left (car left) right (car right))
			(let ((l-idx (position left chess-pgn-tag-order
					       :test 'equal))
			      (r-idx (position right chess-pgn-tag-order
					       :test 'equal)))
			  (cond
			   ((and l-idx (not r-idx)) t)
			   ((and (not l-idx) r-idx) nil)
			   ((and l-idx r-idx) (< l-idx r-idx))
			   (t (string-lessp left right))))))))
    (insert (format "[%s \"%s\"]\n" (car tag) (cdr tag))))
  (insert ?\n)
  (let ((begin (point)))
    (chess-pgn-insert-plies game 1 (chess-game-plies game))
    (insert (or (chess-game-tag game "Result") "*") ?\n)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; PGN-mode for editing and browsing PGN files.
;;

;; (defvar chess-pgn-mode-map
;;   (let ((map (make-sparse-keymap)))
;;     (define-key map [??] 'describe-mode)
;;     (define-key map [?T] 'text-mode)
;;     (define-key map [return] 'chess-pgn-move)
;;     (define-key map [(control ?m)] 'chess-pgn-move)
;;     map)
;;   "Keymap used by Chess PGN mode.")
;;
;; (define-derived-mode chess-pgn-mode text-mode "Chess"
;;   "A mode for editing Chess PGN files.")
;;
;; (defun chess-pgn-move ()
;;   "Make a move from a PGN buffer."
;;   (interactive)
;;   (let ((end (point))
;;	coords move)
;;     (save-excursion
;;       (skip-chars-backward "^ ")
;;       (setq move (buffer-substring-no-properties (point) end)
;;	    coords (chess-algebraic-to-ply chess-display-position move))
;;       ;; it will just get reinserted again
;;       (delete-region (point) end)))
;;
;; (defun chess-pgn-insert-move (move &optional color sequence)
;;   "Insert an algebraic move description into a PGN buffer.
;; If move is the symbol `wait', it means reflect that we are now waiting
;; for the opponent to make his move.  If move is the symbol `ready', it
;; means our opponent is now waiting for us to move our move.  Otherwise,
;; move should be a string representing the algebraic notation for the
;; move."
;;   (while (= (char-before) ?.)
;;     (delete-backward-char 1))
;;   (cond
;;    ((eq move 'wait)
;;     (insert "..."))
;;    ((eq move 'ready) t)
;;    (t
;;     (if (= (char-syntax (char-before)) ? )
;;	(insert move))
;;     (if color
;;	(move-to-column 11 t)
;;       (insert ?\n (format "%d.  " (1+ sequence))))))
;;   (let ((wind (get-buffer-window (current-buffer))))
;;     (if wind
;;	(set-window-point wind (point)))))

(provide 'chess-pgn)

;;; chess-pgn.el ends here
