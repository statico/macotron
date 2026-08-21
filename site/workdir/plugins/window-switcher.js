macotron.plugin({
    title: "Window Switcher",
    description: "Hold Option and press Tab to switch windows.",
    permissions: ["accessibility", "inputMonitoring"],
});

const TAB = 48;
let panelId = null;
let windows = [];
let index = 0;

function esc(text) {
    return String(text || "").replace(/[<>&]/g, "");
}

function rowsHtml() {
    return windows
        .map((win, i) => {
            const on = i === index ? " primary" : "";
            return (
                '<button class="block' +
                on +
                '"><b>' +
                esc(win.app) +
                "</b> — " +
                esc(win.title || "Untitled") +
                "</button>"
            );
        })
        .join("");
}

function listWindows() {
    const focused = macotron.window.focused();
    const all = macotron.window.getAll();
    if (!focused) return all;
    return [focused].concat(all.filter((win) => win.id !== focused.id));
}

function openPanel() {
    panelId = macotron.panel.open({
        title: "Windows",
        width: 420,
        height: 400,
        glass: "translucent",
        frameless: true,
        html:
            '<div id="list" class="grow scroll">' +
            (rowsHtml() || '<p class="muted">No windows</p>') +
            "</div>" +
            "<script>window.__macotronReceive=function(d){if(d&&d.html)document.getElementById('list').innerHTML=d.html};</script>",
    });
}

function render() {
    if (!panelId) {
        openPanel();
        return;
    }
    macotron.panel.postMessage(panelId, { html: rowsHtml() || '<p class="muted">No windows</p>' });
}

function begin() {
    windows = listWindows();
    index = windows.length > 1 ? 1 : 0;
    render();
}

function cycle(delta) {
    if (!windows.length) return;
    index = (index + delta + windows.length) % windows.length;
    render();
}

function commit() {
    if (!panelId) return;
    const win = windows[index];
    macotron.panel.close(panelId);
    panelId = null;
    windows = [];
    if (win) macotron.window.focus(win.id);
}

macotron.event.tap(["keyDown", "keyUp", "flagsChanged"], (e) => {
    const opt = e.flags.includes("opt");
    if (e.type === "keyDown" && e.keyCode === TAB && opt) {
        if (!panelId) begin();
        else cycle(e.flags.includes("shift") ? -1 : 1);
        return false;
    }
    if (e.type === "keyUp" && e.keyCode === TAB && opt) return false;
    if (panelId && e.type === "flagsChanged" && !opt) commit();
});
