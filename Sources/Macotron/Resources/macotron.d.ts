// Type definitions for Macotron JS API
// These are provided to AI models for code generation

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
        getAll(): Array<{ id: number; title: string; app: string; frame: { x: number; y: number; width: number; height: number } }>;
        focused(): { id: number; title: string; app: string; frame: { x: number; y: number; width: number; height: number } } | null;
        move(id: number, frame: { x?: number; y?: number; width?: number; height?: number }): boolean;
        moveToFraction(id: number, frac: { x?: number; y?: number; w?: number; h?: number }): boolean;
        setSnapEnabled(enabled: boolean): boolean;
        isSnapEnabled(): boolean;
    };

    keyboard: {
        on(combo: string, callback: () => void): void;
    };

    screen: {
        capture(opts?: { windowID?: number }): Promise<string>;
    };

    shell: {
        run(command: string, args?: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }>;
    };

    notify: {
        show(title: string, body: string, opts?: { sound?: boolean }): void;
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

    ai: {
        claude(opts?: { model?: string; apiKey?: string }): AIClient;
        openai(opts?: { model?: string; apiKey?: string }): AIClient;
        gemini(opts?: { model?: string; apiKey?: string }): AIClient;
        local(): AIClient;
    };

    spotlight: {
        search(query: string): Promise<Array<{ path: string; name: string; kind: string }>>;
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
        memory(): { total: number; used: number; free: number };
        battery(): { level: number; charging: boolean };
        disk(): { total: number; free: number; used: number };
        network(): { bytesIn: number; bytesOut: number };
        processes(limit?: number): Array<{ name: string; pid: number; cpu: number }>;
        gpu(): { name: string } | null;
    };

    http: {
        get(url: string, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        post(url: string, body: any, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        put(url: string, body: any, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
        delete(url: string, opts?: { headers?: Record<string, string> }): Promise<{ status: number; body: string; headers: Record<string, string> }>;
    };

    menubar: {
        add(id: string, opts: { title: string; icon?: string; shortcut?: string; onClick?: () => void; section?: string; refresh?: number }): void;
        update(id: string, opts: { title?: string; icon?: string }): void;
        remove(id: string): void;
        setIcon(sfSymbolName: string): void;
        setTitle(text: string): void;
    };

    display: {
        list(): Array<{ id: number; width: number; height: number; main: boolean }>;
        getBrightness(id?: number): number;
        setBrightness(level: number, id?: number): boolean;
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
        open(opts: { title?: string; width?: number; height?: number; html: string }): string;
        close(id: string): void;
        postMessage(id: string, data: any): void;
        onMessage(id: string, callback: (data: any) => void): void;
    };

    /**
     * Declare the macOS permissions this plugin needs. Macotron shows a red
     * warning in the menu bar and Settings until the user grants them.
     */
    requirePermissions(list: Array<"accessibility" | "inputMonitoring" | "screenRecording">): void;

    config(options: Record<string, any>): void;

    /**
     * Declare module metadata and configurable options.
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
     * const opts = macotron.module({
     *     title: "Chat",
     *     description: "Talk to a model",
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
    module(metadata: {
        title?: string;
        description?: string;
        options?: Record<string, MacotronModuleOption>;
    }): Record<string, any>;
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
