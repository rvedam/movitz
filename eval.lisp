;;;;------------------------------------------------------------------
;;;; 
;;;;    Copyright (C) 20012000, 2002-2004,
;;;;    Department of Computer Science, University of Troms�, Norway
;;;; 
;;;; Filename:      eval.lisp
;;;; Description:   
;;;; Author:        Frode Vatvedt Fjeld <frodef@acm.org>
;;;; Created at:    Thu Nov  2 17:45:05 2000
;;;; Distribution:  See the accompanying file COPYING.
;;;;                
;;;; $Id: eval.lisp,v 1.1 2004/01/13 11:04:59 ffjeld Exp $
;;;;                
;;;;------------------------------------------------------------------

(in-package movitz)

(defun in-package-form-p (form)
  (and (consp form)
       (string= '#:in-package (car form))))

(defun require-form-p (form)
  (and (consp form)
       (string= '#:require (car form))))

(defun provide-form-p (form)
  (and (consp form)
       (string= '#:provide (car form))))

(defun movitz-module-path (require-form)
  "Given a require form, return the path of the file that is expected ~
   to provide that module."
  (let ((module (second require-form)))
    (concatenate 'string
      "losp/"
      (or (third require-form)
	  (concatenate 'string
	    (string-downcase (symbol-name module))
	    ".lisp")))))

(defun movitzify-package-name (name)
  (let ((name (string name)))
    (if (member name '("cl" "common-lisp" "mop")
		:test #'string-equal)
	(concatenate 'string (string '#:muerte.) name)
      name)))

(defmacro with-retries-until-true ((name format-control &rest format-arguments) &body body)
  `(do () (nil)
     (with-simple-restart (,name ,format-control ,@format-arguments)
       (return (progn ,@body)))))

(defun quote-form-p (x)
  (and (consp x)
       (or (eq 'cl:quote (first x))
	   (eq 'muerte.cl::quote (first x)))
       t))

(defun movitz-constantp (form &optional (environment nil))
  (let ((form (translate-program form :cl :muerte.cl)))
    (typecase form
      (boolean t)
      (number t)
      (keyword t)
      (character t)
      (symbol (or (movitz-env-get form 'constantp nil environment)
		  (typep (movitz-binding form environment) 'constant-object-binding)))
      (cons (case (car form)
	      ((muerte.cl::quote) t)
	      (muerte.cl::not (movitz-constantp (second form))))))))


(defun isconst (x)
  (or (integerp x)
      (stringp x)
      (eq t x)
      (eq nil x)
      (quote-form-p x)))

(defun eval-form (&rest args)
  (apply 'movitz-eval args))

(defun movitz-eval (form &optional env top-level-p)
  "3.1.2.1 Form Evaluation"
  (let ((form (translate-program form :cl :muerte.cl)))
    (typecase form
      (symbol (eval-symbol form env top-level-p))
      (cons   (eval-cons form env top-level-p))
      (t      (eval-self-evaluating form env top-level-p)))))

(defun eval-form-or-error (form env error-value)
  (handler-case (eval-form form env)
    (error () error-value)))

(defun eval-symbol (form env top-level-p)
  "3.1.2.1.1 Symbols as Forms"
  (declare (ignore top-level-p))
  (cond
   ((typep (movitz-binding form env) 'constant-object-binding)
    (movitz-print (constant-object (movitz-binding form env))))
   ((movitz-constantp form env)
    (symbol-value form))
;;;   ((movitz-lexical-binding form env)
;;;    (eval-lexical-variable form env top-level-p))
   (t (error "Don't know how to eval symbol-form ~S" form))))

(defun eval-self-evaluating (form env top-level-p)
  "3.1.2.1.3 Self-Evaluating Objects"
  (declare (ignore env top-level-p))
  form)

(defun eval-cons (form env top-level-p)
  "3.1.2.1.2 Conses as Forms"
  (let ((operator (car form)))
    (declare (ignore operator))
    (cond
     ((movitz-constantp form env)
      (eval-constant-compound form env top-level-p))
;;;     ((lambda-form-p form)
;;;      (eval-lambda-form form env top-level-p))
;;;     ((symbolp operator)
;;;      (cond
;;;       ((movitz-special-operator-p operator)
;;;	(eval-special-operator form env top-level-p))
;;;       ((movitz-macro-function operator env)
;;;	(eval-macro-form form env top-level-p))
;;;       (t (eval-apply-symbol form env top-level-p))))
     (t (case (car form)
	  (muerte.cl::function
	   (if (symbolp (second form))
	       (movitz-env-symbol-function (second form) env)
	     (error "Don't know how to eval function form ~A." form)))
	  (t (error "Don't know how to eval compound form ~A" form)))))))

(defun eval-constant-compound (form env top-level-p)
  (case (car form)
   ((cl:quote muerte.cl::quote)
    (eval-self-evaluating (second form) env top-level-p))
   (muerte.cl::not
    (not (eval-form (second form) env nil)))
   (t (error "Don't know how to compile constant compound form ~A" form))))
