#!/usr/bin/env bash
# import.sh — 内网同步包导入脚本（参考骨架 v4，Windows Git Bash 可用，无 jq 依赖）
# 用法: 在 Git Bash 中执行 ./import.sh（零参数，自读同目录 manifest.sh）
#
# 环境约定：内网执行机是 Windows 个人电脑 + Git Bash，只装了 git。
#          脚本只依赖 git 与基础 bash 命令；内容校验一律用 git 对象 hash
#          （blob/tree），天然免疫 Windows 换行符（CRLF）差异。
# 网络约定：重试逻辑内置于本脚本（与 tools/safe-git.sh 同源模板）——
#          同步包必须自包含，不依赖内网仓库里是否已有 tools/（首包引导）。
#          失败即还原，恢复后重新执行本包（幂等），故无需 outbox。
# 结构约定：【固定区】不得修改；【可变区】按内网环境实现，接口不变。

set -euo pipefail
PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
log() { printf '[import] %s %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "[import] ERROR: $*" >&2; exit 1; }

# ================= 可变区 1：内网环境约定 =================
REPO="$HOME/repos/project"           # 内网仓库路径
MAIN_BRANCH="main"
PROTECTED_PATH="deploy-intranet/"
DEPLOY_TRIGGER=""                    # latest 部署触发命令；空则只打印待办

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
[ -f "$PKG_DIR/manifest.sh" ] || die "缺少 manifest.sh"
source "$PKG_DIR/manifest.sh"
[ "${SCHEMA_VERSION:-}" = "1" ] || die "未知 SCHEMA_VERSION，拒收"
: "${TYPE:?缺字段 TYPE}" "${BRANCH:?缺字段 BRANCH}" "${SEQ:?缺字段 SEQ}" \
  "${BASE_COMMIT:?缺字段 BASE_COMMIT}" "${COMMIT_HASH:?缺字段 COMMIT_HASH}" \
  "${TREE_HASH:?缺字段 TREE_HASH}"
PREV_STATE_HASH="${PREV_STATE_HASH:-}"
[ -f "$PKG_DIR/files.txt" ] || die "缺少 files.txt"

cd "$REPO" || die "仓库不存在: $REPO"

# ================= 固定区 3：同步远端（内置重试） =================
net fetch origin

# ================= 固定区 4：幂等 =================
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
   && git merge-base --is-ancestor "$COMMIT_HASH" "$BRANCH" 2>/dev/null; then
  log "已是最新（$COMMIT_HASH 已在 $BRANCH 上），无副作用退出"; exit 0
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
      [ "$OLD_REF" = "$PREV_STATE_HASH" ] \
        || die "状态不连续：分支当前 $OLD_REF，期望 ${PREV_STATE_HASH:-首包}（可能漏包/乱序）"
      git worktree add "$WT" "$BRANCH" >/dev/null 2>&1
    else
      git cat-file -e "$BASE_COMMIT" 2>/dev/null \
        || die "base 缺失：main 同步落后，请先执行 main 的同步包"
      git worktree add "$WT" -b "$BRANCH" "$BASE_COMMIT" >/dev/null 2>&1
    fi
    ( cd "$WT" && git am "$PKG_DIR"/payload/*.patch )
    # 校验（全部 git 对象级，CRLF 免疫）：tree、commit、逐文件 blob
    ( cd "$WT" && [ "$(git rev-parse HEAD^{tree})" = "$TREE_HASH" ] ) || die "tree 校验失败"
    ( cd "$WT" && [ "$(git rev-parse HEAD)" = "$COMMIT_HASH" ] ) || die "commit 校验失败"
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
    # 推送后确认远端真的收到（ls-remote 同样经内置重试）
    REMOTE_TIP="$(net ls-remote origin "$BRANCH" | cut -f1)"
    [ "$REMOTE_TIP" = "$COMMIT_HASH" ] || die "远端确认失败：Gitee 上 $BRANCH 与预期不一致"
    ;;
  close)
    git worktree add "$WT" "$MAIN_BRANCH" >/dev/null 2>&1
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
exit 0
