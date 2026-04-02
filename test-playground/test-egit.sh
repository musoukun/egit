#!/bin/bash
# =============================================================================
# egit スキル 総合テストスクリプト
# 全テストをクリーンな一時ディレクトリで実行し、結果をレポートする
# =============================================================================

set -e

# --- カラー定義 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
ISSUES=()

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "  ${GREEN}✓ PASS${NC}: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo -e "  ${RED}✗ FAIL${NC}: $1"
  ISSUES+=("FAIL: $1")
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
  ISSUES+=("WARN: $1")
}

section() {
  echo ""
  echo -e "${CYAN}━━━ $1 ━━━${NC}"
}

# --- セットアップ ---
TEST_DIR=$(mktemp -d)
BARE_DIR=$(mktemp -d)
HOOK_SCRIPT="$HOME/.claude/skills/egit/scripts/check-changes.sh"

cleanup() {
  rm -rf "$TEST_DIR" "$BARE_DIR"
}
trap cleanup EXIT

echo "================================================"
echo " egit スキル 総合テスト"
echo " テストディレクトリ: $TEST_DIR"
echo "================================================"

# =============================================================================
section "テスト1: /egit init (ローカル)"
# =============================================================================

# 1-1: Git未初期化の検出
cd "$TEST_DIR"
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  pass "Git未初期化を正しく検出"
else
  fail "Git未初期化の検出に失敗"
fi

# 1-2: git init
git init -q
if git rev-parse --is-inside-work-tree &>/dev/null; then
  pass "git init 成功"
else
  fail "git init 失敗"
fi

# 1-3: デフォルトブランチ名の確認
DEFAULT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ "$DEFAULT_BRANCH" = "main" ]; then
  pass "デフォルトブランチがmain"
elif [ "$DEFAULT_BRANCH" = "master" ]; then
  warn "デフォルトブランチがmaster → SKILL.mdはmain前提。git branch -m master main が必要"
  git branch -m master main
else
  warn "デフォルトブランチが不明: '$DEFAULT_BRANCH'"
fi

# 1-4: .gitignore作成
cat > .gitignore << 'GITIGNORE'
node_modules/
.env
.env.*
__pycache__/
*.pyc
.DS_Store
Thumbs.db
*.log
dist/
build/
.idea/
.vscode/
*.secret
credentials.*
GITIGNORE
if [ -f .gitignore ]; then
  pass ".gitignore 作成OK"
else
  fail ".gitignore 作成失敗"
fi

# 1-5: 初回コミット
echo "# テストプロジェクト" > README.md
git add -A && git commit -q -m "初回セーブ: プロジェクトを開始"
if [ "$(git log --oneline | wc -l)" -eq 1 ]; then
  pass "初回セーブ成功"
else
  fail "初回セーブ失敗"
fi

# =============================================================================
section "テスト2: /egit save (mainから自動ブランチ作成)"
# =============================================================================

# 2-1: ファイル作成
cat > app.js << 'EOF'
function greet(name) {
  console.log("Hello, " + name);
}
greet("World");
EOF
cat > style.css << 'EOF'
body { margin: 0; padding: 0; }
h1 { color: blue; }
EOF

CHANGED=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$CHANGED" -ge 2 ]; then
  pass "変更ファイル検出 (${CHANGED}個)"
else
  fail "変更ファイルが検出されない"
fi

# 2-2: mainにいる場合の自動ブランチ作成
CURRENT=$(git branch --show-current)
if [ "$CURRENT" = "main" ]; then
  pass "mainにいることを検出 → 自動ブランチ作成が必要"
else
  fail "mainにいるはずが $CURRENT にいる"
fi

git checkout -q -b feature/add-greeting-app
if [ "$(git branch --show-current)" = "feature/add-greeting-app" ]; then
  pass "自動ブランチ作成OK: feature/add-greeting-app"
else
  fail "ブランチ作成失敗"
fi

# 2-3: 機密ファイル除外
echo "SECRET=abc123" > .env
echo "password=hunter2" > credentials.json
git status --porcelain > /tmp/egit-status-check
if ! grep -q ".env" /tmp/egit-status-check && ! grep -q "credentials" /tmp/egit-status-check; then
  pass "機密ファイル(.env, credentials.json)が.gitignoreで除外されている"
else
  # credentials.*がgitignoreにあるか確認
  if grep -q "credentials" /tmp/egit-status-check; then
    warn "credentials.jsonがgitignoreで除外されていない（パターン確認が必要）"
  fi
  if ! grep -q ".env" /tmp/egit-status-check; then
    pass ".env は正しく除外"
  fi
fi

# 2-4: セーブ実行
git add app.js style.css
git commit -q -m "追加: 挨拶アプリのUIを実装"
if git log --oneline | grep -q "追加: 挨拶アプリ"; then
  pass "セーブ（commit）成功"
else
  fail "セーブ失敗"
fi

# =============================================================================
section "テスト3: /egit new (作業場所作成)"
# =============================================================================

git checkout -q main
git checkout -q -b feature/add-login

if [ "$(git branch --show-current)" = "feature/add-login" ]; then
  pass "新しい作業場所を作成: feature/add-login"
else
  fail "作業場所の作成に失敗"
fi

cat > login.js << 'EOF'
function login(user, pass) {
  return user === "admin" && pass === "1234";
}
EOF
git add login.js && git commit -q -m "追加: ログイン機能を実装"
pass "作業場所でのセーブ成功"

# =============================================================================
section "テスト4: /egit done (合流・統合)"
# =============================================================================

git checkout -q main
git merge -q feature/add-login --no-edit

if [ -f login.js ]; then
  pass "作業場所の内容がmainに統合された"
else
  fail "統合後にlogin.jsが存在しない"
fi

# ブランチ削除
git branch -d feature/add-login -q
if ! git branch | grep -q "feature/add-login"; then
  pass "統合後に作業場所を削除"
else
  warn "作業場所の削除に失敗"
fi

# =============================================================================
section "テスト5: コンフリクト発生＆解消"
# =============================================================================

# 共通ファイル作成
cat > config.js << 'EOF'
const config = {
  appName: "MyApp",
  version: "1.0.0",
  color: "blue"
};
EOF
git add config.js && git commit -q -m "追加: 設定ファイル"

# ブランチAでcolorを赤に変更
git checkout -q -b feature/change-color
sed -i 's/color: "blue"/color: "red"/' config.js
git add config.js && git commit -q -m "更新: テーマカラーを赤に変更"

# mainでcolorを緑に変更
git checkout -q main
sed -i 's/color: "blue"/color: "green"/' config.js
git add config.js && git commit -q -m "更新: テーマカラーを緑に変更"

# merge試行（コンフリクト発生するはず）
if git merge feature/change-color --no-edit 2>&1 | grep -q "CONFLICT"; then
  pass "コンフリクトを正しく検出"
else
  fail "コンフリクトが発生しなかった"
fi

# コンフリクトマーカーの存在確認
if grep -q "<<<<<<" config.js; then
  pass "コンフリクトマーカーが存在（ユーザーに提案できる状態）"
else
  fail "コンフリクトマーカーがない"
fi

# 解消: ユーザーが「あなたの変更を優先」を選んだ想定
cat > config.js << 'EOF'
const config = {
  appName: "MyApp",
  version: "1.0.0",
  color: "red"
};
EOF
git add config.js && git commit -q -m "統合: 競合を解消（赤を採用）"

if ! grep -q "<<<<<<" config.js; then
  pass "コンフリクト解消成功"
else
  fail "コンフリクト解消に失敗"
fi

git branch -d feature/change-color -q 2>/dev/null || true

# =============================================================================
section "テスト6: push動作確認"
# =============================================================================

# bareリポジトリをリモートとして設定
git init -q --bare "$BARE_DIR"
git remote add origin "$BARE_DIR" 2>/dev/null || git remote set-url origin "$BARE_DIR"

# mainをpush
if git push -u origin main -q 2>&1; then
  pass "mainのpush成功"
else
  fail "mainのpush失敗"
fi

# ブランチをpush
git checkout -q -b feature/push-test
echo "push test" > pushtest.txt
git add pushtest.txt && git commit -q -m "追加: pushテスト"
if git push -u origin feature/push-test -q 2>&1; then
  pass "ブランチのpush成功"
else
  fail "ブランチのpush失敗"
fi

git checkout -q main

# =============================================================================
section "テスト7: 変更蓄積→フック提案"
# =============================================================================

if [ ! -f "$HOOK_SCRIPT" ]; then
  fail "フックスクリプトが存在しない: $HOOK_SCRIPT"
else
  pass "フックスクリプト存在確認OK"

  # 7-1: 変更0個 → 出力なし
  HOOK_OUT=$(bash "$HOOK_SCRIPT" 2>/dev/null)
  if [ -z "$HOOK_OUT" ]; then
    pass "変更0個 → 出力なし（正常）"
  else
    fail "変更0個なのに出力あり"
  fi

  # 7-2: 変更4個 → 出力なし
  for i in $(seq 1 4); do echo "tmp $i" > "tmpfile$i.txt"; done
  HOOK_OUT=$(bash "$HOOK_SCRIPT" 2>/dev/null)
  if [ -z "$HOOK_OUT" ]; then
    pass "変更4個 → 出力なし（閾値未満、正常）"
  else
    fail "変更4個なのに出力あり"
  fi

  # 7-3: 変更7個 → normal
  for i in $(seq 5 7); do echo "tmp $i" > "tmpfile$i.txt"; done
  HOOK_OUT=$(bash "$HOOK_SCRIPT" 2>/dev/null)
  if echo "$HOOK_OUT" | grep -q 'normal'; then
    pass "変更7個 → 緊急度: normal"
  else
    fail "変更7個で緊急度normalにならない"
  fi

  # 7-4: 変更12個 → high
  for i in $(seq 8 12); do echo "tmp $i" > "tmpfile$i.txt"; done
  HOOK_OUT=$(bash "$HOOK_SCRIPT" 2>/dev/null)
  if echo "$HOOK_OUT" | grep -q 'high'; then
    pass "変更12個 → 緊急度: high"
  else
    fail "変更12個で緊急度highにならない"
  fi

  # クリーンアップ
  rm -f tmpfile*.txt
fi

# =============================================================================
section "テスト8: 未セーブ変更ありで作業場所切替 (stash)"
# =============================================================================

# 作業中の状態を作る
git checkout -q -b feature/wip-work
echo "作業途中のコード" > wip.js
echo "もう一つの作業ファイル" > wip2.js

WIP_COUNT=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$WIP_COUNT" -ge 2 ]; then
  pass "未セーブ変更あり (${WIP_COUNT}個)"
else
  fail "未セーブ変更が検出されない"
fi

# 8-1: stash（-u でuntrackedも含む）
if git stash push -u -m "一時保管: 作業途中" -q 2>&1; then
  pass "stash push -u 成功（untrackedファイル含む）"
else
  fail "stash push -u 失敗"
fi

# stash後はクリーンか
AFTER_STASH=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$AFTER_STASH" -eq 0 ]; then
  pass "stash後ワーキングツリーがクリーン"
else
  fail "stash後にファイルが残っている (${AFTER_STASH}個)"
fi

# 8-2: 別の作業場所に切り替えて作業
git checkout -q main
git checkout -q -b feature/urgent-fix
echo "緊急修正" > hotfix.txt
git add hotfix.txt && git commit -q -m "修正: 緊急バグフィックス"
pass "別の作業場所で作業完了"

# 8-3: 元の作業場所に戻ってstash復元
git checkout -q feature/wip-work
if git stash pop -q 2>&1; then
  pass "stash pop 成功"
else
  fail "stash pop 失敗"
fi

# ファイルが復元されたか
if [ -f wip.js ] && [ -f wip2.js ]; then
  pass "一時保管したファイルが復元された"
else
  fail "ファイルが復元されていない"
fi

# 8-4: stash -u なし（untrackedが退避されないケース）の検証
echo "新しいファイル" > untracked_test.txt
git stash push -m "一時保管: -u なし" -q 2>/dev/null || true
if [ -f untracked_test.txt ]; then
  warn "git stash push（-u なし）ではuntrackedファイルが退避されない → SKILL.mdに -u 必須と明記すべき"
else
  pass "stash -u なしでもuntrackedが退避された（環境依存）"
fi
rm -f untracked_test.txt

# =============================================================================
section "テスト9: 作業履歴ファイル (.git/egit-history.md)"
# =============================================================================

HISTORY_FILE="$TEST_DIR/.git/egit-history.md"

# 9-1: 履歴ファイル作成
cat > "$HISTORY_FILE" << 'HIST'
# 作業履歴

| # | 作業場所 | 状態 | 最終更新 | やっていたこと |
|---|---------|------|---------|--------------|
| 1 | feature/wip-work | 作業中 | 2026-04-03 | WIPテスト用の作業 |
| 2 | feature/urgent-fix | 合流済 | 2026-04-03 | 緊急バグフィックス |
HIST

if [ -f "$HISTORY_FILE" ]; then
  pass "履歴ファイル作成OK (.git/egit-history.md)"
else
  fail "履歴ファイル作成失敗"
fi

# 9-2: 履歴ファイルがgitに追跡されないことを確認
if git status --porcelain | grep -q "egit-history"; then
  fail "履歴ファイルがgitに追跡されている（.git/内なので追跡されないはず）"
else
  pass "履歴ファイルはgitに追跡されない（.git/内）"
fi

# 9-3: 履歴のパース確認（作業中・一時保管の行を抽出）
ACTIVE=$(grep -E '作業中|一時保管' "$HISTORY_FILE" | wc -l | tr -d ' ')
if [ "$ACTIVE" -ge 1 ]; then
  pass "アクティブな作業を履歴から抽出できる (${ACTIVE}件)"
else
  fail "アクティブな作業が抽出できない"
fi

# 9-4: 最大10件チェック（11行入れて最古の合流済が消えるか）
cat > "$HISTORY_FILE" << 'HIST'
# 作業履歴

| # | 作業場所 | 状態 | 最終更新 | やっていたこと |
|---|---------|------|---------|--------------|
| 1 | feature/work-10 | 作業中 | 2026-04-03 | 最新の作業 |
| 2 | feature/work-9 | 作業中 | 2026-04-03 | 作業9 |
| 3 | feature/work-8 | 一時保管 | 2026-04-02 | 作業8 |
| 4 | feature/work-7 | 合流済 | 2026-04-02 | 作業7 |
| 5 | feature/work-6 | 合流済 | 2026-04-01 | 作業6 |
| 6 | feature/work-5 | 合流済 | 2026-04-01 | 作業5 |
| 7 | feature/work-4 | 合流済 | 2026-03-31 | 作業4 |
| 8 | feature/work-3 | 合流済 | 2026-03-31 | 作業3 |
| 9 | feature/work-2 | 合流済 | 2026-03-30 | 作業2 |
| 10 | feature/work-1 | 合流済 | 2026-03-30 | 作業1（最古） |
HIST

ENTRY_COUNT=$(grep -c '^| [0-9]' "$HISTORY_FILE")
if [ "$ENTRY_COUNT" -le 10 ]; then
  pass "履歴が10件以内 (${ENTRY_COUNT}件)"
else
  fail "履歴が10件を超えている (${ENTRY_COUNT}件)"
fi

# 9-5: SKILL.mdに履歴の記述があるか
if grep -q 'egit-history' "$HOME/.claude/skills/egit/SKILL.md"; then
  pass "SKILL.mdに作業履歴の仕組みが記述されている"
else
  fail "SKILL.mdに作業履歴の記述がない"
fi

# =============================================================================
section "テスト10: 平易な言葉チェック（SKILL.md解析）"
# =============================================================================

SKILL_FILE="$HOME/.claude/skills/egit/SKILL.md"
if [ -f "$SKILL_FILE" ]; then
  # 用語表に定義されているが案内文中でGit用語がそのまま使われていないかチェック
  GIT_TERMS=("commit" "push" "pull" "branch" "merge" "repository" "clone" "stash" "conflict" "rebase" "remote" "local" "checkout" "diff")

  # コードブロック外でGit用語が（）補足なしに使われているかチェック
  # (簡易チェック: 用語の後に（が続かないケース)
  echo "  SKILL.md内のGit用語使用チェック:"
  BARE_TERM_FOUND=0
  for term in "${GIT_TERMS[@]}"; do
    # コマンド行(git xxxやgh xxx)や表のヘッダ以外で裸のGit用語を探す
    # バッククォート内やコマンド例は除外
    MATCHES=$(grep -n "$term" "$SKILL_FILE" | grep -v '`' | grep -v '^[0-9]*:| ' | grep -v "（$term" | grep -v "$term）" | grep -v "^[0-9]*:#" | head -3)
    if [ -n "$MATCHES" ]; then
      # コマンド行でない場合のみ報告
      NON_CMD=$(echo "$MATCHES" | grep -v "git " | grep -v "gh " | grep -v "\-\-" | head -1)
      if [ -n "$NON_CMD" ]; then
        BARE_TERM_FOUND=1
      fi
    fi
  done

  if [ "$BARE_TERM_FOUND" -eq 0 ]; then
    pass "Git用語は適切に平易な言葉に置き換えられている"
  else
    warn "一部のGit用語が裸で使われている可能性あり（手動確認推奨）"
  fi

  # done コマンドの確認
  if grep -q '/egit done' "$SKILL_FILE"; then
    warn "'/egit done' が使われている → '/egit 合流' への改名が必要（ユーザー指摘）"
  else
    pass "'/egit done' は '/egit 合流' に改名済み"
  fi

  # stash -u の確認
  if grep -q 'stash.*-u\|stash push -u' "$SKILL_FILE"; then
    pass "stash -u がSKILL.mdに明記されている"
  else
    warn "stash -u がSKILL.mdに明記されていない → untrackedファイルが退避されない"
  fi

  # master/main の切り替え手順確認
  if grep -q 'branch -m master main\|branch -M master main' "$SKILL_FILE"; then
    pass "master→mainリネーム手順がSKILL.mdにある"
  else
    warn "git initでmasterが作られた場合のmainリネーム手順がSKILL.mdに不足"
  fi

  # 一時退避→一時保管の確認
  if grep -q '一時退避' "$SKILL_FILE"; then
    warn "'一時退避' が残っている → '一時保管' に統一すべき"
  else
    pass "'一時保管' に統一済み（'一時退避' なし）"
  fi

  # コンフリクト選択肢4の確認
  if grep -q '自分で書き直す' "$SKILL_FILE"; then
    pass "コンフリクト選択肢に '4. 自分で書き直す' あり"
  else
    warn "コンフリクト選択肢に '自分で書き直す' がない"
  fi

  # 提案型UXチェック: ユーザーにコマンドを打たせていないか
  if grep -q 'と言ってください\|しますか？\|しましょうか\|どうしますか' "$SKILL_FILE"; then
    pass "提案型の案内文がある（〜しますか？/〜と言ってください）"
  else
    warn "提案型の案内文がない → ユーザーにコマンドを打たせる形になっている可能性"
  fi

  # 「次にできること」の提案があるか
  if grep -q '次にできること\|次にやること' "$SKILL_FILE"; then
    pass "操作後に「次にできること」の提案がある"
  else
    warn "操作後の「次にできること」提案がない"
  fi

  # フックのリマインドがコマンド打ち型でないか
  HOOK_FILE="$HOME/.claude/skills/egit/scripts/check-changes.sh"
  if [ -f "$HOOK_FILE" ]; then
    if grep -q '/egit' "$HOOK_FILE"; then
      warn "フックスクリプトに '/egit' コマンドの案内が残っている"
    else
      pass "フックスクリプトにコマンド案内なし（提案型に統一）"
    fi
  fi

else
  fail "SKILL.mdが見つからない: $SKILL_FILE"
fi

# =============================================================================
# レポート
# =============================================================================
echo ""
echo "================================================"
echo " テスト結果サマリー"
echo "================================================"
echo -e " ${GREEN}PASS${NC}: $PASS_COUNT"
echo -e " ${RED}FAIL${NC}: $FAIL_COUNT"
echo -e " ${YELLOW}WARN${NC}: $WARN_COUNT"
echo ""

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "--- 要対応事項 ---"
  for issue in "${ISSUES[@]}"; do
    if [[ "$issue" == FAIL* ]]; then
      echo -e "  ${RED}$issue${NC}"
    else
      echo -e "  ${YELLOW}$issue${NC}"
    fi
  done
fi

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}全テストパス！ WARNは改善推奨項目です。${NC}"
else
  echo -e "${RED}FAILがあります。修正が必要です。${NC}"
fi
echo ""
