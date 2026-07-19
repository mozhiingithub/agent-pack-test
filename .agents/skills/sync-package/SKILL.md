---
name: sync-package
description: 生成内外网同步包（sync/close）的强制规范：唯一生成途径、确定性输出、manifest schema、脚本前置校验、无 jq 依赖。任何需要把代码同步到内网的场景必须遵守。
---

# 同步包生成规范（强制执行）

## 第一原则：只允许脚本出包

- 唯一生成途径是 `tools/export_package.sh`，调用形式：`tools/export_package.sh <branch> <sync|close>`；
- **禁止**：手工组包、手工修改包内任何文件、传规范外参数、脚本失败后改用其他方式拼装、改输入重跑直到"碰巧通过"；
- 脚本不可用或报错：立即停止，把 stderr **原文**报告人，由人决定修脚本或放行——AI 没有任何"绕过"选项。

## 脚本骨架（结构固定）

- 两个脚本必须基于 `agent-pack/templates/` 下的参考骨架生成：`export_package.sh`、`import.sh`；
- **固定区**（流程顺序、校验点、git 命令、退出码、日志格式）一字不改；**可变区**（项目路径、提取/组装细节、部署触发）按项目实现，接口与输出格式不变；
- 结构变更必须先由人确认并同步更新模板；禁止 AI 在骨架之外另起炉灶写"自己的版本"。

## 运行环境约束（硬约束）

内网执行环境是内网人员的 **Windows 个人电脑 + Git Bash，只装了 git**（无 jq、无 python 依赖、无其他第三方工具）。因此：

- 包格式与两个脚本**只依赖 git 与基础 bash 命令**；
- 内容校验一律用 **git 对象 hash**（blob/tree），不用磁盘文件 sha256——免疫 Windows 换行符（CRLF）差异；
- 外网出包脚本同样遵守（两侧脚本同源，不维护两套格式）。

## 确定性要求（同码同包）

同一分支状态下两次出包（除序号递增外）内容必须逐字节一致，脚本保证：

- `manifest.sh` 键序固定，`files.txt` 按路径排序；
- 打包条目排序、mtime 置零，包体可复现比对；
- AI 不参与包内容生成，只调用脚本并转述输出。

## 包结构

```
sync-<分支名>-<序号>/
├── manifest.sh      # 可直接 source 的 KEY=VALUE 清单（字段见下表）
├── message.txt      # commit message（close 包用）
├── configImpact.txt # 可选：部署影响待办，无则不生成
├── files.txt        # TSV 清单：action<TAB>blob<TAB>path，按 path 排序；delete 的 blob 为空
├── payload/         # 自上一包以来的增量 format-patch 序列（首包为全量）；规定只允许普通文件时为变更文件全集
└── import.sh        # 内网入口脚本（随模板下发，勿手改）
```

打包为 **zip**，文件**平铺在包根**（无外层目录）：执行人把 zip 放到内网仓库一级目录，右键"解压到当前位置"即可。

## import.sh 行为契约（随包模板必须满足）

AI 维护或下发 import.sh 模板时，必须保证以下行为，缺一即不合格：

- **与执行时所在分支无关**：不要求人员处于任何特定分支。开始先记录现场，随后用 `git worktree` 创建临时工作区，所有检出、应用、合并、校验都在临时工作区内对目标引用操作；不切换人员当前分支、不碰未提交改动；结束（无论成败）移除临时工作区，现场原样恢复；
- **零参数、零配置、自动分派**：向上找 `.git` 自动定位仓库（包须解压到仓库内，约定为一级目录"解压到当前位置"），**执行人不需要编辑脚本任何一行**；自读 manifest，sync 包走建/更新分支流程，close 包走合入 main + 对账 + 删分支流程；
- **成功后自清**：自动删除包文件（payload、manifest、清单等）并尝试自删除；失败则全部保留以便重跑；
- **幂等**：重复执行同一包只报告"已是最新"，无副作用；
- **失败还原**：任何一步失败，目标分支引用恢复执行前的值、临时工作区移除，并输出明确的下一步提示；
- **包自包含**：重试逻辑内置于 import.sh（与 `tools/safe-git.sh` 同源模板），不依赖内网仓库是否已有 `tools/`——首包执行时仓库里还没有它；网络失败后重新执行本包即恢复（幂等），无需 outbox；每步写日志。

## manifest 字段（SCHEMA_VERSION=1）

| 内容 | 载体 | 说明 |
| --- | --- | --- |
| schemaVersion | manifest.sh `SCHEMA_VERSION` | 固定 `1`，结构变更才递增，import.sh 拒收未知版本 |
| type | `TYPE` | `sync` / `close` |
| branch | `BRANCH` | 分支名 |
| seq | `SEQ` | 脚本自增，**AI 不得读写状态文件** |
| baseCommit | `BASE_COMMIT` | `git merge-base`，与 main 的分叉点 |
| prevStateHash | `PREV_STATE_HASH` | 上一包的 TREE_HASH（commit hash 因 committer 被 git am 改写而跨机不可比，tree 才可比），空 = 首包；防漏包乱序 |
| commitHash | `COMMIT_HASH` | 外网分支 tip（仅记录与展示，不参与跨机一致性校验） |
| treeHash | `TREE_HASH` | `git rev-parse <分支>^{tree}`，最终树校验值 |
| message | `message.txt` | sync：tip commit message；close：squash 合入 main 的 message |
| files | `files.txt` | `action<TAB>blob<TAB>path`，按 path 排序；blob 为 git 对象 hash |
| configImpact | `configImpact.txt` | spec"部署影响"一节原文；无则文件不存在 |

manifest.sh 键序固定；缺字段、多字段、值异常：import.sh 一律拒收。

## 生成前置校验（脚本强制，任一不过即失败退出）

1. 工作区干净，无未提交改动；
2. 分支 tip 与远端一致（已推送）；
3. 本地检查通过标记存在（`.checks-ok`，由检查脚本生成，24 小时内有效）；
4. spec 文件存在且含"部署影响"一节；
5. payload 不含 `deploy-intranet/` 路径（硬阻断，无豁免）；
6. close 包额外校验：分支已 squash 合入 main、`git diff main <branch>` 为空、push 已完成。

## 出包后

- 脚本输出：包路径、类型、序号、包体 SHA256；AI **原样转述**给人，不润色、不省略；
- 包目录只读：任何变更必须重新出包（序号递增），不得在旧包上修补。
