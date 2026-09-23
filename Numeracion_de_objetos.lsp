;;; =====================================================================
;;;  NUMERACION DE OBJETOS
;;;  Archivo    : Numeracion_de_objetos.lsp
;;;  Comando    : NOBJ
;;;  Version    : 1.5  PRUEBA VERTICAL (etiquetas LINE orientadas;
;;;               LINE vertical: etiqueta lateral en el punto medio)
;;;  Plataforma : AutoCAD para Windows (AutoLISP + Visual LISP / ActiveX)
;;;
;;;  *** CONDICION DE USO DE ESTA VERSION ***
;;;  El dibujo debe estar realizado en METROS y se trabaja en Model Space.
;;;  El tamano de la etiqueta se calcula a partir de la escala de
;;;  impresion 1:N escrita por el usuario (solo el denominador N):
;;;     Altura del recuadro = N x 0.001  (1 mm en papel)
;;;     Altura del texto    = 60% de la altura del recuadro
;;;     Separacion auto     = 25% de la altura del recuadro
;;;     Margen horizontal   = 15% de la altura a cada lado del texto
;;;  Ejemplos: 1:50 -> 0.05 m | 1:100 -> 0.10 m | 1:175 -> 0.175 m
;;;  No hay deteccion de unidades: en un dibujo en milimetros los
;;;  tamanos resultarian 1000 veces menores (escriba la altura a mano).
;;;
;;;  Evolucion de NUM6.lsp (el archivo original NO se modifica).
;;;  Se reutiliza de NUM6:
;;;    - relleno con ceros a la izquierda (minimo 4 digitos);
;;;    - bounding box via vla-GetBoundingBox con captura de errores;
;;;    - ancho real del texto con TEXTBOX;
;;;    - proporciones del recuadro (texto 60%; margen ahora 15% por lado);
;;;    - creacion de TEXT y LWPOLYLINE con entmakex (lineweight 0.30);
;;;    - preseleccion (PICKFIRST) si existe.
;;;  Novedades:
;;;    - ubicacion Centro/Arriba/Derecha/Izquierda/Abajo con separacion
;;;      real borde-a-borde calculada con el tamano real del recuadro;
;;;    - orden con agrupacion por tolerancia (filas/columnas);
;;;    - memoria de configuracion durante la sesion;
;;;    - manejador de errores, UNDO agrupado y resumen final;
;;;    - v1.2: entidades LINE con Centro/Arriba/Abajo calculados desde el
;;;      punto medio real y en direccion perpendicular a la linea
;;;      (ver seccion "TRATAMIENTO ESPECIAL DE LINE");
;;;    - v1.3: LINE inclinada tambien en Derecha/Izquierda, desde el
;;;      punto medio real y en direccion perpendicular (lado +X / -X);
;;;    - v1.4: en entidades LINE el texto y el recuadro se giran con el
;;;      angulo de la linea (normalizado para que siempre sea legible);
;;;    - v1.5 PRUEBA VERTICAL: en LINE vertical o casi vertical la
;;;      etiqueta queda SIEMPRE junto al punto medio (nunca en los
;;;      extremos), a +90 grados (se lee de abajo hacia arriba).
;;;      Arriba = lado izquierdo, Abajo = lado derecho.
;;;
;;;  Nota: los comentarios y mensajes se escriben sin acentos a proposito
;;;  para evitar problemas de codificacion al cargar con APPLOAD.
;;; =====================================================================

(vl-load-com)


;;; ---------------------------------------------------------------------
;;; MEMORIA DE SESION
;;; Variables globales (solo viven mientras AutoCAD este abierto):
;;;   *nobj-inicio*      numero inicial propuesto (siguiente disponible)
;;;   *nobj-escala*      denominador de la ultima escala usada (1:N)
;;;   *nobj-altura*      ultima altura de recuadro usada
;;;   *nobj-alt-modo*    "ESCALA" = calculada / "MANUAL" = escrita
;;;   *nobj-separacion*  ultima separacion borde-a-borde usada
;;;   *nobj-sep-modo*    "AUTO" = 25% de la altura / "MANUAL" = escrita
;;;   *nobj-ubicacion*   "Centro" "Arriba" "Derecha" "Izquierda" "Abajo"
;;;   *nobj-orden*       "Seleccion" "IzqDer" "DerIzq" "ArrAba" "AbaArr"
;;;
;;; Regla AUTO/MANUAL (para evitar comportamientos confusos):
;;;   - La ESCALA si se recuerda y se propone en la siguiente ejecucion.
;;;   - La ALTURA propuesta se calcula SIEMPRE a partir de la escala
;;;     de esa ejecucion (N x 0.001). Un valor manual solo vale para la
;;;     ejecucion en que se escribe.
;;;   - La SEPARACION propuesta es SIEMPRE el 25% de la altura
;;;     definitiva de esa ejecucion. Un valor manual solo vale para la
;;;     ejecucion en que se escribe.
;;;   Asi, cambiar la escala recalcula siempre los tamanos.
;;;   *nobj-altura*, *nobj-separacion* y sus modos guardan lo ultimo
;;;   utilizado (referencia de la sesion), no se usan como propuesta.
;;; Se validan en cada ejecucion; si faltan o son invalidas se
;;; inicializan con los valores de fabrica.
;;; ---------------------------------------------------------------------

;; Proporciones aprobadas
(defun nobj:k-papel ()  0.001)   ; 1:100 -> recuadro 0.10 m (dibujo en m)
(defun nobj:k-texto ()  0.60)    ; texto = 60% del recuadro
(defun nobj:k-sep ()    0.25)    ; separacion auto = 25% del recuadro
(defun nobj:k-margen () 0.15)    ; margen horizontal = 15% por lado
(defun nobj:k-vertical () 10.0)  ; LINE a menos de 10 grados de la
                                 ; vertical = "casi vertical"
(defun nobj:k-horizontal () 10.0) ; LINE a menos de 10 grados de la
                                  ; horizontal = "casi horizontal"

;; Altura del recuadro correspondiente a la escala 1:N
(defun nobj:height-from-scale (escala)
  (* escala (nobj:k-papel))
)

(defun nobj:init-session ()
  (if (not (and (= (type *nobj-inicio*) 'INT) (>= *nobj-inicio* 0)))
    (setq *nobj-inicio* 1)
  )
  (if (not (and (numberp *nobj-escala*) (> *nobj-escala* 0.0)))
    (setq *nobj-escala* 100.0)
  )
  (if (not (and (numberp *nobj-altura*) (> *nobj-altura* 0.0)))
    (setq *nobj-altura*   (nobj:height-from-scale *nobj-escala*)
          *nobj-alt-modo* "ESCALA"
    )
  )
  (if (not (member *nobj-alt-modo* '("ESCALA" "MANUAL")))
    (setq *nobj-alt-modo* "ESCALA")
  )
  (if (not (member *nobj-sep-modo* '("AUTO" "MANUAL")))
    (setq *nobj-sep-modo* "AUTO")
  )
  (if (not (and (numberp *nobj-separacion*) (>= *nobj-separacion* 0.0)))
    (setq *nobj-separacion* (* (nobj:k-sep) *nobj-altura*)
          *nobj-sep-modo*   "AUTO"
    )
  )
  (if (not (member *nobj-ubicacion*
                   '("Centro" "Arriba" "Derecha" "Izquierda" "Abajo")))
    (setq *nobj-ubicacion* "Arriba")
  )
  (if (not (member *nobj-orden*
                   '("Seleccion" "IzqDer" "DerIzq" "ArrAba" "AbaArr")))
    (setq *nobj-orden* "IzqDer")
  )
  T
)


;;; ---------------------------------------------------------------------
;;; FORMATOS
;;; ---------------------------------------------------------------------

;; Entero -> texto con minimo 4 digitos (1 -> 0001, 10000 -> 10000)
(defun nobj:format-number (n / s)
  (setq s (itoa (abs n)))
  (while (< (strlen s) 4)
    (setq s (strcat "0" s))
  )
  s
)

;; Real -> texto con minimo 2 y maximo 5 decimales
;; (0.1 -> "0.10", 0.025 -> "0.025", 0.04375 -> "0.04375").
;; No usa RTOS para no depender de DIMZIN (que puede quitar ceros).
;; Valores grandes (>= 10000) se formatean con RTOS para evitar
;; desbordar el entero de 32 bits.
(defun nobj:format-real (x / n e d s)
  (if (>= (abs x) 10000.0)
    (rtos x 2 2)
    (progn
      (setq n (fix (+ (* (abs x) 100000.0) 0.5))
            e (/ n 100000)
            d (rem n 100000)
            s (itoa d)
      )
      (while (< (strlen s) 5) (setq s (strcat "0" s)))
      (while (and (> (strlen s) 2) (= (substr s (strlen s) 1) "0"))
        (setq s (substr s 1 (1- (strlen s))))
      )
      (strcat (if (and (minusp x) (> n 0)) "-" "") (itoa e) "." s)
    )
  )
)

;; Denominador de escala -> texto (100.0 -> "100", 12.5 -> "12.50")
(defun nobj:format-scale (esc)
  (if (and (< esc 1.0e9) (equal esc (float (fix esc)) 1.0e-6))
    (itoa (fix esc))
    (nobj:format-real esc)
  )
)


;;; ---------------------------------------------------------------------
;;; PARSERS MANUALES DE OPCIONES
;;; Se evita INITGET/GETKWORD porque "Arriba" y "Abajo" (y "ArrAba" /
;;; "AbaArr") comparten la inicial A. Regla: A = Arriba, AB = Abajo.
;;; Se acepta la palabra completa o cualquier prefijo no ambiguo,
;;; sin importar mayusculas/minusculas.
;;; ---------------------------------------------------------------------

;; T si el texto S (en mayusculas) es prefijo de PALABRA
(defun nobj:prefix-p (s palabra)
  (and (> (strlen s) 0)
       (<= (strlen s) (strlen palabra))
       (= s (substr palabra 1 (strlen s)))
  )
)

;; Texto del usuario -> ubicacion normalizada, o nil si no es valida
(defun nobj:parse-location (s / u)
  (setq u (strcase (vl-string-trim " \t" s)))
  (cond
    ((and (>= (strlen u) 2) (nobj:prefix-p u "ABAJO")) "Abajo")
    ((nobj:prefix-p u "ARRIBA")    "Arriba")
    ((nobj:prefix-p u "CENTRO")    "Centro")
    ((nobj:prefix-p u "DERECHA")   "Derecha")
    ((nobj:prefix-p u "IZQUIERDA") "Izquierda")
    (T nil)
  )
)

;; Texto del usuario -> orden normalizado, o nil si no es valido
;; (mismo criterio: A = ArrAba, AB = AbaArr)
(defun nobj:parse-order (s / u)
  (setq u (strcase (vl-string-trim " \t" s)))
  (cond
    ((and (>= (strlen u) 2) (nobj:prefix-p u "ABAARR")) "AbaArr")
    ((nobj:prefix-p u "ARRABA")    "ArrAba")
    ((nobj:prefix-p u "SELECCION") "Seleccion")
    ((nobj:prefix-p u "IZQDER")    "IzqDer")
    ((nobj:prefix-p u "DERIZQ")    "DerIzq")
    (T nil)
  )
)


;;; ---------------------------------------------------------------------
;;; SOLICITUD DE DATOS (ENTER acepta el valor entre < >)
;;; ---------------------------------------------------------------------

;; Numero inicial: entero >= 0
(defun nobj:get-start (def / v)
  (initget 4)
  (setq v (getint (strcat "\nNumero inicial <" (itoa def) ">: ")))
  (if v v def)
)

;; Escala de impresion: solo el denominador N de 1:N (> 0).
;; Se acepta cualquier valor, no hay lista cerrada de escalas.
(defun nobj:get-scale (def / v)
  (initget 6)
  (setq v (getreal (strcat "\nEscala de impresion 1:<"
                           (nobj:format-scale def) ">: ")))
  (if v (float v) def)
)

;; Altura del recuadro: > 0 (initget 6 = no cero, no negativo).
;; Devuelve nil si el usuario pulsa ENTER (el llamador decide el modo).
(defun nobj:get-height (def)
  (initget 6)
  (getdist (strcat "\nAltura del recuadro <"
                   (nobj:format-real def) ">: "))
)

;; Separacion: >= 0 (initget 4 = no negativo; 0 se permite = contacto).
;; Devuelve nil si el usuario pulsa ENTER (el llamador decide el modo).
(defun nobj:get-separation (def)
  (initget 4)
  (getdist (strcat "\nSeparacion respecto al objeto <"
                   (nobj:format-real def) ">: "))
)

;; Ubicacion con reintento si la opcion no es valida
(defun nobj:get-location (def / s r)
  (while (null r)
    (setq s (getstring
              (strcat "\nUbicacion de la numeracion "
                      "[Centro/Arriba/Derecha/Izquierda/Abajo] <"
                      def ">: ")))
    (if (= (vl-string-trim " \t" s) "")
      (setq r def)
      (progn
        (setq r (nobj:parse-location s))
        (if (null r)
          (princ "\nOpcion no valida. Use C, A (Arriba), D, I o AB (Abajo).")
        )
      )
    )
  )
  r
)

;; Orden con reintento si la opcion no es valida
(defun nobj:get-order (def / s r)
  (while (null r)
    (setq s (getstring
              (strcat "\nOrden de numeracion "
                      "[Seleccion/IzqDer/DerIzq/ArrAba/AbaArr] <"
                      def ">: ")))
    (if (= (vl-string-trim " \t" s) "")
      (setq r def)
      (progn
        (setq r (nobj:parse-order s))
        (if (null r)
          (princ "\nOpcion no valida. Use S, I, D, A (ArrAba) o AB (AbaArr).")
        )
      )
    )
  )
  r
)


;;; ---------------------------------------------------------------------
;;; GEOMETRIA
;;; ---------------------------------------------------------------------

;; Coordenada Z segura
(defun nobj:z (p)
  (if (and (caddr p) (numberp (caddr p))) (caddr p) 0.0)
)

;; T si el punto tiene coordenadas numericas finitas y razonables
(defun nobj:valid-point-p (p)
  (and (listp p)
       (>= (length p) 2)
       (vl-every '(lambda (v) (and (numberp v) (< (abs v) 1.0e15))) p)
  )
)

;; Bounding box (WCS) de una entidad: ((xmin ymin zmin) (xmax ymax zmax))
;; Devuelve nil si el objeto no la admite (XLINE, RAY, etc.)
(defun nobj:get-bbox (ent / obj res pmin pmax)
  (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
  (if (and obj (not (vl-catch-all-error-p obj)))
    (progn
      (setq res (vl-catch-all-apply 'vla-GetBoundingBox
                                    (list obj 'pmin 'pmax)))
      (if (and (not (vl-catch-all-error-p res)) pmin pmax)
        (progn
          (setq pmin (vlax-safearray->list pmin)
                pmax (vlax-safearray->list pmax)
          )
          (if (and (nobj:valid-point-p pmin)
                   (nobj:valid-point-p pmax)
                   (<= (car pmin) (car pmax))
                   (<= (cadr pmin) (cadr pmax))
              )
            (list pmin pmax)
          )
        )
      )
    )
  )
)

;; Centro geometrico de la bounding box
(defun nobj:bbox-center (bb / pmin pmax)
  (setq pmin (car bb)
        pmax (cadr bb)
  )
  (list (/ (+ (car pmin) (car pmax)) 2.0)
        (/ (+ (cadr pmin) (cadr pmax)) 2.0)
        (/ (+ (nobj:z pmin) (nobj:z pmax)) 2.0)
  )
)

;; Centro del recuadro segun la ubicacion.
;; W y H son las dimensiones REALES del recuadro, por eso la distancia
;; entre el borde del objeto y el borde del recuadro es exactamente SEP.
(defun nobj:label-center (bb ubic sep w h / pmin pmax c)
  (setq pmin (car bb)
        pmax (cadr bb)
        c    (nobj:bbox-center bb)
  )
  (cond
    ;; Arriba: base del recuadro = ymax + sep
    ((= ubic "Arriba")
     (list (car c) (+ (cadr pmax) sep (/ h 2.0)) (caddr c)))
    ;; Abajo: tope del recuadro = ymin - sep
    ((= ubic "Abajo")
     (list (car c) (- (cadr pmin) sep (/ h 2.0)) (caddr c)))
    ;; Derecha: borde izquierdo del recuadro = xmax + sep
    ((= ubic "Derecha")
     (list (+ (car pmax) sep (/ w 2.0)) (cadr c) (caddr c)))
    ;; Izquierda: borde derecho del recuadro = xmin - sep
    ((= ubic "Izquierda")
     (list (- (car pmin) sep (/ w 2.0)) (cadr c) (caddr c)))
    ;; Centro: la separacion no interviene
    (T c)
  )
)


;;; ---------------------------------------------------------------------
;;; TRATAMIENTO ESPECIAL DE LINE
;;; Solo para entidades LINE, en las cinco ubicaciones. Cualquier otro
;;; tipo de entidad sigue usando la bounding box (nobj:label-center).
;;;
;;; - Centro: centro del recuadro = punto medio real de la LINE.
;;; - Arriba/Abajo: desde el punto medio, desplazamiento en direccion
;;;   PERPENDICULAR a la linea. El vector perpendicular se normaliza
;;;   para que su componente Y sea positiva (Arriba = lado +Y del WCS);
;;;   Abajo usa el vector contrario. Asi, invertir StartPoint/EndPoint
;;;   no intercambia Arriba y Abajo.
;;; - ORIENTACION (v1.4): el texto y el recuadro se giran con el angulo
;;;   de la linea, atan2(dy, dx), normalizado al intervalo (-90, +90]
;;;   grados para que el texto se lea siempre de izquierda a derecha:
;;;   0 -> 0 | 30 -> 30 | 45 -> 45 | 135 -> -45 | 180 -> 0 | -45 -> -45.
;;;   LINE vertical o casi vertical (v1.5): el angulo se toma de la
;;;   direccion de la linea que apunta hacia +Y, por lo que queda entre
;;;   80 y 100 grados (exactamente +90 si es vertical): el texto se lee
;;;   siempre de abajo hacia arriba y es identico aunque la linea se
;;;   haya dibujado de arriba hacia abajo. No hay salto entre 89 y 91.
;;;   El recuadro se construye ya girado: sus 4 vertices se calculan en
;;;   coordenadas locales y se giran alrededor del centro de la etiqueta.
;;; - Separacion borde-a-borde: para un recuadro W x H girado un angulo
;;;   A, su "media anchura" en una direccion unitaria D es
;;;       e(D) = (W/2)|D.u| + (H/2)|D.v|
;;;   con u = (cos A, sin A) y v = (-sin A, cos A) los ejes del recuadro.
;;;   El centro se aleja la distancia d = sep + e(D) desde la linea (o
;;;   desde su extremo), de modo que el borde mas cercano del recuadro
;;;   queda exactamente a SEP. Como el recuadro es paralelo a la LINE,
;;;   en direccion perpendicular e = H/2 y d = sep + H/2.
;;; - LINE vertical o casi vertical (a menos de nobj:k-vertical grados
;;;   de la vertical) - v1.5 PRUEBA VERTICAL:
;;;   la etiqueta queda SIEMPRE centrada en el punto medio de la linea,
;;;   desplazada en perpendicular hacia un lado (nunca en los extremos):
;;;     Centro            -> sobre el punto medio.
;;;     Izquierda / Arriba -> lado izquierdo (-X del WCS).
;;;     Derecha  / Abajo   -> lado derecho  (+X del WCS).
;;;   El lado se elige con la perpendicular normalizada a X >= 0, que en
;;;   una linea casi vertical es estable (|nx| ~ 1).
;;; - Derecha/Izquierda (v1.3): desde el punto medio, en direccion
;;;   PERPENDICULAR a la linea. El vector se normaliza para que su
;;;   componente X sea positiva (Derecha = lado +X del WCS); Izquierda
;;;   usa el vector contrario. Invertir StartPoint/EndPoint no
;;;   intercambia Derecha e Izquierda. Misma distancia borde-a-borde
;;;   d = sep + e(D).
;;;   Nota: en una LINE inclinada, Derecha coincide con el lado de
;;;   Arriba o de Abajo (solo hay dos lados perpendiculares).
;;; - LINE horizontal o casi horizontal (a menos de nobj:k-horizontal
;;;   grados de la horizontal): Derecha/Izquierda son ambiguos (las
;;;   perpendiculares son arriba y abajo). La etiqueta se coloca en la
;;;   PROLONGACION de la linea: despues del extremo derecho (Derecha) o
;;;   antes del extremo izquierdo (Izquierda), a SEP del extremo. Para
;;;   una linea exactamente horizontal coincide con la bounding box.
;;; - LINE vertical: su perpendicular ya es horizontal, por lo que
;;;   Derecha/Izquierda quedan junto al punto medio, a SEP de la linea.
;;; - LINE de longitud cero o con datos invalidos: no se aplica el
;;;   tratamiento especial y se usa la bounding box (nunca se detiene).
;;; El resto de entidades mantienen texto y recuadro horizontales.
;;; ---------------------------------------------------------------------

;; Datos de una LINE: (p1 p2 dx dy longitud) en WCS, o nil si la
;; entidad no es LINE, sus puntos no son validos o su longitud es cero.
(defun nobj:line-data (ent / ed p1 p2 dx dy l)
  (setq ed (vl-catch-all-apply 'entget (list ent)))
  (if (and ed
           (not (vl-catch-all-error-p ed))
           (= (cdr (assoc 0 ed)) "LINE")
      )
    (progn
      (setq p1 (cdr (assoc 10 ed))
            p2 (cdr (assoc 11 ed))
      )
      (if (and (nobj:valid-point-p p1) (nobj:valid-point-p p2))
        (progn
          (setq dx (- (car p2) (car p1))
                dy (- (cadr p2) (cadr p1))
                l  (sqrt (+ (* dx dx) (* dy dy)))
          )
          ;; Proteccion contra division entre cero
          (if (> l 1.0e-9)
            (list p1 p2 dx dy l)
          )
        )
      )
    )
  )
)

;; Punto medio real de la LINE
(defun nobj:line-midpoint (ld / p1 p2)
  (setq p1 (car ld)
        p2 (cadr ld)
  )
  (list (/ (+ (car p1) (car p2)) 2.0)
        (/ (+ (cadr p1) (cadr p2)) 2.0)
        (/ (+ (nobj:z p1) (nobj:z p2)) 2.0)
  )
)

;; Vector perpendicular unitario (nx ny) con componente Y >= 0
(defun nobj:line-perpendicular (ld / nx ny)
  (setq nx (/ (- (nth 3 ld)) (nth 4 ld))
        ny (/ (nth 2 ld) (nth 4 ld))
  )
  (if (< ny 0.0)
    (setq nx (- nx)
          ny (- ny)
    )
  )
  (list nx ny)
)

;; Vector perpendicular unitario (nx ny) con componente X >= 0
;; (usado por Derecha/Izquierda)
(defun nobj:line-perpendicular-x (ld / nx ny)
  (setq nx (/ (- (nth 3 ld)) (nth 4 ld))
        ny (/ (nth 2 ld) (nth 4 ld))
  )
  (if (< nx 0.0)
    (setq nx (- nx)
          ny (- ny)
    )
  )
  (list nx ny)
)

;; Grados -> radianes
(defun nobj:deg->rad (g)
  (* pi (/ g 180.0))
)

;; T si la LINE esta a menos de nobj:k-vertical grados de la vertical.
;; |dx|/L = |cos(angulo)| < sin(10 grados)  <=>  angulo en 80..100 grados.
(defun nobj:line-vertical-p (ld)
  (< (abs (/ (nth 2 ld) (nth 4 ld)))
     (sin (nobj:deg->rad (nobj:k-vertical))))
)

;; Angulo legible de la LINE (radianes).
;; - LINE vertical o casi vertical (v1.5): angulo de la direccion que
;;   apunta hacia +Y (entre 80 y 100 grados; +90 si es vertical). El
;;   texto se lee de abajo hacia arriba sin importar el sentido de la
;;   linea y sin saltos al cruzar los 90 grados.
;; - Resto: intervalo (-90, +90] grados; si atan2 deja el texto boca
;;   abajo se suma o resta PI (sin cambios respecto a v1.4).
(defun nobj:line-angle (ld / a eps dir)
  (if (nobj:line-vertical-p ld)
    (progn
      (setq dir (nobj:line-direction ld "Y"))
      (atan (cadr dir) (car dir))
    )
    (progn
      (setq a   (atan (nth 3 ld) (nth 2 ld))
            eps 1.0e-6
      )
      (cond
        ((> a (+ (/ pi 2.0) eps))   (- a pi))
        ((<= a (+ (/ pi -2.0) eps)) (+ a pi))
        (T a)
      )
    )
  )
)

;; Direccion unitaria de la LINE normalizada segun un eje:
;; EJE "Y" -> componente Y >= 0 ; EJE "X" -> componente X >= 0
(defun nobj:line-direction (ld eje / ux uy)
  (setq ux (/ (nth 2 ld) (nth 4 ld))
        uy (/ (nth 3 ld) (nth 4 ld))
  )
  (if (or (and (= eje "Y") (< uy 0.0))
          (and (= eje "X") (< ux 0.0)))
    (setq ux (- ux)
          uy (- uy)
    )
  )
  (list ux uy)
)

;; Media anchura de un recuadro W x H girado ANG, medida en la
;; direccion unitaria DIR: (W/2)|DIR.u| + (H/2)|DIR.v|
(defun nobj:half-extent (dir ang w h / c s)
  (setq c (cos ang)
        s (sin ang)
  )
  (+ (* 0.5 w (abs (+ (* (car dir) c) (* (cadr dir) s))))
     (* 0.5 h (abs (- (* (cadr dir) c) (* (car dir) s)))))
)

;; Punto P desplazado S*D en la direccion unitaria DIR (conserva Z)
(defun nobj:offset-point (p dir s d)
  (list (+ (car p)  (* s d (car dir)))
        (+ (cadr p) (* s d (cadr dir)))
        (caddr p))
)

;; Centro de la etiqueta para una LINE (recuadro W x H girado ANG).
;; Devuelve nil solo si la ubicacion no es reconocida.
(defun nobj:line-label-center (ld ubic sep w h ang / m n dir s)
  (setq m (nobj:line-midpoint ld))
  (cond
    ((= ubic "Centro") m)
    ((or (= ubic "Arriba") (= ubic "Abajo"))
     (setq s (if (= ubic "Arriba") 1.0 -1.0)
           n (nobj:line-perpendicular ld)
     )
     (if (not (nobj:line-vertical-p ld))
       ;; Perpendicular desde el punto medio (sin cambios)
       (nobj:offset-point m n s (+ sep (nobj:half-extent n ang w h)))
       ;; v1.5 PRUEBA VERTICAL: casi vertical -> lateral en el punto
       ;; medio. Arriba = izquierda (-X), Abajo = derecha (+X).
       (progn
         (setq dir (nobj:line-perpendicular-x ld))
         (nobj:offset-point m dir (if (= ubic "Arriba") -1.0 1.0)
           (+ sep (nobj:half-extent dir ang w h)))
       )
     )
    )
    ((or (= ubic "Derecha") (= ubic "Izquierda"))
     (setq s (if (= ubic "Derecha") 1.0 -1.0)
           n (nobj:line-perpendicular-x ld)
     )
     ;; nx = |sin(angulo de la linea)|; si es menor que sin(10 grados)
     ;; la linea esta a menos de 10 grados de la horizontal.
     (if (>= (car n) (sin (nobj:deg->rad (nobj:k-horizontal))))
       ;; Perpendicular desde el punto medio
       (nobj:offset-point m n s (+ sep (nobj:half-extent n ang w h)))
       ;; Casi horizontal: prolongacion por el extremo derecho/izquierdo
       (progn
         (setq dir (nobj:line-direction ld "X"))
         (nobj:offset-point m dir s
           (+ (* 0.5 (nth 4 ld)) sep (nobj:half-extent dir ang w h)))
       )
     )
    )
    (T nil)
  )
)


;;; ---------------------------------------------------------------------
;;; TEXTO Y RECUADRO
;;; ---------------------------------------------------------------------

;; Datos del estilo de texto actual: (nombre factor-ancho oblicuo)
(defun nobj:style-data (/ estilo d wf obl)
  (setq estilo (getvar "TEXTSTYLE")
        d      (tblsearch "STYLE" estilo)
  )
  (if (null d)
    (setq estilo "Standard"
          d      (tblsearch "STYLE" "Standard")
    )
  )
  (setq wf  (cdr (assoc 41 d))
        obl (cdr (assoc 50 d))
  )
  (if (not (and (numberp wf) (> wf 0.0))) (setq wf 1.0))
  (if (not (numberp obl)) (setq obl 0.0))
  (list estilo wf obl)
)

;; Ancho real del texto (TEXTBOX); valor de emergencia si falla
(defun nobj:text-width (texto altTexto sdata / caja ancho)
  (setq caja
    (vl-catch-all-apply
      'textbox
      (list (list (cons 1 texto)
                  (cons 40 altTexto)
                  (cons 7 (car sdata))
                  (cons 41 (cadr sdata))
                  (cons 51 (caddr sdata))
            )
      )
    )
  )
  (if (and caja
           (not (vl-catch-all-error-p caja))
           (listp caja)
           (= (length caja) 2)
      )
    (setq ancho (abs (- (car (cadr caja)) (car (car caja)))))
  )
  (if (not (and ancho (> ancho 0.0)))
    (setq ancho (* altTexto 0.65 (strlen texto) (cadr sdata)))
  )
  ancho
)

;; Ancho del recuadro = ancho texto + margen 15% de la altura por lado
;; (30% de la altura en total). Nunca menor que la altura (heredado de
;; NUM6) para que etiquetas cortas no queden deformadas.
(defun nobj:box-width (texto altTexto altCaja sdata / w)
  (setq w (+ (nobj:text-width texto altTexto sdata)
             (* 2.0 (nobj:k-margen) altCaja)))
  (if (< w altCaja) altCaja w)
)

;; Vertice local (LX LY) girado ANG alrededor de CTR -> (10 x y)
(defun nobj:box-vertex (ctr lx ly c s)
  (list 10
        (+ (car ctr)  (- (* lx c) (* ly s)))
        (+ (cadr ctr) (+ (* lx s) (* ly c))))
)

;; Recuadro: LWPOLYLINE cerrada centrada en CTR, girada ANG (radianes),
;; lineweight 0.30 mm. Los 4 vertices se calculan en coordenadas
;; locales y se giran alrededor del centro: se crea ya girada.
;; Con ANG = 0 el resultado es identico al de versiones anteriores.
(defun nobj:make-box (ctr w h lay ang / hw hh c s)
  (setq hw (/ w 2.0)
        hh (/ h 2.0)
        c  (cos ang)
        s  (sin ang)
  )
  (entmakex
    (list
      '(0 . "LWPOLYLINE")
      '(100 . "AcDbEntity")
      (cons 8 lay)
      '(370 . 30)
      '(100 . "AcDbPolyline")
      '(90 . 4)
      '(70 . 1)
      (cons 38 (nobj:z ctr))
      (nobj:box-vertex ctr (- hw) (- hh) c s)
      (nobj:box-vertex ctr hw     (- hh) c s)
      (nobj:box-vertex ctr hw     hh     c s)
      (nobj:box-vertex ctr (- hw) hh     c s)
      '(210 0.0 0.0 1.0)
    )
  )
)

;; Texto con justificacion Medio-Centro (72=1, 73=2) en CTR, girado
;; ANG radianes (mismo angulo que el recuadro).
;; Para digitos, MC centra exactamente la altura visible del numero.
(defun nobj:make-text (ctr texto h sdata lay ang)
  (entmakex
    (list
      '(0 . "TEXT")
      '(100 . "AcDbEntity")
      (cons 8 lay)
      '(100 . "AcDbText")
      (cons 10 ctr)
      (cons 40 h)
      (cons 1 texto)
      (cons 50 ang)
      (cons 41 (cadr sdata))
      (cons 51 (caddr sdata))
      (cons 7 (car sdata))
      '(72 . 1)
      '(73 . 2)
      (cons 11 ctr)
      '(210 0.0 0.0 1.0)
    )
  )
)

;; Borra de forma segura una lista de entidades
(defun nobj:delete-list (lst)
  (foreach e lst
    (if (and e (entget e)) (entdel e))
  )
)


;;; ---------------------------------------------------------------------
;;; ORDENACION
;;; Cada registro: (indice ename bbox centro datos-LINE-o-nil)
;;; Se calcula una clave primaria P y una secundaria S de forma que el
;;; orden deseado sea siempre ascendente:
;;;   IzqDer : P = x    S = -y  (misma columna: de arriba a abajo)
;;;   DerIzq : P = -x   S = -y  (misma columna: de arriba a abajo)
;;;   ArrAba : P = -y   S = x   (misma fila: de izquierda a derecha)
;;;   AbaArr : P = y    S = x   (misma fila: de izquierda a derecha)
;;; Los objetos cuya P difiere menos que TOL respecto al primero del
;;; grupo se consideran en la misma fila/columna y se ordenan por S.
;;; Desempate final: indice en la seleccion (resultado determinista).
;;; ---------------------------------------------------------------------

(defun nobj:sort-keys (r modo / c x y)
  (setq c (nth 3 r)
        x (car c)
        y (cadr c)
  )
  (cond
    ((= modo "IzqDer") (list x     (- y) (car r) r))
    ((= modo "DerIzq") (list (- x) (- y) (car r) r))
    ((= modo "ArrAba") (list (- y) x     (car r) r))
    (T                 (list y     x     (car r) r))   ; AbaArr
  )
)

;; Ordena con vl-sort-i (no elimina elementos duplicados)
(defun nobj:sort-by (lst cmp)
  (mapcar '(lambda (i) (nth i lst)) (vl-sort-i lst cmp))
)

(defun nobj:sort-entities (lst modo tol / claves grupos grupo base res)
  (if (or (= modo "Seleccion") (< (length lst) 2))
    lst
    (progn
      ;; 1) Claves y orden por P (desempate por indice)
      (setq claves (mapcar '(lambda (r) (nobj:sort-keys r modo)) lst))
      (setq claves
        (nobj:sort-by claves
          '(lambda (a b)
             (if (= (car a) (car b))
               (< (caddr a) (caddr b))
               (< (car a) (car b))
             )
           )
        )
      )
      ;; 2) Agrupar filas/columnas por tolerancia
      (foreach k claves
        (if (and base (<= (- (car k) base) tol))
          (setq grupo (cons k grupo))
          (progn
            (if grupo (setq grupos (cons (reverse grupo) grupos)))
            (setq grupo (list k)
                  base  (car k)
            )
          )
        )
      )
      (if grupo (setq grupos (cons (reverse grupo) grupos)))
      (setq grupos (reverse grupos))
      ;; 3) Dentro de cada grupo ordenar por S (desempate por indice)
      (foreach g grupos
        (foreach k (nobj:sort-by g
                     '(lambda (a b)
                        (if (= (cadr a) (cadr b))
                          (< (caddr a) (caddr b))
                          (< (cadr a) (cadr b))
                        )
                      )
                   )
          (setq res (cons (nth 3 k) res))
        )
      )
      (reverse res)
    )
  )
)


;;; ---------------------------------------------------------------------
;;; MENSAJES
;;; ---------------------------------------------------------------------

;; Rellena un texto con espacios a la derecha hasta LARGO caracteres
;; (siempre deja al menos un espacio de separacion)
(defun nobj:pad-right (s largo)
  (setq s (strcat s " "))
  (while (< (strlen s) largo) (setq s (strcat s " ")))
  s
)

(defun nobj:print-summary (inicio escala altura alt-modo altTexto
                           sep sep-modo ubic orden)
  (princ "\n----------------------------------------")
  (princ "\nNOBJ - Numeracion de objetos")
  (princ "\n")
  (princ (strcat "\nInicio:       " (nobj:format-number inicio)))
  (princ (strcat "\nEscala:       1:" (nobj:format-scale escala)))
  (princ (strcat "\nRecuadro:     "
                 (nobj:pad-right (nobj:format-real altura) 7)
                 (if (= alt-modo "MANUAL") "[Manual]" "[Escala]")))
  (princ (strcat "\nTexto:        "
                 (nobj:pad-right (nobj:format-real altTexto) 7)
                 "[Automatico]"))
  (princ (strcat "\nSeparacion:   "
                 (nobj:pad-right (nobj:format-real sep) 7)
                 (if (= sep-modo "MANUAL") "[Manual]" "[Automatico]")
                 (if (= ubic "Centro") "  (no aplica en Centro)" "")))
  (princ (strcat "\nUbicacion:    " ubic))
  (princ (strcat "\nOrden:        " orden))
  (princ "\n----------------------------------------")
  (princ)
)

;; T si el mensaje de error corresponde a una cancelacion (ESC)
(defun nobj:cancel-msg-p (msg)
  (and msg
       (wcmatch (strcase msg)
                "*BREAK*,*CANCEL*,*EXIT*,*QUIT*,*SALIR*,*ABANDON*,*INTERRUMP*")
  )
)


;;; =====================================================================
;;; COMANDO PRINCIPAL
;;; =====================================================================

(defun c:NOBJ (/ *error* doc undo-abierto creados ss-pre ss
                 inicio escala alt-auto alt-in altura alt-modo altTexto
                 sep-def sep-in sep sep-modo ubic orden
                 lay sdata datos omitidos numerados num ultimo
                 i ent bb texto w ang ctr e1 e2)

  ;; ---------------------------------------------------------------
  ;; Manejador local de errores
  ;; - Si falla a mitad de la creacion, borra lo creado en esta
  ;;   ejecucion (todo o nada).
  ;; - Cierra el Undo Mark si quedo abierto.
  ;; - ESC se informa como "*Cancelado*" sin mensajes tecnicos.
  ;; NOBJ no modifica variables de sistema (usa entmakex, no COMMAND),
  ;; por lo que no hay nada que restaurar en ese sentido.
  ;; ---------------------------------------------------------------
  (defun *error* (msg)
    (if creados
      (vl-catch-all-apply 'nobj:delete-list (list creados))
    )
    (if (and undo-abierto doc)
      (vl-catch-all-apply 'vla-EndUndoMark (list doc))
    )
    (if (nobj:cancel-msg-p msg)
      (princ "\n*Cancelado*")
      (if msg (princ (strcat "\nNOBJ interrumpido: " msg)))
    )
    (princ)
  )

  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (nobj:init-session)

  ;; Preseleccion (si el usuario selecciono antes de escribir NOBJ)
  (setq ss-pre (ssget "_I"))
  (if ss-pre (sssetfirst nil nil))

  ;; ---------------------------------------------------------------
  ;; Configuracion
  ;; ---------------------------------------------------------------
  ;; 1) Numero inicial
  (setq inicio (nobj:get-start *nobj-inicio*))

  ;; 2) Escala de impresion (dibujo en METROS)
  (setq escala (nobj:get-scale *nobj-escala*))

  ;; 3) Altura del recuadro: se propone la calculada por escala.
  ;;    ENTER -> [Escala]; otro valor -> [Manual].
  ;;    (Si se escribe exactamente el valor calculado sigue siendo [Escala])
  (setq alt-auto (nobj:height-from-scale escala))
  (setq alt-in   (nobj:get-height alt-auto))
  (if (and alt-in (not (equal alt-in alt-auto 1.0e-9)))
    (setq altura alt-in   alt-modo "MANUAL")
    (setq altura alt-auto alt-modo "ESCALA")
  )

  ;; 4) Con la altura DEFINITIVA: texto 60% y separacion auto 25%
  (setq altTexto (* (nobj:k-texto) altura)
        sep-def  (* (nobj:k-sep) altura)
  )

  ;; 5) Separacion: ENTER -> [Automatico]; otro valor -> [Manual]
  (setq sep-in (nobj:get-separation sep-def))
  (if (and sep-in (not (equal sep-in sep-def 1.0e-9)))
    (setq sep sep-in  sep-modo "MANUAL")
    (setq sep sep-def sep-modo "AUTO")
  )

  (setq ubic  (nobj:get-location *nobj-ubicacion*))
  (setq orden (nobj:get-order    *nobj-orden*))

  ;; Guardar configuracion de la sesion
  (setq *nobj-inicio*     inicio
        *nobj-escala*     escala
        *nobj-altura*     altura
        *nobj-alt-modo*   alt-modo
        *nobj-separacion* sep
        *nobj-sep-modo*   sep-modo
        *nobj-ubicacion*  ubic
        *nobj-orden*      orden
  )

  (nobj:print-summary inicio escala altura alt-modo altTexto
                      sep sep-modo ubic orden)

  ;; ---------------------------------------------------------------
  ;; Seleccion (estandar: pick, ventana, crossing, etc.)
  ;; ---------------------------------------------------------------
  (if ss-pre
    (progn
      (setq ss ss-pre)
      (princ (strcat "\nUsando " (itoa (sslength ss))
                     " objeto(s) preseleccionado(s)."))
    )
    (progn
      (princ "\nSeleccione los objetos a numerar: ")
      (setq ss (ssget))
    )
  )

  (if (null ss)
    (princ "\nNo se seleccionaron objetos.")
    (progn
      ;; -----------------------------------------------------------
      ;; Bounding boxes (los objetos sin bbox se omiten)
      ;; -----------------------------------------------------------
      (setq i 0 omitidos 0 numerados 0 datos nil)
      (repeat (sslength ss)
        (setq ent (ssname ss i)
              bb  (nobj:get-bbox ent))
        (if bb
          (setq datos (cons (list i ent bb (nobj:bbox-center bb)
                                  (nobj:line-data ent))
                            datos))
          (setq omitidos (1+ omitidos))
        )
        (setq i (1+ i))
      )
      (setq datos (reverse datos))

      ;; Orden (tolerancia de fila/columna = 10% de la altura)
      (setq datos (nobj:sort-entities datos orden (* 0.10 altura)))

      ;; -----------------------------------------------------------
      ;; Creacion de etiquetas dentro de un solo grupo de UNDO
      ;; -----------------------------------------------------------
      (setq lay      (getvar "CLAYER")
            sdata    (nobj:style-data)
            num      inicio
      )
      (vla-StartUndoMark doc)
      (setq undo-abierto T)

      (foreach r datos
        (setq texto (nobj:format-number num)
              w     (nobj:box-width texto altTexto altura sdata)
              ;; LINE -> etiqueta girada con la linea (angulo legible);
              ;; resto de entidades -> horizontal
              ang   (if (nth 4 r) (nobj:line-angle (nth 4 r)) 0.0)
              ;; LINE -> calculo geometrico desde el punto medio;
              ;; en cualquier otro caso -> bounding box
              ctr   (if (nth 4 r)
                      (nobj:line-label-center (nth 4 r) ubic sep w altura ang)
                    )
              ctr   (if ctr
                      ctr
                      (nobj:label-center (caddr r) ubic sep w altura)
                    )
              e1    (nobj:make-box  ctr w altura lay ang)
              e2    (nobj:make-text ctr texto altTexto sdata lay ang)
        )
        (if (and e1 e2)
          (setq creados   (cons e2 (cons e1 creados))
                ultimo    num
                num       (1+ num)
                numerados (1+ numerados)
          )
          (progn
            ;; Si una de las dos piezas fallo, no dejar restos
            (nobj:delete-list (list e1 e2))
            (setq omitidos (1+ omitidos))
          )
        )
      )

      (vla-EndUndoMark doc)
      (setq undo-abierto nil
            creados      nil)

      ;; Proponer el siguiente numero en la proxima ejecucion
      (setq *nobj-inicio* num)

      ;; -----------------------------------------------------------
      ;; Resumen final
      ;; -----------------------------------------------------------
      (princ "\nNOBJ completado.")
      (princ (strcat "\nObjetos numerados: " (itoa numerados)))
      (princ (strcat "\nObjetos omitidos: "  (itoa omitidos)))
      (princ (strcat "\nNumeracion final: "
                     (if ultimo (nobj:format-number ultimo) "-")))
      (princ (strcat "\nSiguiente numero: " (nobj:format-number num)))
    )
  )
  (princ)
)


;;; ---------------------------------------------------------------------
;;; MENSAJE AL CARGAR
;;; ---------------------------------------------------------------------
(princ "\n========================================")
(princ "\nNumeracion de objetos cargado.")
(princ "\nEscriba NOBJ para comenzar.")
(princ "\n========================================")
(princ)
