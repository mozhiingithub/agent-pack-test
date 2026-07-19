// 极简留言板后端：原生 http，零外部依赖
const http = require('http');
const fs = require('fs');
const path = require('path');
const store = require('./store');

const WEB_DIR = path.join(__dirname, '..', 'web');
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1e5) req.destroy();
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.pathname === '/api/messages' && req.method === 'GET') {
    return sendJson(res, 200, store.readAll());
  }

  if (url.pathname === '/api/messages' && req.method === 'POST') {
    const body = await readBody(req);
    let text = '';
    try {
      text = JSON.parse(body).text || '';
    } catch {
      return sendJson(res, 400, { error: 'bad json' });
    }
    text = String(text).trim();
    if (!text) return sendJson(res, 400, { error: 'text required' });
    return sendJson(res, 201, store.add(text));
  }

  const del = url.pathname.match(/^\/api\/messages\/([\w-]+)$/);
  if (del && req.method === 'DELETE') {
    return store.remove(del[1])
      ? sendJson(res, 204, {})
      : sendJson(res, 404, { error: 'not found' });
  }

  if (req.method === 'GET') {
    const p = path.normalize(
      path.join(WEB_DIR, url.pathname === '/' ? 'index.html' : url.pathname)
    );
    if (p.startsWith(WEB_DIR) && fs.existsSync(p) && fs.statSync(p).isFile()) {
      res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
      return res.end(fs.readFileSync(p));
    }
  }

  sendJson(res, 404, { error: 'not found' });
});

if (require.main === module) {
  const port = process.env.PORT || 3000;
  server.listen(port, () => console.log(`message-board listening on :${port}`));
}

module.exports = server;
