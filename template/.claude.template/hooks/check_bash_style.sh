#!/bin/bash
# bash-style.md の禁止パターンを検出してブロックする

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null)

# python3 -c / python -c によるインライン実行
if echo "$COMMAND" | grep -qE "python3? -c ['\"]|python3? -c'"; then
  echo '{"decision":"block","reason":"【bash-style.md違反】python -c によるインライン実行は禁止。./tmp/*.py を作成し uv run python ./tmp/*.py で実行すること"}'
  exit 0
fi

# python ヒアドキュメント実行
if echo "$COMMAND" | grep -qP "python3?\s+<<\s*'?EOF'?"; then
  echo '{"decision":"block","reason":"【bash-style.md違反】python ヒアドキュメント実行は禁止。./tmp/*.py を作成し uv run python ./tmp/*.py で実行すること"}'
  exit 0
fi

# source .venv/bin/activate && python
if echo "$COMMAND" | grep -qE "source .venv/bin/activate"; then
  echo '{"decision":"block","reason":"【bash-style.md違反】source .venv/bin/activate は禁止。uv run python <script> を使うこと"}'
  exit 0
fi

# source .env / set -a && source .env
if echo "$COMMAND" | grep -qE "source \.env|set -a && source"; then
  echo '{"decision":"block","reason":"【bash-style.md違反】source .env は禁止。Pythonスクリプト内で load_dotenv() を使うこと"}'
  exit 0
fi

exit 0
