macotron.plugin({
    title: "Now Playing",
    description: "Show the current track in the menu bar, and play, pause, or skip.",
});

function clip(s, n) {
    s = s || "";
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function menu(info) {
    const has = !!(info.title || info.artist);
    const rows = [];
    if (has) {
        rows.push({ title: info.title || "Unknown" });
        if (info.artist) rows.push({ title: info.artist });
        if (info.album) rows.push({ title: info.album });
        if (info.app) rows.push({ title: info.app });
        rows.push("-");
    } else {
        rows.push({ title: "Nothing playing" });
        rows.push("-");
    }
    rows.push({
        title: info.playing ? "Pause" : "Play",
        onClick: () => macotron.media.playPause(),
    });
    rows.push({ title: "Next", onClick: () => macotron.media.next() });
    rows.push({ title: "Previous", onClick: () => macotron.media.previous() });
    if (info.bundle) {
        rows.push("-");
        rows.push({
            title: "Open " + (info.app || "Player"),
            onClick: () => macotron.app.launch(info.bundle),
        });
    }
    return rows;
}

function paint(info) {
    info = info || macotron.media.nowPlaying();
    const has = !!(info.title || info.artist);
    macotron.menubar.status("nowplaying", {
        title: has ? clip(info.title || "Unknown", 22) : "",
        subtitle: has ? clip(info.artist || "", 22) : "",
        image: info.artwork,
        sfSymbol: info.artwork ? undefined : has ? (info.playing ? "pause.fill" : "play.fill") : "music.note",
        secondary: true,
        onClick: () => macotron.media.playPause(),
        menu: menu(info),
    });
}

macotron.on("media:changed", paint);
paint();

macotron.command("Play/Pause", "Toggle the current media player", () => {
    macotron.media.playPause();
});
macotron.command("Next Track", "Skip to the next track", () => {
    macotron.media.next();
});
