# 接口契约：message-board API

> 本文件是双方 agent 的必读契约区。任何接口变更必须先改本文件，再改代码。

## Message

```json
{ "id": "string", "text": "string", "ts": 1720000000000 }
```

## 端点

| 方法 | 路径 | 入参 | 返回 | 说明 |
| --- | --- | --- | --- | --- |
| GET | `/api/messages` | - | `Message[]` | 全部留言 |
| POST | `/api/messages` | `{ "text": string }` | 201 `Message` / 400 | text trim 后非空 |
| DELETE | `/api/messages/:id` | - | 204 / 404 | id 不存在返回 404 |

## 静态资源

`GET /` → `web/index.html`；`GET /<file>` → `web/` 下静态文件（防目录穿越）。
