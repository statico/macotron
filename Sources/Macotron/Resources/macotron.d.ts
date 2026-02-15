// Type definitions for Macotron JS API
// These are provided to AI models for code generation

declare const macotron: {
    version: {
        app: string;
        modules: Record<string, number>;
    };

    on(event: string, callback: (...args: any[]) => void): void;
    off(event: string, callback: (...args: any[]) => void): void;
    command(name: string, description: string, handler: () => void | Promise<void>): void;
    log(...args: any[]): void;
    sleep(ms: number): Promise<void>;
    every(ms: number, callback: () => void | Promise<void>): () => void;

    window: {
        getAll(): Array<{ id: number; title: string; app: string; frame: { x: number; y: number; width: number; height: number } }>;
        focused(): { id: number; title: string; app: string; frame: { x: number; y: number; width: number; height: number } } | null;
        move(id: number, frame: { x?: number; y?: number; width?: number; height?: number }): boolean;
        moveToFraction(id: number, frac: { x?: number; y?: number; w?: number; h?: number }): boolean;
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

    camera: {
        isActive(): boolean;
    };

    url: {
        on(scheme: string, host: string, callback: (event: { url: string; scheme: string; host: string; path: string }) => void): void;
        open(url: string, bundleID?: string): void;
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
    };

    system: {
        cpuTemp(): Promise<number>;
        memory(): { total: number; used: number; free: number };
        battery(): { level: number; charging: boolean };
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
    };

    keychain: {
        get(key: string): string | null;
        set(key: string, value: string): void;
        delete(key: string): void;
        has(key: string): boolean;
    };

    config(options: Record<string, any>): void;
};

interface AIClient {
    chat(prompt: string, opts?: { image?: string; system?: string }): Promise<string>;
    stream(prompt: string, opts?: { image?: string; system?: string; onChunk?: (chunk: string) => void }): Promise<string>;
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
