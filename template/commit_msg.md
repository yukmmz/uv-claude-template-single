fix: ruff + mypy lint pass on scripts/

- scripts/01_parse_cfd.py: E702 — セミコロン区切り複数文を1行1文に分割（回転行列代入 6箇所）
- scripts/02_prep_fitdata.py: F841 — 未使用変数 N を削除
- scripts/utils/make_wing_morph.py: E402 — import 順を整理（load_dotenv をインポート群の末尾へ移動、matplotlib.pyplot に # noqa: E402 を付与）
- pyproject.toml: [tool.mypy.overrides] を追加（h5py / scipy / nlinfit_flapaero / flapcfd_io の import-untyped を抑制）

- scripts/01_parse_cfd.py: デフォルト出力先を REMOTE_ROOT/data/processed/ に変更
  - _resolve_remote_root() ヘルパーを追加し _resolve_input_path() と共有
  - main() の output_path デフォルトを _resolve_remote_root() ベースに変更
- scripts/02_prep_fitdata.py: import os / load_dotenv を追加
  - _DEFAULT_ELEM, _DEFAULT_OUTPUT を REMOTE_ROOT ベースに変更（None ガード付き）
  - main() に REMOTE_ROOT 未設定時の EnvironmentError チェックを追加
- README.md: gitignore 表に data/processed/*.hdf5 の説明を追記
