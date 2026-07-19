---
name: fix-workflow
description: 修复 main 上可复现 bug 的全流程：根因 spec、fix 分支、修复检查、同步实测、合并收尾与回归测试沉淀。当任务是修 bug 时使用。
---

# Bug 修复流程

## 前置检查（不满足就退回，不接手）

- bug 必须在 main（latest/stable）上可复现；feat 分支内的问题不是 bug，退回开发线；
- 判定类型：局部缺陷直接修；设计性缺陷先请人裁定是否派回原作者（流程不变）。

## 步骤

1. 在 `docs/exec-plans/active/` 建执行计划，写四要素：现象、根因、修复方案、影响面；
2. 从最新 main 建 `fix/<bug>`；
3. 修复 + 本地检查全绿（同 feat 清单）；只改既有文件，不加新功能；
4. 出 sync 包交人实测；失败走 `skills/iteration-round`；
5. 通过后走 `skills/merge-and-close`，squash message 正文必须写根因与影响面；
6. **沉淀回归测试**：把本 bug 场景转化为外网可跑的自动化测试，随本分支或下一变更合入。

## 红线

- 一个 fix 分支只修一个 bug；范围扩大就拆成多个修复；
- 不顺手重构、不顺手改样式、不顺手加功能；
- 无回归测试不算修完。
