// API 冒烟测试（node:test 内置运行器，零外部依赖）
const test = require('node:test');
const assert = require('node:assert');
const server = require('../server');

test('message board api: list/create/delete', async () => {
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;

  let res = await fetch(`${base}/api/messages`);
  assert.strictEqual(res.status, 200);
  const before = await res.json();
  assert.ok(Array.isArray(before));

  res = await fetch(`${base}/api/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'hello agent-pack' }),
  });
  assert.strictEqual(res.status, 201);
  const msg = await res.json();
  assert.ok(msg.id && msg.text === 'hello agent-pack');

  res = await fetch(`${base}/api/messages`);
  const list = await res.json();
  assert.strictEqual(list.length, before.length + 1);

  res = await fetch(`${base}/api/messages/${msg.id}`, { method: 'DELETE' });
  assert.strictEqual(res.status, 204);

  res = await fetch(`${base}/api/messages/${msg.id}`, { method: 'DELETE' });
  assert.strictEqual(res.status, 404);

  await new Promise((r) => server.close(r));
});
