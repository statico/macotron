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
        const color = ok ? "#22863a" : "#cb2431";
        const mark = ok ? "OK" : "CHECK";
        return `<div style="margin:0 0 10px"><b>${name}</b> <span style="color:${color}">${mark}</span><div style="color:#666;font:12px ui-monospace,monospace">${String(detail).replace(/[<>&]/g, "")}</div></div>`;
    }).join("");

    macotron.panel.open({
        title: "Security Checklist",
        width: 420,
        height: 320,
        html: `<!DOCTYPE html><html><body style="font:13px system-ui;margin:16px">${rows}</body></html>`,
    });
});
