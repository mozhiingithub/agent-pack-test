const list = document.getElementById('list');
const form = document.getElementById('form');
const input = document.getElementById('text');

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
    li.append(span, btn);
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
