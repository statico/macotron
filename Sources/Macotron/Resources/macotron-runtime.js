// macotron-runtime.js
// Loaded into JSContext before any user snippets.
// The native macotron object already exists with module APIs.
// This file adds convenience helpers on top.

// --- Config ---

macotron.config = function(options) {
    $$__config(options);
};

// --- Module metadata ---

macotron.module = function(metadata) {
    return $$__module(metadata);
};

// --- Convenience helpers ---

macotron.on = function(event, callback) {
    $$__on(event, callback);
};

macotron.off = function(event, callback) {
    $$__off(event, callback);
};

macotron.command = function(name, description, handler) {
    $$__registerCommand(name, description, handler);
};

macotron.log = function() {
    var args = Array.prototype.slice.call(arguments);
    $$__log(args.map(function(a) {
        return typeof a === 'object' ? JSON.stringify(a) : String(a);
    }).join(' '));
};

macotron.sleep = function(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
};

macotron.every = function(ms, callback) {
    var id = setInterval(callback, ms);
    return function() { clearInterval(id); };
};

// --- console shim ---

var console = {
    log: function()   { macotron.log.apply(null, arguments); },
    warn: function()  { macotron.log.apply(null, ['[WARN]'].concat(Array.prototype.slice.call(arguments))); },
    error: function() { macotron.log.apply(null, ['[ERROR]'].concat(Array.prototype.slice.call(arguments))); },
    info: function()  { macotron.log.apply(null, ['[INFO]'].concat(Array.prototype.slice.call(arguments))); },
};
