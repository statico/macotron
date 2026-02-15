// macotron-runtime.js
// Loaded into JSContext before any user snippets.
// Native modules populate macotron.window, macotron.keyboard, etc.

const macotron = {
    // --- Version info (populated by native) ---
    version: {
        app: "1.0.0",
        modules: {}
    },

    // Unified event listener (backed by native $$__on)
    on(event, callback) {
        $$__on(event, callback);
    },

    off(event, callback) {
        $$__off(event, callback);
    },

    // Register a named command (appears in launcher + optionally menubar)
    command(name, description, handler) {
        $$__registerCommand(name, description, handler);
    },

    // Logging
    log(...args) {
        $$__log(args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' '));
    },

    // Sleep helper for async snippets
    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    },

    // Interval helper that returns a cancel function
    every(ms, callback) {
        const id = setInterval(callback, ms);
        return () => clearInterval(id);
    }
};

// console.log → macotron.log
const console = {
    log: (...args) => macotron.log(...args),
    warn: (...args) => macotron.log('[WARN]', ...args),
    error: (...args) => macotron.log('[ERROR]', ...args),
    info: (...args) => macotron.log('[INFO]', ...args),
};
