;; Copyright 2022 Curtis Klassen
;; This file is part of Spiderweb Wiki.

;; Spiderweb Wiki is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; Spiderweb Wiki is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with Spiderweb Wiki.  If not, see <https://www.gnu.org/licenses/>.

(in-package :web)

(defmacro ningle/route ((path &rest keys) (&rest args) &body body)
  (alexandria:with-gensyms (maybe-key route-func)
    (labels ((make-optional (opt getter)
	       (if opt
		   `(alexandria:if-let ((,maybe-key ,getter))
		      ,maybe-key
		      ,opt)
		   getter))
	     (make-getter (key is-array ls)
	       (if is-array
		   `(get-param-array ,key ,ls)
		   `(get-param ,key ,ls)))
	     (make-binding (sym)
	       (if (listp sym)
		   (let* ((plist (cdr sym))
			  (bind (car sym))
			  (key (getf plist :key (ps:symbol-to-js-string bind)))
			  (array (getf plist :array))
			  (opt (getf plist :optional)))
		     (list bind (make-optional opt (make-getter key array 'params))))
		   (list sym (list 'get-param
                                   (ps:symbol-to-js-string sym)
                                   'params)))))
      (destructuring-bind (&key binding-list fail-clause) args
        (let ((bindings (mapcar #'make-binding binding-list)))
	  `(labels ((,route-func (params)
                      (declare (ignorable params))
                      (alexandria:if-let ,bindings
                        (handler-case (progn ,@body)
                          ,(ana:aif fail-clause
                             ana:it
                             '(condition (c)
                               (html/with-page (:title "Error")
                                 (:p "Got an error")
                                 (:br)
                                 (:br)
                                 (princ-to-string c))))
                          (:no-error (ret)
                            ret))
                        (warn "Could not fill params for route `~a`; required ~
                              args `~a`, got args `~a`~%"
                              ,path
                              ',binding-list
                              params))))
             (setf (ningle:route *app* ,path ,@keys)
                   #',route-func
                   (ningle:route *app*
                                 ,(if (string= (str:s-last path) "/")
                                      (str:substring 0 -1 path)
                                      (str:concat path "/"))
                                 ,@keys)
                   #',route-func)))))))

(defun ningle/push-response (response)
  (alexandria:appendf (lack.response:response-headers ningle:*response*)
                      response))

(defun ningle/add-response-header (key val)
  (ningle/push-response (list key val)))

(defun ningle/respond-type (type)
  (ningle/add-response-header :content-type type))

(defun ningle/set-response-status (code)
  (setf (lack.response:response-status ningle:*response*)
	code)
  (princ-to-string code))

;;; can be used in an end point for caching static files on the client
;;; file-type should be a string which will be passed to ningle/respond-type, or nil
;;; if you're setting it manually
(defun ningle/cache-file (file hash &key (file-type nil))
  (am:-<> ningle:*request*
    (lack.request:request-headers)
    (gethash "if-none-match" am:<>)
    (if (string= hash am:<>)
        (ningle/set-response-status 304)
        (progn (if file-type
                   (ningle/respond-type file-type))
               (ningle/add-response-header "Cache-Control" "must-revalidate")
               (ningle/add-response-header "ETag" (princ-to-string hash))
               (ningle/set-response-status 200)
               file))))

;;; can be used to redirect the user to a different page
(defun ningle/redirect (url &key (type :tmp))
  (ningle/add-response-header "Location" url)
  (ningle/set-response-status (ccase type
                                (:permanent 301)
                                (:tmp 307))))

(defun get-param (param params)
  (cdr (assoc param params :test #'equal)))

(defun get-param-array (param params)
  (am:-<>> params
    (remove param
	    am:<>
	    :test-not #'equal
	    :key #'car)
    (mapcar #'cdr)))