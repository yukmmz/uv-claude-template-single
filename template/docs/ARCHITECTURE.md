# ARCHITECTURE.md

## 1. System Core Concept

本プロジェクトは、TurtleBot に搭載された 6ch 歪みゲージ（ひげセンサ）の時系列データから、
**接触検出** および **接触荷重分類・回帰**を行うパイプラインを構築することを目的とする。

コアアプローチ：
- **Reservoir Computing (RC)**：ESN/EuSN ベースのリザバーで時系列を固定ネットワークに投影し、
  読み出し層（リッジ回帰）のみを学習する。これにより少数データでも過学習しにくい特徴量抽出を実現。
- **接触検出（RPD）**：スライディングウィンドウ方式の閾値ベース検出器で、
  反応点インデックスを推定。Optuna によってハイパーパラメータを自動最適化する。

---

## 2. Textual Class / Module Diagram

```
src/analysis_turtlebot_strain_gauge/
├── config.py                          # 共通定数: N_SENSORS=6, SENSOR_COLS=[AI0_V..AI5_V],
│                                      #   DT=0.01, WEIGHT_TO_CLASS={1:0,2:1,3:2}, etc.
├── preprocessing/                     # Track A: データ前処理パイプライン
│   ├── dat_loader.py                  # DatLoader → DatRecord(time_s, signals:(T,6))
│   ├── csv_loader.py                  # AprilTagCsvLoader → CameraRecord(robot_track, obstacle_tracks)
│   │                                  #   ロボット識別: 累積移動量最大タグ
│   ├── trial_loader.py                # TrialLoader → list[Trial(meta, dat, camera)]
│   │                                  #   ファイル名パース: W(\d+)_S(\d+)_A(-?\d+)_O(-?[\d.]+)_T(\d+)
│   ├── pose_computer.py               # PoseComputer → PoseTimeSeries(elapsed_s, angle_deg, offset_norm)
│   │                                  #   ロボット正面方向 = tag.angle_deg + 90° [ASSUMPTION]
│   │                                  #   相対角度: v_fwd を CCW に angle だけ回すと v_boxface になる角度
│   │                                  #   (v_boxface = 障害物4面法線のうち v_fwd となす角が最小のもの, ≤45°)
│   │                                  #   範囲 (-45°, +45°), CCW+, 側方オフセット右=正
│   └── dataset_builder.py             # DatasetBuilder → dataset_task{1,2,3}.pkl
│                                      #   Task1: ndarray(N,T_max,6) パディング済み
│                                      #   Task2/3: list[ndarray(T_i,6)] 可変長
├── reservoir/
│   ├── config.py                      # ReservoirConfig dataclass
│   ├── topology.py                    # W行列ビルダー群 + LIFA + 可視化ユーティリティ
│   └── core.py                        # NNReservoir, ReservoirPredictor, save/load_checkpoint
│                                      #   追加: reservoir_forward_sequence, fit_ridge_regression_sequence
└── contact_detection/
    └── detector.py                    # ContactSegment, ReactionIndexDetector, load_best_params

scripts/
├── build_datasets.py                  # 前処理パイプライン実行エントリーポイント
│                                      #   引数: --hp-rpd (RPDハイパラJSON), --n-pre, --out
├── make_trial_video.py                # 全試行の可視化動画を1本のMP4に結合
│                                      #   引数: --fps, --window, --tag-size, --dpi, --out
├── auto_annotate_rpd.py               # カメラ速度から反応点を自動アノテーション → Optuna最適化
│                                      #   LEAD_OFFSET_S=-1.35s (ひげ接触→ロボット減速の時差)
│                                      #   --optimize で RPD Optuna 最適化を続けて実行
│                                      #   最適化結果: data/output/hp_rpd/hyper_param_rpd_auto.json
│                                      #   [ASSUMPTION] tag_size_mm=250mm (未検証; 実測値は~100mmの可能性)
├── train_task1.py                     # Task1: 6ch センサ全試行 → 荷重クラス分類
│                                      #   reservoir_forward(X:(N,T,6)) → H:(N,n_units) → fit_ridge → argmax
│                                      #   --optuna N で Optuna 探索 (w_mode, n_units, alpha, variant 等)
│                                      #   出力: result_task1.json, predictions_task1.json (stems/cm/per-class)
│                                      #   ベースライン (drosophila,n=300): val=61.5%, test=53.8%
├── train_task2.py                     # Task2: 6ch センサ接触区間 → 相対角度時系列 [deg]
│                                      #   reservoir_forward_sequence → fit_ridge_regression_sequence
│                                      #   |angle|>90° の外れ値試行を除外 (2試行: tag誤識別疑い)
│                                      #   出力: result_task2.json, predictions_task2.json (stems/binned-cm/per-trial)
│                                      #   _PRED_BINS: -45°〜+45° 5°刻み (18 bins)
│                                      #   ベースライン (drosophila,n=300): val RMSE=21.0°, r=0.18
├── train_task3.py                     # Task3: 6ch センサ接触区間 → 側方オフセット時系列 (正規化)
│                                      #   train_task2.py と同構造; 出力のみ異なる
│                                      #   出力: result_task3.json, predictions_task3.json (stems/binned-cm/per-trial)
│                                      #   _PRED_BINS: -1.5〜+1.5 等間隔 16点 (15 bins)
│                                      #   ベースライン (drosophila,n=300): val RMSE=0.964, r=0.098
├── run_topology_sweep.sh              # 17トポロジ × 3タスク の Optuna 並列スイープ
│                                      #   --test: 5トポロジ・30試行, --n-jobs: 並列数, --n-optuna: 試行数
│                                      #   出力: data/output/topology_sweep/{topo}/task{1,2,3}/
├── plot_topology_results.py           # スイープ結果の一括可視化 (8種 PDF)
│                                       #   bar_metrics / confusion_{1,2,3} / scatter_{2,3} / timeseries_{2,3}
└── build_topology_sweep_report.py     # スイープ結果集計 → reports/<topic>/<topic>_analysis.md
                                       #   引数: --sweep-dir, --topic
                                       #   出力: 自動生成セクション (表/設定/図) + 手動「主要所見」
```

### モジュール間の依存関係

- `visualization/video_maker.py` → `preprocessing/trial_loader.py`, `preprocessing/pose_computer.py`, `config.py`
- `preprocessing/dataset_builder.py` → `preprocessing/trial_loader.py`, `pose_computer.py`, `contact_detection/detector.py`, `config.py`
- `preprocessing/pose_computer.py` → `preprocessing/csv_loader.py`, `config.py`
- `preprocessing/trial_loader.py` → `preprocessing/dat_loader.py`, `preprocessing/csv_loader.py`
- `reservoir/core.py` → `reservoir/topology.py`（W_BUILDERS, load_droso_cache, is_eusn, LIFA）
- `reservoir/core.py` → `reservoir/config.py`（ReservoirConfig）
- `scripts/optimize_contact_detection.py` → `contact_detection/detector.py`

---

## 3. Mathematical & Logical Background

### Reservoir Computing (EuSN/ESN)

**EuSN ステップ更新（連続時間近似）**：
```
pre_t = W_in x_t + W_hh h_t + b
s_t   = activation(pre_t - γ h_t)
h_{t+1} = h_t + ε s_t
```
ε（euler step size）と γ（damping）がコアハイパーパラメータ。
W_hh は反対称行列（`W - W^T`）に設定されることで Euler 法でのエネルギー保存性を近似。

**ESN（leaky）ステップ更新**：
```
pre_t = W_in x_t + W_hh h_t + b
s_t   = tanh(pre_t)
h_{t+1} = (1 - α) h_t + α s_t
```

**読み出し（リッジ回帰）**：
```
W_out = argmin_W ||H W - Y||^2 + α ||W||^2
```
拡張行列法：`[H; sqrt(α) I] W = [Y; 0]` を lstsq で解く。

分類用（fit_ridge）はクラス不均衡補正（inverse frequency weighting）付き。
回帰用（fit_ridge_regression）はシンプルな L2 正則化のみ。

### 相対角度の計算（PoseComputer）

AprilTag の `angle_deg` は `atan2(top_edge_y, top_edge_x)` （画像座標、y下向き）。

障害物 AprilTag の**4つの内側向き法線**（ワールド座標）:

```
normals_world[k] = -obs_angle_rad + k * π/2,  k = 0, 1, 2, 3
```

（画像 → ワールド変換: y 軸を反転するため `obs_angle_deg` を否定）

**相対角度アルゴリズム**:
1. ロボット正面ベクトルをワールド座標で計算:  
   `fwd_world = arctan2(-fwd_y, fwd_x)`  （fwd = image-space の forward）
2. 4法線のうち `fwd_world` となす角が最小（必ず ≤ 45°）の法線を `v_boxface` として選択
3. `angle = v_boxface - fwd_world`（-π, π] に正規化

**物理的意味**:
- `angle > 0`: ロボットが箱の左面から当たる（v_fwd を CCW に回すと v_boxface と一致）
- `angle < 0`: ロボットが箱の右面から当たる
- `angle = 0`: 正面衝突
- `angle` は障害物の回転角 `obs_angle_deg` のみに依存し、ロボットの側方位置（offset）とは独立

### 接触検出（ReactionIndexDetector）

スライディングウィンドウ内でベース統計（mean, std）を計算し、
`thresh_detect = base_mean ± factor_detect * base_std` を超える点が
`n_seq_outside` 点連続したとき「反応検出」とみなす。
反応点は検出点から後方にさかのぼり、stand 閾値内に戻った最初の点。

---

## 4. Topology Zoo

`W_BUILDERS` に登録された重み行列生成関数：

| キー | トポロジ |
|---|---|
| random | 一様乱数密行列 |
| delay_line | 一方向チェーン |
| delay_line_feedback | 双方向チェーン |
| cyclic | 単方向リング |
| double_cyclic | 双方向リング |
| self_feedback_cyclic | リング+自己ループ |
| self_feedback_double_cyclic | 双方向リング+自己ループ |
| multiplexed_cyclic | 多オフセットリング |
| lattice | 2Dグリッド（非周期） |
| torus | 2Dグリッド（周期） |
| small_world | Watts-Strogatz |
| modular | Stochastic Block Model |
| scale_free | Barabási-Albert |
| mesh | 高密度完全グラフ |
| star | ハブ+スポーク |
| mesh_ring | mesh+ring 複合 |
| star_mesh | mesh+star 複合 |
| mode_block | 2×2 回転ブロック（反対称） |
| drosophila | ショウジョウバエコネクトーム |

EuSN 以外のモードでは全トポロジが `construct_weight_matrix` によりスペクトル半径正規化される。

---

## 5. Trade-offs

| 設計選択 | 採用理由 | 不採用案 |
|---|---|---|
| リッジ回帰読み出し | 閉形式解・少数データ対応 | MLP読み出し（過学習リスク） |
| スライディングウィンドウ RPD | 実装シンプル・解釈性高い | NN ベース検出（ラベル収集コスト） |
| src レイアウト + uv | 標準的パッケージング | スクリプト直置き |
| topology.py / core.py 分割 | SRP 遵守・テスト容易 | 単一ファイル（参照実装の形式） |

---

## 6. Data Flow

```
REMOTE_ROOT/
├── W{w}_S{s}_A{a}_O{o}_T{t}.dat        # センサ (100Hz, CSV, AI0_V..AI7_V)
└── W{w}_S{s}_A{a}_O{o}_T{t}_apriltag.csv  # カメラ (30fps, 24列)

        ↓ TrialLoader (DatLoader + AprilTagCsvLoader)
Trial(meta, dat: DatRecord, camera: CameraRecord)

        ↓ PoseComputer                     ↓ ReactionIndexDetector
PoseTimeSeries(angle_deg, offset_norm)    reaction_idx (int)
(30fps → 100Hz, np.interp で補間)

        ↓ DatasetBuilder (合成)

dataset_task1.pkl:
  X_{train,val,test} (N, T_max, 6) float32  ← パディング済み全試行信号
  y_{train,val,test} (N,) int               ← 荷重クラス {0:W1, 1:W2, 2:W3}
  stems_{train,val,test} list[str]           ← ファイル stem (ファイル名から拡張子除く)

dataset_task2.pkl / task3.pkl:
  X_{train,val,test} list[ndarray(T_i, 6)]  ← 接触区間信号 (反応点以降)
  y_{train,val,test} list[ndarray(T_i,)]    ← 角度[deg] / 正規化側方オフセット
  stems_{train,val,test} list[str]           ← ファイル stem

        ↓ train_task{1,2,3}.py (Phase 3 — 未実装)

NNReservoir.reservoir_forward()         → H (N, n_units)  [Task1]
NNReservoir.reservoir_forward_sequence() → H (N, T, n_units) [Task2/3]

        ↓ fit_ridge / fit_ridge_regression_sequence
読み出し重み W_out → 予測
```

実験データの統計・データ品質問題・ベースライン結果・研究仮説の検証状況は `docs/RESEARCH_MEMO.md` を参照。
