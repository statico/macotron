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

// Compile JS source as an ES module, returning the JSModuleDef* pointer.
// Swift can't access JS_VALUE_GET_PTR (it's a macro accessing a union member).
JSModuleDef *QJS_CompileModule(JSContext *ctx, const char *source, size_t source_len, const char *module_name) {
    JSValue func_val = JS_Eval(ctx, source, source_len, module_name,
                               JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(func_val)) {
        return NULL;
    }
    JSModuleDef *m = JS_VALUE_GET_PTR(func_val);
    JS_FreeValue(ctx, func_val);
    return m;
}

// Decide whether source must run as an ES module.
//
// JS_DetectModule assumes "module" and only says "script" when the source fails
// to parse as a module, so it calls every plain script a module. Modules
// evaluate to a promise and defer errors into a rejection, which loses both the
// result and the error. Ask the opposite question instead: import and export
// only parse in module scope, so anything the script parser accepts is a script.
static int qjs_is_module(JSContext *ctx, const char *source, size_t source_len,
                         const char *filename) {
    JSValue probe = JS_Eval(ctx, source, source_len, filename,
                            JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
    int is_module = JS_IsException(probe);
    if (is_module) {
        // Drop the parse error so it cannot leak into the real evaluation.
        JS_FreeValue(ctx, JS_GetException(ctx));
    }
    JS_FreeValue(ctx, probe);
    return is_module;
}

// Evaluate a JS file, auto-detecting whether it's a module (import/export).
// Returns the eval result as a JSValue.
JSValue QJS_EvalAutoDetect(JSContext *ctx, const char *source, size_t source_len, const char *filename) {
    int eval_type = JS_EVAL_TYPE_GLOBAL;
    if (qjs_is_module(ctx, source, source_len, filename)) {
        eval_type = JS_EVAL_TYPE_MODULE;
    }
    return JS_Eval(ctx, source, source_len, filename, eval_type);
}

// Compile JS to bytecode. Caller must free the returned buffer with js_free(ctx, buf).
uint8_t *QJS_CompileToBytecode(JSContext *ctx, const char *source, size_t source_len,
                                const char *filename, size_t *out_len) {
    int eval_type = JS_EVAL_TYPE_GLOBAL;
    if (qjs_is_module(ctx, source, source_len, filename)) {
        eval_type = JS_EVAL_TYPE_MODULE;
    }
    JSValue obj = JS_Eval(ctx, source, source_len, filename,
                          eval_type | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(obj)) {
        *out_len = 0;
        return NULL;
    }
    int flags = JS_WRITE_OBJ_BYTECODE | JS_WRITE_OBJ_STRIP_SOURCE;
    uint8_t *buf = JS_WriteObject(ctx, out_len, obj, flags);
    JS_FreeValue(ctx, obj);
    return buf;
}

// Load and execute bytecode.
JSValue QJS_EvalBytecode(JSContext *ctx, const uint8_t *buf, size_t buf_len) {
    JSValue obj = JS_ReadObject(ctx, buf, buf_len, JS_READ_OBJ_BYTECODE);
    if (JS_IsException(obj)) {
        return JS_EXCEPTION;
    }
    if (JS_VALUE_GET_TAG(obj) == JS_TAG_MODULE) {
        if (JS_ResolveModule(ctx, obj) < 0) {
            JS_FreeValue(ctx, obj);
            return JS_EXCEPTION;
        }
    }
    return JS_EvalFunction(ctx, obj);
}
