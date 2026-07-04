#lang racket/gui
;; sankaku-racket
;; 単位円の回転を sin/cos/tan 波として「射影（影）」で表現する 2D統合ビュー
;; PLAN.md の仕様に完全準拠して実装
;;
;; レイアウト:
;;   - 円: 左側
;;   - サイン波: 円の右側（縦向き、振幅上下・時間右）
;;   - コサイン波: 円の下側（横向き、振幅左右・時間下）
;;   - 点が反時計回りに動くと波が描かれる
;;   - 現在点から水平/垂直の射影線で「影の対応」を明確に表示
;;
;; モード切り替え (t キー):
;;   - sin+cos モード: 従来の sin/cos 波
;;   - tan モード: 円 + 2つの tan 波のみ (sin/cos 非表示)
;;
;; Developed with Grok by xAI (https://grok.x.ai)
;; コーディングは Grok と協力して行いました。
;;
;; すべて Racket 標準ライブラリ (racket/gui + racket/draw) のみ

(require racket/draw
         racket/class
         racket/list
         racket/math)

;; =====================
;; config (定数)
;; =====================
(define WINDOW-WIDTH          1200)
(define WINDOW-HEIGHT         820)
(define CIRCLE-RADIUS         115)
(define CIRCLE-CX             260)
(define CIRCLE-CY             295)
(define SINE-ORIGIN-X         480)
(define SINE-AMP              115)
(define SINE-WAVE-LENGTH      620)
(define COS-ORIGIN-Y          470)
(define COS-AMP               115)
(define COS-WAVE-LENGTH       280)
(define TAN-AMP               45)
(define TAN-CLAMP             5.5)
(define DT                    0.023)
(define INITIAL-SPEED         1.0)
(define INITIAL-DISPLAY-CYCLES 2.5)
(define MIN-DISPLAY-CYCLES    0.5)
(define MAX-DISPLAY-CYCLES    8.0)
(define MAX-HISTORY           1200)

;; 色（ダークテーマ）
(define BG-COLOR        (make-color 18 20 26))
(define CIRCLE-COLOR    (make-color 245 248 255))
(define POINT-COLOR     (make-color 255 210 70))
(define COS-COLOR       (make-color 80 160 255))
(define SIN-COLOR       (make-color 255 95 105))
(define GUIDE-COLOR     (make-color 140 145 160))
(define PROJ-COLOR      (make-color 200 180 120))
(define AXIS-COLOR      (make-color 70 75 90))
(define TEXT-COLOR      (make-color 225 230 240))
(define LABEL-COLOR     (make-color 170 180 195))
(define TRIANGLE-COLOR  (make-color 190 200 215))
(define WAVE-AXIS-COLOR (make-color 95 100 110))
(define TAN-COLOR       (make-color 100 210 130))

;; =====================
;; state (状態変数)
;; =====================
(define theta          0.0)     ; 現在角度 [0, 2π)
(define speed          1.0)
(define paused?        #f)
(define display-cycles 2.5)
(define display-mode   'sin-cos) ; 'sin-cos | 'tan
(define history        '())     ; (list (list age c s) ...) age in radians, 0=現在

;; =====================
;; animation
;; =====================
(define (get-max-age)
  (* display-cycles 2.0 pi))

(define (trim-history!)
  (define max-a (get-max-age))
  (set! history (filter (λ (e) (< (first e) max-a)) history))
  (when (> (length history) MAX-HISTORY)
    (set! history (take history MAX-HISTORY))))

(define (add-to-history! dtheta)
  ;; 既存エントリの age を進める
  (set! history
        (for/list ([entry (in-list history)])
          (list (+ (first entry) dtheta)
                (second entry)
                (third entry))))
  ;; 現在値を age=0 で先頭に追加
  (define c (cos theta))
  (define s (sin theta))
  (set! history (cons (list 0.0 c s) history))
  (trim-history!))

(define (reset-state!)
  (set! theta 0.0)
  (set! speed INITIAL-SPEED)
  (set! paused? #f)
  (set! display-cycles INITIAL-DISPLAY-CYCLES)
  (set! history '()))

(define (adjust-speed! delta)
  (set! speed (max 0.1 (min 6.0 (+ speed delta)))))

(define (adjust-display-cycles! delta)
  (set! display-cycles (max MIN-DISPLAY-CYCLES
                            (min MAX-DISPLAY-CYCLES
                                 (+ display-cycles delta))))
  (trim-history!))

(define (update-animation!)
  (define dtheta (* speed DT))
  (set! theta (+ theta dtheta))
  (when (>= theta (* 2 pi))
    (set! theta (- theta (* 2 pi))))
  (add-to-history! dtheta))

;; =====================
;; mode & tan helpers (追加仕様)
;; =====================
(define (toggle-display-mode!)
  (set! display-mode (if (eq? display-mode 'sin-cos) 'tan 'sin-cos)))

(define (get-tan c s)
  (if (< (abs c) 1e-8)
      0.0   ; 特異点付近は 0 扱い（呼び出し側で分断処理）
      (/ s c)))

(define (clamp-tan t)
  (max (- TAN-CLAMP) (min TAN-CLAMP t)))

;; =====================
;; render
;; =====================
(define (draw-unit-circle dc cx cy r theta)
  ;; Only the circle outline + thin cross axes (per PLAN.md drawing order)
  ;; Thin axes (cos horizontal / sin vertical)
  (send dc set-pen AXIS-COLOR 1 'solid)
  (send dc draw-line (- cx r 18) cy (+ cx r 18) cy)
  (send dc draw-line cx (- cy r 18) cx (+ cy r 18))

  ;; Unit circle
  (send dc set-pen CIRCLE-COLOR 2.2 'solid)
  (send dc set-brush (make-color 0 0 0 0) 'solid)
  (send dc draw-ellipse (- cx r) (- cy r) (* 2 r) (* 2 r)))

(define (draw-projection-lines dc cx cy c s sine-x cos-y amp)
  (define px (+ cx (* c amp)))
  (define py (- cy (* s amp)))

  ;; sin への水平射影線（影の対応を明確に）
  (send dc set-pen PROJ-COLOR 1.4 'long-dash)
  (send dc draw-line px py sine-x py)

  ;; cos への垂直射影線（影の対応を明確に）
  (send dc draw-line px py px cos-y))

(define (draw-right-triangle dc cx cy r theta)
  ;; Right triangle O-Q-P inside the unit circle
  ;; O: center, Q: (cos θ, 0), P: (cos θ, sin θ)
  ;; Right angle at Q
  (define c (cos theta))
  (define s (sin theta))
  (define px (+ cx (* c r)))
  (define py (- cy (* s r)))
  (define qx px)
  (define qy cy)

  (send dc set-pen TRIANGLE-COLOR 1.7 'solid)

  ;; O -> Q (adjacent / cos leg, horizontal)
  (send dc draw-line cx cy qx qy)
  ;; Q -> P (opposite / sin leg, vertical)
  (send dc draw-line qx qy px py)
  ;; O -> P (hypotenuse)
  (send dc draw-line cx cy px py)

  ;; Small right-angle mark at Q (inside the angle)
  (define mark 6)
  (send dc set-pen TRIANGLE-COLOR 1.2 'solid)
  (define hx (if (> c 0) (- mark) mark))
  (define vy (if (> s 0) (- mark) mark))
  (send dc draw-line qx qy (+ qx hx) qy)
  (send dc draw-line qx qy qx (+ qy vy))
  (send dc draw-line (+ qx hx) qy (+ qx hx) (+ qy vy))  ; close the small square corner

  ;; Subtle English labels for the legs (only when large enough)
  (send dc set-font (make-font #:size 9))
  (send dc set-text-foreground LABEL-COLOR)
  (when (> (abs c) 0.25)
    (send dc draw-text "cos θ" (+ cx (* c r 0.45)) (+ cy 3)))
  (when (> (abs s) 0.25)
    (send dc draw-text "sin θ" (+ px 3) (if (> s 0)
                                            (- py 12)
                                            (+ py 3))))

  ;; Hypotenuse label "1"
  (when (and (> (abs c) 0.15) (> (abs s) 0.15))
    (send dc draw-text "1" 
          (+ cx (* c r 0.5) (if (> s 0) 5 -10))
          (- cy (* s r 0.5) (if (> s 0) 10 -2)))))

(define (draw-sine-wave dc base-x base-y history max-age amp)
  (when (and (pair? history) (> max-age 0))
    (define scale (/ SINE-WAVE-LENGTH max-age))
    (define pts
      (for/list ([e (in-list history)])
        (define age (first e))
        (define s   (third e))
        (cons (+ base-x (* age scale))
              (- base-y (* s amp)))))
    ;; 波本体（古い方から新しい方へ）
    (send dc set-pen SIN-COLOR 2.4 'solid)
    (send dc draw-lines (reverse pts))

    ;; 現在先端マーカー
    (define curr-s (third (first history)))
    (define mx base-x)
    (define my (- base-y (* curr-s amp)))
    (send dc set-pen SIN-COLOR 1 'solid)
    (send dc set-brush SIN-COLOR 'solid)
    (send dc draw-ellipse (- mx 5) (- my 5) 10 10)))

(define (draw-cosine-wave dc base-x base-y history max-age amp)
  (when (and (pair? history) (> max-age 0))
    (define scale (/ COS-WAVE-LENGTH max-age))
    (define pts
      (for/list ([e (in-list history)])
        (define age (first e))
        (define c   (second e))
        (cons (+ base-x (* c amp))
              (+ base-y (* age scale)))))
    ;; 波本体
    (send dc set-pen COS-COLOR 2.4 'solid)
    (send dc draw-lines (reverse pts))

    ;; 現在先端マーカー
    (define curr-c (second (first history)))
    (define mx (+ base-x (* curr-c amp)))
    (define my base-y)
    (send dc set-pen COS-COLOR 1 'solid)
    (send dc set-brush COS-COLOR 'solid)
    (send dc draw-ellipse (- mx 5) (- my 5) 10 10)))

;; Horizontal axes (横軸) for the waves as per additional spec
(define (draw-sine-horizontal-axis dc base-x base-y max-age amp)
  ;; sin = 0 horizontal baseline, aligned with circle center
  (define end-x (+ base-x SINE-WAVE-LENGTH))
  (send dc set-pen WAVE-AXIS-COLOR 1 'solid)
  (send dc draw-line base-x base-y end-x base-y))

(define (draw-cosine-horizontal-axis dc base-x base-y max-age amp)
  ;; Horizontal reference at the "current time" front for the cosine wave
  (send dc set-pen WAVE-AXIS-COLOR 1 'solid)
  (send dc draw-line (- base-x amp 8) base-y (+ base-x amp 8) base-y))

;; tan wave drawers (2つの構図を維持して tan を描く)
(define (draw-tan-wave-right dc base-x base-y history max-age amp)
  (when (and (pair? history) (> max-age 0))
    (define scale (/ SINE-WAVE-LENGTH max-age))
    (define segments '())
    (define current-seg '())
    (define prev-t #f)
    (for ([e (in-list (reverse history))])   ; 古い→新しい順
      (define age (first e))
      (define c (second e))
      (define s (third e))
      (define t (get-tan c s))
      (define ct (clamp-tan t))
      (define wx (+ base-x (* age scale)))
      (define wy (- base-y (* ct amp)))
      (define too-big (> (abs (- t (or prev-t t))) 8.0))  ; 大きく跳ねたら分断
      (if (or (not prev-t) too-big)
          (begin
            (when (pair? current-seg)
              (set! segments (cons (reverse current-seg) segments)))
            (set! current-seg (list (cons wx wy))))
          (set! current-seg (cons (cons wx wy) current-seg)))
      (set! prev-t t))
    (when (pair? current-seg)
      (set! segments (cons (reverse current-seg) segments)))
    (send dc set-pen TAN-COLOR 2.2 'solid)
    (for ([seg (in-list segments)])
      (when (>= (length seg) 2)
        (send dc draw-lines seg)))
    ;; 現在先端マーカー
    (define curr-t (get-tan (second (first history)) (third (first history))))
    (define ct (clamp-tan curr-t))
    (define mx base-x)
    (define my (- base-y (* ct amp)))
    (send dc set-pen TAN-COLOR 1 'solid)
    (send dc set-brush TAN-COLOR 'solid)
    (send dc draw-ellipse (- mx 5) (- my 5) 10 10)))

(define (draw-tan-wave-bottom dc base-x base-y history max-age amp)
  (when (and (pair? history) (> max-age 0))
    (define scale (/ COS-WAVE-LENGTH max-age))
    (define segments '())
    (define current-seg '())
    (define prev-t #f)
    (for ([e (in-list (reverse history))])
      (define age (first e))
      (define c (second e))
      (define s (third e))
      (define t (get-tan c s))
      (define ct (clamp-tan t))
      (define wx (+ base-x (* ct amp)))
      (define wy (+ base-y (* age scale)))
      (define too-big (> (abs (- t (or prev-t t))) 8.0))
      (if (or (not prev-t) too-big)
          (begin
            (when (pair? current-seg)
              (set! segments (cons (reverse current-seg) segments)))
            (set! current-seg (list (cons wx wy))))
          (set! current-seg (cons (cons wx wy) current-seg)))
      (set! prev-t t))
    (when (pair? current-seg)
      (set! segments (cons (reverse current-seg) segments)))
    (send dc set-pen TAN-COLOR 2.2 'solid)
    (for ([seg (in-list segments)])
      (when (>= (length seg) 2)
        (send dc draw-lines seg)))
    ;; 現在先端マーカー
    (define curr-t (get-tan (second (first history)) (third (first history))))
    (define ct (clamp-tan curr-t))
    (define mx (+ base-x (* ct amp)))
    (define my base-y)
    (send dc set-pen TAN-COLOR 1 'solid)
    (send dc set-brush TAN-COLOR 'solid)
    (send dc draw-ellipse (- mx 5) (- my 5) 10 10)))

(define (draw-labels dc)
  ;; タイトル
  (send dc set-text-foreground TEXT-COLOR)
  (send dc set-font (make-font #:size 16 #:family 'default #:weight 'bold))
  (send dc draw-text "Sine and Cosine Waves as Projections" 40 12)
  (send dc set-font (make-font #:size 15 #:family 'default #:weight 'bold))
  (send dc draw-text "of a Rotating Unit Circle" 40 30)

  ;; 各領域ラベル（英語）
  (send dc set-font (make-font #:size 11 #:weight 'normal))
  (send dc set-text-foreground LABEL-COLOR)

  ;; Unit Circle
  (send dc draw-text "Unit Circle" (- CIRCLE-CX 45) (- CIRCLE-CY CIRCLE-RADIUS 28))

  (if (eq? display-mode 'tan)
      (begin
        ;; tan mode labels (2 tan waves)
        (send dc set-text-foreground TAN-COLOR)
        (send dc draw-text "tan wave" (+ SINE-ORIGIN-X 8) (- CIRCLE-CY TAN-AMP 22))
        (send dc draw-text "tan wave" (+ CIRCLE-CX TAN-AMP 12) (+ COS-ORIGIN-Y 6)))
      (begin
        ;; sin-cos mode
        (send dc set-text-foreground SIN-COLOR)
        (send dc draw-text "sine wave" (+ SINE-ORIGIN-X 8) (- CIRCLE-CY SINE-AMP 22))
        (send dc set-text-foreground COS-COLOR)
        (send dc draw-text "cosine wave" (+ CIRCLE-CX COS-AMP 12) (+ COS-ORIGIN-Y 6)))))

(define (draw-hud dc w h)
  (define current-c (cos theta))
  (define current-s (sin theta))

  (send dc set-text-foreground TEXT-COLOR)

  ;; 左上：角度・値（タイトル下）
  (send dc set-font (make-font #:size 13 #:family 'default #:weight 'bold))
  (send dc draw-text (format "θ = ~a rad   (~a°)"
                             (~r theta #:precision '(= 3))
                             (~r (* theta (/ 180 pi)) #:precision '(= 1)))
                     40 58)

  (send dc set-font (make-font #:size 11))
  (send dc draw-text (format "cos θ = ~a" (~r current-c #:precision '(= 4))) 40 76)
  (send dc draw-text (format "sin θ = ~a" (~r current-s #:precision '(= 4))) 40 92)

  ;; 下部操作説明
  (send dc set-font (make-font #:size 11))
  (define mode-str (if (eq? display-mode 'tan) "tan (2 waves)" "sin+cos"))
  (send dc draw-text (format "speed ×~a   |   display ~a cycles   |   mode: ~a   |   space: pause   r: reset   +/-: speed   [/]: wave length   t: toggle mode"
                             (~r speed #:precision '(= 2))
                             (~r display-cycles #:precision '(= 2))
                             mode-str)
                     40 (- h 32))

  (send dc set-text-foreground (make-color 130 135 145))
  (send dc draw-text "Triangle in circle deforms with P | t: switch sin/cos <-> tan waves" 40 (- h 14)))

(define (draw-everything dc w h)
  (send dc set-smoothing 'smoothed)

  ;; 背景
  (send dc set-brush BG-COLOR 'solid)
  (send dc set-pen BG-COLOR 1 'solid)
  (send dc draw-rectangle 0 0 w h)

  (define current-c (cos theta))
  (define current-s (sin theta))
  (define max-age (get-max-age))

  ;; ラベル（タイトル含む）
  (draw-labels dc)

  ;; 1. 単位円の輪郭 + 薄い軸
  (draw-unit-circle dc CIRCLE-CX CIRCLE-CY CIRCLE-RADIUS theta)

  ;; 2. 円内の直角三角形（変形する O-Q-P）
  (draw-right-triangle dc CIRCLE-CX CIRCLE-CY CIRCLE-RADIUS theta)

  ;; 3. 現在点（強調）
  (define px (+ CIRCLE-CX (* current-c CIRCLE-RADIUS)))
  (define py (- CIRCLE-CY (* current-s CIRCLE-RADIUS)))
  (send dc set-pen POINT-COLOR 1 'solid)
  (send dc set-brush POINT-COLOR 'solid)
  (send dc draw-ellipse (- px 7) (- py 7) 14 14)

  ;; 4. 影の対応をはっきり見せる射影線（sin-cos モードのみ）
  (when (eq? display-mode 'sin-cos)
    (draw-projection-lines dc CIRCLE-CX CIRCLE-CY current-c current-s
                           SINE-ORIGIN-X COS-ORIGIN-Y CIRCLE-RADIUS))

  ;; 5. 波の横軸 + 本体（モードによる分岐）
  (if (eq? display-mode 'tan)
      (begin
        ;; tanモード: 2つの tan波（sin/cos は描かない）
        (draw-sine-horizontal-axis dc SINE-ORIGIN-X CIRCLE-CY max-age TAN-AMP)
        (draw-cosine-horizontal-axis dc CIRCLE-CX COS-ORIGIN-Y max-age TAN-AMP)
        (draw-tan-wave-right dc SINE-ORIGIN-X CIRCLE-CY history max-age TAN-AMP)
        (draw-tan-wave-bottom dc CIRCLE-CX COS-ORIGIN-Y history max-age TAN-AMP))
      (begin
        ;; sin-cosモード（従来）
        (draw-sine-horizontal-axis dc SINE-ORIGIN-X CIRCLE-CY max-age SINE-AMP)
        (draw-cosine-horizontal-axis dc CIRCLE-CX COS-ORIGIN-Y max-age COS-AMP)
        (draw-sine-wave dc SINE-ORIGIN-X CIRCLE-CY history max-age SINE-AMP)
        (draw-cosine-wave dc CIRCLE-CX COS-ORIGIN-Y history max-age COS-AMP)))

  ;; HUD
  (draw-hud dc w h))

;; =====================
;; GUI
;; =====================
(define sankaku-canvas%
  (class canvas%
    (inherit get-width get-height refresh get-dc)

    (define/override (on-paint)
      (draw-everything (get-dc) (get-width) (get-height)))

    (define/override (on-char event)
      (define key (send event get-key-code))
      (cond
        [(char=? key #\space)
         (set! paused? (not paused?))
         (refresh)]

        [(char=? key #\r)
         (reset-state!)
         (add-to-history! 0.0)
         (refresh)]

        [(or (char=? key #\+) (char=? key #\=))
         (adjust-speed! 0.2)
         (refresh)]

        [(or (char=? key #\-) (char=? key #\_))
         (adjust-speed! -0.2)
         (refresh)]

        [(char=? key #\0)
         (set! speed 1.0)
         (refresh)]

        [(char=? key #\[)
         (adjust-display-cycles! -0.25)
         (refresh)]

        [(char=? key #\])
         (adjust-display-cycles! 0.25)
         (refresh)]

        [(char=? key #\t)
         (toggle-display-mode!)
         (refresh)]))

    ;; マウス操作は不要（PLAN.md 仕様）
    ;; on-event はオーバーライドしない

    (super-new)))

;; =====================
;; ウィンドウ + タイマー
;; =====================
(define frame (new frame%
                   [label "Sankaku Racket — Sine & Cosine Projections (2D View)"]
                   [width WINDOW-WIDTH]
                   [height WINDOW-HEIGHT]
                   [min-width 980]
                   [min-height 620]))

(define canvas (new sankaku-canvas%
                    [parent frame]
                    [style '(border)]
                    [min-width WINDOW-WIDTH]
                    [min-height WINDOW-HEIGHT]))

(define timer
  (new timer%
       [notify-callback
        (λ ()
          (unless paused?
            (update-animation!)
            (send canvas refresh)))]
       [interval 15]))

;; =====================
;; 起動
;; =====================
(send frame show #t)
(reset-state!)
(add-to-history! 0.0)
(send canvas refresh)

(displayln "=== sankaku-racket (PLAN.md 仕様 2D統合ビュー + tanモード) ===")
(displayln "space : pause / resume")
(displayln "r     : reset")
(displayln "+ / - : speed")
(displayln "0     : speed = 1.0")
(displayln "[ / ] : wave display length (cycles)")
(displayln "t     : toggle sin+cos mode <-> tan mode (2 tan waves)")
(displayln "")
(displayln "sin+cos mode: Circle + sine (right) + cosine (bottom)")
(displayln "tan mode    : Circle + 2× tan waves (right vertical + bottom horizontal)  [sin/cos hidden]")
(displayln "Inside circle: right triangle (O-Q-P) that deforms with the point")
(displayln "Waves have horizontal axes. Projection lines + triangle show shadow correspondence.")