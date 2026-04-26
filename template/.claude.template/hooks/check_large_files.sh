#!/bin/bash
# git の変更ファイルに2MB超がないかチェック
# 以下のコマンドでフックとして登録してください
# chmod +x .claude/hooks/check_large_files.sh

LIMIT_BYTES=$((2 * 1024 * 1024))  # 2MB
FOUND=0

# ステージング前の変更ファイルを取得
while IFS= read -r file; do
  [ -f "$file" ] || continue
  size=$(wc -c < "$file")
  if [ "$size" -gt "$LIMIT_BYTES" ]; then
    echo "WARNING: $file is $(( size / 1024 / 1024 ))MB (超過)" >&2
    FOUND=1
  fi
done < <(git diff --name-only 2>/dev/null)

if [ "$FOUND" -eq 0 ]; then
  echo "OK: 2MB超のファイルはありません"
fi