#!/usr/bin/env bash
# export_package.sh — 同步包生成脚本（参考骨架 v4，无 jq 依赖，Git Bash 兼容）
# 用法: tools/export_package.sh <branch> <sync|close>
#
# 结构约定：【固定区】流程顺序、校验点、git 命令、退出码、日志格式 —— 不得修改；
#          【可变区】项目路径、提取细节 —— 可按项目实现，接口与输出格式不变。
# v4 修订：默认 zip 打包（文件平铺在包根，内网“解压到当前位置”即可用）；
#          import.sh 零配置自动定位仓库，执行人无需编辑任何脚本。

set -euo pipefail

# ================= 固定区 1：参数、日志、退出码 =================
BRANCH="${1:?用法: export_package.sh <branch> <sync|close> (exit 2)}"
TYPE="${2:?类型必须是 sync 或 close (exit 2)}"
{ [ "$TYPE" = "sync" ] || [ "$TYPE" = "close" ]; } || { echo "类型必须是 sync 或 close" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
ARCHIVE_FMT="zip"                      # zip（推荐，Windows 资源管理器可直接解压）或 tar

# ================= 固定区 2：前置校验（任一不过即失败，无豁免参数）=====
[ -z "$(git status --porcelain)" ]            || die "工作区不干净"
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || die "分支不存在: $BRANCH"
TIP="$(git rev-parse "$BRANCH")"
REMOTE_TIP="$("$SCRIPT_DIR/safe-git.sh" ls-remote origin "$BRANCH" | cut -f1)" \
                                              || die "远端 tip 查询失败（网络问题，稍后重试）"
[ "$TIP" = "$REMOTE_TIP" ]                    || die "分支 tip 未推送或与远端不一致"
[ -f "$CHECKS_OK" ]                           || die "缺少本地检查通过标记 $CHECKS_OK"
[ -n "$(find "$CHECKS_OK" -mtime -1 2>/dev/null)" ] || die "检查标记已过期（>24h），先重跑本地检查"
if [ "$BRANCH" != "$MAIN_BRANCH" ]; then
  [ -f "$SPEC_FILE" ]                       || die "缺少 spec: $SPEC_FILE"
  grep -q "部署影响" "$SPEC_FILE"           || die "spec 缺少「部署影响」一节"
fi

# ================= 固定区 3：状态字段计算 =================
BASE="$(git merge-base "origin/$MAIN_BRANCH" "$BRANCH")"
TREE="$(git rev-parse "$BRANCH^{tree}")"
mkdir -p "$STATE_DIR" "$OUT_DIR"
SAFE_BRANCH="${BRANCH//\//-}"   # 分支名含 /，文件名/路径一律用转义后的安全名
SEQ_FILE="$STATE_DIR/seq-$SAFE_BRANCH"
PREV_TREE_FILE="$STATE_DIR/prev-tree-$SAFE_BRANCH"
PREV_COMMIT_FILE="$STATE_DIR/prev-commit-$SAFE_BRANCH"
SEQ=$(( $(cat "$SEQ_FILE" 2>/dev/null || echo 0) + 1 ))
PREV_TREE="$(cat "$PREV_TREE_FILE" 2>/dev/null || echo "")"
PREV_COMMIT="$(cat "$PREV_COMMIT_FILE" 2>/dev/null || echo "")"
# 旧版单文件（内容为 tree）一次性迁移
if [ -z "$PREV_TREE" ] && [ -f "$STATE_DIR/prev-$SAFE_BRANCH" ]; then
  PREV_TREE="$(cat "$STATE_DIR/prev-$SAFE_BRANCH")"; rm -f "$STATE_DIR/prev-$SAFE_BRANCH"
fi
# 增量出包：只有上一包 tip 之后的新 commit 进 payload（全量重放会与内网已应用内容冲突）；
# 无记录或历史被改写则回退全量
RANGE_BASE="$BASE"
if [ -n "$PREV_COMMIT" ] && git merge-base --is-ancestor "$PREV_COMMIT" "$BRANCH" 2>/dev/null; then
  RANGE_BASE="$PREV_COMMIT"
fi
if [ "$TYPE" = "close" ]; then MSG_SRC="origin/$MAIN_BRANCH"; else MSG_SRC="$BRANCH"; fi

# ================= 固定区 4：close 包附加校验 =================
if [ "$TYPE" = "close" ]; then
  if ! git merge-base --is-ancestor "$BRANCH" "origin/$MAIN_BRANCH" \
     && ! git diff --quiet "origin/$MAIN_BRANCH" "$BRANCH"; then
    HINT=""
    if git diff --name-only "origin/$MAIN_BRANCH" "$BRANCH" | grep -qE '^(tools/|\.agents/)' \
       && ! git diff --name-only "origin/$MAIN_BRANCH" "$BRANCH" | grep -vqE '^(tools/|\.agents/)'; then
      HINT="（差异仅在 tools/ 与 .agents/ 机制路径：按 merge-and-close 时序约定——先出 close 包，再推送 main 上的机制修复）"
    fi
    die "分支未合入 main 且与 main 有 diff，不能出 close 包$HINT"
  fi
fi

# ================= 固定区 5：组包（保护路径硬阻断）=================
# 所有产出路径的 git 命令统一 core.quotePath=false：
# 默认开启时非 ASCII 路径被转义成 "\344\270\255..."，^ 锚点匹配失效，硬阻断可被绕过
PKG="$OUT_DIR/sync-$SAFE_BRANCH-$SEQ"
rm -rf "$PKG"; mkdir -p "$PKG/payload"
DIFF_FILES="$(git -c core.quotePath=false diff --name-only "$BASE..$BRANCH")"
if printf '%s\n' "$DIFF_FILES" | grep -q "$(printf '\t')"; then
  die "文件名含制表符，TSV 清单不支持"
fi
if printf '%s\n' "$DIFF_FILES" | grep -q "^$PROTECTED_PATH"; then
  die "变更包含保护路径 $PROTECTED_PATH（无豁免）"
fi
if [ "$TYPE" = "sync" ]; then
  git format-patch -o "$PKG/payload" "$RANGE_BASE..$BRANCH" >/dev/null
  # 可变区 2：若规定只允许普通文件，改为导出变更文件全集（清单格式不变）
  if [ "$(git rev-list --count "$RANGE_BASE..$BRANCH")" = "0" ]; then
    log "提示：本包无新增 commit（仅校验包）"
  fi
fi

# ================= 固定区 6：清单文件（纯 bash + git，无 jq）===========
# manifest.sh：键序固定，import.sh 直接 source
{
  echo "SCHEMA_VERSION=1"
  echo "TYPE=$TYPE"
  printf 'BRANCH="%s"\n' "$BRANCH"
  echo "SEQ=$SEQ"
  echo "BASE_COMMIT=$BASE"
  printf 'PREV_STATE_HASH="%s"\n' "$PREV_TREE"
  echo "COMMIT_HASH=$TIP"
  echo "TREE_HASH=$TREE"
} > "$PKG/manifest.sh"
# message.txt：commit message
git log -1 --format=%B "$MSG_SRC" > "$PKG/message.txt"
# files.txt：action<TAB>blob<TAB>path，按 path 排序；delete 的 blob 为空
# 注意：name-status 输出是 status+path 两列，-k2,2 即按 path 排序；blob 在循环内才计算
# 用 git 对象 hash（blob），不用磁盘文件 sha256——免疫 Windows CRLF 差异
git -c core.quotePath=false diff --name-status "$BASE..$BRANCH" \
  | LC_ALL=C sort -t"$(printf '\t')" -k2,2 \
  | while IFS=$'\t' read -r st p; do
      case "$st" in
        A) a=add;    b="$(git rev-parse "$BRANCH:$p")" ;;
        D) a=delete; b="" ;;
        *) a=modify; b="$(git rev-parse "$BRANCH:$p")" ;;
      esac
      printf '%s\t%s\t%s\n' "$a" "$b" "$p"
    done > "$PKG/files.txt"
# configImpact.txt：spec「部署影响」一节原文；"无"/空白视为无影响，不生成该文件
if [ -f "$SPEC_FILE" ]; then
  IMPACT="$(awk '/^#+.*部署影响/{f=1;next} f&&/^#/{exit} f' "$SPEC_FILE")"
else
  IMPACT=""   # main 无对应 spec 文件
fi
IMPACT_KEY="$(printf '%s' "$IMPACT" | tr -d '[:space:]')"
case "$IMPACT_KEY" in "" | 无 | 无。 | none | None | NONE ) IMPACT="" ;; esac
if [ -n "$IMPACT" ]; then printf '%s\n' "$IMPACT" > "$PKG/configImpact.txt"; fi
cp "$IMPORT_TEMPLATE" "$PKG/import.sh"; chmod +x "$PKG/import.sh"

# ================= 固定区 7：确定性打包、落账、汇报 =================
# zip 内容平铺在包根（无外层目录），配合内网“解压到当前位置”约定
if [ "$ARCHIVE_FMT" = "zip" ]; then
  command -v zip >/dev/null || die "需要 zip 命令（或将可变区 ARCHIVE_FMT 改为 tar）"
  find "$PKG" -exec touch -d @0 {} +    # mtime 置零，包体可复现
  PKG_ABS="$(cd "$PKG" && pwd)"
  ( cd "$PKG" && find . -print | LC_ALL=C sort | TZ=UTC zip -X -q "$PKG_ABS.zip" -@ )
  PKG_ARC="$PKG.zip"
else
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$PKG.tar" -C "$PKG" .
  PKG_ARC="$PKG.tar"
fi
# 注意：PREV_STATE_HASH 记录的是 tree hash 而非 commit hash——
# git am 跨机重放会改写 committer 身份/时间，commit hash 跨机不可比，tree 才可比
echo "$SEQ" > "$SEQ_FILE"; echo "$TREE" > "$PREV_TREE_FILE"; echo "$TIP" > "$PREV_COMMIT_FILE"
# close 包同时登记 main 的同步基线：close 合入后内网 main 与此 tree 对齐，
# 后续 main 同步包以此为增量起点（否则 main 无参考点可算增量）
if [ "$TYPE" = "close" ]; then
  echo "$TREE" > "$STATE_DIR/prev-tree-$MAIN_BRANCH"
  git rev-parse "origin/$MAIN_BRANCH" > "$STATE_DIR/prev-commit-$MAIN_BRANCH"
fi
PKG_SHA="$(sha256sum "$PKG_ARC" | cut -d' ' -f1)"
log "包路径: $PKG_ARC"
log "类型: $TYPE  序号: $SEQ  包体SHA256: $PKG_SHA"
[ -n "$IMPACT" ] && log "注意：含 configImpact，内网需追加 [config] commit"
exit 0
