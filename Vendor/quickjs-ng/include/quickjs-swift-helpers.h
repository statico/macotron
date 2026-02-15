// quickjs-swift-helpers.h — Swift-friendly wrappers for QuickJS macros
#ifndef QUICKJS_SWIFT_HELPERS_H
#define QUICKJS_SWIFT_HELPERS_H

#include "quickjs.h"

// Swift can't import C macros that use compound literals/tagged unions.
// These functions provide the same values as proper C functions.
JS_EXTERN JSValue QJS_Undefined(void);
JS_EXTERN JSValue QJS_Null(void);
JS_EXTERN JSValue QJS_True(void);
JS_EXTERN JSValue QJS_False(void);
JS_EXTERN JSValue QJS_Exception(void);
JS_EXTERN JSValue QJS_NewBool(JSContext *ctx, int val);

// Variadic function wrappers (Swift can't call C variadic functions)
JS_EXTERN JSValue QJS_ThrowTypeError(JSContext *ctx, const char *msg);
JS_EXTERN JSValue QJS_ThrowInternalError(JSContext *ctx, const char *msg);

// ES module support — compile source as a module, returning JSModuleDef*
JS_EXTERN JSModuleDef *QJS_CompileModule(JSContext *ctx, const char *source, size_t source_len, const char *module_name);

// Auto-detect module vs script and evaluate
JS_EXTERN JSValue QJS_EvalAutoDetect(JSContext *ctx, const char *source, size_t source_len, const char *filename);

// Bytecode compilation — compile to bytecode, returning malloc'd buffer
JS_EXTERN uint8_t *QJS_CompileToBytecode(JSContext *ctx, const char *source, size_t source_len,
                                          const char *filename, size_t *out_len);

// Bytecode execution — load and execute bytecode
JS_EXTERN JSValue QJS_EvalBytecode(JSContext *ctx, const uint8_t *buf, size_t buf_len);

#endif
