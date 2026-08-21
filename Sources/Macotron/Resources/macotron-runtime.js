// macotron-runtime.js
// Loaded into JSContext before any user snippets.
// The native macotron object already exists with host APIs.
// This file adds convenience helpers on top.

// --- Config ---

macotron.config = function(options) {
    $$__config(options);
};

// --- Plugin metadata ---

macotron.plugin = function(metadata) {
    return $$__module(metadata);
};
macotron.module = macotron.plugin;

// --- Permissions (also accepted as plugin({ permissions })) ---

macotron.requirePermissions = function(list) {
    $$__requirePermissions(list);
};

// --- Convenience helpers ---

macotron.on = function(event, callback) {
    $$__on(event, callback);
};

macotron.off = function(event, callback) {
    $$__off(event, callback);
};

macotron.command = function(name, description, handler, opts) {
    $$__registerCommand(name, description, handler, opts || {});
};

macotron.checks = function(rows) {
    $$__checks(Array.isArray(rows) ? rows : []);
};

macotron.settings = {
    open: function() { $$__openSettings(); },
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

// --- console shim ---

var console = {
    log: function()   { macotron.log.apply(null, arguments); },
    warn: function()  { macotron.log.apply(null, ['[WARN]'].concat(Array.prototype.slice.call(arguments))); },
    error: function() { macotron.log.apply(null, ['[ERROR]'].concat(Array.prototype.slice.call(arguments))); },
    info: function()  { macotron.log.apply(null, ['[INFO]'].concat(Array.prototype.slice.call(arguments))); },
};
