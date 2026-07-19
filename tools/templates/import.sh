#!/usr/bin/env bash
# import.sh — 内网同步包导入脚本（参考骨架 v8，Windows Git Bash 可用，无 jq 依赖）
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
#          一切跨机一致性校验（幂等/连续/逐文件/对账）一律用 tree/blob hash。
# v8 修订：幂等按包类型区分判定（close 不再被误杀）且早退前确认远端 tip；
#          操作改用 detached worktree + update-ref，真正与现场分支无关；
#          GIT_TERMINAL_PROMPT=0（无凭据快速死于明确文案，不挂起）；
#          trap 还原原子化；成功/失败横幅；全程 tee 落 import.log；https remote 提示。
# 结构约定：【固定区】不得修改；【可变区】按内网环境实现，接口不变。

set -euo pipefail
export GIT_TERMINAL_PROMPT=0   # P1-2：任何鉴权提示直接失败，不进入交互挂起
PKG_DIR="$(cd "$(dirname "$0")" && pwd)"

# ================= 固定区 0：日志与横幅（P3-8） =================
exec > >(tee -a "$PKG_DIR/import.log") 2>&1
log()  { printf '[import] %s %s\n' "$(date +%H:%M:%S)" "$*"; }
banner() { printf '\n========== %s ==========\n\n' "$1"; }
die()  { banner "FAILED"; echo "[import] ERROR: $*" >&2; echo "（现场已自动还原，包文件保留，可修复后重跑）" >&2; exit 1; }

# ================= 可变区 1：内网环境约定 =================
MAIN_BRANCH="main"
PROTECTED_PATH="deploy-intranet/"
DEPLOY_TRIGGER=""                    # latest 部署触发命令；空则只打印待办

# ================= 固定区 1：定位仓库（零配置，无需编辑脚本） ============
REPO="${IMPORT_REPO:-$(git -C "$PKG_DIR" rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$REPO" ] || die "未定位内网仓库：请把本包解压到内网仓库目录内再执行（或用 IMPORT_REPO=/path 指定）"
log "内网仓库: $REPO"

# ================= 固定区 2：网络出口（内置重试，本脚本唯一联网通道）======
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
    if echo "$out" | grep -qiE 'authentication failed|permission denied|denied|401|403|not found|does not exist|could not read|terminal prompts disabled'; then
      die "网络永久错误，不重试：$out（若为鉴权问题，请配置凭据或改用 SSH remote 后重跑本包）"
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

# ================= 固定区 3：读取并校验 manifest =================
[ -f "$PKG_DIR/manifest.sh" ] || die "缺少 manifest.sh（若已成功执行过，包文件已被自动清理）"
source "$PKG_DIR/manifest.sh"
[ "${SCHEMA_VERSION:-}" = "1" ] || die "未知 SCHEMA_VERSION，拒收"
: "${TYPE:?缺字段 TYPE}" "${BRANCH:?缺字段 BRANCH}" "${SEQ:?缺字段 SEQ}" \
  "${BASE_COMMIT:?缺字段 BASE_COMMIT}" "${COMMIT_HASH:?缺字段 COMMIT_HASH}" \
  "${TREE_HASH:?缺字段 TREE_HASH}"
PREV_STATE_HASH="${PREV_STATE_HASH:-}"
[ -f "$PKG_DIR/files.txt" ] || die "缺少 files.txt"

cd "$REPO" || die "仓库不存在: $REPO"

# P3-9：https remote 在无凭据环境下推送必挂，提前提示（不阻断）
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
case "$REMOTE_URL" in
  http://*|https://*) log "提示：origin 为 https（$REMOTE_URL）。无凭据帮手时推送会失败，建议改用 SSH（git@gitee.com:...）。" ;;
esac

git var GIT_COMMITTER_IDENT >/dev/null 2>&1 || die "未配置 git 提交者身份。请先执行：
  git config --global user.name \"你的名字\"
  git config --global user.email \"你的邮箱\"
然后重新执行本包（幂等，无副作用）。"

# ================= 固定区 4：同步远端 =================
net fetch origin

# ================= 固定区 5：工具函数 =================
reconcile_tree() { # 排除保护路径后的 tree（对账用）
  git ls-tree "$1" | grep -v "$(printf '\t')${PROTECTED_PATH%/}\$" | git mktree
}
cleanup_pkg() {  # P2-7：所有成功路径统一清理（保留 import.log 与 zip）
  rm -rf "$PKG_DIR/payload"
  rm -f "$PKG_DIR/manifest.sh" "$PKG_DIR/message.txt" "$PKG_DIR/files.txt" "$PKG_DIR/configImpact.txt"
  log "包文件已清理（import.log 保留备查）。"
  rm -f "$0" 2>/dev/null || true   # 自删除；Windows 文件占用时残留可手动删除
}
success_exit() {
  if [ -n "$DEPLOY_TRIGGER" ]; then "$DEPLOY_TRIGGER"; else log "下一步：触发 latest 部署"; fi
  banner "SUCCESS"
  cleanup_pkg
  exit 0
}

# ================= 固定区 6：幂等（P1-1 按包类型判定；P1-3 早退前确认远端）=
if [ "$TYPE" = "sync" ]; then
  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
     && [ "$(git rev-parse "$BRANCH^{tree}")" = "$TREE_HASH" ]; then
    LOCAL_TIP="$(git rev-parse "$BRANCH")"
    REMOTE_TIP="$(net ls-remote origin "$BRANCH" | cut -f1)"
    if [ "$REMOTE_TIP" = "$LOCAL_TIP" ]; then
      log "已是最新且远端一致（$BRANCH 内容与本包一致）"
      success_exit
    fi
    # P1-3：本地已是目标内容但远端落后（半完成态）→ 只补推送与确认
    log "本地已是目标内容，远端落后（半完成态）→ 直接补推送"
    net push origin "$BRANCH"
    REMOTE_TIP="$(net ls-remote origin "$BRANCH" | cut -f1)"
    [ "$REMOTE_TIP" = "$LOCAL_TIP" ] || die "远端确认失败：Gitee 上 $BRANCH 与本地不一致"
    success_exit
  fi
else # close：完成态 = main 排除保护路径后 tree 已等于 TREE_HASH 且交付分支已删除
  if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
     && [ "$(reconcile_tree "refs/heads/$MAIN_BRANCH")" = "$TREE_HASH" ]; then
    log "close 已完成（main 内容与本包一致，分支已删）"
    success_exit
  fi
fi

# ================= 固定区 7：现场保护（detached worktree，真正与现场无关）=
WT="$(mktemp -d)/wt"
OLD_REF="$(git rev-parse --verify "$BRANCH" 2>/dev/null || true)"
on_exit() {
  rc=$?
  trap '' INT TERM   # P2-5：还原段原子执行，不被二次中断
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

# ================= 固定区 8：分派执行 =================
case "$TYPE" in
  sync)
    if [ -n "$OLD_REF" ]; then
      if [ -n "$PREV_STATE_HASH" ]; then
        [ "$(git rev-parse "$BRANCH^{tree}")" = "$PREV_STATE_HASH" ] \
          || die "状态不连续：分支内容与本包上一状态不符（可能漏包/乱序，请按序号连续执行）"
      fi
      git worktree add --detach "$WT" "$BRANCH"
      [ "$( cd "$WT" && git rev-parse HEAD )" = "$OLD_REF" ] || die "工作区起点校验失败"
    else
      # feat/fix 分支从 base commit 新建；main 从本仓远端的 origin/main 新建（bootstrap 场景）
      START_POINT="$BASE_COMMIT"
      [ "$BRANCH" = "$MAIN_BRANCH" ] && START_POINT="origin/$MAIN_BRANCH"
      git cat-file -e "$START_POINT" 2>/dev/null \
        || die "起点缺失：$START_POINT（main 同步落后或远端未获取，先补 main 的同步）"
      git worktree add --detach "$WT" "$START_POINT"
      [ "$( cd "$WT" && git rev-parse HEAD )" = "$(git rev-parse "$START_POINT")" ] \
        || die "工作区起点校验失败"
    fi
    # 增量 patch 应用；payload 为空（无新增 commit）时跳过 am，仅做校验
    shopt -s nullglob; PATCHES=( "$PKG_DIR"/payload/*.patch ); shopt -u nullglob
    if ((${#PATCHES[@]})); then
      ( cd "$WT" && git am "${PATCHES[@]}" )
    else
      log "payload 为空（分支无新增 commit），仅校验状态"
    fi
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
    # P1-4：detached 工作区完成后写回分支引用（分支被其他工作区占用也不受影响）
    git update-ref "refs/heads/$BRANCH" "$NEW_TIP"
    if [ -f "$PKG_DIR/configImpact.txt" ]; then
      log "待办（部署 latest 前必须消化）："; cat "$PKG_DIR/configImpact.txt"
    fi
    net push origin "$BRANCH"
    REMOTE_TIP="$(net ls-remote origin "$BRANCH" | cut -f1)"
    [ "$REMOTE_TIP" = "$NEW_TIP" ] || die "远端确认失败：Gitee 上 $BRANCH 与本地推送结果不一致"
    ;;
  close)
    MAIN_REF="$(git rev-parse --verify "refs/heads/$MAIN_BRANCH" 2>/dev/null)" \
      || die "本地缺少 $MAIN_BRANCH 分支"
    git worktree add --detach "$WT" "$MAIN_REF"
    if [ "$(reconcile_tree HEAD)" = "$TREE_HASH" ]; then
      # 半完成自愈：main 已是目标内容（如上次中断在删分支前），跳过合并直接收尾
      log "main 已是目标内容，跳过合并，直接收尾"
      NEW_SHA="$MAIN_REF"
    else
      ( cd "$WT" && git merge --squash "$BRANCH" && git commit -F "$PKG_DIR/message.txt" )
      NEW_SHA="$( cd "$WT" && git rev-parse HEAD )"
      [ "$( cd "$WT" && reconcile_tree HEAD )" = "$TREE_HASH" ] || die "对账失败：与外网 main 不等价"
      git update-ref "refs/heads/$MAIN_BRANCH" "$NEW_SHA"
      log "$MAIN_BRANCH 引用已推进至 $NEW_SHA；若你的工作区停在 $MAIN_BRANCH，请执行 git reset --hard 同步显示"
    fi
    net push origin "$MAIN_BRANCH"
    REMOTE_MAIN="$(net ls-remote origin "$MAIN_BRANCH" | cut -f1)"
    [ "$REMOTE_MAIN" = "$NEW_SHA" ] || die "远端确认失败：Gitee 上 $MAIN_BRANCH 与预期不一致"
    # P1-4.3：分支被占用时明确警告，不再静默残留
    if ! git branch -D "$BRANCH" 2>/dev/null; then
      log "警告：本地分支 $BRANCH 正被某工作区占用，未能删除；请切换占用后执行：git branch -D $BRANCH"
    fi
    net push origin --delete "$BRANCH" || log "警告：远程分支 $BRANCH 删除失败，请手动清理"
    ;;
  *) die "未知包类型: $TYPE" ;;
esac

# ================= 固定区 9：成功收尾 =================
log "完成：$TYPE $BRANCH ($COMMIT_HASH)"
success_exit
