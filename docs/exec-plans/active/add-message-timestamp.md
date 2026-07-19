# 执行计划：消息列表显示时间戳

> 供双工协作试运行第一个练习任务使用（分支：`feat/add-message-timestamp`）。

## 目标

留言板列表中每条消息显示发布时间（如 `2026-07-19 14:30`）。

## 触及的既有模块

- `web/app.js`（渲染列表处追加时间展示，新增辅助函数，不改数据逻辑）；
- `web/style.css`（时间样式，新增规则）。

数据已有 `ts` 字段（见 `docs/design-docs/api.md`；`server/store.js` 写入 `ts: Date.now()`，存量数据文件为空、无历史包袱），**不改后端、不改接口**。

## 方案细节

1. `web/app.js`：
   - 新增辅助函数 `formatTs(ts)`：对毫秒时间戳返回
     `new Date(ts).toLocaleString(undefined, { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })`，
     即"年月日 + 24 小时制时分"，locale 与时区跟随浏览器，不硬编码；
   - 渲染处：每条 `<li>` 在文本 `<span>` 与删除按钮之间插入
     `<time class="msg-time" datetime="<ISO 串>">`，文本为 `formatTs` 结果；
   - 防御：`ts` 不是有限数字时不创建 `<time>` 元素（其余渲染照常）；
   - 数据获取 / 提交 / 删除逻辑一律不动。
2. `web/style.css`：新增 `.msg-time` 规则——`font-size: 12px`、`color: #6b7280`、`margin-left: auto`、`margin-right: 12px`，把时间推到每行右侧、删除按钮之前。
3. 接口与数据结构零变化，`docs/design-docs/` 无需更新。
4. 测试策略：纯前端展示层，仓库无前端测试设施，**不新增自动化测试**；验证靠 `tools/check.sh` 全绿（回归 server 侧）+ `node --check web/app.js` 语法自检 + 内网页面实测。

## 部署影响

无

## 验收标准

- [ ] 本地检查（`bash tools/check.sh`）全绿，且 `node --check web/app.js` 通过
- [ ] 页面每条消息显示"年月日 24 小时制时分"的本地时区时间（形如 `2026/07/19 14:30`，locale 不同分隔符可变），无时区/locale 硬编码
- [ ] 内网 latest 实测通过
