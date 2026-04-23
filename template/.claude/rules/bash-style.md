# Bash コマンドのスタイルルール

## Pythonのインライン実行を禁止
以下のパターンは全て禁止：
- `python3 -c "..."` での複数行インラインコード
- `python3 << 'EOF' ... EOF` のヒアドキュメント形式

代わりに一時スクリプトファイルを作成して実行すること：
- ファイル作成: `./tmp/check_*.py`
- 実行: `uv run python ./tmp/check_something.py`

## Python実行コマンド
- `source .venv/bin/activate && python3` を極力使わない
- `uv run python <script>` のように、可能な限り `uv` を使うこと

## .env の扱い
- シェルで `source .env` や `set -a && source .env && set +a` を使わない
- Pythonスクリプト内で `load_dotenv()` を使って .env を読み込むこと