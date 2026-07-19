#!/usr/bin/env bash
# import.sh — 内网同步包导入脚本（参考骨架 v7，Windows Git Bash 可用，无 jq 依赖）
# 用法: ① 把 zip 拷到内网仓库一级目录；② 右键“解压到当前位置”；
#       ③ Git Bash 执行 ./import.sh —— 零参数、零配置，成功后自动清理包文件。
#
# 环境约定：内网执行机是 Windows 个人电脑 + Git Bash，只装了 git。
#          脚本只依赖 git 与基础 bash 命令；内容校验一律用 git 对象 hash
#          （blob/tree），天然免疫 Windows 换行符（CRLF）差异。
# 网络约定：重试逻辑内置于本脚本（与 tools/safe-git.sh 同源模板）——
#          同步包必须自包含，不依赖内网仓库里是否已有 tools/（首包引导）。
#          失败即还原并保留包文件，恢复后重新执行本包（幂等），故无需 outbox。
# 校验约定：git am 跨机重放会改写 committer 身份/时间，commit hash 跨机不可比；
#          因此一切跨机一致性校验（幂等/连续/逐文件/对账）一律用 tree/blob hash。
# 结构约定：【固定区】不得修改；【可变区】按内网环境实现，接口不变。

set -euo pipefail
PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
log() { printf '[import] %s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "[import] ERROR: $*" >&2; exit 1; }

# ================= 可变区 1：内网环境约定 =================
MAIN_BRANCH="main"
PROTECTED_PATH="deploy-intranet/"
DEPLOY_TRIGGER=""                    # latest 部署触发命令；空则只打印待办

# ================= 固定区 0：定位仓库（零配置，无需编辑脚本） ============
# 约定：包解压到内网仓库一级目录（或仓库内任意位置），脚本向上找 .git 自动定位。
# 例外：包在仓库外时，用环境变量 IMPORT_REPO 显式指定。
REPO="${IMPORT_REPO:-$(git -C "$PKG_DIR" rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$REPO" ] || die "未定位内网仓库：请把本包解压到内网仓库目录内再执行（或用 IMPORT_REPO=/path 指定）"
log "内网仓库: $REPO"

# ================= 固定区 1：网络出口（内置重试，本脚本唯一联网通道）======
BACKOFFS=(5 15 45 120 300)
net() {
  # 用法: net fetch|push|ls-remote [git 参数...]
  # 代理：人指定，存于 $REPO/.sync-state/proxy（一行 URL）；不存在则直连
  if [ -f "$REPO/.sync-state/proxy" ]; then
    local PROXY; PROXY="$(head -n1 "$REPO/.sync-state/proxy" | tr -d '[:space:]')"
    [ -n "$PROXY" ] && export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY"
  fi
  local out i
  for i in "${!BACKOFFS[@]}"; do
    out="$(timeout 60 git "$@" 2>&1)" && { [ -n "$out" ] && printf '%s\n' "$out"; return 0; }
    if echo "$out" | grep -qiE 'authentication failed|permission denied|denied|401|403|not found|does not exist|could not read'; then
      die "网络永久错误，不重试：$out"
    fi
    log "网络第 $((i+1)) 次失败（${BACKOFFS[$i]}s 后重试）"
    sleep "${BACKOFFS[$i]}"
  done
  out="$(timeout 60 git "$@" 2>&1)" && { [ -n "$out" ] && printf '%s\n' "$out"; return 0; }
  # 代理兜底：配置了代理且全部失败 → 摘掉代理直连试一次（代理是临时的，可能已失效）
  if [ -n "${http_proxy:-}" ]; then
    log "代理疑似失效，尝试直连兜底…"
    unset http_proxy https_proxy all_proxy
    out="$(timeout 60 git "$@" 2>&1)" && { [ -n "$out" ] && printf '%s\n' "$out"; log "已直连成功。如代理持续失效，请删除 .sync-state/proxy"; return 0; }
  fi
  die "网络持续不通：本包状态已还原，网络恢复后重新执行本包即可（最后错误：$out）"
}

# ================= 固定区 2：读取并校验 manifest =================
[ -f "$PKG_DIR/manifest.sh" ] || die "缺少 manifest.sh（若已成功执行过，包文件已被自动清理）"
source "$PKG_DIR/manifest.sh"
[ "${SCHEMA_VERSION:-}" = "1" ] || die "未知 SCHEMA_VERSION，拒收"
: "${TYPE:?缺字段 TYPE}" "${BRANCH:?缺字段 BRANCH}" "${SEQ:?缺字段 SEQ}" \
  "${BASE_COMMIT:?缺字段 BASE_COMMIT}" "${COMMIT_HASH:?缺字段 COMMIT_HASH}" \
  "${TREE_HASH:?缺字段 TREE_HASH}"
PREV_STATE_HASH="${PREV_STATE_HASH:-}"
[ -f "$PKG_DIR/files.txt" ] || die "缺少 files.txt"

cd "$REPO" || die "仓库不存在: $REPO"

# git am 需要提交者身份；缺失时给出明确指引，而不是中途报 "Committer identity unknown"
git var GIT_COMMITTER_IDENT >/dev/null 2>&1 || die "未配置 git 提交者身份。请先执行：
  git config --global user.name \"你的名字\"
  git config --global user.email \"你的邮箱\"
然后重新执行本包（幂等，无副作用）。"

# ================= 固定区 3：同步远端（内置重试） =================
net fetch origin

# ================= 固定区 4：幂等（tree 比对，跨机可比）=================
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
   && [ "$(git rev-parse "$BRANCH^{tree}")" = "$TREE_HASH" ]; then
  log "已是最新（$BRANCH 内容与本包一致），无副作用退出"; exit 0
fi

# ================= 固定区 5：现场保护（与执行时所在分支无关）=========
# mktemp 在 Git Bash 下自动落到 Windows 临时目录，跨平台无需改路径；
# Windows 如报路径过长：git config --global core.longpaths true
WT="$(mktemp -d)/wt"
OLD_REF="$(git rev-parse --verify "$BRANCH" 2>/dev/null || true)"
on_exit() {
  rc=$?
  git worktree remove --force "$WT" 2>/dev/null || true
  if [ $rc -ne 0 ]; then
    if [ -n "$OLD_REF" ]; then
      git update-ref "refs/heads/$BRANCH" "$OLD_REF" 2>/dev/null || true
      log "已还原 $BRANCH 到执行前状态 ($OLD_REF)"
    else
      git update-ref -d "refs/heads/$BRANCH" 2>/dev/null || true
    fi
  fi
}
trap on_exit EXIT

# ================= 固定区 6：分派执行 =================
case "$TYPE" in
  sync)
    if [ -n "$OLD_REF" ]; then
      if [ -n "$PREV_STATE_HASH" ]; then
        [ "$(git rev-parse "$BRANCH^{tree}")" = "$PREV_STATE_HASH" ] \
          || die "状态不连续：分支内容与本包上一状态不符（可能漏包/乱序，请按序号连续执行）"
      fi
      git worktree add "$WT" "$BRANCH"
      [ "$( cd "$WT" && git branch --show-current )" = "$BRANCH" ] \
        || die "工作区未落在预期分支 $BRANCH，已中止（未做任何变更）"
    else
      # feat/fix 分支从 base commit 新建；main 从本仓远端的 origin/main 新建（bootstrap 场景）
      START_POINT="$BASE_COMMIT"
      [ "$BRANCH" = "$MAIN_BRANCH" ] && START_POINT="origin/$MAIN_BRANCH"
      git cat-file -e "$START_POINT" 2>/dev/null \
        || die "起点缺失：$START_POINT（main 同步落后或远端未获取，先补 main 的同步）"
      git worktree add "$WT" -b "$BRANCH" "$START_POINT"
      [ "$( cd "$WT" && git branch --show-current )" = "$BRANCH" ] \
        || die "新建工作区未落在预期分支 $BRANCH，已中止（未做任何变更）"
    fi
    # 增量 patch 应用；payload 为空（无新增 commit）时跳过 am，仅做校验
    shopt -s nullglob; PATCHES=( "$PKG_DIR"/payload/*.patch ); shopt -u nullglob
    if ((${#PATCHES[@]})); then
      ( cd "$WT" && git am "${PATCHES[@]}" )
    else
      log "payload 为空（分支无新增 commit），仅校验状态"
    fi
    # 校验（全部 git 对象级，CRLF/跨机免疫）：tree + 逐文件 blob
    NEW_TIP="$( cd "$WT" && git rev-parse HEAD )"
    ( cd "$WT" && [ "$(git rev-parse HEAD^{tree})" = "$TREE_HASH" ] ) || die "tree 校验失败"
    while IFS=$'\t' read -r action blob path; do
      if [ "$action" = "delete" ]; then
        ( cd "$WT" && ! git cat-file -e "HEAD:$path" 2>/dev/null ) || die "应删除的文件仍存在: $path"
      else
        actual="$( cd "$WT" && git rev-parse "HEAD:$path" 2>/dev/null || echo missing )"
        [ "$actual" = "$blob" ] || die "文件校验失败: $path"
      fi
    done < "$PKG_DIR/files.txt"
    if [ -f "$PKG_DIR/configImpact.txt" ]; then
      log "待办（部署 latest 前必须消化）："; cat "$PKG_DIR/configImpact.txt"
    fi
    net push origin "$BRANCH"
    # 推送后确认远端真的收到：远端 tip 必须等于本地重放后的新 tip
    REMOTE_TIP="$(net ls-remote origin "$BRANCH" | cut -f1)"
    [ "$REMOTE_TIP" = "$NEW_TIP" ] || die "远端确认失败：Gitee 上 $BRANCH 与本地推送结果不一致"
    ;;
  close)
    git worktree add "$WT" "$MAIN_BRANCH"
    [ "$( cd "$WT" && git branch --show-current )" = "$MAIN_BRANCH" ] \
      || die "工作区未落在预期分支 $MAIN_BRANCH，已中止（未做任何变更）"
    ( cd "$WT" && git merge --squash "$BRANCH" && git commit -F "$PKG_DIR/message.txt" )
    NEW_SHA="$( cd "$WT" && git rev-parse HEAD )"
    # 对账：内网 main 顶层排除保护目录后的 tree 必须等于外网 main 的 TREE_HASH
    RECONCILE="$( cd "$WT" && git ls-tree HEAD \
      | grep -v "$(printf '\t')${PROTECTED_PATH%/}\$" | git mktree )"
    [ "$RECONCILE" = "$TREE_HASH" ] || die "对账失败：与外网 main 不等价"
    net push origin "$MAIN_BRANCH"
    REMOTE_MAIN="$(net ls-remote origin "$MAIN_BRANCH" | cut -f1)"
    [ "$REMOTE_MAIN" = "$NEW_SHA" ] || die "远端确认失败：Gitee 上 $MAIN_BRANCH 与预期不一致"
    git branch -D "$BRANCH" || true
    net push origin --delete "$BRANCH" || true
    ;;
  *) die "未知包类型: $TYPE" ;;
esac

# ================= 固定区 7：成功收尾 =================
log "完成：$TYPE $BRANCH ($COMMIT_HASH)"
if [ -n "$DEPLOY_TRIGGER" ]; then "$DEPLOY_TRIGGER"; else log "下一步：触发 latest 部署"; fi

# ================= 固定区 8：清理包文件（仅成功后；失败保留以便重跑）======
rm -rf "$PKG_DIR/payload"
rm -f "$PKG_DIR/manifest.sh" "$PKG_DIR/message.txt" "$PKG_DIR/files.txt" "$PKG_DIR/configImpact.txt"
log "包文件已清理。"
rm -f "$0" 2>/dev/null || true   # 自删除；Windows 文件占用时残留可手动删除
exit 0
