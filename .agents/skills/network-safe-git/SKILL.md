---
name: network-safe-git
description: git 网络操作纪律：强制走 safe-git.sh 包装、重试策略、挂起续做、失败汇报话术。任何 push/fetch 操作及网络失败时适用。
---

# 网络操作纪律

外网 GitHub、内网 Gitee 访问均不稳定，本纪律为强制要求。

## 先说清楚：本 skill 不是执行依据，是解释文档

agent 是否读 skill 靠自觉，**不能把可靠性寄托在"AI 记得读"上**。真正的执行依据是结构：

1. **逻辑在脚本里**：重试、挂起、幂等续做全部实现于 `tools/safe-git.sh`（模板见 `agent-pack/templates/safe-git.sh`），不依赖 agent 记住流程；
2. **裸推被钩子拦截**：仓库启用 `.githooks/pre-push`（`git config core.hooksPath .githooks`，模板见 `agent-pack/templates/githooks/pre-push`），未经 safe-git.sh 的 push 直接拒绝。注意 `git push --no-verify` 可跳过钩子——这不是漏洞，是审计可发现的违规；
3. **本 skill 的作用**：让 agent 理解失败时怎么向人汇报、为什么不能裸推、为什么不得重做全流程。

内网 `import.sh` 执行时没有 agent 在场——这正是设计要求：它的一切网络操作（推 Gitee）都经 `safe-git.sh`，重试/挂起在脚本内部完成，不需要任何人在旁边判断。

## 规则

1. 一切 push / fetch / ls-remote 只调用 `tools/safe-git.sh`，禁止裸命令；
2. 临时性错误（超时、连接重置、5xx）由脚本自动退避重试（5s/15s/45s/2m/5m，最多 5 次），你不干预；
3. 永久错误（鉴权失败、404、权限拒绝）脚本不重试，你立即报告人，不自行换法子硬试；
4. 持续不通：脚本把操作挂起进本地 outbox（退出码 3），你向人报告"已挂起，恢复后自动续做"，然后停手；
5. 恢复后的续做（`safe-git.sh --resume`）是幂等的，不重复发起、不检查性重推；
6. 会话内首次网络操作前，先经 safe-git.sh 做 `ls-remote` 探活，不通就直接提示人稍后，不做任何本地改动；
7. **代理只用人指定的地址**：人说"网络走代理 X"时，把 X 写入 `.sync-state/proxy`（一行 URL；该目录已 gitignore，不会入库），探活后向人报告；此后网络操作自动走代理，无需重复说明。**禁止自行编造或搜索代理地址**。取消代理 = 删除该文件。该配置**只作用于 git 包装命令**（等效于手动在每条命令前加 `http_proxy=…` 前缀），不改系统/全局环境，不影响其他程序联网；代理失效时脚本自动直连兜底并提示取消。

## 红线

- 不因一次 push 失败重做整个合并流程；
- 不在挂起期间重复发起同一操作；
- 不使用 `--force`、`--no-verify` 类参数（main 平台侧已禁 force push，`--no-verify` 属违规）。
