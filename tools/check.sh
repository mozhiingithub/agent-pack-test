#!/usr/bin/env bash
# tools/check.sh — 本地检查：语法 + 测试，全绿后写 .checks-ok 标记
# （export_package.sh 前置校验要求该标记 24h 内有效）
set -euo pipefail
cd "$(dirname "$0")/.."

node --check server/index.js
node --check server/store.js
node --test tests/*.test.js

touch .checks-ok
echo "[check] 全部通过，已更新 .checks-ok"
