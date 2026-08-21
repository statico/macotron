macotron.plugin({
    title: "DryRun Fixture",
    description: "Exercises every mutating bridge under --check.",
});

macotron.shell.run("touch", ["/tmp/macotron-dryrun-fixture"]);
macotron.fs.write("/tmp/macotron-dryrun-fixture.txt", "x");
macotron.fs.rename("/tmp/macotron-dryrun-a", "/tmp/macotron-dryrun-b");
macotron.fs.watch("/tmp", () => {})();
macotron.keychain.set("macotron-dryrun-fixture", "secret");
macotron.keychain.delete("macotron-dryrun-fixture");
macotron.http.get("http://127.0.0.1:1/");
macotron.http.post("http://127.0.0.1:1/", "{}");
macotron.ai.local().chat("hi");
macotron.url.open("https://example.com");
macotron.shortcuts.run("Does Not Exist");
macotron.hid.sendOutput("dev", [1]);
macotron.hid.sendFeature("dev", [1]);
macotron.notes.open("does-not-exist");
macotron.app.launch("com.apple.Finder");
macotron.app.quit("com.apple.Finder");
macotron.app.hide("com.apple.Finder");
macotron.window.focus(1);
macotron.window.move(1, { x: 0, y: 0 });
macotron.window.moveToFraction(1, { x: 0, y: 0, w: 1, h: 1 });
macotron.window.minimize(1);
macotron.window.close(1);
macotron.window.setFullscreen(1, true);
macotron.window.restore([{ id: 1, app: "X" }]);
macotron.alert("hi");
macotron.confirm("hi");
macotron.prompt("hi");
macotron.clipboard.set("clobbered");
macotron.display.setGamma({ red: 1, green: 0, blue: 0 });
macotron.display.restoreGamma();
macotron.ocr.recognize({ image: "aGk=" });
macotron.qr.scan();
macotron.qr.show("hello");
macotron.camera.snapshot();
macotron.snippets.set("abbr", "body");
macotron.snippets.insert("abbr");
macotron.snippets.setExpansionEnabled(true);
macotron.calendar.upcoming();
macotron.power.lock();
