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

#endif
