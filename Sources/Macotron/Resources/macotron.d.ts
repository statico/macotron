// Type definitions for Macotron JS API
// These are provided to AI models for code generation

interface MenuBarMenuItem {
    title: string;
    icon?: string;
    onClick?: () => void;
    menu?: MenuBarMenuItem[];
}

declare const macotron: {
    version: {
        app: string;
        api: string;
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
    log(...args: any[]): void;
    sleep(ms: number): Promise<void>;
    every(ms: number, callback: () => void | Promise<void>): () => void;

    window: {
        getAll(): Array<{
            id: number;
            title: string;
            app: string;
            display?: number;
            frame: { x: number; y: number; width: number; height: number };
        }>;
        focused(): {
            id: number;
            title: string;
            app: string;
            display?: number;
            frame: { x: number; y: number; width: number; height: number };
        } | null;
        /** Raise, unminimize, and activate the window's app. */
        focus(id: number): boolean;
        move(id: number, frame: { x?: number; y?: number; width?: number; height?: number }): boolean;
        /** Fractions of the window's current display. Pass `display` from `macotron.display.list()` to send it to another screen. */
        moveToFraction(id: number, frac: { x?: number; y?: number; w?: number; h?: number; display?: number }): boolean;
        setSnapEnabled(enabled: boolean): boolean;
        isSnapEnabled(): boolean;
        /** Drag-to-edge tiling. Zones are fractions of the visible frame (same as moveToFraction). Omit a slot to disable it. */
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
        }): boolean;
    };

    keyboard: {
        on(id: string, defaultCombo: string, callback: () => void): void;
        /** Current modifier state from the HID system. */
        flags(): { cmd: boolean; shift: boolean; ctrl: boolean; opt: boolean; caps: boolean; fn: boolean };
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
        capture(opts?: { windowID?: number; selection?: boolean }): Promise<string> | string;
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
                color?: "success" | "failure" | "warning" | string;
            }
        ): void;
    };

    url: {
        on(scheme: string, host: string, callback: (event: { url: string; scheme: string; host: string; path: string }) => void): void;
        open(url: string, bundleID?: string, profile?: string): boolean;
        registerHandler(scheme: string): void;
    };

    fs: {
        read(path: string): string;
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
    };

    network: {
        wifiSSID(): string | null;
        interfaces(): Array<{ name: string; ip: string }>;
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
        search(query: string): Promise<Array<{ path: string; name: string; kind: string }>>;
    };

    launcher: {
        set(
            id: string,
            items: Array<{
                id: string;
                title: string;
                subtitle?: string;
                /** Bundle ID, e.g. `com.apple.Notes`. */
                app?: string;
                sfSymbol?: string;
                kind?: string;
                onClick?: () => void;
            }>
        ): void;
        remove(id: string): void;
    };

    notes: {
        list(): Array<{ id: string; title: string; folder: string }>;
        open(id: string): void;
    };

    app: {
        list(): Array<{ name: string; bundleID: string; pid: number }>;
        launch(bundleID: string): void;
        switch(bundleID: string): void;
        frontmost(): { name: string; bundleID: string; pid: number } | null;
    };

    calendar: {
        upcoming(opts?: { hours?: number }): Array<{ id: string; title: string; start: number; end: number }>;
    };

    ocr: {
        recognize(opts: { path?: string; image?: string }): Promise<string>;
    };

    system: {
        cpuTemp(): Promise<number>;
        cpu(): { usage: number };
        locale(): { language: string; region: string; measurement: "metric" | "us" };
        memory(): { total: number; used: number; free: number };
        battery(): { level: number; charging: boolean };
        disk(): { total: number; free: number; used: number };
        network(): { bytesIn: number; bytesOut: number };
        processes(limit?: number): Array<{ name: string; pid: number; cpu: number }>;
        gpu(): { name: string; usage: number } | null;
        /**
         * Fan floor. `floor` is 50 or 100 while Macotron is holding a minimum;
         * omitted means system default. Actual RPM is never forced below what
         * macOS already wants.
         */
        fans(): {
            available: boolean;
            floor?: number;
            error?: string;
            fans: Array<{ index: number; rpm: number; min: number; max: number }>;
        };
        /** `null` restores system default. Left-click demo uses 100. */
        setFanFloor(percent: number | null): {
            available: boolean;
            floor?: number;
            error?: string;
            fans: Array<{ index: number; rpm: number; min: number; max: number }>;
        };
    };

    http: {
        get(url: string, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        post(url: string, body: any, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        put(url: string, body: any, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        delete(url: string, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
    };

    menubar: {
        add(id: string, opts: { title: string; icon?: string; shortcut?: string; onClick?: () => void; section?: string; refresh?: number; menu?: MenuBarMenuItem[] }): void;
        update(id: string, opts: { title?: string; icon?: string }): void;
        remove(id: string): void;
        setIcon(sfSymbolName: string): void;
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
    };

    keychain: {
        get(key: string): string | null;
        set(key: string, value: string): void;
        delete(key: string): void;
        has(key: string): boolean;
    };

    panel: {
        /** `html` is body markup in a host document (fonts, padding, light/dark). `rawHtml` is a full document. `glass` is Liquid Glass: `true`/`"regular"` (translucent) or `"clear"`. */
        open(opts: {
            title?: string;
            width?: number;
            height?: number;
            html?: string;
            rawHtml?: string;
            glass?: boolean | "regular" | "clear";
        }): string;
        close(id: string): void;
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
        permissions?: Array<"accessibility" | "inputMonitoring" | "screenRecording">;
        options?: Record<string, MacotronModuleOption>;
    }): Record<string, any>;
    /** @deprecated Use plugin() */
    module(metadata: {
        title?: string;
        description?: string;
        permissions?: Array<"accessibility" | "inputMonitoring" | "screenRecording">;
        options?: Record<string, MacotronModuleOption>;
    }): Record<string, any>;
    /** @deprecated Pass `permissions` to plugin() */
    requirePermissions(list: Array<"accessibility" | "inputMonitoring" | "screenRecording">): void;
};

type MacotronModuleOption =
    | { type: "string"; label: string; default?: string; required?: boolean }
    | { type: "boolean"; label: string; default?: boolean; required?: boolean }
    | { type: "number"; label: string; default?: number; required?: boolean }
    | { type: "keybinding"; label: string; default?: string; required?: boolean }
    | { type: "dropdown"; label: string; default?: string; required?: boolean; choices: Array<{ value: string; label: string }> }
    | { type: "password"; label: string; required?: boolean }
    | { type: "file"; label: string; default?: string; required?: boolean }
    | { type: "directory"; label: string; default?: string; required?: boolean };

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
