const opts = macotron.plugin({
    title: "AI Chat",
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
    } catch (_) {}
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
.msg { max-width: 82%; white-space: pre-wrap; word-wrap: break-word; }
.msg[data-role="user"] {
  align-self: flex-end;
  padding: 8px 14px;
  border-radius: 18px;
  background: var(--macotron-accent);
  color: var(--macotron-accent-text);
}
.msg[data-role="assistant"] {
  align-self: flex-start;
  padding: 2px 4px;
  color: var(--macotron-label);
}
.msg[data-role="error"] {
  align-self: flex-start;
  padding: 8px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--macotron-control-border) 35%, transparent);
  color: inherit;
}
</style>
<div id="log" class="grow scroll"></div>
<div class="toolbar">
  <select id="model">${modelOptions(opts.model || "small")}</select>
  <textarea id="input" autofocus rows="2" placeholder="Message…"></textarea>
  <button id="send" class="primary">Send</button>
  <button id="neu" class="secondary">New</button>
</div>
<script>
const log = document.getElementById("log");
const input = document.getElementById("input");
function add(role, text) {
  const el = document.createElement("div");
  el.className = "msg";
  el.dataset.role = role;
  if (role === "error") el.classList.add("bad");
  el.textContent = text || "";
  log.appendChild(el);
  log.scrollTop = log.scrollHeight;
  return el;
}
let streamEl = null;
document.getElementById("send").onclick = () => {
  const text = input.value.trim();
  if (!text) return;
  input.value = "";
  window.webkit.messageHandlers.macotron.postMessage({
    type: "send",
    text: text,
    model: document.getElementById("model").value,
  });
};
input.onkeydown = (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    document.getElementById("send").click();
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
    if (!streamEl) streamEl = add("assistant", "");
    streamEl.textContent += data.chunk;
    log.scrollTop = log.scrollHeight;
  }
  if (data.type === "done") {
    if (streamEl) streamEl.textContent = data.text || streamEl.textContent;
    streamEl = null;
  }
  if (data.type === "error") { add("error", data.text); streamEl = null; }
};
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
