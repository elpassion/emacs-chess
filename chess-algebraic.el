;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Convert a ply to/from standard chess algebraic notation
;;
;; A thing to deal with in chess is algebraic move notation, such as
;; Nxf3+.  (I leave description of this notation to better manuals
;; than this).  This notation is a shorthand way of representing where
;; a piece is moving from and to, by specifying the piece is involved,
;; where it's going, and whether or not a capture or check is
;; involved.
;;
;; You can convert from algebraic notation to a ply (one pair in most
;; cases, but two for a castle) using the following function (NOTE:
;; POSITION determines which side is on move (by calling
;; `chess-pos-side-to-move')):
;;
;;    (chess-algebraic-to-ply POSITION STRING)
;;
;; The function also checks if a move is legal, and will raise an
;; error if not.
;;
;; To convert from a ply to algebraic notation, use:
;;
;;    (chess-ply-to-algebraic PLY)
;;
;; Castling is determined by the movement of both a king and a rook.
;;
;; Lastly, there is a regexp for quickly checking if a string is in
;; algebraic notation or not, or searching out algebraic strings in a
;; buffer:
;;
;;    chess-algebraic-regexp

;; $Revision$

(require 'chess-ply)

(defconst chess-algebraic-pieces-regexp "[RNBKQ]")

(defconst chess-algebraic-regexp
  (format (concat "\\("
		    "O-O\\(-O\\)?\\|"
		    "\\(%s?\\)"
		    "\\([a-h]?[1-8]?\\)"
		    "\\([x-]?\\)"
		    "\\([a-h][1-8]\\)"
		    "\\(=\\(%s\\)\\)?"
		  "\\)"
		  "\\([#+]\\)?")
	  chess-algebraic-pieces-regexp
	  chess-algebraic-pieces-regexp)
  "A regular expression that matches all possible algebraic moves.
This regexp handles both long and short form.")

(defconst chess-algebraic-regexp-entire
  (concat chess-algebraic-regexp "$"))

(defun chess-algebraic-to-ply (position move &optional trust)
  "Convert the algebraic notation MOVE for POSITION to a ply."
  (when (string-match chess-algebraic-regexp-entire move)
    (let ((color (chess-pos-side-to-move position))
	  (mate (match-string 9 move))
	  (piece (aref move 0))
	  changes ply)
      (if (eq piece ?O)
	  (let ((long (= (length (match-string 1 move)) 5)))
	    (if (chess-pos-can-castle position (if long (if color ?Q ?q)
						 (if color ?K ?k)))
		(setq changes (chess-ply-create-castle position long))))
	(let ((promotion (match-string 8 move)))
	  (setq changes
		(let ((source (match-string 4 move))
		      (target (chess-coord-to-index (match-string 6 move))))
		  (if (and source (= (length source) 2))
		      (list (chess-coord-to-index source) target)
		    (if (= (length source) 0)
			(setq source nil)
		      (setq source (aref source 0)))
		    (let (candidates which)
		      (unless (< piece ?a)
			(setq source piece piece ?P))
		      ;; we must use our knowledge of how pieces can
		      ;; move, to determine which piece is meant by the
		      ;; piece indicator
		      (if (setq candidates
				(chess-search-position position target
						       (if color piece
							 (downcase piece))))
			  (if (= (length candidates) 1)
			      (list (car candidates) target)
			    (if (null source)
				(error "Clarify piece to move by rank or file")
			      (while candidates
				(if (if (>= source ?a)
					(eq (chess-index-file (car candidates))
					    (- source ?a))
				      (eq (chess-index-rank (car candidates))
					  (- 7 (- source ?1))))
				    (setq which (car candidates)
					  candidates nil)
				  (setq candidates (cdr candidates))))
			      (if (null which)
				  (error "Could not determine which piece to use")
				(list which target))))
			(error "There are no candidate moves for '%s'"
			       move))))))
	  (if promotion
	      (nconc changes (list :promote (aref promotion 0))))))

      (when trust
	(if mate
	    (nconc changes (list (if (equal mate "#") :checkmate :check))))
	(nconc changes (list :valid)))

      (or ply (apply 'chess-ply-create position changes)))))

(defun chess-ply-to-algebraic (ply &optional long)
  "Convert the given PLY to algebraic notation.
If LONG is non-nil, render the move into long notation."
  (if (let ((source (chess-ply-source ply)))
	(or (null source) (symbolp source)))
      ""
    (or (and (chess-ply-has-keyword ply :castle) "O-O")
	(and (chess-ply-has-keyword ply :long-castle) "O-O-O")
	(let* ((pos (chess-ply-pos ply))
	       (from (chess-ply-source ply))
	       (to (chess-ply-target ply))
	       (from-piece (chess-pos-piece pos from))
	       (color (chess-pos-side-to-move pos))
	       (candidates (chess-search-position pos to from-piece))
	       (rank 0) (file 0)
	       (from-rank (/ from 8))
	       (from-file (mod from 8))
	       differentiator)
	  (when (> (length candidates) 1)
	    (dolist (candidate candidates)
	      (if (= (/ candidate 8) from-rank)
		  (setq rank (1+ rank)))
	      (if (= (mod candidate 8) from-file)
		  (setq file (1+ file))))
	    (cond
	     ((= file 1)
	      (setq differentiator (+ from-file ?a)))
	     ((= rank 1)
	      (setq differentiator (+ (- 7 from-rank) ?1)))
	     (t (error "Could not differentiate piece"))))
	  (concat
	   (unless (= (upcase from-piece) ?P)
	     (char-to-string (upcase from-piece)))
	   (if long
	       (chess-index-to-coord from)
	     (if differentiator
		 (char-to-string differentiator)
	       (if (and (not long) (= (upcase from-piece) ?P)
			(/= (chess-index-file from)
			    (chess-index-file to)))
		   (char-to-string (+ (chess-index-file from) ?a)))))
	   (if (/= ?  (chess-pos-piece pos to))
	       "x" (if long "-"))
	   (chess-index-to-coord to)
	   (let ((promote (memq :promote (chess-ply-changes ply))))
	     (if promote
		 (concat "=" (char-to-string
			      (upcase (cadr promote))))))
	   (if (chess-ply-has-keyword ply :check) "+"
	     (if (chess-ply-has-keyword ply :checkmate) "#")))))))

(provide 'chess-algebraic)

;;; chess-algebraic.el ends here
