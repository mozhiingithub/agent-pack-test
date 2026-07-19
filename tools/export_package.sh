#!/usr/bin/env bash
# export_package.sh — 同步包生成脚本（参考骨架 v2，无 jq 依赖，Git Bash 兼容）
# 用法: tools/export_package.sh <branch> <sync|close>
#
# 结构约定：【固定区】流程顺序、校验点、git 命令、退出码、日志格式 —— 不得修改；
#          【可变区】项目路径、提取细节 —— 可按项目实现，接口与输出格式不变。

set -euo pipefail

# ================= 固定区 1：参数、日志、退出码 =================
BRANCH="${1:?用法: export_package.sh <branch> <sync|close> (exit 2)}"
TYPE="${2:?类型必须是 sync 或 close (exit 2)}"
{ [ "$TYPE" = "sync" ] || [ "$TYPE" = "close" ]; } || { echo "类型必须是 sync 或 close" >&2; exit 2; }
log() { printf '[export] %s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "[export] ERROR: $*" >&2; exit 1; }

# ================= 可变区 1：项目路径约定 =================
MAIN_BRANCH="main"
SPEC_FILE="docs/exec-plans/active/${BRANCH#*/}.md"   # 分支 → 执行计划映射（docs/ 结构）
STATE_DIR=".sync-state"                # seq 与 prevStateHash 存放处（AI 不得手工读写）
OUT_DIR="outbox"
PROTECTED_PATH="deploy-intranet/"      # 保护路径，硬阻断
CHECKS_OK=".checks-ok"                 # 本地检查通过标记（24h 内有效）
IMPORT_TEMPLATE="tools/templates/import.sh"

# ================= 固定区 2：前置校验（任一不过即失败，无豁免参数）=====
[ -z "$(git status --porcelain)" ]            || die "工作区不干净"
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || die "分支不存在: $BRANCH"
TIP="$(git rev-parse "$BRANCH")"
REMOTE_TIP="$(git ls-remote origin "$BRANCH" | cut -f1)"
[ "$TIP" = "$REMOTE_TIP" ]                    || die "分支 tip 未推送或与远端不一致"
[ -f "$CHECKS_OK" ]                           || die "缺少本地检查通过标记 $CHECKS_OK"
[ -n "$(find "$CHECKS_OK" -mtime -1 2>/dev/null)" ] || die "检查标记已过期（>24h），先重跑本地检查"
[ -f "$SPEC_FILE" ]                           || die "缺少 spec: $SPEC_FILE"
grep -q "部署影响" "$SPEC_FILE"               || die "spec 缺少「部署影响」一节"

# ================= 固定区 3：状态字段计算 =================
BASE="$(git merge-base "origin/$MAIN_BRANCH" "$BRANCH")"
TREE="$(git rev-parse "$BRANCH^{tree}")"
mkdir -p "$STATE_DIR" "$OUT_DIR"
SEQ_FILE="$STATE_DIR/seq-$BRANCH"; PREV_FILE="$STATE_DIR/prev-$BRANCH"
SEQ=$(( $(cat "$SEQ_FILE" 2>/dev/null || echo 0) + 1 ))
PREV="$(cat "$PREV_FILE" 2>/dev/null || echo "")"
if [ "$TYPE" = "close" ]; then MSG_SRC="origin/$MAIN_BRANCH"; else MSG_SRC="$BRANCH"; fi

# ================= 固定区 4：close 包附加校验 =================
if [ "$TYPE" = "close" ]; then
  git merge-base --is-ancestor "$BRANCH" "origin/$MAIN_BRANCH" \
    || git diff --quiet "origin/$MAIN_BRANCH" "$BRANCH" \
    || die "分支未合入 main 且与 main 有 diff，不能出 close 包"
fi

# ================= 固定区 5：组包（保护路径硬阻断）=================
PKG="$OUT_DIR/sync-$BRANCH-$SEQ"
rm -rf "$PKG"; mkdir -p "$PKG/payload"
if git -c core.quotePath=false diff --name-only "$BASE..$BRANCH" | grep -q "$(printf '\t')"; then
  die "文件名含制表符，TSV 清单不支持"
fi
if git diff --name-only "$BASE..$BRANCH" | grep -q "^$PROTECTED_PATH"; then
  die "变更包含保护路径 $PROTECTED_PATH（无豁免）"
fi
if [ "$TYPE" = "sync" ]; then
  git format-patch -o "$PKG/payload" "$BASE..$BRANCH" >/dev/null
  # 可变区 2：若规定只允许普通文件，改为导出变更文件全集（清单格式不变）
fi

# ================= 固定区 6：清单文件（纯 bash + git，无 jq）===========
# manifest.sh：键序固定，import.sh 直接 source
{
  echo "SCHEMA_VERSION=1"
  echo "TYPE=$TYPE"
  printf 'BRANCH="%s"\n' "$BRANCH"
  echo "SEQ=$SEQ"
  echo "BASE_COMMIT=$BASE"
  printf 'PREV_STATE_HASH="%s"\n' "$PREV"
  echo "COMMIT_HASH=$TIP"
  echo "TREE_HASH=$TREE"
} > "$PKG/manifest.sh"
# message.txt：commit message
git log -1 --format=%B "$MSG_SRC" > "$PKG/message.txt"
# files.txt：action<TAB>blob<TAB>path，按 path 排序；delete 的 blob 为空
# 用 git 对象 hash（blob），不用磁盘文件 sha256——免疫 Windows CRLF 差异
git diff --name-status "$BASE..$BRANCH" | LC_ALL=C sort -k2 \
  | while IFS=$'\t' read -r st p; do
      case "$st" in
        A) a=add;    b="$(git rev-parse "$BRANCH:$p")" ;;
        D) a=delete; b="" ;;
        *) a=modify; b="$(git rev-parse "$BRANCH:$p")" ;;
      esac
      printf '%s\t%s\t%s\n' "$a" "$b" "$p"
    done > "$PKG/files.txt"
# configImpact.txt：spec「部署影响」一节原文；为空则不生成该文件
IMPACT="$(awk '/^#+.*部署影响/{f=1;next} f&&/^#/{exit} f' "$SPEC_FILE")"
if [ -n "$IMPACT" ]; then printf '%s\n' "$IMPACT" > "$PKG/configImpact.txt"; fi
cp "$IMPORT_TEMPLATE" "$PKG/import.sh"; chmod +x "$PKG/import.sh"

# ================= 固定区 7：确定性打包、落账、汇报 =================
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$PKG.tar" -C "$PKG" .
# 可变区 3：若规定用 zip，替换为排序 + zip -X，原则（可复现）不变
echo "$SEQ" > "$SEQ_FILE"; echo "$TIP" > "$PREV_FILE"
PKG_SHA="$(sha256sum "$PKG.tar" | cut -d' ' -f1)"
log "包路径: $PKG.tar"
log "类型: $TYPE  序号: $SEQ  包体SHA256: $PKG_SHA"
[ -n "$IMPACT" ] && log "注意：含 configImpact，内网需追加 [config] commit"
exit 0
