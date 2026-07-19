const list = document.getElementById('list');
const form = document.getElementById('form');
const input = document.getElementById('text');

// 毫秒时间戳 → 本地时区"年月日 24 小时制时分"；locale/时区跟随浏览器，不硬编码
function formatTs(ts) {
  if (typeof ts !== 'number' || !Number.isFinite(ts)) return '';
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(undefined, {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
  });
}

async function refresh() {
  const res = await fetch('/api/messages');
  const msgs = await res.json();
  list.innerHTML = '';
  for (const m of msgs) {
    const li = document.createElement('li');
    const span = document.createElement('span');
    span.textContent = m.text;
    const btn = document.createElement('button');
    btn.textContent = '删除';
    btn.onclick = async () => {
      await fetch(`/api/messages/${m.id}`, { method: 'DELETE' });
      refresh();
    };
    li.append(span);
    const timeText = formatTs(m.ts);
    if (timeText) {
      const time = document.createElement('time');
      time.className = 'msg-time';
      time.dateTime = new Date(m.ts).toISOString();
      time.textContent = timeText;
      li.append(time);
    }
    li.append(btn);
    list.appendChild(li);
  }
}

form.onsubmit = async (e) => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  await fetch('/api/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  input.value = '';
  refresh();
};

refresh();
