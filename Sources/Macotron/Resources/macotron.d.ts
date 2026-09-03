// Type definitions for Macotron JS API
// These are provided to AI models for code generation

interface MenuBarMenuItem {
    title: string;
    icon?: string;
    onClick?: () => void;
    menu?: MenuBarMenuItem[];
    /**
     * Show a web page as the row itself instead of a title. The page keeps
     * running while the menu is open, but menu tracking eats mouse events
     * before the page sees them, so keep buttons in ordinary rows.
     * Reloaded only when this markup changes.
     */
    html?: string;
    /** Size of the `html` row in points. Defaults to 260 x 160. */
    width?: number;
    height?: number;
    /**
     * Draw these as buttons across one row. Unlike an ordinary row, clicking
     * one runs its `onClick` and leaves the menu open, so a menu can be paged
     * or stepped without closing.
     */
    buttons?: MenuBarMenuItem[];
}

interface LauncherItem {
    id: string;
    title: string;
    subtitle?: string;
    /** Bundle ID, e.g. `com.apple.Notes`. */
    app?: string;
    sfSymbol?: string;
    kind?: string;
    onClick?: () => void;
}

interface HIDFilter {
    vendorID?: number;
    productID?: number;
    usagePage?: number;
    usage?: number;
    serial?: string;
    path?: string;
    /** Hex vid/pid like hidapitester: `"27b8/1ed"`. */
    vidpid?: string;
}

interface HIDDeviceInfo {
    name: string;
    vendor: string;
    vendorID: number;
    productID: number;
    usagePage: number;
    usage: number;
    serial: string;
    path: string;
    maxInput: number;
    maxOutput: number;
    maxFeature: number;
}

declare function alert(message?: any): void;
declare function confirm(message?: any): boolean;
declare function prompt(message?: any, defaultValue?: string): string | null;

declare const macotron: {
    version: {
        app: string;
        api: string;
        /** Host API versions keyed by native namespace (`window`, `panel`, …), not user plugins. */
        modules: Record<string, number>;
    };

    on(event: string, callback: (...args: any[]) => void): void;
    off(event: string, callback: (...args: any[]) => void): void;
    command(
        name: string,
        description: string,
        handler: (args: Record<string, any>) => void | Promise<void>,
        opts?: {
            id?: string;
            arguments?: Array<
                | { name: string; type: "text"; placeholder?: string; required?: boolean; default?: string }
                | { name: string; type: "number"; placeholder?: string; required?: boolean; default?: number }
                | {
                      name: string;
                      type: "dropdown";
                      placeholder?: string;
                      required?: boolean;
                      default?: string;
                      choices: Array<{ title?: string; label?: string; value: string }>;
                  }
            >;
        }
    ): void;
    /** Blocking OK sheet. Same as global `alert`. */
    alert(message?: any): void;
    /** Blocking OK/Cancel sheet. Same as global `confirm`. */
    confirm(message?: any): boolean;
    /** Blocking text sheet. Cancel returns `null`. Same as global `prompt`. */
    prompt(message?: any, defaultValue?: string): string | null;
    log(...args: any[]): void;
    sleep(ms: number): Promise<void>;
    every(msOrDuration: number | string, callback: () => void | Promise<void>): () => void;
    at(
        time: string,
        callbackOrOpts: (() => void | Promise<void>) | { weekdays?: number[] },
        callback?: () => void | Promise<void>
    ): () => void;
    /**
     * Replace this plugin's Checks list in Settings → Plugins.
     * A row with `ok: false` shows an orange warning on the plugin.
     * Pass `[]` to clear. Call again whenever the status changes.
     */
    checks(rows: Array<{ title: string; ok: boolean; message?: string }>): void;
    settings: {
        /** Open Settings → Plugins on this plugin. */
        open(): void;
    };

    window: {
        getAll(): Array<{
            id: number;
            title: string;
            app: string;
            bundleID?: string;
            display?: number;
            frame: { x: number; y: number; width: number; height: number };
        }>;
        focused(): {
            id: number;
            title: string;
            app: string;
            bundleID?: string;
            display?: number;
            frame: { x: number; y: number; width: number; height: number };
        } | null;
        /** Raise, unminimize, and activate the window's app. */
        focus(id: number): boolean;
        minimize(id: number, on?: boolean): boolean;
        close(id: number): boolean;
        setFullscreen(id: number, on: boolean): boolean;
        move(id: number, frame: { x?: number; y?: number; width?: number; height?: number }): boolean;
        /** Fractions of the window's current display. Pass `display` from `macotron.display.list()` to send it to another screen. */
        moveToFraction(id: number, frac: { x?: number; y?: number; w?: number; h?: number; display?: number }): boolean;
        /** Show or hide the snap destination overlay. Pass `null` to hide. */
        previewFraction(frac: { x?: number; y?: number; w?: number; h?: number; display?: number; gap?: number } | null): boolean;
        setSnapEnabled(enabled: boolean): boolean;
        isSnapEnabled(): boolean;
        /** Drag-to-edge tiling. Zones are fractions of the visible frame (same as moveToFraction). Omit a slot to disable it. `modifiers` swaps the map while those keys are held (`shift`, `cmd+shift`). */
        snap(opts: boolean | {
            enabled?: boolean;
            threshold?: number;
            corner?: number;
            gap?: number;
            zones?: {
                left?: { x: number; y: number; w: number; h: number };
                right?: { x: number; y: number; w: number; h: number };
                top?: { x: number; y: number; w: number; h: number };
                bottom?: { x: number; y: number; w: number; h: number };
                tl?: { x: number; y: number; w: number; h: number };
                tr?: { x: number; y: number; w: number; h: number };
                bl?: { x: number; y: number; w: number; h: number };
                br?: { x: number; y: number; w: number; h: number };
                [slot: string]: { x: number; y: number; w: number; h: number } | undefined;
            };
            modifiers?: Record<string, {
                left?: { x: number; y: number; w: number; h: number };
                right?: { x: number; y: number; w: number; h: number };
                top?: { x: number; y: number; w: number; h: number };
                bottom?: { x: number; y: number; w: number; h: number };
                tl?: { x: number; y: number; w: number; h: number };
                tr?: { x: number; y: number; w: number; h: number };
                bl?: { x: number; y: number; w: number; h: number };
                br?: { x: number; y: number; w: number; h: number };
                [slot: string]: { x: number; y: number; w: number; h: number } | undefined;
            }>;
        }): boolean;
        /** Match by app name (or bundleID) and title, then move. IDs change after a restart. */
        restore(
            entries: Array<{
                app: string;
                bundleID?: string;
                title?: string;
                frame: { x?: number; y?: number; width?: number; height?: number };
                display?: number;
            }>
        ): { restored: number; missing: number };
    };

    keyboard: {
        /** `id` is the Settings label, unique per plugin. */
        on(id: string, defaultCombo: string, callback: () => void): void;
        /** Current modifier state from the HID system. */
        flags(): { cmd: boolean; shift: boolean; ctrl: boolean; opt: boolean; caps: boolean; fn: boolean };
        /** Caps Lock or Fn becomes Command+Shift+Control+Option while held. Pass `null` to clear. */
        setHyperKey(key: "caps" | "fn" | null): boolean;
        hyperKey(): "caps" | "fn" | null;
    };

    event: {
        post(
            event:
                | { type: "click"; button?: "left" | "right" | "middle"; x?: number; y?: number }
                | { type: "key"; key: string; flags?: Array<"cmd" | "shift" | "ctrl" | "opt" | "fn" | "caps"> }
                | { type: "unicode"; string: string }
                | { type: "scroll"; dx?: number; dy?: number; pixel?: boolean }
        ): boolean;
        /**
         * HID tap. Return `false` to swallow the event. Host-posted events are ignored
         * so a tap cannot loop on `event.post`.
         */
        tap(
            types: string | string[],
            callback: (e: {
                type: string;
                flags: string[];
                x: number;
                y: number;
                keyCode?: number;
                dx?: number;
                dy?: number;
                button?: string;
                down?: boolean;
                fingers?: number;
                direction?: string;
                delta?: number;
            }) => boolean | void
        ): void;
    };

    mouse: {
        /** Cocoa screen points (origin bottom-left of the main display). */
        location(): { x: number; y: number };
        warp(x: number, y: number): boolean;
        warp(point: { x: number; y: number }): boolean;
        buttons(): { left: boolean; right: boolean; center: boolean };
    };

    screen: {
        capture(opts?: { windowID?: number; selection?: boolean }): Promise<string>;
        /** System magnifier eyedropper. Resolves null if cancelled. Coords are Cocoa screen points. */
        pickColor(): Promise<{
            hex: string;
            r: number;
            g: number;
            b: number;
            x: number;
            y: number;
        } | null>;
    };

    shell: {
        run(command: string, args?: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }>;
    };

    notify: {
        show(title: string, body: string, opts?: { sound?: boolean; subtitle?: string; id?: string }): void;
        /** One-line HUD centered on the screen under the cursor. Default duration 3000ms. */
        toast(
            title: string,
            body?: string,
            opts?: {
                position?: "top" | "bottom";
                duration?: number;
                sfSymbol?: string;
                color?: "info" | "success" | "error" | "failure" | "warning" | string;
            }
        ): void;
    };

    url: {
        on(scheme: string, host: string | RegExp, callback: (event: { url: string; scheme: string; host: string; path: string; query?: string; sourceBundle?: string }) => void): void;
        open(url: string, bundleID?: string, profile?: string): boolean;
        setDefaultHandler(scheme: string): boolean;
        onFallback(callback: (event: { url: string; scheme: string; host: string; path: string; query?: string; sourceBundle?: string }) => void): void;
    };

    fs: {
        read(path: string): string;
        /** File contents as a base64 string. */
        readBytes(path: string): string;
        write(path: string, content: string): void;
        exists(path: string): boolean;
        /** Fails if `to` already exists. Both paths expand `~`. */
        rename(from: string, to: string): void;
        list(path: string): string[];
        watch(path: string, callback: (event: { path: string; type: string }) => void): () => void;
    };

    clipboard: {
        text(): string;
        set(text: string): void;
        setImage(base64: string): boolean;
        history(): Array<{ id: string; text: string; kind: "text" | "image"; ts: number }>;
        paste(id: string): boolean;
        remove(id: string): boolean;
        clearHistory(): void;
        clear(): void;
        types(): string[];
        /** Pasteboard bytes for a UTI, base64, or null. */
        data(uti: string): string | null;
        /** Command-V pastes `public.utf8-plain-text` only. */
        setPastePlain(on: boolean): boolean;
        isPastePlain(): boolean;
    };

    snippets: {
        list(): Array<{ abbr: string; body: string }>;
        set(abbr: string, body: string): void;
        remove(abbr: string): void;
        insert(abbr: string): boolean;
        setExpansionEnabled(enabled: boolean): boolean;
        isExpansionEnabled(): boolean;
    };

    power: {
        preventSleep(opts?: { display?: boolean; reason?: string }): boolean;
        allowSleep(): void;
        isPreventing(): boolean;
        lock(): boolean;
        sleep(): boolean;
        displaySleep(): boolean;
        screensaver(): boolean;
        logOut(): boolean;
        restart(): boolean;
        shutdown(): boolean;
    };

    network: {
        /** Current SSID, or null when Wi-Fi is off or disconnected. */
        wifiSSID(): Promise<string | null>;
        wifi(): Promise<{ available: boolean; on: boolean; ssid?: string }>;
        setWifi(on: boolean): Promise<{ ok: boolean; available: boolean; on: boolean; ssid?: string; error?: string }>;
        bluetooth(): Promise<{
            on: boolean;
            devices: Array<{ name: string; address: string; connected: boolean; battery?: number }>;
        }>;
        setBluetooth(on: boolean): { ok: boolean; on: boolean; error?: string };
        /** AirDrop discovery. `contacts` is Contacts Only. */
        airDrop(): { mode: "off" | "contacts" | "everyone" };
        setAirDrop(mode: "off" | "contacts" | "everyone"): Promise<{
            ok: boolean;
            mode: "off" | "contacts" | "everyone";
            error?: string;
        }>;
        interfaces(): Array<{ name: string; ip: string }>;
        counters(): Array<{ name: string; ip?: string; bytesIn: number; bytesOut: number }>;
        ping(host?: string): Promise<{ ms: number | null; host: string; error?: string }>;
    };

    /** `timeout` is seconds (default 1.5). Types may omit `local.` */
    bonjour: {
        browse(type: string, opts?: { timeout?: number }): Promise<Array<{
            name: string;
            type: string;
            host: string;
            port: number;
            txt: Record<string, string>;
        }>>;
    };

    udp: {
        send(host: string, port: number, data: string | number[]): { ok: boolean; error?: string };
        listen(port: number): { ok: boolean; error?: string };
        unlisten(port: number): void;
    };

    appletv: {
        list(): Promise<Array<{ id: string; name: string; host: string; port: number; type: string }>>;
        send(
            id: string,
            command: "up" | "down" | "left" | "right" | "select" | "menu" | "home" | "play" | "pause" | "playpause"
        ): Promise<{ ok: boolean; error?: string }>;
    };

    idle: {
        seconds(): number;
        setThreshold(seconds: number): void;
    };

    media: {
        nowPlaying(): {
            playing: boolean;
            title: string;
            artist: string;
            album: string;
            app: string;
            bundle: string;
            artwork?: string;
        };
        playPause(): void;
        next(): void;
        previous(): void;
    };

    ai: {
        claude(opts?: { model?: string; apiKey?: string }): AIClient;
        anthropic(opts?: { model?: string; apiKey?: string }): AIClient;
        openai(opts?: { model?: string; apiKey?: string }): AIClient;
        gemini(opts?: { model?: string; apiKey?: string }): AIClient;
        local(): AIClient;
    };

    spotlight: {
        /**
         * Find files and folders by name. A plain query matches by name prefix
         * first, then fuzzily across folder names, so a few letters spanning a
         * parent and child folder still land. A query containing "/" is
         * completed as a path, one segment per level, with "~" for home and a
         * trailing "/" listing a folder's children.
         */
        search(query: string, opts?: { folder?: string; kind?: string }): Promise<Array<{ path: string; name: string; kind: string }>>;
    };

    launcher: {
        set(id: string, items: LauncherItem[]): void;
        /**
         * Answer the launcher's text directly instead of matching a fixed list.
         * Runs on every keystroke, so return fast and return `[]` when the text
         * is not yours. These results appear above the fuzzy-matched ones.
         *
         * A promise is allowed, but the launcher does not wait on it: the
         * keystroke is answered with whatever is ready and late rows are pushed
         * in when it settles, so a stale answer is dropped and a rejection
         * clears this provider's rows.
         *
         * @example
         * macotron.launcher.query("calc", (q) => {
         *     const n = Number(q);
         *     return isFinite(n) ? [{ id: "n", title: String(n * 2), subtitle: "double" }] : [];
         * });
         */
        query(
            id: string,
            handler: (query: string) => LauncherItem[] | Promise<LauncherItem[]>
        ): void;
        remove(id: string): void;
    };

    notes: {
        list(): Promise<Array<{ id: string; title: string; folder: string }>>;
        open(id: string): Promise<void>;
    };

    contacts: {
        list(): Promise<Array<{
            id: string;
            name: string;
            first: string;
            last: string;
            organization: string;
            emails: string[];
            phones: string[];
        }>>;
        search(query: string): Promise<Array<{
            id: string;
            name: string;
            first: string;
            last: string;
            organization: string;
            emails: string[];
            phones: string[];
        }>>;
    };

    app: {
        list(): Array<{ name: string; bundleID: string; pid: number }>;
        launch(bundleID: string): void;
        switch(bundleID: string): void;
        frontmost(): { name: string; bundleID: string; pid: number } | null;
        hide(bundleID?: string): boolean;
        quit(bundleID?: string): boolean;
        /** AX menu path, e.g. `["File", "New Window"]`. Omit bundle id for the frontmost app. */
        menu(path: string[], bundleID?: string): boolean;
    };

    audio: {
        devices(): Array<{ id: number; name: string; uid: string; input: boolean; output: boolean }>;
        input(): { id: number; name: string; uid: string; input: boolean; output: boolean } | null;
        output(): { id: number; name: string; uid: string; input: boolean; output: boolean } | null;
        setInput(idOrName: number | string): boolean;
        setOutput(idOrName: number | string): boolean;
        volume(id?: number | string): number | null;
        setVolume(level: number, id?: number | string): boolean;
        isMuted(id?: number | string): boolean;
        setMuted(on: boolean, id?: number | string): boolean;
        record(opts: { path: string }): boolean;
        stopRecord(): { path: string; seconds: number } | null;
        isRecording(): boolean;
    };

    spaces: {
        list(): Array<{
            id: number;
            index: number;
            desktop: number;
            display: string;
            current: boolean;
            type: string;
        }>;
        current(): { id: number; index: number; desktop: number; display: string; current: boolean; type: string } | null;
        go(spec: number | { id?: number; index?: number; display?: string }): boolean;
        moveWindow(windowID: number, spec: number | { id?: number; index?: number; display?: string }): boolean;
    };

    usb: {
        list(): Array<{ name: string; vendor: string; vendorID: number; productID: number }>;
    };

    hid: {
        list(filter?: HIDFilter | string): HIDDeviceInfo[];
        open(filter?: HIDFilter | string): (HIDDeviceInfo & { id: string }) | null;
        close(id: string): void;
        sendOutput(id: string, data: number[] | string, opts?: { length?: number }): { ok: boolean; written?: number; error?: string };
        sendFeature(id: string, data: number[] | string, opts?: { length?: number }): { ok: boolean; written?: number; error?: string };
        /**
         * Wait for the next input report on the interrupt pipe, the way
         * `hid_read` does — what a device answers a query with. Reports queue
         * from the moment `open` returns, so a reply that beats this call is
         * not lost. Resolves `null` if nothing arrives before `timeout`
         * (default 1000 ms). While `listen` is on, reports arrive as
         * `hid:input` events instead.
         */
        readInput(
            id: string,
            opts?: { timeout?: number }
        ): Promise<{ id: string; reportId: number; data: number[] } | null>;
        /** Control GetReport for an input report. Most devices never answer it. */
        readInputReport(id: string, opts?: { reportId?: number; length?: number }): number[] | null;
        readFeature(id: string, reportId: number, opts?: { length?: number }): number[] | null;
        listen(id: string): { ok: boolean; error?: string };
        unlisten(id: string): void;
        reportDescriptor(id: string): number[] | null;
    };

    shortcuts: {
        list(): Promise<string[]>;
        run(name: string): Promise<boolean>;
    };

    calendar: {
        /** `calendars` narrows the fetch to calendars with those titles; omit
         *  it (or pass an empty array) to search every calendar. */
        upcoming(opts?: { hours?: number; calendars?: string[] }): Promise<Array<{
            id: string;
            title: string;
            start: number;
            end: number;
            allDay: boolean;
            location: string;
            calendar: string;
            /** Join link from the URL field, location, or notes; `""` if there is none. */
            url: string;
        }>>;
    };

    reminders: {
        list(opts?: { days?: number; completed?: boolean }): Promise<Array<{
            id: string;
            title: string;
            due: number | null;
            completed: boolean;
            list: string;
        }>>;
        add(row: { title: string; due?: number; list?: string }): { ok: boolean; id?: string; error?: string };
        complete(id: string, on?: boolean): { ok: boolean; error?: string };
    };

    homekit: {
        available(): boolean;
        homes(): Array<{ id: string; name: string }>;
        accessories(homeId?: string): Array<{
            id: string;
            name: string;
            room: string;
            type: string;
            on?: boolean;
            value?: number;
            reachable: boolean;
        }>;
        set(id: string, state: { on?: boolean; value?: number }): { ok: boolean; error?: string };
    };

    dock: {
        badges(): Array<{ app: string; bundleID?: string; badge: string }>;
    };

    ax: {
        focused(): { id: number; role: string; title: string; value: string; frame: { x: number; y: number; width: number; height: number } } | null;
        selectedText(): Promise<string | null>;
        children(id: number): Array<{ id: number; role: string; title: string; value: string; frame: { x: number; y: number; width: number; height: number } }>;
        parent(id: number): { id: number; role: string; title: string; value: string; frame: { x: number; y: number; width: number; height: number } } | null;
        press(id: number): boolean;
        setValue(id: number, value: string): boolean;
        find(opts: { role?: string; title?: string }): { id: number; role: string; title: string; value: string; frame: { x: number; y: number; width: number; height: number } } | null;
    };

    camera: {
        list(): Array<{ id: string; name: string }>;
        preview(opts?: { id?: string; width?: number; height?: number }): boolean;
        stopPreview(): void;
        snapshot(): string | null;
    };

    share: {
        open(opts: { files?: string[]; text?: string; url?: string }): boolean;
        airDrop(paths: string[]): boolean;
    };

    ocr: {
        recognize(opts: { path?: string; image?: string }): Promise<string>;
    };

    qr: {
        /** First QR payload in an image, or `null`. */
        detect(opts: { path?: string; image?: string }): Promise<string | null>;
        /** Interactive scan. Camera preview, or a screenshot (selection by default). */
        scan(opts?: { camera?: boolean; screenshot?: boolean; selection?: boolean }): Promise<string | null>;
        /** PNG (base64) of a QR code. */
        image(text: string, opts?: { size?: number }): string | null;
        /** Show a QR code in a floating window. */
        show(text: string, opts?: { size?: number }): void;
    };

    system: {
        /** `performance` / `efficiency` are per-cluster busy percentages; Intel Macs report every core as performance. */
        cpu(): {
            usage: number;
            performance: number;
            efficiency: number;
            performanceCores: number;
            efficiencyCores: number;
        };
        locale(): { language: string; region: string; measurement: "metric" | "us"; hour12: boolean };
        /**
         * The time now in an IANA zone, e.g. `timeIn("Europe/London")` -> "18:42".
         * There is no Intl in this runtime, so this is the way to format another
         * zone. `format` is a DateFormatter pattern and defaults to "HH:mm".
         * Returns "" for a zone macOS does not know.
         */
        timeIn(zone: string, format?: string): string;
        memory(): {
            total: number;
            used: number;
            free: number;
            active: number;
            inactive: number;
            wired: number;
            compressed: number;
        };
        battery(): {
            level: number;
            charging: boolean;
            charged: boolean;
            /** Minutes until empty, or -1 if unknown. */
            timeRemaining: number;
            /** Minutes until full, or -1 if unknown. */
            timeToFull: number;
            /** `"ac"` or `"battery"`. */
            source: "ac" | "battery";
            /** Maximum capacity as a percent of design, when known. */
            health?: number;
            /** Charge cycle count, when known. */
            cycles?: number;
            /** Adapter wattage when on AC, when known. */
            watts?: number;
            lowPowerMode: boolean;
        };
        /** Needs an admin password. `pmset` Low Power Mode for battery and adapter. */
        setLowPowerMode(enabled: boolean): Promise<{
            ok: boolean;
            lowPowerMode: boolean;
            error?: string;
        }>;
        /** System appearance, not Macotron's own Settings theme. */
        darkMode(): boolean;
        setDarkMode(on: boolean): Promise<{ ok: boolean; darkMode: boolean; error?: string }>;
        /** Whether a Focus mode (Do Not Disturb, Sleep, Work, …) is on. */
        focus(): { focused: boolean };
        disk(): { total: number; free: number; used: number };
        network(): { bytesIn: number; bytesOut: number };
        processes(limit?: number): Promise<Array<{ name: string; pid: number; cpu: number }>>;
        gpu(): { name: string; usage: number } | null;
        /**
         * Fan floor. `available` means this Mac has fans, so RPM can be read;
         * `controllable` means a floor can be set right now, which needs the
         * background helper (install it from this plugin's Settings page with the
         * `helper` permission). `floor` is 50 or 100 while Macotron is holding a minimum;
         * omitted means system default. Actual RPM is never forced below what
         * macOS already wants.
         */
        fans(): {
            available: boolean;
            controllable: boolean;
            floor?: number;
            error?: string;
            fans: Array<{ index: number; rpm: number; min: number; max: number }>;
        };
        /** `null` restores system default. Built-in fan plugin left-click uses 100. Resolves with `error` when not `controllable`. */
        setFanFloor(percent: number | null): Promise<{
            available: boolean;
            controllable: boolean;
            floor?: number;
            error?: string;
            fans: Array<{ index: number; rpm: number; min: number; max: number }>;
        }>;
    };

    /**
     * A request that fails resolves with `status: 0` and the reason in `body`
     * rather than rejecting, so one status check covers a 500 and a dead
     * network alike.
     *
     * `timeout` is milliseconds and defaults to 30000. It is enforced by
     * URLSession, so a request that runs out of time is actually cancelled --
     * racing the promise against setTimeout in the plugin would leave the
     * request and its socket running.
     *
     * `headers` carries the common ones: Content-Type, Authorization, Accept,
     * User-Agent, X-API-Key, X-Request-ID. Others are dropped.
     */
    http: {
        get(url: string, opts?: HTTPOptions): Promise<HTTPResponse>;
        post(url: string, body: any, opts?: HTTPOptions): Promise<HTTPResponse>;
        put(url: string, body: any, opts?: HTTPOptions): Promise<HTTPResponse>;
        delete(url: string, opts?: HTTPOptions): Promise<HTTPResponse>;
    };

    menubar: {
        add(id: string, opts: { title: string; icon?: string; shortcut?: string; onClick?: () => void; section?: string; refresh?: number; menu?: MenuBarMenuItem[] }): void;
        update(id: string, opts: { title?: string; icon?: string }): void;
        remove(id: string): void;
        setIcon(sfSymbolName: string): void;
        /** Tint the Macotron menu bar glyph. Pass `null` to restore the system color. */
        setIconColor(color?: string | null): void;
        setTitle(text: string): void;
        /** Extra status item next to the Macotron icon. */
        status(
            id: string,
            opts: {
                title: string;
                subtitle?: string;
                color?: string;
                subtitleColor?: string;
                bold?: boolean;
                italic?: boolean;
                /** Smaller, dimmer subtitle. Default is the same size and color as title. */
                secondary?: boolean;
                /** Minimum extra width in points. Stops proportional digits from shifting neighbors. */
                minWidth?: number;
                sfSymbol?: string;
                icon?: string;
                image?: string;
                /**
                 * Warn in Settings, with a Restore button, when the user
                 * command-drags this item out of the menu bar. Default true.
                 * Pass `false` for an item that is fine to hide.
                 */
                required?: boolean;
                sparkline?: { values: number[]; width?: number; height?: number; color?: string };
                svg?: string;
                /**
                 * Treat `svg` as a mask the menu bar tints for its own
                 * background, so the icon stays legible whatever the bar
                 * looks like. Off by default, which keeps the SVG's own
                 * colors -- use that only for an icon that is meant to be
                 * colorful, since the bar's background is not predictable.
                 */
                template?: boolean;
                onClick?: () => void;
                /** Left-click runs `onClick` when set; right/ctrl-click opens this menu. */
                menu?: MenuBarMenuItem[];
            }
        ): void;
    };

    display: {
        list(): Array<{
            id: number;
            width: number;
            height: number;
            main: boolean;
            frame: { x: number; y: number; width: number; height: number };
            visibleFrame: { x: number; y: number; width: number; height: number };
            scale: number;
            rotation: number;
            builtin: boolean;
            mirrored: boolean;
            serial: number;
            mm: { width: number; height: number };
        }>;
        getBrightness(id?: number): number;
        setBrightness(level: number, id?: number): boolean;
        /**
         * Per-channel gamma LUT. `white` / `black` are `{ red, green, blue }` in 0…1.
         * Omit `id` to apply to every display. Red-only: `setGamma({ red: 1, green: 0, blue: 0 })`.
         */
        setGamma(
            white: { red?: number; green?: number; blue?: number },
            black?: { red?: number; green?: number; blue?: number } | number,
            id?: number
        ): boolean;
        getGamma(id?: number): {
            white: { red: number; green: number; blue: number };
            black: { red: number; green: number; blue: number };
        };
        restoreGamma(): boolean;
        setXDREnabled(enabled: boolean): boolean;
        isXDREnabled(): boolean;
        /**
         * Draws a CRT mask (scanlines, phosphor grille, vignette, rolling bar) over
         * every screen. It composites on top of the desktop, so it darkens and tints
         * but cannot warp the pixels underneath. Returns false when Metal is
         * unavailable. Covers the screens present when it is switched on.
         */
        setCRTEnabled(enabled: boolean): boolean;
        isCRTEnabled(): boolean;
        nightShift(): { on: boolean; strength?: number; available: boolean };
        setNightShift(on: boolean | { strength?: number }): { ok: boolean; on: boolean; strength?: number; available: boolean; error?: string };
        trueTone(): { on: boolean; available: boolean };
        setTrueTone(on: boolean): { ok: boolean; on: boolean; available: boolean; error?: string };
        grayscale(): { on: boolean; available: boolean };
        setGrayscale(on: boolean): { ok: boolean; on: boolean; available: boolean; error?: string };
    };

    keychain: {
        get(key: string): string | null;
        set(key: string, value: string): void;
        delete(key: string): void;
        has(key: string): boolean;
    };

    panel: {
        /** `html` is body markup in a host document (fonts, padding, light/dark). `rawHtml` is a full document. `url` loads a web page first-party, so its localStorage persists. `glass` is Liquid Glass (`true`/`"regular"` or `"clear"`) or `"translucent"` for a HUD blur. `frameless` hides the title bar. `closeOnBlur` closes when the panel loses key focus. */
        open(opts: {
            title?: string;
            width?: number;
            height?: number;
            html?: string;
            rawHtml?: string;
            /** http(s) page to load instead of html/rawHtml. First-party, so site storage persists. */
            url?: string;
            glass?: boolean | "regular" | "clear" | "translucent";
            /** No title bar. Escape closes. */
            frameless?: boolean;
            closeOnBlur?: boolean;
            /** Escape closes a frameless or fullscreen panel unless this is false. */
            escapeCloses?: boolean;
            /** Reuse this id. Closes an existing panel with the same id. */
            id?: string;
            /** Stretch to the edges of the screen under the cursor. */
            fullscreen?: boolean;
            /** QR payload. Host appends a PNG of the code. */
            qr?: string;
        }): string;
        close(id: string): void;
        /** Brings an open panel forward without reloading it. False if no panel has that id. */
        focus(id: string): boolean;
        postMessage(id: string, data: any): void;
        onMessage(id: string, callback: (data: any) => void): void;
    };

    config(options: Record<string, any>): void;

    /**
     * Declare plugin metadata, permissions, and configurable options.
     * Returns resolved options (user overrides from Settings, else defaults).
     *
     * Option types:
     * - "string"      — text field. Plugin sees the string value.
     * - "text"        — multi-line text area, for values with one entry per line.
     * - "boolean"     — checkbox. Plugin sees true/false.
     * - "number"      — number field. Plugin sees a number.
     * - "keybinding"  — hotkey recorder. Plugin sees a combo like "cmd+shift+c".
     * - "dropdown"    — popup menu. Requires `choices`. Plugin sees the choice value.
     * - "password"    — secure field. The secret lives in the Keychain;
     *                   settings.json stores only a Keychain ref. The plugin
     *                   receives the resolved secret string ("" when unset) —
     *                   never the ref. `default` is ignored; passwords start unset.
     * - "file"        — absolute path chosen via NSOpenPanel (files).
     * - "directory"   — absolute path chosen via NSOpenPanel (directories).
     * - "calendars"   — checkbox list of the user's calendars (Settings fills
     *                   in the choices). Plugin sees an array of calendar
     *                   titles; an empty array means every calendar.
     *
     * Every option takes `label` (shown in Settings), optional `default`,
     * and optional `required` (Settings shows a "Needs setup" hint while unset;
     * commands are not blocked).
     *
     * Users configure values in Macotron Settings → Plugins. Never write real
     * secrets into settings.json or plugin source.
     *
     * @example
     * const opts = macotron.plugin({
     *     title: "Chat",
     *     description: "Talk to a model",
     *     permissions: ["accessibility"],
     *     options: {
     *         model:      { type: "dropdown",   label: "Model", default: "sonnet",
     *                       choices: [
     *                           { value: "sonnet", label: "Claude Sonnet" },
     *                           { value: "opus",   label: "Claude Opus" },
     *                       ] },
     *         apiKey:     { type: "password",   label: "Anthropic API key", required: true },
     *         openHotkey: { type: "keybinding", label: "Open chat", default: "cmd+shift+c" },
     *         notesFile:  { type: "file",       label: "Notes file" },
     *         workspace:  { type: "directory",  label: "Workspace folder" },
     *     }
     * });
     * // opts.apiKey === resolved secret string (or "")
     */
    plugin(metadata: {
        title?: string;
        description?: string;
        /** Extra explanation shown in Settings → Plugins. */
        help?: string;
        /** `helper` lists the background helper on this plugin's Settings page. */
        permissions?: Array<"accessibility" | "inputMonitoring" | "screenRecording" | "camera" | "microphone" | "helper">;
        options?: Record<string, MacotronPluginOption>;
    }): Record<string, any>;
    /** @deprecated Use plugin() */
    module(metadata: {
        title?: string;
        description?: string;
        help?: string;
        permissions?: Array<"accessibility" | "inputMonitoring" | "screenRecording" | "camera" | "microphone">;
        options?: Record<string, MacotronPluginOption>;
    }): Record<string, any>;
    /** @deprecated Pass `permissions` to plugin() */
    requirePermissions(list: Array<"accessibility" | "inputMonitoring" | "screenRecording" | "camera" | "microphone">): void;
};

/**
 * `placeholder` is the grey hint shown in an empty field. It is read when the
 * plugin loads, so it can describe live state — e.g. `macotron.system.locale().language`.
 *
 * `help` is a sentence shown under the field. Put the explanation there and
 * keep `label` to a few words, rather than writing a sentence as the label.
 */
type MacotronPluginOption =
    | { type: "string"; label: string; default?: string; required?: boolean; placeholder?: string; help?: string }
    | { type: "text"; label: string; default?: string; required?: boolean; placeholder?: string; help?: string }
    | { type: "boolean"; label: string; default?: boolean; required?: boolean; help?: string }
    | { type: "number"; label: string; default?: number; required?: boolean; placeholder?: string; help?: string }
    | { type: "keybinding"; label: string; default?: string; required?: boolean; help?: string }
    | { type: "dropdown"; label: string; default?: string; required?: boolean; choices: Array<{ value: string; label: string }>; help?: string }
    | { type: "password"; label: string; required?: boolean; placeholder?: string; help?: string }
    | { type: "file"; label: string; default?: string; required?: boolean; placeholder?: string; help?: string }
    | { type: "directory"; label: string; default?: string; required?: boolean; placeholder?: string; help?: string }
    | { type: "calendars"; label: string; default?: string[]; required?: boolean; help?: string };

interface HTTPOptions {
    headers?: Record<string, string>;
    /** Milliseconds. Default 30000. */
    timeout?: number;
}

interface HTTPResponse {
    /** 0 when the request never completed; `body` is then the reason. */
    status: number;
    body: string;
    headers: Record<string, string>;
}

interface AIChatMessage {
    role: "user" | "assistant";
    content: string;
}

interface AIClient {
    chat(
        promptOrMessages: string | AIChatMessage[],
        opts?: { system?: string; model?: string; maxTokens?: number; temperature?: number }
    ): Promise<string>;
    stream(
        promptOrMessages: string | AIChatMessage[],
        opts?: {
            system?: string;
            model?: string;
            maxTokens?: number;
            temperature?: number;
            onChunk?: (chunk: string) => void;
        }
    ): Promise<string>;
}

declare const console: {
    log(...args: any[]): void;
    warn(...args: any[]): void;
    error(...args: any[]): void;
    info(...args: any[]): void;
};

declare function setTimeout(callback: () => void, ms?: number): number;
declare function setInterval(callback: () => void, ms: number): number;
declare function clearTimeout(id: number): void;
declare function clearInterval(id: number): void;

declare const localStorage: {
    getItem(key: string): string | null;
    setItem(key: string, value: string): void;
    removeItem(key: string): void;
    clear(): void;
    readonly length: number;
    key(index: number): string | null;
};
