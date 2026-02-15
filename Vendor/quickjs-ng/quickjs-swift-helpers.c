// quickjs-swift-helpers.c — C functions for macros/variadics Swift can't import
#include "include/quickjs.h"

JSValue QJS_Undefined(void) { return JS_UNDEFINED; }
JSValue QJS_Null(void) { return JS_NULL; }
JSValue QJS_True(void) { return JS_TRUE; }
JSValue QJS_False(void) { return JS_FALSE; }
JSValue QJS_Exception(void) { return JS_EXCEPTION; }

JSValue QJS_NewBool(JSContext *ctx, int val) {
    return JS_NewBool(ctx, val);
}

// Variadic C functions can't be called from Swift.
// These wrappers take a plain string message instead.
JSValue QJS_ThrowTypeError(JSContext *ctx, const char *msg) {
    return JS_ThrowTypeError(ctx, "%s", msg);
}

JSValue QJS_ThrowInternalError(JSContext *ctx, const char *msg) {
    return JS_ThrowInternalError(ctx, "%s", msg);
}
