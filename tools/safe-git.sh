#!/usr/bin/env bash
# safe-git.sh — git 网络操作包装（参考骨架，无 jq 依赖，Git Bash 兼容）
# 用法:
#   tools/safe-git.sh push|fetch|ls-remote [git 参数...]   唯一允许的网络操作入口
#   tools/safe-git.sh --resume                             网络恢复后重放 outbox
#
# 设计要点（对应 skills/network-safe-git）：
#   - 重试/挂起逻辑全部在本脚本内，不依赖 agent 或人记住流程；
#   - 指数退避只针对临时错误；鉴权/404/权限拒绝立即失败；
#   - push 持续不通则写入 outbox，exit 3（调用方据此知道"已挂起"）；
#   - 本脚本设置 SAFE_GIT_WRAPPER=1，配合 .githooks/pre-push 放行。
set -uo pipefail   # 注意：故意不用 -e，重试循环要自己控制退出码

STATE_DIR="$(git rev-parse --show-toplevel)/.sync-state"
OUTBOX="$STATE_DIR/outbox"
BACKOFFS=(5 15 45 120 300)
export SAFE_GIT_WRAPPER=1

# 固定区：代理支持（人指定，存于 .sync-state/proxy，一行 URL；不存在则直连）
if [ -f "$STATE_DIR/proxy" ]; then
  PROXY="$(head -n1 "$STATE_DIR/proxy" | tr -d '[:space:]')"
  if [ -n "$PROXY" ]; then
    export http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY"
  fi
fi

log() { printf '[safe-git] %s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

is_permanent() { # 永久错误：不重试
  echo "$1" | grep -qiE 'authentication failed|permission denied|denied|401|403|not found|does not exist|could not read'
}

run_once() { timeout 60 git "$@" 2>&1; }

retry() {
  local out i
  for i in "${!BACKOFFS[@]}"; do
    out="$(run_once "$@")" && { [ -n "$out" ] && echo "$out"; return 0; }
    if is_permanent "$out"; then log "永久错误，不重试：$out"; return 1; fi
    log "第 $((i+1)) 次失败（${BACKOFFS[$i]}s 后重试）：$out"
    sleep "${BACKOFFS[$i]}"
  done
  out="$(run_once "$@")" && { [ -n "$out" ] && echo "$out"; return 0; }
  # 代理兜底：配置了代理且全部失败 → 摘掉代理直连试一次（代理是临时的，可能已失效）
  if [ -n "${http_proxy:-}" ]; then
    log "代理疑似失效，尝试直连兜底…"
    unset http_proxy https_proxy all_proxy
    out="$(run_once "$@")" && { [ -n "$out" ] && echo "$out"; log "已直连成功。如代理持续失效，请删除 .sync-state/proxy"; return 0; }
  fi
  log "最终失败：$out"; return 1
}

if [ "${1:-}" = "--resume" ]; then
  [ -s "$OUTBOX" ] || { log "outbox 为空，无待办"; exit 0; }
  TMP="$OUTBOX.tmp"; : > "$TMP"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    log "续做: $line"
    # outbox 只存 refspec 类无空格参数，直接分词（如有空格参数需求请改用制表符分隔）
    if ! retry $line >/dev/null; then
      echo "$line" >> "$TMP"
    fi
  done < "$OUTBOX"
  mv "$TMP" "$OUTBOX"
  [ -s "$OUTBOX" ] && { log "仍有未完成项，保留队列"; exit 3; }
  log "outbox 已全部完成"; exit 0
fi

OP="${1:?用法: safe-git.sh push|fetch|ls-remote [参数...]}"; shift
case "$OP" in push|fetch|ls-remote) ;; *) echo "只允许 push/fetch/ls-remote" >&2; exit 2 ;; esac

mkdir -p "$STATE_DIR"
if retry "$OP" "$@"; then exit 0; fi

if [ "$OP" = "push" ]; then
  printf 'push %s\n' "$*" >> "$OUTBOX"
  log "网络持续不通，已挂起 outbox（恢复后执行: safe-git.sh --resume）"
  exit 3
fi
exit 1
