const opts = macotron.plugin({
    title: "AI Chat",
    description: "Chat with the on-device small model, Claude, or Gemini.",
    options: {
        model: {
            type: "dropdown",
            label: "Model",
            default: "small",
            choices: [
                { value: "small", label: "Small" },
                { value: "gpu", label: "GPU" },
                { value: "sonnet", label: "Sonnet" },
                { value: "opus", label: "Opus" },
                { value: "gemini", label: "Gemini" },
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
    { value: "small", label: "Small" },
    { value: "gpu", label: "GPU" },
    { value: "sonnet", label: "Sonnet" },
    { value: "opus", label: "Opus" },
    { value: "gemini", label: "Gemini" },
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

macotron.command("AI Chat", "Open a streaming chat panel", () => {
    const state = loadState();
    if (!state.chats.length) {
        const chat = newChat();
        state.chats = [chat];
        state.activeId = chat.id;
        saveState(state);
    }

    const selected = opts.model || "small";
    const options = MODELS.map((m) =>
        "<option value=\"" + m.value + "\"" + (m.value === selected ? " selected" : "") + ">" + m.label + "</option>"
    ).join("");

    const id = macotron.panel.open({
        title: "AI Chat",
        width: 440,
        height: 520,
        html: `<div id="log" class="grow scroll"></div>
<div class="toolbar">
  <select id="model">${options}</select>
  <input id="input" autofocus placeholder="Message…">
  <button id="send">Send</button>
  <button id="neu" class="secondary">New</button>
</div>
<script>
const log = document.getElementById("log");
const input = document.getElementById("input");
function add(role, text) {
  const el = document.createElement("div");
  el.dataset.role = role;
  el.style.margin = "0 0 10px";
  el.style.whiteSpace = "pre-wrap";
  el.innerHTML = "<b>" + role + "</b><div></div>";
  el.lastChild.textContent = text || "";
  log.appendChild(el);
  log.scrollTop = log.scrollHeight;
  return el.lastChild;
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
input.onkeydown = (e) => { if (e.key === "Enter") document.getElementById("send").click(); };
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
