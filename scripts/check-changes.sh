#!/bin/bash
# egit - UserPromptSubmit hook script
# 未セーブの変更が溜まったらClaudeにリマインドを注入する

# Gitリポジトリかチェック
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# 変更ファイル数を取得（untracked + modified + staged）
CHANGED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# 5個未満なら何もしない
if [ "$CHANGED_COUNT" -lt 5 ]; then
  exit 0
fi

# 現在のブランチ
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

URGENCY="normal"
if [ "$CHANGED_COUNT" -ge 10 ]; then
  URGENCY="high"
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[egit] 未セーブの変更が${CHANGED_COUNT}個あります (作業場所: ${CURRENT_BRANCH}, 緊急度: ${URGENCY})。回答の最後にさりげなくセーブを提案してください（「セーブして」と言ってもらう形で案内）。ただし、前回の回答で既に提案済みの場合は提案しないでください。"
  }
}
EOF

exit 0
