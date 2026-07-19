// 极简 JSON 文件存储：留言数据
const fs = require('fs');
const path = require('path');

const DATA_FILE = path.join(__dirname, '..', 'data', 'messages.json');

function readAll() {
  try {
    return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
  } catch {
    return [];
  }
}

function writeAll(list) {
  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
  fs.writeFileSync(DATA_FILE, JSON.stringify(list, null, 2));
}

function add(text) {
  const list = readAll();
  const msg = {
    id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
    text,
    ts: Date.now(),
  };
  list.push(msg);
  writeAll(list);
  return msg;
}

function remove(id) {
  const list = readAll();
  const next = list.filter((m) => m.id !== id);
  if (next.length === list.length) return false;
  writeAll(next);
  return true;
}

module.exports = { readAll, add, remove, DATA_FILE };
