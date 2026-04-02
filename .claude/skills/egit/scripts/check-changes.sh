#!/bin/bash
# egit - UserPromptSubmit hook script
# 1. 未セーブの変更が溜まったらリマインド
# 2. untrackedファイルの急増を検知して無視リスト追加を提案

# Gitリポジトリかチェック
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)

# --- 間引き（3回に1回だけチェック） ---
COUNT_FILE="$GIT_DIR/egit-check-count.txt"
COUNT=$(($(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1))
echo "$COUNT" > "$COUNT_FILE"
if [ $((COUNT % 6)) -ne 0 ]; then
  exit 0
fi

BASELINE_FILE="$GIT_DIR/egit-baseline.txt"

# --- ベースライン管理 ---
# 現在のuntrackedファイル数
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

# ベースラインが無ければ作成して終了（初回）
if [ ! -f "$BASELINE_FILE" ]; then
  echo "$UNTRACKED_COUNT" > "$BASELINE_FILE"
fi

BASELINE=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0")

# --- 急増検知 ---
SPIKE_MSG=""
DIFF=$((UNTRACKED_COUNT - BASELINE))

# 20個以上増加した場合に検知
if [ "$DIFF" -ge 20 ]; then
  # 増えたファイルのパターンを分析（上位フォルダ・拡張子を集計）
  # 上位フォルダTOP3
  TOP_DIRS=$(git ls-files --others --exclude-standard 2>/dev/null \
    | sed 's|/.*||' | sort | uniq -c | sort -rn | head -3 \
    | awk '{printf "%s(%d個) ", $2, $1}')

  # 拡張子TOP3
  TOP_EXTS=$(git ls-files --others --exclude-standard 2>/dev/null \
    | grep -o '\.[^./]*$' | sort | uniq -c | sort -rn | head -3 \
    | awk '{printf "%s(%d個) ", $2, $1}')

  SPIKE_MSG="[egit-spike] 管理対象外のファイルが${DIFF}個増えています。フォルダ別: ${TOP_DIRS}/ 拡張子別: ${TOP_EXTS}/ これらを無視リストに追加するか提案してください（「○○フォルダをセーブ対象から外しますか？」の形式で）。提案済みなら繰り返さないでください。"
fi

# --- 通常のセーブリマインド ---
CHANGED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

SAVE_MSG=""
if [ "$CHANGED_COUNT" -ge 5 ]; then
  URGENCY="normal"
  if [ "$CHANGED_COUNT" -ge 10 ]; then
    URGENCY="high"
  fi
  SAVE_MSG="[egit] 未セーブの変更が${CHANGED_COUNT}個あります (作業場所: ${CURRENT_BRANCH}, 緊急度: ${URGENCY})。回答の最後にさりげなくセーブを提案してください（「セーブして」と言ってもらう形で案内）。ただし、前回の回答で既に提案済みの場合は提案しないでください。"
fi

# --- 出力 ---
# どちらかのメッセージがあれば出力
if [ -n "$SPIKE_MSG" ] || [ -n "$SAVE_MSG" ]; then
  COMBINED=""
  [ -n "$SAVE_MSG" ] && COMBINED="$SAVE_MSG"
  if [ -n "$SPIKE_MSG" ]; then
    [ -n "$COMBINED" ] && COMBINED="$COMBINED "
    COMBINED="$COMBINED$SPIKE_MSG"
  fi

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "$COMBINED"
  }
}
EOF
fi

exit 0
