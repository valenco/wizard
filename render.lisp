(in-package :wizard)

;; activate
;; example-json
;; show-acts

(defclass wizard-render () ()) ;; default
(defclass action-render () ()) ;; actions : none, tpl, grid, linear, announce, yamap, file.
(defclass grid-render   () ()) ;; grids   : fld, btn, popbtn.
(defclass linear-render () ()) ;; linears : fld, btn, popbtn, grid
;; TODO - проверка прав - в around-методах


(setf *default-render-method* (mi 'wizard-render))

;; RENDER DISPATCHER (ACTS)
(defmethod restas:render-object ((designer wizard-render) (acts list))
  (let* ((*popups*  (list (list :id "popupLogin" :title "Вход" :content (tpl:popuplogin) :left 720 :width 196)))
         (personal  (let ((userid (hunchentoot:session-value 'userid)))
                      (if (null userid)
                          (tpl:loginform)
                          (tpl:logoutform (list :user (a-name (gethash userid *USER*))
                                                :usertype (string-downcase (type-of (gethash userid *USER*)))
                                                :userid userid))))))
    (declare (special *popups*))
    ;; Рендерить вложенные объекты надо именно здесь - чтобы работало *popups*!
    (let ((in-render (loop :for act :in acts :collect
                        (if (check-perm (a-perm act) (cur-user) (a-val act))
                            (restas:render-object (mi 'action-render) act)
                            ""))))
      (tpl:root
       (list
        :mapkey         *mapkey*
        :popups         *popups*
        :personal       personal
        :right          (if (eql 1 (length (request-list))) ;; main page
                            (tpl:right)
                            "")
        :navpoints      (menu)
        :searchcategory (aif (hunchentoot:post-parameter "searchcategory") it "")
        :searchstring   (aif (hunchentoot:post-parameter "searchstring") it "")
        :content        (format nil "~{~A~}" in-render))))))

;; before start-session
(defmethod restas:render-object :before ((designer wizard-render) (acts list))
  (hunchentoot:start-session))


;; ACT: default (error)
(defmethod restas:render-object ((designer action-render) (obj action))
  (error "no applicable render method for subclass of ACTION: ~A" (type-of obj)))


;; ACT: none
(defmethod restas:render-object ((designer action-render) (obj none))
  (tpl:content-block
   (list :title (a-title obj)
         :content "Раздел находится в разработке")))


;; ACT: tpl
(defmethod restas:render-object ((designer action-render) (obj tpl))
  (tpl:content-block
   (list :title (a-title obj)
         :content (format nil "~A" (funcall (a-val obj))))))


;; ACT: grid --> grid-render (fld, btn, popbtn)
(defmethod restas:render-object ((designer action-render) (obj grid))
  (let ((grid-id  (gensym "J"))
        (pager-id (gensym "P"))
        (col-titles)
        (col-models)
        (col-replace)) ;; <-- не используется, но возможно пригодится в будущем
    (declare (special *popups*))
    (loop :for infld :in (a-fields obj) :collect
       (multiple-value-bind (col-title col-model)
           (restas:render-object (mi 'grid-render) infld) ;; <-dispatcher
         (unless (null col-title)
           (push col-title col-titles)
           (push col-model col-models))))
    (tpl:content-block
     (list :title   (a-title obj)
           :content (tpl:gridview
                     (list :idgrid grid-id
                           :idpager pager-id
                           :json (replace-all
                                  (json:encode-json-to-string
                                   `(("url" . ,(format nil "/~A~A" (a-grid obj) (if (a-param-id obj) (format nil "/~A" (cur-id)) ""))) ;; absolute uri
                                     ("datatype" . "json")
                                     ("colNames" . ,(reverse col-titles))
                                     ("colModel" . ,(reverse col-models))
                                     ("rowNum" . 10)
                                     ("rowList" . (10 20 30))
                                     ("pager" . ,(format nil "#~A" pager-id))
                                     ("sortname" . "id")
                                     ("viewrecords" . t)
                                     ("sortorder" . "desc")
                                     ("height" . ,(aif (a-height obj) it "180"))
                                     ("editurl" . "/edit_url")
                                     ("gridComplete" . "-=|=-")
                                     ("caption" . ,(a-title obj))
                                     ))
                                  "\"-=|=-\"" ;; замена после кодирования в json - иначе никак не вставить js :)
                                  (format nil "
function(){
  var ids = jQuery(\"#~A\").jqGrid('getDataIDs');
  for(var i=0;i < ids.length;i++){
    var cl = ids[i];
    ~{~A~%~}
  }
}
" grid-id (loop :for (in-name btn-str) :in (reverse col-replace) :collect
             (format nil "jQuery(\"#~A\").jqGrid('setRowData',ids[i],{~A: ~A});"
                     grid-id in-name btn-str))))))))))


;; ACT: linear
(defmethod restas:render-object ((designer action-render) (obj linear))
  (let ((*val*  (a-val obj)))
    (declare (special *val*))
    (tpl:frmobj
     (list :content (format nil "~{~A~}"
                            (loop :for infld :in (a-fields obj) :collect
                               (restas:render-object (mi 'linear-render) infld))))))) ;; <-- dispatcher


;; ACT: announce
(defmethod restas:render-object ((designer action-render) (obj announce))
  (format nil "~{~A~}"
          (loop :for (id . announce) :in (funcall (a-val obj)) :append
             (list
              (tpl:postannounce (list :title (a-title announce)
                                      :date (a-date announce)
                                      :photoannounce (or (a-announce-photo announce) "")
                                      :announce (a-announce announce)
                                      :id id))))))

;; ACT: post
(defmethod restas:render-object ((designer action-render) (obj post))
  (let ((val (funcall (a-val obj))))
    (tpl:posttext (list :title (a-title val)
                        :text (a-text val)
                        :date (a-date val)
                        :phototext (or (a-text-photo val) "")))))


;; ACT: yamap
(defmethod restas:render-object ((designer action-render) (obj yamap))
  (tpl:map (list :center (a-center-coord obj)
                 :placemarks (format nil "~{~A~}"
                                     (mapcar #'(lambda (point)
                                                 (tpl:placemark
                                                  (list :title (a-title point)
                                                        :link  (a-link  point)
                                                        :coord (a-coord point)
                                                        :descr (a-descr point))))
                                             (a-mark-points obj))))))


;; ACT: #'function

;; (defmethod restas:render-object ((designer wizard-render) (func function))
;;   (funcall func))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; GRID-RENDER ;;;;;;;;;;;;;;;;



;; GRID: default (error)
(defmethod restas:render-object ((designer grid-render) (obj t))
  (error "no applicable render method for grid: ~A" (type-of obj)))


(defmethod restas:render-object ((designer grid-render) (obj fld))
  (unless (check-perm (a-show (a-perm obj)) (cur-user))
    (return-from restas:render-object nil))
  (values
   (a-title obj)
   `(("name"     . ,(a-name obj))
     ("index"    . ,(a-name obj))
     ("width"    . ,(a-width obj))
     ("align"    . ,(if (equal '(:num) (a-typedata obj)) "center" "left"))
     ("sortable" . t)
     ("editable" . nil))))


(defmethod restas:render-object ((designer grid-render) (obj btn))
  (unless (check-perm (a-perm obj) (cur-user))
    (return-from restas:render-object nil))
  (values
   ""
   `(("name"     . "")
     ("index"    . "")
     ("width"    . ,(a-width obj))
     ("align"    . "center")
     ("sortable" . nil)
     ("editable" . nil))))


(defmethod restas:render-object ((designer grid-render) (obj popbtn))
  (unless (check-perm (a-perm obj) (cur-user))
    (return-from restas:render-object nil))
  (let ((in-action (a-action obj)))
    (push
     (list :id (a-name obj)
           :title (a-title in-action)
           :content (restas:render-object (mi 'action-render) in-action)
           :left 200
           :width 500)
     *popups*))
  (values
   ""
   `(("name"     . "")
     ("index"    . "")
     ("width"    . ,(a-width obj))
     ("align"    . "center")
     ("sortable" . nil)
     ("editable" . nil))))


;; (cond
;; ((equal :calc (car infld))
;;  (when (check-perm (getf infld :perm) (cur-user))
;;    (let* ((in-name (getf infld :calc))
;;           (width   (getf infld :width))
;;           (model `(("name" . ,in-name)
;;                    ("index" . ,in-name)
;;                    ("width" . ,width)
;;                    ("align" . "left")
;;                    ("sortable" . t)
;;                    ("editable" . nil))))
;;      (push in-name col-names)
;;      (push model col-model))))
;; (t (error "show-grid unk fld" )))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; LINEAR-RENDER ;;;;;;;;;;;;;;


;; LINEAR: default (error)
(defmethod restas:render-object ((designer linear-render) (obj t))
  (error "no applicable render method for linear: ~A" (type-of obj)))


(defmethod restas:render-object ((designer linear-render) (obj fld))
  (let ((val       (funcall      *val*))
        (namefld   (a-name       obj))
        (captfld   (a-title      obj))
        (permfld   (a-perm       obj))
        (typedata  (a-typedata   obj)))
    (declare (ignore permfld))
    (show-linear-elt typedata val namefld captfld permfld)))


(defmethod restas:render-object ((designer linear-render) (obj btn))
  (if (check-perm (a-perm obj) (cur-user))
      (tpl:btnlin (list :name (a-name obj) :value (a-value obj)))
      ""))


(defmethod restas:render-object ((designer linear-render) (obj popbtn))
  (if (check-perm (a-perm obj) (cur-user))
      (progn
        (let ((in-action (a-action obj)))
          (push
           (list :id (a-name obj)
                 :title (a-title in-action)
                 :content (restas:render-object (mi 'action-render) in-action)
                 :left 200
                 :width 800)
           *popups*))
        (tpl:popbtnlin (list :popid (a-name obj)
                             :value (a-value obj))))
      ""))


(defmethod restas:render-object ((designer linear-render) (obj grid))
  (restas:render-object (mi 'action-render) obj))



(defmethod restas:render-object ((designer linear-render) (obj file))
  (tpl:fld
   (list :fldname (a-value obj)
         :fldcontent (tpl:fileupd (list :name (a-name obj))))))



(restas:define-route test ("/test")
  (list
   (mi 'linear :title "Поставщик"
       :perm ':ALL
       :val (named-lambda ACTNL-1216 () (GETHASH 2 *USER*))
       :fields (list
                (mi 'fld :name "NAME" :typedata '(:STR) :title "Название организации" :width 300 :xref NIL
                    :perm (MI 'PERM :UPDATE (OR :ADMIN :SELF) :SHOW :ALL :VIEW :ALL :DELETE :ADMIN
                              :CREATE (OR :ADMIN :NOT-LOGGED)))
                (mi 'fld :name "CONTACT-EMAIL" :typedata '(:STR) :title "Контактный email" :width 200 :xref NIL
                    :perm (MI 'PERM :UPDATE (OR :ADMIN :SELF) :SHOW :ALL :VIEW :ALL :DELETE :ADMIN
                              :CREATE (OR :ADMIN :NOT-LOGGED)))
                (mi 'btn :name "b1217" :width 200 :perm '(OR :ADMIN :SELF) :value "Сохранить")
                (mi 'popbtn :name "p1237" :width 200 :perm :all :value "Добавить распродажу"
                    :action
                    (mi 'linear :title "Добавление расподажи"
                        :perm ':all
                        :val (named-lambda ACTNL-1238 () NIL)
                        :fields (list
                                 (mi 'btn :name "b1239" :width 200 :perm :ALL :value "Добавить распродажу"))))
                (mi 'grid :title "Адреса филиалов и магазинов"
                    :perm ':ALL
                    :grid "jg1218"
                    :param-id T
                    :height "180"
                    :val (named-lambda ACTNL-1220 () (CONS-INNER-OBJS *SUPPLIER-AFFILIATE* (A-AFFILIATES (GETHASH 5 *USER*))))
                    :fields (list
                             (mi 'fld :name "ADDRESS" :typedata '(:STR) :title "Адрес" :width 850 :xref NIL
                                 :perm (MI 'PERM :UPDATE (OR :ADMIN :SELF) :SHOW :ALL :VIEW :ALL :DELETE :ADMIN
                                           :CREATE :ADMIN))))
                (mi 'grid :title "Список заявок на тендеры"
                    :perm ':ALL
                    :grid "jg1242"
                    :param-id T
                    :height "180"
                    :val (named-lambda ACTNL-1244 () (CONS-INNER-OBJS *OFFER* (A-OFFERS (GETHASH (CUR-ID) *USER*))))
                    :fields (list
                             (mi 'fld :name "TENDER" :typedata '(:LINK TENDER) :title "Тендер" :width 640 :xref NIL
                                 :perm (MI 'PERM :UPDATE (AND :ACTIVE :OWNER) :SHOW :ALL :VIEW :ALL :DELETE
                                           (AND :OWNER :ACTIVE) :CREATE (AND :ACTIVE :SUPPLIER)))
                             (mi 'btn :name "b1240" :width 110 :perm :ALL :value "Страница заявки")
                             (mi 'btn :name "b1241" :width 105 :perm :ALL :value "Удалить заявку")))
                ))))