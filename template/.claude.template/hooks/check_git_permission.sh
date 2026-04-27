#!/bin/bash
# git add / git commit は /commit コマンド実行中のみ許可する

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git add / git commit 以外はスキップ（通常のパーミッション処理に委ねる）
echo "$COMMAND" | grep -qE '^git (add|commit)( |$)' || exit 0

# マーカーファイルがあれば許可（deny ルールを上書き）
if [ -f "/tmp/claude_commit_mode" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

# /commit コマンド外からの実行 → ブロック
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git add / git commit は /commit コマンド経由でのみ実行できます。"}}'
exit 0
