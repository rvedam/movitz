;;;;------------------------------------------------------------------
;;;; 
;;;;    Copyright (C) 2001-2004, 
;;;;    Department of Computer Science, University of Troms�, Norway.
;;;; 
;;;;    For distribution policy, see the accompanying file COPYING.
;;;; 
;;;; Filename:      cpu-id.lisp
;;;; Description:   
;;;; Author:        Frode Vatvedt Fjeld <frodef@acm.org>
;;;; Created at:    Mon Apr 15 22:47:13 2002
;;;;                
;;;; $Id: cpu-id.lisp,v 1.1 2004/01/13 11:05:05 ffjeld Exp $
;;;;                
;;;;------------------------------------------------------------------

(provide :muerte/cpu-id)

(in-package muerte)

(defun write-cpu-vendor-string (&optional (stream *standard-output*))
  (multiple-value-call (lambda (stream &rest bytes)
			 (declare (dynamic-extent bytes))
			 (dolist (b (nthcdr 4 bytes))
			   (write (code-char b) :stream stream :escape nil)))
    stream
    (cpu-id)))

(defun cpu-486-class-p ()
  "Is the CPU 486 class or better?"
  (with-inline-assembly (:returns :boolean-zf=0)
    (:testl :edi :edi)			; clear ZF
    (:pushfl)				; push original EFLAGS
    (:popl :eax)			; get original EFLAGS
    (:movl :eax :ecx)			; save original EFLAGS
    (:xorl #x40000 :eax)		; flip AC bit in EFLAGS
    (:pushl :eax)			; save new EFLAGS value on stack
    (:popfl)				; replace current EFLAGS value
    (:pushfl)				; get new EFLAGS
    (:popl :eax)			; store new EFLAGS in EAX
    (:xorl :ecx :eax)			; can't toggle AC bit, processor=80386, ZF=1
    (:jz 'end_cpu_type)			; jump if 80386 processor
    (:pushl :ecx)
    (:movl :edi :ecx)
    (:movl :edi :eax)
    (:popfl)				; restore AC bit in EFLAGS first
    end_cpu_type))

(defun cpu-586-class-p ()
  "Is the CPU 586 class or better? This must be true in order to run cpu-id."
  (and (cpu-486-class-p)
       (with-inline-assembly (:returns :boolean-zf=0)
	 (:pushfl)
	 (:popl :ecx)
	 (:movl :ecx :eax)		; get original EFLAGS
	 (:xorl #x200000 :eax)		; flip ID bit in EFLAGS
	 (:pushl :eax)			; save new EFLAGS value on stack
	 (:popfl)			; replace current EFLAGS value
	 (:pushfl)			; get new EFLAGS
	 (:popl :eax)			; store new EFLAGS in :EAX
	 (:xorl :ecx :eax)		; can't toggle ID bit, => ZF=1
	 (:movl :edi :ecx)
	 (:movl :edi :eax))))

(defun cpu-signature ()
  "Return the CPU's family, type, model number, and stepping."
  (cond
   ((not (cpu-486-class-p))
    :386)
   ((not (cpu-586-class-p))
    :486)
   ((= 0 (cpu-id 0))
    :586)
   (t (multiple-value-bind (b0 b1)
	  (cpu-id 1)
	(values (case (ldb (byte 4 0) b1) ; family code
		  (4 :486)
		  (5 :586)
		  (6 :686)
		  (7 :786))
		(case (ldb (byte 2 4) b1) ; processor type
		  (#b00 :original)
		  (#b01 :over-drive)
		  (#b10 :dual)
		  (#b11 :reserved-type))
		(ldb (byte 4 4) b0)	; model number
		(ldb (byte 4 0) b0)))))) ; stepping
		
(defun cpu-id (&optional (c0 0) (c1 0) (c2 0) (c3 0))
  "Run assembly instruction CPUID with EAX initialzed to the (little-endian)
octets in c0, c1, c2, and c3. The 16 values returned represent the individual
octets of EAX, EBX, EDX, and ECX, also in little-endian order."
  (when (cpu-586-class-p)
    (with-inline-assembly (:returns :multiple-values) pack octets
      ;; c0-c1-c2-c3 into eax..
      (:compile-form (:result-mode :eax) c3)
      (:compile-form (:result-mode :ecx) c2)
      (:shll 8 :eax)
      (:xorl :ecx :eax)
      (:compile-form (:result-mode :ecx) c1)
      (:shll 8 :eax)
      (:xorl :ecx :eax)
      (:compile-form (:result-mode :ecx) c0)
      (:shll #.(cl:- 8 movitz::+movitz-fixnum-shift+) :eax)
      (:shrl #.movitz::+movitz-fixnum-shift+ :ecx)
      (:xorl :ecx :eax)
      ;; do actual cpu-id instruction
      (:cpuid)
      ;; unpack eax, ebx, edx, ecx to 16 values..
      (:call '(:sub-program (unpack-eax)
	       (:popl (:esp -20))	; return address
	       (:pushl :eax)
	       (:andl #x000000ff (:esp))
	       (:shll #.movitz::+movitz-fixnum-shift+ (:esp))
	       (:pushl :eax)
	       (:andl #x0000ff00 (:esp))
	       (:shrl #.(cl:- 8 movitz::+movitz-fixnum-shift+) (:esp))
	       (:pushl :eax)
	       (:andl #x00ff0000 (:esp))
	       (:shrl #.(cl:- 16 movitz::+movitz-fixnum-shift+) (:esp))
	       (:pushl :eax)
	       (:andl #xff000000 (:esp))
	       (:shrl #.(cl:- 24 movitz::+movitz-fixnum-shift+) (:esp))
	       (:subl 4 :esp)
	       (:ret)))
      (:movl :ebx :eax)
      (:call 'unpack-eax)
      (:movl :edx :eax)
      (:call 'unpack-eax)
      (:movl :ecx :eax)
      (:call 'unpack-eax)
      ;; return multiple-values (16 values, actually..)
      (:movl (:esp #.(cl:* 4 (cl:- 16 1))) :eax)
      (:movl (:esp #.(cl:* 4 (cl:- 16 2))) :ebx)
      ;; (:leal (:esp #.(cl:* 4 (cl:- 16 3))) :edx)
      (:movb 16 :cl)
      (:load-constant muerte.cl::values :edx)
      (:movl (:edx #.(bt:slot-offset 'movitz::movitz-symbol 'movitz::function-value))
	     :esi)			; load new funobj from symbol into ESI
      (:call (:esi #.(bt:slot-offset 'movitz::movitz-funobj 'movitz::code-vector))))))


(defconstant +cpu-id-feature-map+
    #(:fpu				; FPU on chip
      :vme				; Virtual 8086 Mode Enhancement
      :de				; Debugging Extensions
      :pse				; Page Size Extensions
      :tsc				; Time Stamp Counter
      :msr				; RDMSR and WRMSR Support
      :pae				; Physical Address Extensions
      :mce				; Machine Check Exception
      :cxs				; CMPXCHG8B Instruction
      :apic				; APIC on chip
      :reserved-bit-10
      :sep				; SYSENTER and SYSEXIT
      :mtrr				; Memory Type Range Req.
      :pge				; PTE Global Bit
      :mca				; Machine Check Architecture
      :cmov				; Conditional mov/cmp instructions
      :pat				; Page Attribute Table
      :pse-36				; 32-bit Page Size Extension
      :psn				; Processor Serial Number
      :clfsh				; CLFLUSH instruction is supported
      :reserved-bit-20
      :ds				; Debug Store 
      :acpi				; Thermal Monitor and Software Controlled Clock Facilities
      :mmx				; Intel MMX Technology
      :fxsr				; FXSAVE and FXRSTOR instructions
      :sse				; Processor supports SSE extensions
      :sse2				; Processor supports SSE2 extensions
      :ss				; Self Snoop
      :htt				; Hyper-Threading Technology
      :tm				; Thermal Monitor
      :reserved-bit-30										   
      :pbe))				; Pending Break Enable

(defvar *cpu-features*)

(defun find-cpu-features ()
  (let ((cpu-id-max-input (cpu-id 0)))
    (when (and cpu-id-max-input
	       (>= cpu-id-max-input 1))
      (multiple-value-bind (a0 a1 a2 a3 b0 b1 b2 b3 d0 d1)
	  (cpu-id 1)
	(declare (ignore a0 a1 a2 a3 b0 b1 b2 b3))
	(let ((x (dpb d1 (byte 8 8) d0)))
	  (loop for i from 0 to 31
	      when (logbitp i x)
	      collect (elt +cpu-id-feature-map+ i)))))))

(defun cpu-featurep (feature)
  (member feature *cpu-features*))

(defun read-time-stamp-counter ()
  "Read the 64-bit i686 time-stamp counter.
Returned as three values: low 24 bits, mid 24 bits, high 16 bits.
This is an illegal instruction on lesser CPUs."
  (with-inline-assembly (:returns :multiple-values)
    (:std)
    (:rdtsc)				; Read Time-Stamp Counter into EDX:EAX
    ;; Load upper 16 bits (of EDX) as ternary value.
    (:movl :edx :ebx)
    (:andl #xffff0000 :edx)
    (:shll #.(cl:- 16 movitz::+movitz-fixnum-shift+) :edx)
    ((:fs-override) :movl :edx (:edi #.(movitz::global-constant-offset 'values)))
    ;; Bits 24-47 as fixnum into EBX
    (:shldl #.(cl:+ 8 movitz::+movitz-fixnum-shift+) :eax :ebx)
    (:andl #.(cl:* #x00ffffff movitz::+movitz-fixnum-factor+) :ebx)
    ;; Bits 0-23 as fixnum into EAX
    (:andl #x00ffffff :eax)
    (:shll #.movitz::+movitz-fixnum-shift+ :eax)
    (:cld)
    ;; Return 3 values
    ((:fs-override) :movl 1 (:edi #.(movitz::global-constant-offset 'num-values)))
    (:movl 3 :ecx)
    (:stc)))

(defun clear-time-stamp-counter ()
  "Reset the i686 time-stamp-counter.
This is an illegal instruction on lesser CPUs, and a no-op on some, such as bochs."
  (with-inline-assembly (:returns :nothing)
    (:xorl :eax :eax)
    (:xorl :edx :edx)			; not really used, according to Vol. II: sec. 10.5.
    (:movl #x10 :ecx)
    (:wrmsr)))

(define-compiler-macro eflags ()
  `(with-inline-assembly (:returns :register)
     (:pushfl)
     (:popl (:result-register))
     (:movl (:result-register) (#x1000))
     (:shll 2 (:result-register))))
;;;     (:popl :ecx)
;;;     (:leal ((:ecx ,movitz::+movitz-fixnum-factor+) :edi ,(movitz::edi-offset))
;;;	    (:result-register))))

(defun eflags ()
  (eflags))

(define-compiler-macro (setf eflags) (value)
  `(with-inline-assembly (:returns :register)
     (:compile-form (:result-mode :ecx) ,value)
     (:shrl ,movitz::+movitz-fixnum-shift+ :ecx)
     (:pushl :ecx)
     (:popfl)
     (:leal ((:ecx ,movitz::+movitz-fixnum-factor+) :edi ,(movitz::edi-offset))
	    (:result-register))))

(defun (setf eflags) (value)
  (setf (eflags) value))

(defun load-idt (idt-vector)
  (assert (= #.(bt:enum-value 'movitz::movitz-vector-element-type :u32)
	     (muerte:vector-element-type idt-vector)))
  (let ((limit (- (* (length idt-vector) 4)
		  1)))
    ;; (format t "Load-idt: ~Z / ~D~%" idt-vector limit)
    (with-inline-assembly (:returns :nothing)
      (:subl 8 :esp)
      (:movl :esp :eax)
      (:compile-form (:result-mode :ebx) limit)
      (:shrl #.movitz::+movitz-fixnum-shift+ :ebx)
      (:movw :bx (:eax 2))
      (:compile-form (:result-mode :ebx) idt-vector)
      (:addl 2 :ebx)
      (:globally (:addl (:edi (:edi-offset physical-address-offset)) :ebx))
      (:movl :ebx (:eax 4))
      (:lidt (:eax 2))
      (:addl 8 :esp))))
