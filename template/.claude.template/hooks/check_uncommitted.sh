#!/bin/bash
# セッション内で1回だけ、未コミットの変更をチェックしてユーザーに確認を促す

SESSION_FILE="/tmp/claude_uncommitted_checked_${CLAUDE_SESSION_ID:-default}"

# 既に確認済みならスキップ
[ -f "$SESSION_FILE" ] && exit 0
touch "$SESSION_FILE"

# git リポジトリでなければスキップ
git rev-parse --git-dir > /dev/null 2>&1 || exit 0

# 未コミットの変更を確認
UNCOMMITTED=$(git status --porcelain 2>/dev/null)
[ -z "$UNCOMMITTED" ] && exit 0

# 未コミットの変更がある場合、ブロッキングエラーで通知
echo "未コミットの変更があります。このまま作業を開始しますか？"
echo ""
git status --short 2>/dev/null
exit 2
