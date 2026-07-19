---
name: merge-and-close
description: 分支收尾：squash 合入 main、diff 校验、push、打 tag、删分支、出 close 包。内网实测通过后使用。
---

# 合并与收尾流程

## 前置检查（不满足先补齐，不发起合并）

- 分支 tip 与远端一致（有未推送 commit 先 push）——否则内网分支与 main 内容错位，close 包对账必败；
- 分支 tree 与最近一次 sync 包的 treeHash 一致——不一致说明"被合并的不是被实测的"，要么补一轮同步实测，要么由人明确豁免（如纯脚本类变更）。

## 步骤

1. 最后 `git merge main` 进分支；若有新内容合入，**停止**，提示人"需再同步实测一轮"；
2. `git checkout main`，`git merge --squash <分支>`，`git commit`——message 按规范 `type(scope): 摘要`，fix 正文写根因与影响面；
3. 本地校验 `git diff main <分支>` 为空；不为空立即停止排查，不继续；
4. 向人汇报：实测通过状态 + diff 为空 + 拟写入的 commit message，**等待确认**；
5. 确认后 push main（包装脚本，自动重试），并确认远端已包含该 commit；
6. 需要发布时（人按 checklist 确认后）：打 tag（message 写本批摘要），`git push --atomic` 推送 commit + tag；
7. 全部确认后删分支：本地 `git branch -D`、远程 `git push --delete`（均走包装脚本）；
8. 生成 close 包（见 `skills/sync-package`），交人带入内网；
9. 归档执行计划：`git mv docs/exec-plans/active/<功能>.md docs/exec-plans/completed/`（目录移动即状态更新），随下一次提交或单独提交。

## 红线

- 未获人确认不 push；任何校验不为空不继续；
- 删分支永远在最后一步，且用 `-D`（squash 合并后 git 不认合并关系）；
- 打 tag 只在人明确发布指令后；
- 此流程产生的一切网络操作失败，按 `skills/network-safe-git` 处理，不重做全流程。
