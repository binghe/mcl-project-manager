;; -*- mode:lisp; -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; system:	P R O J E C T  M A N A G E R
;;
;; file: 	component-views.lisp
;; author: 	Adam Alpern
;; created: 	6/11/1995
;;
;; Please send comments, improvements, or whatever to aalpern@hampshire.edu.
;; If you redistribute this file, please keep this header intact, and
;; please send me any changes. I would like to know if you use this utility,
;; and if you find it useful.
;;
;;	Views for displaying defsystem components.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Revision History
;; ----------------
;; 02/04/96	- added expanded-icon to component-view, updated
;;		  draw methods.
;; 02/03/96	- added view-default-position for project-manager-window
;; 01/22/96	- added view-default-size for project-manager-window
;; 12/09/95     (David B. Lamkins)
;;              - Extension display for files and private files is now
;;                taken from the defsystem form, instead of being hardwired.
;;              - Long filenames are condensed and truncated so they don't
;;                overwrite the display of file size.  This is especially
;;                needed with private files, since defsystem includes the
;;                path in the component name.
;;              - File size display looks better: right justified, aligned
;;                vertically with the name, and comma separated.
;;              - Completely reworked highlighting.  It _finally_ does the
;;                right thing on color Macs with *project-manager-color-p*
;;                set to NIL.  Now *project-manager-color-p* controls only
;;                window background shading and the use of 3D buttons.
;; 12/05/95	- use (unless (window-color-p (view-window view))
;;            	   (#_TextMode #$hilitetransfermode)) to draw properly
;;		  in b/w. Set *projman-color-p* to nil to make a
;;		  b/w window, which will draw properly on a b/w screen
;; 		  (although the text in a non color-p window will still
;;		  draw in the hilit color on a color screen).
;; 11/29/95     Changes from David B. Lamkins incorporated:
;;		- Many cosmetic fixes: Do highlight changes on window activate
;;                and deactivate. Eliminate unsightly redrawing glitches on
;;                changing selected component. Highlight only text area (to
;;                improve appearance on B&W monitors.)  Display watch cursor
;;                while preparing component views following twist-down.  Use
;;                #_Delay for animation, rather than redrawing icon N times.
;;                Use new *PROJMAN-COLOR-P* variable.
;;		- added with-cursor to add-component-subviews
;;		- added view-activate-event-handler and view-deactivate-event-handler
;;		  for component-view
;;		- in draw-twist-down-animation and draw-twist-up-animation, use #_Delay
;;		  instead of drawing icon mulitple times
;;		- new rect r2 in view-draw-contents (component-view)
;;		- project-manager-window gets :color-p from *projman-color-p*
;; 11/10/95	- Thanks to Kai Zimmerman for pointing out and fixing
;;		  a bug in view-click-event-handler for component-view
;;		  that resulted in a stack overflow if you clicked in the
;;		  lock-region.
;;		- update my email address.
;; 07/21/95	- major rewrite. Uses list-views.lisp. Finally works.
;; 06/11/95	- File created
;;
;; TODO - file size for MCL 2.0.1, ditto for line-height
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#|
(declaim (optimize (speed 3) (safety 0) (compilation-speed 0) (space 0))
         (inline make-component-subviews select-component-view
                 deselect-component-view twist-region icon-region
                 name-region point-in-twist-region-p
                 point-in-icon-region-p point-in-name-region-p
                 has-sub-components))
|#

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; component-view classes
;;
;; Based on the possible component types:
;;	:defsystem, :system, :subsystem, :module, :file, or :private-file

(defclass component-view (list-view-mixin view)
  ((component :initarg :component :initform nil :accessor component)
   (icon      :initarg :icon      :initform nil :accessor icon)
   (expanded-icon :initarg :expanded-icon :initform nil
                  :accessor expanded-icon)
   (name      :initarg :name      :initform nil :accessor name)
   (path :initarg :path :initform nil :accessor path)
   (depth     :initarg :depth     :initform 1   :accessor depth)
   (has-sub-components :reader 	   has-sub-components
                       :allocation :class)
   (expanded-p :initarg :expanded-p :initform nil :accessor expanded-p)
   (selected-p :initarg :selected-p :initform nil :accessor selected-p))
  (:default-initargs :vsize 15 :view-font '("Geneva" 9 :plain)))

(defmethod print-object ((obj component-view) stream)
  (format stream "#<component-view ~a " (depth obj))
  (if (component obj)
    (format stream "(~a ~a)>"
            (make::component-type (component obj))
            (make::component-name (component obj)))
    (format stream ">")))

(defclass defsystem-component-view (component-view)
  ((has-sub-components :initform 	t))
  (:default-initargs :icon *pm-system-icon*
    :view-font '("Geneva" 9 :italic)))

(defclass system-component-view (component-view)
  ((has-sub-components :initform 	t))
  (:default-initargs :icon *pm-system-icon*))

(defclass subsystem-component-view (system-component-view)
  ((has-sub-components :initform 	t))
  (:default-initargs :icon *pm-subsystem-icon*
    :expanded-icon *pm-subsystem-open-icon*))

(defclass module-component-view (component-view)
  ((has-sub-components :initform 	t))
  (:default-initargs
    :icon *pm-folder-icon*
    :expanded-icon *pm-open-folder-icon*
    :view-font '("Geneva" 9 :bold)))

(defclass file-component-view (component-view)
  ((size :initarg :size :initform nil :accessor size)
   (has-sub-components :initform 	nil)
   (locked :initarg :locked :initform nil :accessor locked))
  (:default-initargs :icon *pm-lisp-icon*))

(defclass fasl-file-component-view (file-component-view)
  ((has-sub-components :initform 	nil))
  (:default-initargs :icon *pm-fasl-icon*))

(defclass private-file-component-view (file-component-view)
  ((has-sub-components :initform 	nil))
  (:default-initargs :icon *pm-file-icon*
    :view-font '("Geneva" 9 :plain)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun make-component-view (component &key
                                      (view-position #@(0 0))
                                      (depth 1)
                                      (h-size 200))
  (declare (optimize (speed 3) (safety 0)))
  (let ((view (make-one-component-view component :view-position view-position)))
    (setf (path view) (make::component-full-pathname component :source))
    (when depth (setf (depth view) depth))
    (set-view-size view h-size (list-view-vsize view))
    #+CCL-3(when (and (typep view 'file-component-view)
                      (probe-file (path view)))
             (setf (size view) (ccl::file-data-size (path view))))
    (when (typep view 'file-component-view)
      (if (probe-file (path view))
        (when (file-locked-p (path view))
          (setf (locked view) t))
        (setf (icon view) *pm-missing-icon*)))
    view))

(defun make-one-component-view (component &rest initargs)
  (declare (optimize (speed 3) (safety 0)))
  (let ((name (make::component-name component))
        (extension (make::component-source-extension component)))
    (case (make::component-type component)
      (:defsystem 	(apply #'make-instance 'defsystem-component-view
                               :name (string-capitalize name)
                               :component component initargs))
      (:system 		(apply #'make-instance 'system-component-view
                               :name (string-capitalize name)
                               :component component initargs))
      (:subsystem 	(apply #'make-instance 'subsystem-component-view
                               :name (string-capitalize name)
                               :component component initargs))
      (:module 		(apply #'make-instance 'module-component-view
                               :name (string-capitalize name)
                               :component component initargs))
      (:file 		(apply #'make-instance 'file-component-view
                               :name (format nil "~a.~a" name extension)
                               :component component initargs))
      (:private-file 	(apply #'make-instance 'private-file-component-view
                               :name (format nil "~a.~a" name extension)
                               :component component initargs)))))

(defun make-component-subviews (component)
  (let* ((sub-components (make::component-components component))
         (subviews (mapcar #'make-component-view sub-components)))
    (declare (dynamic-extent sub-components))
    subviews))

(defun add-component-subviews (component-view)
  (declare (optimize (speed 3) (safety 0)))
  (with-cursor *watch-cursor*
    (dolist (v (make-component-subviews (component component-view)))
      (setf (depth v) (1+ (depth component-view)))
      (add-view-to-list component-view v))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; view-activate-event-handler
;; view-deactivate-event-handler

#|
(defmethod view-activate-event-handler ((view component-view))
  (invalidate-view view))

(defmethod view-deactivate-event-handler ((view component-view))
  (invalidate-view view))
|#

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; view-draw-contents

(defmethod view-draw-contents ((view component-view))
  (declare (optimize (speed 3) (safety 0)))
  (with-font-focused-view view
    (rlet ((rect :rect))
      ;; draw the triangle
      (when (has-sub-components view)
        (multiple-value-call #'(lambda (top left bottom right)
                                 (ccl::setup-rect rect left top right bottom))
                             (twist-region view))
        (#_PlotCIcon rect (if (expanded-p view)
                            (get-ui-resource "Triangle Down")
                            (get-ui-resource "Triangle Up"))))

      ;; draw the icon
      (when (icon view)
        (multiple-value-call #'(lambda (top left bottom right)
                                 (ccl::setup-rect rect left top right bottom))
                             (icon-region view))
        (#_EraseRect rect)
        (#_PlotCIcon rect (if (expanded-p view)
                            (or (expanded-icon view)
                                (icon view))
                            (icon view))))

      ; draw the component name
      (multiple-value-call #'(lambda (top left bottom right)
                               (ccl::setup-rect rect left top right bottom))
                           (name-region view))
      (#_EraseRect rect)
      (let ((name-width-limit
             (the fixnum (- 177 (* (the fixnum (depth view)) 16)))))
        (when (> (ccl::string-width (name view)) name-width-limit)
          (set-view-font view '(:condense))
          (focus-view view view))
        (#_MoveTo (+ 18 (the fixnum (* (the fixnum (depth view)) 16)))
         10)
        (with-fore-color *black-color*
          (ccl::draw-string-crop (name view) name-width-limit))))
    (call-next-method)))

(defmethod view-draw-contents :after ((view file-component-view))
  (declare (optimize (speed 3) (safety 0)))
   #+CCL-3
   (when (size view)
     (with-font-focused-view view
       (multiple-value-bind (ff ms)
                            (view-font-codes view)
         (let ((size-string (format nil "~,,',d" (size view))))
           (#_MoveTo (- 245 (ccl::string-width size-string))
            (- (font-codes-line-height ff ms) 2))
           (with-pstrs ((s size-string))
             (with-fore-color *black-color*
               (#_drawstring s))))
         )))
   (multiple-value-bind (top left bottom right)
                        (lock-region view)
     (ccl::with-rectangle-arg (r left top right bottom)
       (if (locked view)
         (#_PlotCIcon r *pm-lock-icon*)
         (#_EraseRect r)))))

(defmethod view-draw-contents :around ((view component-view))
  (declare (optimize (speed 3) (safety 0)))
  (call-next-method)
  (when (selected-p view)               ; do the highlighting
    (multiple-value-bind (top left bottom right)
                         (name-region view)
      (ccl::with-rectangle-arg (rect left top right bottom)
        (if (not (window-active-p (view-window view)))
          (ccl::highlight-rect-frame rect)
          (with-macptrs ((p (%int-to-ptr #$HiliteMode)))
            (%put-byte p (ccl::%ilogand2 #x7f (%get-byte p)))
            (#_InvertRect rect)))
        ))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar *project-manager-default-size* #@(265 265))

(defclass project-manager-window (window)
  ((selected-components
    :initarg :selected-components
    :initform nil
    :accessor selected-components)
   (system :initarg :system :initform nil :accessor system)
   (scroller :initarg :scroller :initform nil :accessor scroller))
  (:Default-initargs :color-p *project-manager-color-p*
    ))

(defmethod view-default-position ((self project-manager-window))
  (make-point (- *screen-width* (point-h (view-default-size self)) 4)
              41))

(defmethod view-default-size ((w project-manager-window))
  *project-manager-default-size*)

(defmethod window-select-event-handler :After ((w project-manager-window))
  (when (selected-components w)
     (mapc #'invalidate-view (selected-components w))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; view-click-event-handler

(defun deselect-component-view (cv)
  (declare (optimize (speed 3) (safety 0)))
  (setf (selected-p cv) nil)
  (setf (selected-components (view-window cv))
        (delete cv (selected-components (view-window cv))))
  (invalidate-view cv))

(defun select-component-view (cv)
  (declare (optimize (speed 3) (safety 0)))
  (setf (selected-p cv) t)
  (push cv (selected-components (view-window cv)))
  (invalidate-view cv))

(defun select-or-deselect-component-view (cv)
  (declare (optimize (speed 3) (safety 0)))
  (cond ((or (command-key-p) (shift-key-p))
         (if (selected-p cv)
           (deselect-component-view cv)
           (select-component-view cv)
           ))
        (t
         (dolist (v (selected-components (view-window cv)))
           (deselect-component-view v))
         (select-component-view cv))))

(defmethod view-click-event-handler ((view component-view) where)
  (cond ((point-in-twist-region-p view where)
         (expand-or-collapse-component-view view))

        ;; Kai W. Zimmermann, 10.11.1995, changed
        ;; If you click into the lock region a stack overflow will happen
        ;; because the T-clause leads into unlimited recursion in
        ;; view-click-event-handler via view-convert-coordinates-and-click

        ((or (point-in-lock-region-p view where)
             (point-in-icon-region-p view where)
             (point-in-name-region-p view where))
         (select-or-deselect-component-view view))

        (t
         (when (subviews view)
           (view-convert-coordinates-and-click (find-clicked-subview view where)
                                               where view)))))

(defmethod view-click-event-handler :after ((view file-component-view) where)
  (declare (ignore where))
  (when (double-click-p)
    (ed (make::component-full-pathname (component view) :source))))

(defmethod view-click-event-handler :after ((view defsystem-component-view) where)
  (when (and (double-click-p) (eq (find-clicked-subview view where) view))
    (ed (make::compute-system-path (intern (make::component-name (component view))
                                           :keyword)
                                   (make::component-name (component view))))))

(defmethod expand-or-collapse-component-view ((view component-view))
  (cond ((and (not (expanded-p view))
              (has-sub-components view))
         (draw-twist-down-animation view)
         (add-component-subviews view)
         (setf (expanded-p view) t)
         (invalidate-view view))
        ((expanded-p view)
         (draw-twist-up-animation view)
         (dolist (sv (subviews view))
           (when (member sv (selected-components (view-window view)))
             (setf (selected-components (view-window view))
                   (delete sv (selected-components (view-window view)))))
           (remove-view-from-list view sv))
         (setf (expanded-p view) nil)
         (invalidate-view view)
         ))
  #|(when (typep (view-window view) 'project-manager-window)
    (setf (slot-value (scroller (view-window view))
                      'ccl::field-size)
          (view-size view))
    (ccl::update-scroll-bars (scroller (view-window view))))|#
  )

(defmethod draw-twist-down-animation ((view component-view))
  (with-focused-view view
    (multiple-value-bind (top left bottom right)
                         (twist-region view)
      (declare (dynamic-extent top left bottom right))
      (with-back-color (if (selected-p view)
                         (rgb-to-color (%int-to-ptr #$hilitergb))
                         *white-color*)
        (ccl::with-rectangle-arg (r left top right bottom)
          (dolist (icon (list (get-ui-resource "Triangle Up/Hilited")
                              (get-ui-resource "Triangle Middle/Hilited")
                              (get-ui-resource "Triangle Down/Hilited")
                              (get-ui-resource "Triangle Down")))
            (#_EraseRect r)
            ; kluge - or else it goes by too fast, even in emulation
            ; on a slow powermac
            (dotimes (n 14) (#_PlotCIcon r icon)))
          (#_EraseRect r)))
      )))



(defmethod draw-twist-up-animation ((view component-view))
  (with-focused-view view
    (multiple-value-bind (top left bottom right)
                         (twist-region view)
      (declare (dynamic-extent top left bottom right))
      (with-back-color (if (selected-p view)
                         (rgb-to-color (%int-to-ptr #$hilitergb))
                         *white-color*)
        (ccl::with-rectangle-arg (r left top right bottom)
          (dolist (icon (list (get-ui-resource "Triangle Down/Hilited")
                              (get-ui-resource "Triangle Middle/Hilited")
                              (get-ui-resource "Triangle Up/Hilited")
                              (get-ui-resource "Triangle Up")))
            (#_EraseRect r)
            (dotimes (n 14) (#_PlotCIcon r icon)))
          (#_EraseRect r)))
      )))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; xxx-region methods return a list of 4 values, the top, left, bottom, and
;; right coords of the specified region.
;;

(defmethod twist-region ((view component-view))
  (values 0 0 16 16))

(defmethod icon-region ((view component-view))
    (values 0  (* 16 (the fixnum (depth view)))
            16 (+ 16 (the fixnum (* 16 (the fixnum (depth view)))))))

(defmethod lock-region ((view component-view))
  (if (zerop (depth view))
    (values 0 0 0 0)
    (values 0  (* 16 (the fixnum (1- (depth view))))
            16 (+ 16 (the fixnum (* 16 (the fixnum (1- (depth view)))))))))

(defmethod name-region ((view component-view))
  (values 0  (+ 16 (the fixnum (* (the fixnum (depth view)) 16)))
          13 (point-h (view-size view))))

(defmethod point-in-twist-region-p ((view component-view) where)
  (multiple-value-bind (top left bottom right)
                       (twist-region view)
    (declare (dynamic-extent top left bottom right))
    (ccl::with-rectangle-arg (r left top right bottom)
      (point-in-rect-p r where))))

(defmethod point-in-lock-region-p ((view component-view) where)
  (multiple-value-bind (top left bottom right)
                       (lock-region view)
    (declare (dynamic-extent top left bottom right))
    (ccl::with-rectangle-arg (r left top right bottom)
      (point-in-rect-p r where))))

(defmethod point-in-icon-region-p ((view component-view) where)
  (multiple-value-bind (top left bottom right)
                       (icon-region view)
    (declare (dynamic-extent top left bottom right))
    (ccl::with-rectangle-arg (r left top right bottom)
      (point-in-rect-p r where))))

(defmethod point-in-name-region-p ((view component-view) where)
  (multiple-value-bind (top left bottom right)
                       (name-region view)
    (declare (dynamic-extent top left bottom right))
    (ccl::with-rectangle-arg (r left top right bottom)
      (point-in-rect-p r where))))
