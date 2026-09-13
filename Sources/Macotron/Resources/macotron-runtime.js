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

function $$__format(args) {
    return Array.prototype.slice.call(args).map(function(a) {
        return typeof a === 'object' ? JSON.stringify(a) : String(a);
    }).join(' ');
}

macotron.log = function() { $$__log($$__format(arguments)); };

macotron.sleep = function(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
};

// --- console shim ---

// Levels map onto the system log: error and warn are kept by default, plain
// logs are info and need `log show --info`.
var console = {
    log: function()   { $$__log($$__format(arguments)); },
    info: function()  { $$__log($$__format(arguments)); },
    warn: function()  { $$__log($$__format(arguments), 'warn'); },
    error: function() { $$__log($$__format(arguments), 'error'); },
    debug: function() { $$__log($$__format(arguments)); },
};
