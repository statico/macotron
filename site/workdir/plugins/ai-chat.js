const opts = macotron.plugin({
    title: "AI Chat Window",
    description: "Chat with Apple Intelligence, Claude, or Gemini.",
    options: {
        model: {
            type: "dropdown",
            label: "Model",
            default: "small",
            choices: [
                { value: "small", label: "On-device (Apple Intelligence)" },
                { value: "sonnet", label: "Claude Sonnet" },
                { value: "opus", label: "Claude Opus" },
                { value: "gemini", label: "Gemini Flash" },
            ],
        },
        anthropicKey: {
            type: "password",
            label: "Anthropic API key",
        },
        geminiKey: {
            type: "password",
            label: "Gemini API key",
        },
    },
});

const STORE_KEY = "macotron.ai-chat.v1";
const MAX_CHATS = 50;
const MODELS = [
    { value: "small", label: "On-device", group: "This Mac · Apple Intelligence" },
    { value: "sonnet", label: "Claude Sonnet", group: "Cloud · needs API key" },
    { value: "opus", label: "Claude Opus", group: "Cloud · needs API key" },
    { value: "gemini", label: "Gemini Flash", group: "Cloud · needs API key" },
];

function loadState() {
    try {
        const raw = localStorage.getItem(STORE_KEY);
        if (raw) {
            const parsed = JSON.parse(raw);
            if (parsed && parsed.version === 1 && Array.isArray(parsed.chats)) return parsed;
        }
    } catch (_) { }
    const chat = newChat();
    return { version: 1, activeId: chat.id, chats: [chat] };
}

function saveState(state) {
    state.chats.sort((a, b) => b.updatedAt - a.updatedAt);
    if (state.chats.length > MAX_CHATS) state.chats = state.chats.slice(0, MAX_CHATS);
    if (!state.chats.some((c) => c.id === state.activeId)) {
        state.activeId = state.chats[0] ? state.chats[0].id : newChat().id;
    }
    localStorage.setItem(STORE_KEY, JSON.stringify(state));
}

function newChat() {
    return { id: String(Date.now()) + "-" + Math.random().toString(16).slice(2), title: "Untitled", updatedAt: Date.now(), messages: [] };
}

function activeChat(state) {
    return state.chats.find((c) => c.id === state.activeId) || state.chats[0];
}

function client(model) {
    if (model === "opus") {
        return macotron.ai.anthropic({ apiKey: opts.anthropicKey, model: "claude-opus-4-6" });
    }
    if (model === "sonnet") {
        return macotron.ai.claude({ apiKey: opts.anthropicKey, model: "claude-sonnet-4-6" });
    }
    if (model === "gemini") {
        return macotron.ai.gemini({ apiKey: opts.geminiKey, model: "gemini-2.5-flash" });
    }
    return macotron.ai.local();
}

function modelOptions(selected) {
    const current = selected === "gpu" ? "small" : selected;
    let html = "";
    let group = "";
    for (const m of MODELS) {
        if (m.group !== group) {
            if (group) html += "</optgroup>";
            group = m.group;
            html += "<optgroup label=\"" + group + "\">";
        }
        html += "<option value=\"" + m.value + "\"" + (m.value === current ? " selected" : "") + ">" + m.label + "</option>";
    }
    if (group) html += "</optgroup>";
    return html;
}

macotron.command("AI Chat", "Open a streaming chat panel", () => {
    const state = loadState();
    if (!state.chats.length) {
        const chat = newChat();
        state.chats = [chat];
        state.activeId = chat.id;
        saveState(state);
    }

    const id = macotron.panel.open({
        title: "AI Chat",
        width: 440,
        height: 520,
        html: `<style>
#log { display: flex; flex-direction: column; gap: 12px; padding: 4px 0 8px; }
.msg { max-width: 82%; word-wrap: break-word; }
.msg[data-role="user"] {
  align-self: flex-end;
  padding: 8px 14px;
  border-radius: 18px;
  background: var(--macotron-accent);
  color: #fff;
  white-space: pre-wrap;
}
.msg[data-role="assistant"] { align-self: flex-start; padding: 2px 4px; max-width: 100%; }
.msg[data-role="error"] {
  align-self: flex-start;
  padding: 8px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--macotron-control-border) 35%, transparent);
  white-space: pre-wrap;
}
.msg p, .msg ul, .msg ol, .msg pre { margin: 0 0 8px; }
.msg > :last-child { margin-bottom: 0; }
.msg ul, .msg ol { padding-left: 20px; }
.msg code {
  font-size: 12px;
  padding: 1px 4px;
  border-radius: 4px;
  background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.10));
}
.msg pre {
  padding: 10px 12px;
  border-radius: 10px;
  background: light-dark(rgba(0,0,0,0.05), rgba(255,255,255,0.07));
  overflow-x: auto;
}
.msg pre code { padding: 0; background: none; }
#composer {
  border: 1px solid light-dark(rgba(0,0,0,0.12), rgba(255,255,255,0.14));
  border-radius: 20px;
  background: light-dark(#ffffff, #2c2c2e);
  padding: 10px 10px 8px 14px;
}
#composer:focus-within { border-color: light-dark(rgba(0,0,0,0.25), rgba(255,255,255,0.3)); }
#input {
  display: block;
  width: 100%;
  border: 0;
  padding: 0 0 8px;
  background: none;
  resize: none;
  max-height: 160px;
  box-shadow: none;
}
#bar { display: flex; align-items: center; gap: 8px; }
#bar button, #bar select {
  height: 28px;
  padding: 0 10px;
  border-radius: 14px;
  font-size: 12px;
  background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.10));
  border: 0;
}
#model {
  width: auto;
  padding-right: 24px;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath fill='%2398989d' d='M1 1l4 4 4-4'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 9px center;
}
#neu, #send { width: 28px; padding: 0; font-size: 18px; line-height: 28px; text-align: center; flex: none; }
#send { margin-left: auto; background: var(--macotron-accent); color: #fff; }
#send:disabled { opacity: 0.35; cursor: default; }
</style>
<div id="log" class="grow scroll"></div>
<div id="composer">
  <textarea id="input" autofocus rows="1" placeholder="Message…"></textarea>
  <div id="bar">
    <button id="neu" class="secondary" title="New chat">+</button>
    <select id="model" title="Model">${modelOptions(opts.model || "small")}</select>
    <button id="send" title="Send" disabled>↑</button>
  </div>
</div>
<script>
const log = document.getElementById("log");
const input = document.getElementById("input");
const send = document.getElementById("send");
function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function inline(s) {
  return esc(s)
    .replace(/\`([^\`\\n]+)\`/g, "<code>$1</code>")
    .replace(/\\*\\*([^*]+)\\*\\*/g, "<strong>$1</strong>")
    .replace(/(^|\\s)\\*([^*\\n]+)\\*/g, "$1<em>$2</em>");
}
// Minimal markdown: fenced code, inline code, bold, italics, lists, paragraphs.
function markdown(text) {
  const parts = text.split(/\`\`\`[^\\n]*\\n?/);
  let html = "";
  for (let i = 0; i < parts.length; i++) {
    if (i % 2) { html += "<pre><code>" + esc(parts[i].replace(/\\n$/, "")) + "</code></pre>"; continue; }
    let mode = "";
    const close = () => { if (mode) html += "</" + mode + ">"; mode = ""; };
    for (const line of parts[i].split("\\n")) {
      const li = /^\\s*(?:[-*]|(\\d+)\\.) (.*)/.exec(line);
      if (li) {
        const kind = li[1] ? "ol" : "ul";
        if (mode !== kind) { close(); mode = kind; html += "<" + kind + ">"; }
        html += "<li>" + inline(li[2]) + "</li>";
      } else if (line.trim()) {
        if (mode !== "p") { close(); mode = "p"; html += "<p>"; } else html += "<br>";
        html += inline(line);
      } else close();
    }
    close();
  }
  return html;
}
function add(role, text) {
  const el = document.createElement("div");
  el.className = "msg";
  el.dataset.role = role;
  if (role === "error") el.classList.add("bad");
  if (role === "assistant") el.innerHTML = markdown(text || "");
  else el.textContent = text || "";
  log.appendChild(el);
  log.scrollTop = log.scrollHeight;
  return el;
}
let streamEl = null;
let streamText = "";
function grow() {
  input.style.height = "auto";
  input.style.height = input.scrollHeight + "px";
  send.disabled = !input.value.trim();
}
input.oninput = grow;
send.onclick = () => {
  const text = input.value.trim();
  if (!text) return;
  input.value = "";
  grow();
  window.webkit.messageHandlers.macotron.postMessage({
    type: "send",
    text: text,
    model: document.getElementById("model").value,
  });
};
input.onkeydown = (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    send.click();
  }
};
document.getElementById("neu").onclick = () => window.webkit.messageHandlers.macotron.postMessage({ type: "new" });
window.__macotronReceive = (data) => {
  if (!data) return;
  if (data.type === "history") {
    log.innerHTML = "";
    (data.messages || []).forEach((m) => add(m.role, m.content));
  }
  if (data.type === "user") add("user", data.text);
  if (data.type === "chunk") {
    if (!streamEl) { streamEl = add("assistant", ""); streamText = ""; }
    streamText += data.chunk;
    streamEl.innerHTML = markdown(streamText);
    log.scrollTop = log.scrollHeight;
  }
  if (data.type === "done") {
    if (streamEl) streamEl.innerHTML = markdown(data.text || streamText);
    streamEl = null;
  }
  if (data.type === "error") { add("error", data.text); streamEl = null; }
};
grow();
input.focus();
</script>`,
    });

    function dumpHistory() {
        const chat = activeChat(state);
        macotron.panel.postMessage(id, { type: "history", messages: chat.messages });
    }
    dumpHistory();

    macotron.panel.onMessage(id, async (data) => {
        if (!data) return;
        if (data.type === "new") {
            const chat = newChat();
            state.chats.unshift(chat);
            state.activeId = chat.id;
            saveState(state);
            dumpHistory();
            return;
        }
        if (data.type !== "send") return;
        const text = String(data.text || "").trim();
        if (!text) return;
        const chat = activeChat(state);
        chat.messages.push({ role: "user", content: text });
        if (chat.title === "Untitled") chat.title = text.slice(0, 40);
        chat.updatedAt = Date.now();
        macotron.panel.postMessage(id, { type: "user", text });
        try {
            const reply = await client(String(data.model || opts.model || "small")).stream(chat.messages, {
                onChunk: (chunk) => macotron.panel.postMessage(id, { type: "chunk", chunk }),
            });
            chat.messages.push({ role: "assistant", content: reply });
            chat.updatedAt = Date.now();
            saveState(state);
            macotron.panel.postMessage(id, { type: "done", text: reply });
        } catch (err) {
            saveState(state);
            macotron.panel.postMessage(id, { type: "error", text: String(err) });
        }
    });
});
