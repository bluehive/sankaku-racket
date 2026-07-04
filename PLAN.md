# sankaku-racket — 計画書 / 仕様書 (改訂版)

**日付**: 2026-07-04  
**ステータス**: ユーザー回答に基づく再検討完了版 ＋ 追加仕様追記  
**目的**: 単位円の回転を「影（射影）」として sin / cos 波に変換する様子を、**2D統合ビュー**で明確に視覚化するアニメーションを Racket 標準ライブラリのみで実装する。

---

## 1. ユーザー回答に基づく確定要件

### 質問1: レイアウト
- **円 (Unit Circle)**: ビュー左側に配置。
- **サイン波 (Sine wave)**: 円の**右側**に**縦向き**に配置（振幅方向が縦、時間軸が右方向に伸びる）。
- **コサイン波 (Cosine wave)**: 円の**下側**に**横向き**に配置（振幅方向が横、時間軸が下方向に伸びる）。
- 円周上の点を**反時計回り (CCW)** に移動させると、サイン波とコサイン波が描かれる。

### 質問2: ビューのスタイル
- **2Dの統合ビュー**で作成。
- 「影の対応（射影の対応関係）」がはっきり視覚的にわかること。
  - 現在点から水平線（sin 射影）と垂直線（cos 射影）を引き、波の現在先端に接続する。
  - 射影線により「円のY座標 → sin波」「円のX座標 → cos波」の関係が一目で理解できる。

### 質問3: 機能範囲
- **必須**:
  - 速度変更（+/-）
  - 一時停止 / 再開（space）
  - 波の表示長（周期数）の変更（例: [ / ] キー）
- **不要**:
  - マウス対応（ドラッグで角度操作は削除）
- ラベルは**英語**でよい。

---

## 2. ビジュアル設計（2D統合ビュー）

### 画面構成（概略）
```
[タイトル]

          sin θ  (右側・縦向き)
   ○――――――→  ~~~~~~~~
  /|\          /        \
 / | \        /          \
|  |  |      /   sine     \
 \ | /      /    wave      \
  \|/      /                \
   ●      /                  \
         ~~~~~~~~~~~~~~~~~~~~~   ← 現在先端（水平射影線で接続）

   cos θ  (下側・横向き)
          ← oscillate →
          ~~~~~~~~~~~~~~~
               |
               v 時間（下方向）
```

- 左: 単位円（中心に原点、反時計回り回転）
  - 円内には直角三角形（O-Q-P）を描画し、Pの移動で変形させる。
- 右: sin 波グラフ（時間右、振幅上下）。現在先端は円の右近辺に固定。
  - 横軸（sin=0 の水平基準線）を追加。
- 下: cos 波グラフ（時間下、振幅左右）。現在先端は円の下近辺に固定。
  - 横軸（現在時刻フロントの水平基準線）を追加。
- 現在点 P から:
  - **水平射影線**: P の y (=sin) を右へ伸ばし、sin波の現在値マーカーに接続（「影」）。
  - **垂直射影線**: P の x (=cos) を下へ伸ばし、cos波の現在値マーカーに接続（「影」）。
- 波は履歴をトレース。表示長（周期数）で過去の長さを制御。
- 現在点、射影マーカー、波の色で区別（sin=赤系、cos=青系）。

### 座標系（論理 → 画面）
- 数学: θ=0 で正のX軸、CCW正。
- P = (cos θ, sin θ)
- 画面Yは上方向が負（draw 座標系に注意）。

### 表示長の意味
- `display-cycles`（周期数）で制御。
- 例: 2.5 cycles → 過去 2.5 × 2π ラジアン分の履歴を表示。
- キーで 0.5〜8.0 の範囲で調整可能。調整時に履歴を即時トリム。

---

## 3. 全体構造・モジュール構成

### ファイル構成（v1）
- `main.rkt` （単一ファイルで完結。Racket GUIアプリの標準的スタイル）
  - `#lang racket/gui`
  - 内部で論理的にセクション分割（必要なら後でサブモジュール化可）

### 論理モジュール名（仕様書上の呼称）
- **`config`** — 定数定義セクション（画面サイズ、色、レイアウトパラメータ）
- **`state`** — 状態変数定義セクション
- **`animation`** — 時間進行・履歴管理関数群
- **`render`** — 描画関数群（draw-*）
- **`gui`** — canvas% / frame / timer / イベント処理
- **`main`** — エントリポイント（起動・初期化）

（実装はすべて `main.rkt` 内にトップレベルで記述。コメントで `;; === config ===` 等で区切る。）

---

## 4. 仕様：変数名 / 定数名（config + state）

```racket
;; === config (定数) ===
(define WINDOW-WIDTH          1200)
(define WINDOW-HEIGHT         820)     ; cos波を下に確保するためやや高め
(define CIRCLE-RADIUS         115)
(define CIRCLE-CX             260)     ; 円を左寄せ
(define CIRCLE-CY             295)
(define SINE-ORIGIN-X         480)     ; 円右側のsin波開始X
(define SINE-AMP              115)     ; 円と揃えて射影を直線的に
(define SINE-WAVE-LENGTH      620)     ; 視覚的な波の横幅（ピクセル）
(define COS-ORIGIN-Y          470)     ; 円下側のcos波開始Y
(define COS-AMP               115)
(define COS-WAVE-LENGTH       280)     ; 視覚的な波の下方向長さ
(define DT                    0.023)   ; 1ステップあたりの角度増分ベース
(define INITIAL-SPEED         1.0)
(define INITIAL-DISPLAY-CYCLES 2.5)
(define MIN-DISPLAY-CYCLES    0.5)
(define MAX-DISPLAY-CYCLES    8.0)
(define MAX-HISTORY           1200)    ; 安全上限

;; 色（ダークテーマ）
(define BG-COLOR        (make-color 18 20 26))
(define CIRCLE-COLOR    (make-color 245 248 255))
(define POINT-COLOR     (make-color 255 210 70))
(define COS-COLOR       (make-color 80 160 255))
(define SIN-COLOR       (make-color 255 95 105))
(define GUIDE-COLOR     (make-color 140 145 160))
(define PROJ-COLOR      (make-color 200 180 120))  ; 射影線用
(define AXIS-COLOR      (make-color 70 75 90))
(define TEXT-COLOR      (make-color 225 230 240))
(define LABEL-COLOR     (make-color 170 180 195))
```

```racket
;; === state (状態変数) ===
(define theta          0.0)     ; 現在角度 [0, 2π)
(define speed          1.0)     ; 速度倍率
(define paused?        #f)
(define display-cycles 2.5)     ; 表示する周期数（ユーザー制御）
(define history        '())     ; (list (list age c s) ...)
                                ;   age: 現在からの経過（ラジアン単位、0=現在）
                                ;   c: (cos θ_at_that_time), s: (sin ...)
```

---

## 5. 仕様：関数名 / 手続き名（animation + render）

### Animation / State 操作
| 関数名                  | シグネチャ例                          | 役割 |
|-------------------------|---------------------------------------|------|
| `reset-state!`          | `(-> void?)`                          | theta/speed/paused/display-cycles/history を初期化 |
| `add-to-history!`       | `(dtheta:real? -> void?)`             | 現在値を age=0 で追加 + 全エントリの age += dtheta + trim |
| `trim-history!`         | `(-> void?)`                          | display-cycles に基づき age >= max-age のエントリを除去 |
| `update-animation!`     | `(-> void?)`                          | 1ステップ進行（theta更新 + add-to-history! + ループ処理） |
| `adjust-speed!`         | `(delta:real? -> void?)`              | speed を delta だけ変更（範囲制限） |
| `adjust-display-cycles!`| `(delta:real? -> void?)`              | display-cycles 変更 + 即時 trim + refresh 準備 |
| `get-max-age`           | `(-> real?)`                          | (* display-cycles 2 pi) を返す |

### 描画関数（render）
| 関数名                     | シグネチャ例                                      | 役割 |
|----------------------------|---------------------------------------------------|------|
| `draw-everything`          | `(dc:dc<%>? w:real? h:real? -> void?)`            | 背景〜HUDまでの全描画エントリ |
| `draw-unit-circle`         | `(dc cx cy r theta -> void?)`                     | 単位円・軸・現在点・半径線 |
| `draw-projection-lines`    | `(dc cx cy c s sine-x cos-y amp -> void?)`        | 水平(sin)・垂直(cos) 射影線 |
| `draw-sine-wave`           | `(dc base-x base-y history max-age amp -> void?)` | sin波ポリライン + 現在マーカー |
| `draw-cosine-wave`         | `(dc base-x base-y history max-age amp -> void?)` | cos波ポリライン + 現在マーカー |
| `draw-wave-grids`          | `(dc ...)`                                        | 波領域のグリッド・周期目盛り（任意） |
| `draw-labels`              | `(dc ...)`                                        | "sine wave", "cosine wave", "Unit Circle" 等 |
| `draw-hud`                 | `(dc w h)`                                        | θ値 / cos / sin / speed / 操作説明 |

### GUI / イベント
| 名前                        | 種類          | 役割 |
|-----------------------------|---------------|------|
| `sankaku-canvas%`           | class         | on-paint / on-char のみ（on-event は実装せず） |
| `frame`                     | frame%        | メインウィンドウ |
| `canvas`                    | sankaku-canvas% | ... |
| `timer`                     | timer%        | 15ms 間隔で update + refresh（paused 時はスキップ） |
| `on-char` (override)        | method        | space / r / + / - / 0 / [ / ] 処理 |

---

## 6. キー操作仕様（英語ラベルベース）

| キー     | 動作 |
|----------|------|
| `Space`  | pause / resume |
| `r`      | reset（θ=0、履歴クリア、paused解除、display-cycles初期値） |
| `+` / `=`| speed += 0.2（上限 6.0） |
| `-` / `_`| speed -= 0.2（下限 0.1） |
| `0`      | speed = 1.0 |
| `[`      | display-cycles -= 0.25（下限 0.5） → 即 trim |
| `]`      | display-cycles += 0.25（上限 8.0） → 即 trim |

マウス操作は一切使用しない（削除）。

---

## 7. 実装フェーズ（改訂）

1. **Phase 1: 基盤 + 2Dレイアウト描画**
   - 定数・状態定義（上記名前で）
   - `draw-everything` スケルトン + 背景・タイトル
   - `draw-unit-circle`（円・現在点・軸）
   - 静的な sin/cos 領域の枠やラベル仮置き

2. **Phase 2: 射影線 + 波の現在マーカー**
   - `draw-projection-lines`
   - sin/cos の現在位置マーカー（ドット）
   - 水平・垂直の接続線が「影の対応」を明確に見せる

3. **Phase 3: 履歴管理 + 波トレース**
   - `add-to-history!` / `trim-history!` / `get-max-age`
   - `draw-sine-wave` / `draw-cosine-wave`（age に応じたオフセット計算）
   - 履歴の age を**ラジアン単位**で管理（周期計算が直感的）

4. **Phase 4: アニメーション + 制御**
   - timer コールバックと `update-animation!`
   - on-char 実装（マウスドラッグコードは**完全に削除**）
   - display-cycles 調整と即時反映

5. **Phase 5: ラベル・グリッド・HUD・調整**
   - 英語ラベル追加（Unit Circle, sine wave, cosine wave, projections など）
   - 波に薄いグリッド / π/2 ごとの目盛り（任意で視認性向上）
   - HUD に display-cycles 表示と操作説明
   - 色・線幅・位置の微調整（影の対応が際立つように）

6. **Phase 6: ドキュメント更新**
   - README.md 更新（現在の状態、実行方法、計画サマリ）
   - 本 PLAN.md を最新に保つ
   - 可能なら静的スクリーンショット追加

---

## 8. 数学的正確性ポイント

- `theta` の増加方向: **反時計回り**（`(cos theta)` がX、`(sin theta)` がY正）。
- 履歴追加時の age 単位: **ラジアン**（`(* display-cycles 2 pi)` で比較）。
- 波のスケール: 円の振幅と波の振幅を同一値（115）にして、射影線を**水平・垂直に綺麗に揃える**。
- 表示長変更時: 履歴を即トリム。スケールは描画時に `(/ visual-length max-age)` で動的計算。

---

## 9. 非目標（現フェーズ）

- 3D斜投影・床/壁表現（現在の main.rkt プロトタイプは参考のみ）
- マウスドラッグによる手動角度操作
- 日本語ラベル
- 外部3Dライブラリ（後日任意）

---

## 10. 次のアクション提案

1. この PLAN.md をレビュー。
2. 合意後、`main.rkt` を上記仕様に従って**全面的に書き換え**（または大幅リファクタ）。
3. 各 Phase ごとに動作確認（`racket main.rkt`）。
4. 最終的に README を最新の見た目・操作説明に更新。

---

## 11. 追加仕様（2026-07-04 追記）

ユーザーの追加要求に基づく拡張。

### 11.1 単位円内の直角三角形（Right Triangle in Circle）
- 単位円の内部に**直角三角形**を常時描画する。
- 三角形の3頂点（数学座標）:
  - O: 円の中心 (0, 0)
  - Q: x軸上の射影点 `(cos θ, 0)` （現在点の cos 成分を水平に落とした点）
  - P: 円周上の現在点 `(cos θ, sin θ)`
- 性質:
  - 直角は点 Q にある。
  - 辺 OQ = 隣辺 (adjacent) = `cos θ` （水平方向）
  - 辺 QP = 対辺 (opposite) = `sin θ` （垂直方向）
  - 辺 OP = 斜辺 (hypotenuse) = 1 （半径と一致）
- アニメーション:
  - 点 P が円周上を反時計回りに移動するのに合わせて、三角形全体が**連続的に変形**する。
  - θ = 0 のときは平らに潰れた状態、θ = π/2 で最大の高さ、など。
- 描画要件:
  - 3辺をはっきりした線で描画（色は GUIDE-COLOR または専用 TRIANGLE-COLOR）。
  - 点 Q に小さな**直角マーク**（小さな正方形または L 字）を描く。
  - 可能であれば各辺の近くに短い英語ラベルを付ける（例: "cos θ", "sin θ", "1" または "adj", "opp", "hyp"）。
  - 既存の半径線（O→P）は hypotenuse と重なるため活用または統合。
- 影響:
  - `draw-unit-circle` を拡張するか、新規関数 `draw-right-triangle` を追加。
  - 射影線（水平・垂直）と三角形の脚（OQ, QP）が視覚的に連動するよう調和させる。
- 推奨関数名（仕様として）:
  - `(draw-right-triangle dc cx cy r theta)`
  - または `(draw-unit-circle ...)` 内部で三角形も描くように更新。

### 11.2 サイン波・コサイン波への横軸追加
- **サイン波（右側・縦向き）** と **コサイン波（下側・横向き）** の**両方**に横軸（基準となる水平線）を追加する。
- サイン波への横軸:
  - 時間軸方向（右方向）に伸びる**水平な基準線**を引く。
  - 位置: y = CIRCLE-CY （円の中心高さと完全に揃える）。
  - この線が sin = 0 のゼロ線となる。波はこの横軸の上下に振動する。
  - 線の長さは波の表示長全体にわたる（または SINE-WAVE-LENGTH 分）。
  - 色は薄めの AXIS-COLOR または GUIDE-COLOR、線幅は 1 〜 1.5。
- コサイン波への横軸:
  - コサイン波のレイアウトでは時間軸が下方向のため振幅のゼロ基準は垂直線（x = CIRCLE-CX）になるが、**横軸**として以下を追加する:
    - 現在時刻フロント（波の開始位置）で**水平方向の基準線**を明示的に描画。
    - この水平線を「横軸」として、波がこの線から下方向へ伸び、左右に振動する様子を強調。
    - 長さはコサインの振幅範囲（±COS-AMP）をカバーする。
  - 必要に応じて、cos = 0 の位置を示す短い水平参照も補助的に追加（視認性向上）。
- 目的:
  - 波の「ゼロ位置」と「時間進行の基準」が一目でわかるようにする。
  - 特にサイン波の横軸は円の水平軸と視覚的に連結し、射影の理解を助ける。
- 実装:
  - 既存の `draw-sine-wave` / `draw-cosine-wave` を更新して軸描画を内包する。
  - または補助関数を追加:
    - `(draw-sine-horizontal-axis dc base-x base-y max-age amp)`
    - `(draw-cosine-horizontal-axis dc base-x base-y max-age amp)`
  - `draw-everything` 内で波の前に軸を描画（波が前面に来るように）。

### 11.3 更新が必要な要素（変数・関数）
**config への追加候補（必要に応じて）**:
```racket
(define TRIANGLE-COLOR   (make-color 200 200 210))
(define WAVE-AXIS-COLOR  (make-color 90 95 105))
```

**render セクションで更新/追加する関数名（仕様）**:
- `draw-right-triangle`
- `draw-sine-horizontal-axis` （または波関数に統合）
- `draw-cosine-horizontal-axis`
- `draw-unit-circle` の拡張（三角形呼び出しを追加）
- `draw-everything` 内の描画順を調整（円＋三角形 → 軸 → 射影線 → 波本体）

**既存関数の変更**:
- `draw-sine-wave`, `draw-cosine-wave` : 横軸描画ロジックを追加（または呼び出す）。
- `draw-unit-circle` : 三角形描画を呼び出す、または三角形専用関数を分離。

### 11.4 描画順序の推奨（draw-everything 内）
1. 背景
2. タイトル・ラベル
3. 単位円の輪郭 + 軸（薄い）
4. 直角三角形（OQ, QP, OP + 直角マーク）
5. 現在点の強調
6. 射影線（水平 sin / 垂直 cos）
7. 波の横軸（sine / cosine）
8. 波のトレース本体 + 現在マーカー
9. HUD

### 11.5 その他の注意点
- すべてのラベル・説明は英語のまま。
- 三角形と波の横軸は「数学的な対応関係」をより強く視覚化するためのもの。
- 性能: 追加要素はすべて少数の line/ellipse 呼び出しなので影響は極小。
- 表示長変更時も三角形は影響を受けない（現在点のみによる）。

---

## 12. 追加仕様: tan波モード（2つのtan波表示）とモード切り替え

**目的**: 既存の「円 + 右側波パネル + 下側波パネル」という**2つの構図（レイアウト）**をそのまま維持したまま、tan波をサポートする。tanモード時は cos波とsin波を一切表示せず、円 + 2つのtan波のみを表示する。ユーザーが実行中にモードを選択できる。

### 12.1 表示モード
- `sin-cos` モード（デフォルト / 従来）:
  - 円（左） + sin波（右・縦向き） + cos波（下・横向き）
- `tan` モード:
  - 円（左） + tan波1（右・縦向き構図） + tan波2（下・横向き構図）
  - sin波・cos波・それら専用のラベル・波軸は**非表示**
  - 円、三角形、現在点などは維持（または最小限調整）

切り替え方法:
- キーボード操作でトグル（例: `t` キー）
- 状態変数 `display-mode` で管理（'sin-cos または 'tan）
- 切り替え後即時 refresh

### 12.2 2つの tan波の構図維持
- **右側パネル（縦向き構図を維持）**:
  - 時間軸: 右方向
  - 振幅: 垂直（上下）
  - プロット: tan(θ) を垂直方向に
- **下側パネル（横向き構図を維持）**:
  - 時間軸: 下方向
  - 振幅: 水平（左右）
  - プロット: tan(θ) を水平方向に

これにより「2つの構図」は sin/cos の時と同じ物理的位置・方向性で tan波を表示する。

### 12.3 tan(θ) の計算と特別扱い
- tan(θ) = sin(θ) / cos(θ)
- 履歴データ（age, c, s）から都度計算
- 不連続（asymptote: cos(θ) ≈ 0 の π/2 + kπ 付近）:
  - 波の線を分断する（連続した polyline として描かない）
  - 点生成時に |cos| < epsilon の前後でセグメントを分割
- 表示範囲制御:
  - `TAN-CLAMP`（例 5.0〜6.0）で値をクランプ
  - `TAN-AMP`（sin/cosより小さめの値、例 40-50）を別途定義して画面に収める
- 色: TAN-COLOR を定義（例 緑系）

### 12.4 共通で表示する要素（両モード）
- 単位円（左）
- 直角三角形（tan = opp/adj の理解に有用なので維持）
- 現在点 P
- 波の横軸（tanモードでも右パネルに水平軸、下パネルにフロント水平軸を利用）
- HUD（現在のモード表示を追加）

### 12.5 モード別表示内容
- sin-cos モード:
  - sin/cos 波 + 専用ラベル + 専用横軸 + 射影線
- tan モード:
  - 2つの tan波 + "tan wave" ラベル（右側/下側それぞれ）
  - 射影線は非表示（または tan 特有の接線投影に後で拡張可）
  - sin/cos 関連ラベルを抑制

### 12.6 追加する名前（仕様書として）
**状態**:
```racket
(define display-mode 'sin-cos)  ; 'sin-cos | 'tan
```

**config**:
```racket
(define TAN-AMP 45)
(define TAN-CLAMP 5.5)
(define TAN-COLOR (make-color 100 210 130))
```

**関数名**:
- `(draw-tan-wave-right dc base-x base-y history max-age amp)`
- `(draw-tan-wave-bottom dc base-x base-y history max-age amp)`
- `(toggle-display-mode!)` または `(set-display-mode! mode)`
- `draw-everything` 内の条件分岐（mode による波の出し分け）
- ラベル処理をモード対応（draw-labels または別ヘルパー）

**キー操作**（追加）:
- `t` : モード切り替え (sin-cos ↔ tan)
- 既存の space/r/+/-/0/[/] は両モードで共通に有効

### 12.7 HUD / 説明の更新
- HUD に現在モードを表示（例: "mode: sin+cos" / "mode: tan (2 waves)"）
- コンソール起動メッセージにモード切り替え説明を追加
- タイトルやラベルはモードに応じて動的に "tan wave" を使用

### 12.8 注意・エッジケース
- tan の周期は π（sin/cos は 2π）。表示長（display-cycles）は同じ値で視覚的に tan の方が「速く」感じるが許容。
- クランプ + 分断処理で asymptote 近辺の描画が崩れないようにする。
- 初回実装では tan 特有の射影線（原点から P を延長して x=1 の接線に当てる）は任意。将来的に追加可能。
- 性能影響は小さい（tan計算は軽い）。

### 12.9 実装ステップ提案
1. PLAN.md に本セクションを追加（仕様明確化）
2. 状態変数 `display-mode` と toggle 関数追加
3. config に TAN-* 定数 + 色追加
4. `draw-tan-wave-right` / `draw-tan-wave-bottom` 実装（clamp + 分断ロジック）
5. `draw-everything` をモード分岐に修正（sin/cos 系を if で隠す）
6. ラベル/HUD/キー/起動メッセージをモード対応
7. テスト: 両モードの切り替え、tanの不連続点での見た目、sin/cos 隠蔽の確認

---

**MIT License**（Racket パブリック公開時のデフォルトに従う）

この計画書は、ユーザーの3質問への回答をすべて反映し、モジュール・変数・関数名を仕様レベルで明示した改訂版です。
（2026-07-04 追加仕様セクション追記済み）
