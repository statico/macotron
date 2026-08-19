// APIs: command, shell.run, panel, notify

async function run(cmd, args) {
    try {
        return await macotron.shell.run(cmd, args);
    } catch (err) {
        return { stdout: "", stderr: String(err), exitCode: 1 };
    }
}

macotron.command("Security Checklist", "Probe FileVault, firewall, and SIP", async () => {
    const fv = await run("/usr/bin/fdesetup", ["status"]);
    const fw = await run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]);
    const sip = await run("/usr/bin/csrutil", ["status"]);
    const gate = await run("/usr/sbin/spctl", ["--status"]);

    const items = [
        ["FileVault", /FileVault is On/i.test(fv.stdout), (fv.stdout || fv.stderr).trim()],
        ["Firewall", /enabled/i.test(fw.stdout), (fw.stdout || fw.stderr).trim()],
        ["SIP", /enabled/i.test(sip.stdout), (sip.stdout || sip.stderr).trim()],
        ["Gatekeeper", /assessments enabled/i.test(gate.stdout), (gate.stdout || gate.stderr).trim()],
    ];

    const rows = items.map(([name, ok, detail]) => {
        const mark = ok ? "OK" : "CHECK";
        return `<div><b>${name}</b> <span class="${ok ? "ok" : "bad"}">${mark}</span><div class="muted mono">${String(detail).replace(/[<>&]/g, "")}</div></div>`;
    }).join("");

    macotron.panel.open({
        title: "Security Checklist",
        width: 420,
        height: 320,
        html: `<div class="grow scroll">${rows}</div>
<button onclick="close()">Close</button>`,
    });
});
