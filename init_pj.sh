#!/bin/bash


# このシェルファイルのディレクトリへ移動
cd "$(dirname "$0")"

TEMPLATE_DIR='template'

# 1. 親プロジェクトディレクトリの作成と移動
# コマンドライン引数で受け取る
PROJECT_ROOT=$1
# エラーチェック
if [ -z "$PROJECT_ROOT" ]; then
  echo "Usage: $0 <project_root_directory>"
  exit 1
fi

# TEMPLATE_DIR を再起的にコピーして、PROJECT_ROOTの名前にする
cp -r $TEMPLATE_DIR output/$PROJECT_ROOT

cd output/$PROJECT_ROOT

# 3. uv プロジェクト初期化
uv init

# # pyproject.toml に以下を追記
# cat <<EOL >> pyproject.toml
# [tool.uv.workspace]
# members = [
# ]

# [tool.uv.sources]
# flapcfd-io = { workspace = true, editable = true }
# nlinfit-flapaero = { workspace = true, editable = true }

# [[tool.mypy.overrides]]
# module = ["h5py", "h5py.*", "scipy", "scipy.*", "nlinfit_flapaero", "nlinfit_flapaero.*", "flapcfd_io", "flapcfd_io.*"]
# ignore_missing_imports = true
# EOL

# # 4. フォルダ構造の作成 (データとスクリプト)
# mkdir -p data/input data/output data/processed
# mkdir -p scripts tests src

# # 空フォルダをGit管理するためのダミーファイル
# touch data/input/.gitkeep
# touch data/processed/.gitkeep
# touch data/output/.gitkeep

# # 7. CLAUDE関連ファイルフォルダ の作成 (AIへの全体指示)
# bash /Users/yukmmz/my_scripts/shell/init_claude.sh $PROJECT_ROOT

# .claude/以下のすべてのmdファイルに対して、 {{PROJECT_NAME}} をプロジェクト名に置換
# ex.) .claude/rules/rules.md の {{PROJECT_NAME}} を $PROJECT_ROOT に置換
# macOS (BSD sed) と Linux (GNU sed) で -i のシグネチャが異なるため分岐
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE=(-i '')
else
  SED_INPLACE=(-i)
fi
find .claude -type f -name "*.md" -exec sed "${SED_INPLACE[@]}" "s/{{PROJECT_NAME}}/$PROJECT_ROOT/g" {} \;

# memo.tmp.txt を作成
# ../../version の中身から数字（"1.0.0"など）を読み取り、
# それを memo.tmp.txt に "version: 1.0.0" の形式で書き込む
VERSION=$(cat ../../version)
echo "version: $VERSION" > memo.tmp.txt


# # make initial commit
# git add .
# git commit -m "Initial commit: Project structure and uv workspace setup"

echo "Project initialized at: $PROJECT_ROOT"

