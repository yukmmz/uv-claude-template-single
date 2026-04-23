# ARCHITECTURE.md — nlinfit_flapaero_pipeline (ワークスペース全体)

> **目的**: このドキュメントはコードを一行も読まなくても、外部AI（Gemini等）や研究パートナーがシステム構造を90%把握し、同様の実装を再構成できることを目標とする。実装の詳細ではなく、設計の「なぜ」と「何を」を記述する。

---

## 1. System Core Concept

### 解決する研究課題

昆虫の羽ばたき翼の**空力係数を CFD シミュレーション結果から同定する**。

具体的には：

- HLCFD（羽ばたき専用CFDソルバー）が出力する時系列データ（翼の位置・姿勢・速度・力・トルク）を読み込む
- 準定常（Quasi-Steady）空力モデルを仮定し、**翼速度・迎角・Reynolds数**の関数として揚力・抗力を表現する
- **LASSO + Levenberg-Marquardt（Ridge 正則化）**の2段階回帰により、66 または 109 個のパラメータを同定する
- 同定されたパラメータが物理的に妥当か（CL/CD vs AoA 曲線）を検証する

### パイプラインの概要

```
CFD シミュレーション
      │ HLCFD 出力ファイル群
      ▼
[Stage 1] 01_parse_cfd.py
      │ 無次元→有次元変換 + 座標系統一
      ▼ cfd_1w_sample.elem.hdf5 (hierarchical)
      │
      ├──[Stage 2a] make_wing_morph.py
      │        │ グリッドファイル → 翼形態メタデータ
      │        ▼ HM_wing_morph.hdf5
      │
      └──[Stage 2b] optimize_rep_points.py
               │ 34 代表点の最適座標を決定
               ▼ HM_rep_points.hdf5
                    │
      ┌─────────────┘
      │
      ▼
[Stage 3] 02_prep_fitdata.py
      │ KinematicsCalculator → 607 派生変数
      ▼ dataset_{insect}.hdf5 (flat, 前処理済み)
      │
      ▼
[Stage 4] run_fitting() / run_e2e.py
      │ LASSO [5] → 再正規化 [5.5] → LM+Ridge [6]
      ▼ PipelineResult (k_final, RMSE/NRMSE, CL/CDプロット)
```

---

## 2. Workspace 構造

UV workspace（`pyproject.toml` でメンバー管理）として3つのリポジトリが共存する。

```
nlinfit_flapaero_pipeline/         ← ワークスペースルート（本ファイルの所在）
├── flapcfd_io/                    ← CFD I/O ライブラリ（独立 Git リポジトリ）
│   ├── src/flapcfd_io/
│   │   ├── core.py                FlappingData / Component (Reader API)
│   │   ├── builder.py             FlappingDataBuilder (Writer API)
│   │   └── math_utils.py          純粋数学関数群
│   └── scripts/examples/
│       └── convert_cfd_to_h5.py   HLCFD 1W → .elem.hdf5 変換スクリプト例
│
├── nlinfit_flapaero/              ← 空力係数同定ライブラリ（独立 Git リポジトリ）
│   ├── src/nlinfit_flapaero/
│   │   ├── pipeline.py            E2E パイプライン（公開API）
│   │   ├── preprocessing/
│   │   │   └── kinematics.py      KinematicsCalculator（派生変数一括計算）
│   │   ├── models/
│   │   │   ├── base.py            BaseAeroModel (ABC)
│   │   │   ├── aerodynamics.py    cl21, cl32, cd_si, cd_co 関数
│   │   │   ├── model_66param.py   QuasiSteadyModel66
│   │   │   └── model_109param.py  UnsteadyModel109
│   │   ├── fitting/
│   │   │   ├── base.py            BaseFitter (ABC), FitResult
│   │   │   ├── linear.py          LassoFitter, LassoCVFitter, ElasticNetFitter
│   │   │   └── nonlinear.py       LMFitter
│   │   └── data_loading/
│   │       ├── mat_data_loader.py  MatDataLoader, StructElement
│   │       ├── hdf5_data_loader.py HDF5DataLoader
│   │       ├── mat_path_finder.py  MatPathFinder
│   │       └── elem_parser.py      ElemParser
│   └── scripts/
│       └── run_e2e.py             run_fitting() API + CLI エントリーポイント
│
├── scripts/                       ← ワークスペースレベルのオーケストレーション
│   ├── 01_parse_cfd.py            CFD出力 → elem.hdf5
│   ├── 02_prep_fitdata.py         elem.hdf5 + rep_points → dataset.hdf5
│   └── utils/
│       ├── make_wing_morph.py     グリッド → 翼形態 HDF5
│       └── optimize_rep_points.py 翼形態 → 代表点 HDF5
│
└── data/
    ├── processed/
    │   ├── cfd_1w_sample.elem.hdf5   (Stage 1 出力)
    │   └── dataset_HM.hdf5           (Stage 3 出力、フィッティング入力)
    ├── wing_morph/
    │   ├── HM_wing_morph.hdf5        (Stage 2a 出力)
    │   └── HM_rep_points.hdf5        (Stage 2b 出力)
    └── output/run_e2e/
        └── clcd_fa_zl.png            (Stage 4 出力)
```

---

## 3. 各 Stage の詳細

### Stage 1: `01_parse_cfd.py` — CFD 出力 → 統一 HDF5

**入力**: HLCFD ソルバーが出力する複数テキストファイル（Fortran 倍精度形式 `1.23d-04`）  
**出力**: `REMOTE_ROOT/data/processed/cfd_1w_sample.elem.hdf5`（階層型 HDF5）

**処理の要点**:
- `parse_inpF()`: `.ini` パラメータファイルから Lref, Uref, tconv, Fconv, Nconv, kin_vis を直接読み取る（Reynolds数からの逆算ではなく直接値を使用）
- `flapcfd_io.FlappingDataBuilder` を使い、無次元→有次元変換後に統一スキーマへ書き込む
- グローバル座標系と翼固定座標系の変換は `flapcfd_io.math_utils` が担う

**出力 HDF5 スキーマ**（`flapcfd_io` 規約）:
```
/metadata/kinematics/     回転軸・ストロークプレーン定義
/kinematics/              time, euler_angles, position（全コンポーネント）
/dynamics/                force, torque（全コンポーネント）
/otherparams/             cm_dim, winglength_dim, kin_vis（スカラー）
```

---

### Stage 2a: `make_wing_morph()` — グリッドファイル → 翼形態 HDF5

**入力**: HLCFD グリッドファイル (`.grid`)、INP パラメータファイル (`.ini`)  
**出力**: `data/wing_morph/{insect_id}_wing_morph.hdf5`

**処理の要点**:
- 翼の LE/TE スプラインを 3 次補間（n_be=100 分割）
- 翼面積 S_wing、一次・二次面積モーメント S_x, S_y, S_xx, S_yy, S_xy を計算
- 翼重心（wing_centroid）、回転半径（rad_gyr）、翼端（WT_coord）、後縁（TE_coord）座標を出力

**用途**: Stage 2b（代表点最適化）の入力。また S_wing 等は Stage 4 の `QuasiSteadyModel66._build_amat_lin()` が設計行列構築に使用する。

---

### Stage 2b: `optimize_rep_points()` — 翼形態 → 代表点 HDF5

**入力**: `HM_wing_morph.hdf5`  
**出力**: `data/wing_morph/{insect_id}_rep_points.hdf5`

**代表点とは**: 空力モデルの各物理効果（CL21, CL32, CDsi, CDco など）において、時刻ごとの代表的な速度・迎角を計算する翼面上の座標点。

**34 代表点メンバー**:

| 方向 | 効果種別 | 速度種別 | 合計 |
|------|---------|---------|------|
| chordwise (`c_`) | CL21, CL32, CDsi, CDco | tra, rv, cp, al | 16 |
| spanwise (`s_`) | CL21, CL32, CDsi, CDco | tra, rv, cp | 12 |
| spanwise (`s_`) | rotL | al | 1 |
| chordwise (`c_`) | rotL | al | 1 |

**最適化方法**: 乱数キネマティクス（n_rand=50 セット × n_kin=1000 タイムステップ）を生成し、各メンバーについて翼面上の全格子点から **相関係数最大の点** を選ぶ。

**出力 HDF5 構造**:
```
/RepPoint/{name}     (2,) float64  最適代表点座標 [x, y]（翼面上）
/RepPoint_rand/      最適化時の乱数データ（デバッグ用）
/corrs/              各メンバーの最終相関係数
S_wing, S_x, S_y, S_xx, S_yy, S_xy  翼面積モーメント（スカラー）
wing_centroid, WT_coord, TE_coord     重要座標（(2,) 配列）
cm_dim               平均翼弦長 [m]
```

---

### Stage 3: `02_prep_fitdata.py` — ブリッジ層（前処理済み HDF5 生成）

**入力**: `cfd_1w_sample.elem.hdf5` + `HM_rep_points.hdf5`  
**出力**: `REMOTE_ROOT/data/processed/dataset_HM.hdf5`（フラット構造、607 フィールド + 12 otherparams）

これがパイプラインの**最重要ブリッジ**であり、CFD 側と回帰側の責任分離点となっている。

**処理フロー**:
```
[1] FlappingData(elem.hdf5)
    → _extract_raw_fields()
    → 34 基本フィールド
       (time_dim, v_w_xl/yl/zl, omega_w_xl/yl/zl × 瞬時+1Dt8,
        WRG11..WRG33, fa_xl/yl/zl, ma_w_xl/yl/zl, pos_w/ele_w/fea_w)

[2] rep_points.hdf5
    → _load_morph_from_rep_points()
    → wing_centroid, WT_coord, TE_coord, S_wing, S_x/y/xx/yy/xy, cm_dim

[3] KinematicsCalculator.from_hdf5(rep_points.hdf5)
    .calculate(se)
    → 607 フィールド（34基本 + 573 派生）

[4] _write_dataset()
    → /field_name: float64[N] (top-level, flat)
    → /otherparams/: スカラー + ベクトル
```

**1Dt8 前進シフト**: 非定常空力モデルは「現在の AoA」と「8 ステップ先の AoA」の差を特徴量として使用する（加速・減速による非定常効果）。`_shift_forward(arr, 8)` で全速度・迎角を 8 タイムステップ分前進コピーする。

---

### Stage 4: `run_fitting()` / `run_e2e.py` — E2E フィッティング

**入力**: `dataset_{insect}.hdf5`（1本以上）  
**出力**: `PipelineResult`、CL/CD 妥当性プロット

```python
# 使用例（Python API）
import os
from nlinfit_flapaero.scripts.run_e2e import run_fitting

remote = os.getenv("REMOTE_ROOT")
dataset = f"{remote}/data/processed/dataset_HM.hdf5"

result = run_fitting(
    train_files=[dataset],
    test_files =[dataset],
    model_name      ="66",
    target_variable ="fa_zl",
    plot_clcd=True,
)
print(result.metrics_kfinal.nrmse_te)
```

---

## 4. Textual Class Diagram

### 4.1 flapcfd_io — CFD データ読み書き

```
FlappingDataBuilder                          ← Write-side (mutable)
│  method-chain パターン
│  set_metadata() / set_otherparams() / set_time()
│  add_component(name, rot_axes, ...) → self
│  build(path) → self
│
└─ 書き込み先: {stem}.elem.hdf5

                ↕ HDF5 ファイル

FlappingData                                 ← Read-side (immutable)
├── .time         NDArray(N,)
├── .body         Body
├── .wing_R       Wing
└── .wing_L       Wing (存在する場合)

Component (ABC)
├── cached_property .rotmat   (N,3,3)
│    Body: euler_to_rotmat(angles, rot_seq)
│    Wing: R_body @ R_spa @ R_wing_local    ← 3段階合成
├── cached_property .velocity (N,3)
│    numpy.gradient による数値微分
├── .get_force(frame)         (N,3)
│    frame ∈ {"local", "global", "body"}
└── .get_torque(target, frame) (N,3)
     target ∈ {"hinge", "com"}
     "com": モーメント移動式 T_B = T_A + r×F
```

### 4.2 nlinfit_flapaero — 空力係数同定

```
StructElement                                ← データコンテナ（両ローダーが返す）
├── .fields: dict[str, NDArray]              607 時系列フィールド
├── .trvate: NDArray[int]                    12=trva / 3=te フラグ
└── .otherparams: dict[str, Any]            12 スカラー/ベクトル

     ↑ 生成
MatDataLoader   .load(mat_paths, elemcell)  ← .mat ファイル群
HDF5DataLoader  .load(trva_files, te_files)  ← dataset.hdf5

     ↓ 変換 (Stage 3 完了後は不要)
KinematicsCalculator
├── .from_mat(rep_mat_path)    ← MATLAB .mat から代表点読み込み
├── .from_hdf5(rep_points_hdf5) ← HDF5 から代表点読み込み
└── .calculate(se) → se       607 フィールドに拡張

     ↓ 設計行列構築
BaseAeroModel (ABC)
├── .get_design_matrix(se) → NDArray(N, n_lin)   線形設計行列
├── .predict(k, se)        → NDArray(N,)          予測値
├── .jacobian(k, se)       → NDArray(N, n_params) ヤコビアン
└── 実装クラス:
    QuasiSteadyModel66   (n_params=66, n_lin=43)
    UnsteadyModel109     (n_params=109, n_lin=?)

     ↓ 最適化
BaseFitter (ABC)
├── .fit(model, se, y, k_init) → FitResult
└── 実装クラス:
    LassoFitter          sklearn.Lasso, 固定 alpha
    LassoCVFitter        k-fold 交差検証で alpha 自動選択
    LMFitter             scipy Levenberg-Marquardt + Ridge

FitResult: params, cost, n_iter, success, message

     ↓ 統合
run_pipeline_files(trva_files, te_files, objname, config)
    → PipelineResult
        .k_final       (66,) 最終パラメータ
        .metrics_kfinal  RMSE/NRMSE
        .data           PipelineData (keep_data=True 時)
```

---

## 5. Mathematical & Logical Background

### 5.1 準定常空力モデル（QuasiSteadyModel66）

翼に作用する空気力を翼固定座標系で以下のように分解する：

$$F_z = \sum_{j} k_j^{lin} \cdot A_j(v, \omega, \theta) \cdot f_{Re}(k^{nlin}, Re) + k_{intercept}$$

**設計行列 A の列構造**（43 列）:

| 列番号 | 物理効果 | 基底関数 |
|--------|---------|---------|
| 0–2 | 翼弦方向 CL21 × {tra, rv, cp} | $\alpha(\alpha - \pi/2) \cdot v^2$ |
| 3–5 | 翼弦方向 CL32 × {tra, rv, cp} | $\alpha^2(\alpha - \pi/2) \cdot v^2$ |
| 6–8 | 翼弦方向 CDsi × {tra, rv, cp} | $\sin^2(\alpha) \cdot v^2$ |
| 9–11 | 翼弦方向 CDco × {tra, rv, cp} | $\cos^2(\alpha) \cdot v^2$ |
| 12–15 | 非定常 CL/CD（加速度） | $(f(\alpha_{1Dt8}) v_{1Dt8} - f(\alpha) v) \cdot \text{sign}(a) \sqrt{|a|}$ |
| 16–21 | 回転揚力・翼端摩擦・加速度 | 各種積項 |
| 22–42 | 翼幅方向（翼長方向）の同様の効果 | y方向速度・AoA 使用 |

**AoA 関数**:
- $\text{CL21}(\alpha) = \alpha(\alpha - \pi/2)$  — 失速前後で符号反転
- $\text{CL32}(\alpha) = \alpha^2(\alpha - \pi/2)$  — 高 AoA での修正項
- $\text{CDsi}(\alpha) = \sin^2(\alpha)$  — 垂直抗力成分
- $\text{CDco}(\alpha) = \cos^2(\alpha)$  — 法線方向成分

### 5.2 Reynolds 数スケーリング（非線形パラメータ k[44:65]）

Reynolds 数依存を各物理効果グループに乗じるスケール因子として表現する：

| 効果 | スケール関数 | パラメータ |
|------|------------|---------|
| 翼弦方向 L.tra CL | $\exp(k_{44} \cdot Re_{xz}^{k_{45}})$ | k[44], k[45] |
| 翼弦方向 CDsi | $\exp(k_{46} \cdot Re_{xz}^{k_{47}})$ | k[46], k[47] |
| 翼弦方向 CDco | $Re_{xz}^{k_{48}}$ | k[48] |
| 翼弦方向 回転 | $\exp(k_{49} \cdot Re_{xz}^{k_{50}})$ | k[49], k[50] |
| 翼弦方向 摩擦 | $\exp(k_{51} \cdot Re_{xz}^{k_{52}})$ | k[51], k[52] |
| 翼弦方向 附加質量 | $1 + k_{53} \cdot Re_{xyz}^{k_{54}}$ | k[53], k[54] |
| 翼幅方向 × 6効果 | （同様、Re_yz 使用） | k[55:65] |

初期値は Lee et al. 2016 (B&B) の実験値。

**Reynolds 数の定義**（代表点 GEN = 翼重心での速度）:

$$Re_{xz} = \frac{c_m \cdot \overline{|v_{xz,GEN}|}}{\nu}, \quad Re_{yz} = \frac{c_m \cdot \overline{|v_{yz,GEN}|}}{\nu}, \quad Re_{xyz} = \frac{c_m \cdot \overline{|v_{GEN}|}}{\nu}$$

### 5.3 2段階最適化アルゴリズム

**Stage 1 — LASSO（線形パラメータの選択）**:

$$\hat{k}^{lin} = \arg\min_{k} \|A k - y\|_2^2 + \alpha \|k\|_1$$

- 設計行列 A を列標準偏差で正規化（`stdtr` を注入）
- 不要な特徴量を 0 に落として疎な解を得る
- $\alpha$ は固定値または `LassoCVFitter` で 5-fold CV 自動選択

**Stage 1.5 — 再正規化**:

$$\text{maBn} = \text{mean}(|k_1^{lin}|), \quad k_1^{lin} \leftarrow k_1^{lin} / \text{maBn}$$

Ridge ペナルティが全パラメータに均等に効くよう線形係数を O(1) スケールに揃える。

**Stage 2 — LM+Ridge（非線形最適化）**:

$$\hat{k} = \arg\min_{k} \|r(k)\|_2^2 + \lambda \|M \cdot k\|_2^2$$

- $r(k) = y - \hat{y}(k)$: 残差ベクトル
- $M$: Ridge ペナルティマスク（全 66 パラメータに適用）
- scipy `least_squares(method='lm')` + 人工残差行追加で Ridge を実現

### 5.4 代表点速度の計算

翼面上の代表点 $(x_{rep}, y_{rep})$（翼固定座標）での速度（翼固定フレーム）:

$$\begin{pmatrix} v_{rx} \\ v_{ry} \\ v_{rz} \end{pmatrix} = \begin{pmatrix} v_{w,xl} \\ v_{w,yl} \\ v_{w,zl} \end{pmatrix} + \boldsymbol{\omega}_w \times \begin{pmatrix} x_{rep} \\ y_{rep} \\ 0 \end{pmatrix}$$

ここで $v_{w,\cdot}$ は翼固定座標系での並進速度、$\boldsymbol{\omega}_w$ は同フレームでの角速度。

---

## 6. HDF5 スキーマ一覧

### 6.1 `cfd_1w_sample.elem.hdf5`（flapcfd_io 出力）

```
/metadata/kinematics/  rot_axes, angle_names, stroke_plane_axis, etc.
/kinematics/
  time                 [N]
  stroke_plane_angle   [N]
  {comp}/position      [N,3]
  {comp}/euler_angles  [N,3]   Wing は SPA 相対角
/dynamics/
  {comp}/force         [N,3]   翼固定フレーム
  {comp}/torque        [N,3]   ヒンジ点周り、翼固定フレーム
/otherparams/
  cm_dim, winglength_dim, kin_vis   float64 スカラー
```

### 6.2 `HM_rep_points.hdf5`（代表点最適化出力）

```
/RepPoint/{name}       (2,) float64  最適代表点 [x, y]（34 メンバー）
/RepPoint_rand/        (n_rand, 2)  最適化時の乱数データ
/corrs/                ()  各メンバーの最終相関係数
S_wing, S_x, S_y, S_xx, S_yy, S_xy  翼面積モーメント [m^n]
wing_centroid, WT_coord, TE_coord   (2,) 配列
cm_dim                 float64 スカラー
```

### 6.3 `dataset_{insect}.hdf5`（Stage 3 フラット出力）

```
/{field_name}          float64[N]  607 個の時系列フィールド（全て直下）
/otherparams/
  cm_dim               float64 スカラー  [m]
  kin_vis              float64 スカラー  [m^2/s]
  winglength_dim       float64 スカラー  [m]
  S_wing               float64 スカラー  [m^2]
  S_x, S_y             float64 スカラー  [m^3]
  S_xx, S_yy, S_xy     float64 スカラー  [m^4]
  wing_centroid        float64[2]  翼重心座標 [m]
  WT_coord             float64[2]  翼端座標 [m]
  TE_coord             float64[2]  後縁座標 [m]
```

**主要フィールドカテゴリ**:

| カテゴリ | 例 | 数 |
|---------|----|----|
| 基本キネマティクス | `v_w_xl`, `omega_w_xl`, `WRG11`..`WRG33` | ~15 |
| 空力・トルク | `fa_xl`, `fa_yl`, `fa_zl`, `ma_w_xl/yl/zl` | 6 |
| Euler 角 | `pos_w`, `ele_w`, `fea_w`, `pit_b/rol_b/yaw_b` | 6 |
| 1Dt8 前進シフト版 | `v_w_xl_1Dt8`, `omega_w_xl_1Dt8` 等 | ~12 |
| 代表点速度・迎角 | `vrx_{name}`, `AoAx_{name}` (34 メンバー × 2 方向) | ~340 |
| Reynolds 数 | `Re_xz`, `Re_yz`, `Re_xyz`, `Re_te`, `Re_wt` | 7 |
| 翼重心 (GEN) | `vrx_GEN`, `ary_GEN`, `AoAy_GEN` 等 | ~15 |
| 角加速度 | `domega_w_xl`, `domega_w_yl` | 2 |

---

## 7. Research Hypotheses & Roadblocks

### 現在検証中の仮説

1. **HDF5 前処理パイプラインの等価性**: `02_prep_fitdata.py` が生成する `dataset_HM.hdf5` は、MATLAB 参照実装が `.mat` ファイル経由で生成する SE（StructElement）と等価な特徴量を持つ。
   - **現状**: 動作確認済み（`run_fitting()` が完走、NRMSE k_final = 0.20 @train=test）
   - **未検証**: MATLAB との数値一致（NRMSE が MATLAB 参照値と同等かどうか）

2. **代表点最適化の妥当性**: 34 代表点の乱数探索（n_kin=1000, n_rand=50）で選ばれた座標が、真の最適代表点に近い。
   - **現状**: アルゴリズムは実装済み。物理的妥当性（CL/CD 曲線のピーク位置）は `plot_clcd_validity()` で確認可能。

### 既知の設計上の制限

- **KinematicsCalculator が `from_mat()` と `from_hdf5()` の2つのファクトリを持つ**: MATLAB ワークフローとの後方互換性維持のため。将来的には HDF5 路線に一本化予定。
- **domega_w_xl/yl の数値微分精度**: `_finite_diff()` は前進・中央・後退差分の1次精度。翼端の急峻な加速度変化では誤差が大きい可能性がある。
- **trvate フラグが 12/3 ハードコード**: MATLAB 規約から継承。HDF5 モードでは全データが同一ファイル内のため train/test の物理的分離がない（同一データでの自己評価になる）。

---

## 8. Trade-offs

| 設計決定 | 採用理由 | 不採用の代替案 |
|---------|---------|-------------|
| **dataset.hdf5 をフラット構造にする** | HDF5DataLoader が単純なキー列挙でロード可能、読み込み速度最大化 | 階層構造（カテゴリ別グループ）— 人間には読みやすいが処理が複雑化 |
| **Stage 3 で全派生変数を事前計算** | Step 4 で KinematicsCalculator をスキップでき、複数回の fitting を高速化 | オンデマンド計算（fitting 時に計算）— ストレージ削減だが fitting ループが遅い |
| **kin_vis を .ini から直接読む** | Uref × Lref / Re から逆算すると丸め誤差が伝播する | Re からの逆算（参照実装の一部がこの方式） |
| **run_pipeline_files() を別関数として追加** | 既存の run_pipeline() の MAT ワークフローを壊さず HDF5 路線を追加 | run_pipeline() に if 分岐を増やす（既存コードへの影響を避けるため分離） |
| **代表点座標を (x, y) 2D に限定** | 翼面内の 2D 座標で十分（z 方向はゼロ） | 3D 座標（不要な自由度） |
| **CL/CD プロットを run_fitting() 内でオプション化** | フィッティング後に物理妥当性確認まで一気通貫で行える | 別スクリプトとして分離（ユーザーが手動で呼ぶ手間が増える） |
