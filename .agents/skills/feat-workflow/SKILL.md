---
name: feat-workflow
description: 新功能开发全流程：spec 前置检查、建 feat 分支、开发与本地检查、同步实测、合并收尾。当任务是在 main 之外新增功能时使用。
---

# 新功能开发流程

## 前置检查（不满足就先补，不动手写码）

- 执行计划已存在于 `docs/exec-plans/active/` 且经人确认，必须包含：触及的既有模块声明、"部署影响"一节；
- 需求已拆成 ≤3~5 天可独立交付的单元；拆不出就先帮人拆 spec，不开大分支。

## 步骤

1. 从最新 main 建分支（网络操作走 `tools/` 包装脚本）：`git checkout -b feat/<功能>`，推送远端；
2. 按 spec 开发，尽量**新增文件**、少改既有文件；
3. 本地检查全绿：构建、类型检查、lint、单测、关键流程契约测试、spec 与代码一致性；
4. 每天（或 main 有新合入时）`git merge main`，冲突当场解；
5. 需要内网实测 → 按 `skills/sync-package` 出包交给人，等待实测反馈；
6. 实测失败 → 走 `skills/iteration-round`；通过 → 走 `skills/merge-and-close` 收尾。

## 红线

- 不改 spec 未声明的既有模块；行为变更与重构不混在同一分支/commit；
- 未通过内网实测不发起合入（typo/文案/样式类低风险改动除外，且需人确认）；
- 合入前最后一次 merge main 若带来新内容，必须再同步实测一轮。
