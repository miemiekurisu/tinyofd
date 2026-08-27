/*
 * fp_magnify.m — Native magnification (pinch-to-zoom) handler.
 *
 * Compiled with clang separately, then linked into the FPC executable.
 * Uses Objective-C method swizzling to override -magnifyWithEvent: on a
 * target NSView so that LCL (which has no gesture support) can receive
 * pinch-to-zoom events.
 *
 * The Pascal side calls FPInstallMagnifyHandler() once after the view has
 * been created, passing the NSView handle and a callback pointer.
 *
 * Callback signature (Pascal cdecl):
 *   procedure(AContext: Pointer; AMagnification: Double;
 *     ALocationX, ALocationY: Double); cdecl;
 */

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

/* ---------- callback storage ---------- */

typedef void (*FPMagnifyCallback)(void *context,
                                   double magnification,
                                   double locationX,
                                   double locationY);

static FPMagnifyCallback gMagnifyCallback = NULL;
static const void *kFPMagnifyContextKey = &kFPMagnifyContextKey;
static const void *kFPMagnifySwizzledClassKey = &kFPMagnifySwizzledClassKey;

static void *FPMagnifyContextForView(NSView *view, NSView **contextViewOut) {
    NSView *cursor = view;
    while (cursor) {
        NSValue *ctxValue = objc_getAssociatedObject(cursor, kFPMagnifyContextKey);
        if (ctxValue) {
            void *context = [ctxValue pointerValue];
            if (context) {
                if (contextViewOut) *contextViewOut = cursor;
                return context;
            }
        }
        cursor = cursor.superview;
    }
    if (contextViewOut) *contextViewOut = nil;
    return NULL;
}

/* ---------- category on NSView ---------- */

@interface NSView (FPMagnify)
- (void)fp_magnifyWithEvent:(NSEvent *)event;
@end

@implementation NSView (FPMagnify)

- (void)fp_magnifyWithEvent:(NSEvent *)event {
    if (gMagnifyCallback) {
        NSView *contextView = nil;
        void *context = FPMagnifyContextForView(self, &contextView);
        if (!context) return;
        NSPoint loc = [(contextView ? contextView : self)
            convertPoint:[event locationInWindow]
                 fromView:nil];
        gMagnifyCallback(context, [event magnification], loc.x, loc.y);
    }
    /* Do NOT call the original — LCL's default impl is a no-op; calling it
       would just recurse via the swizzle. */
}

@end

/* ---------- public C entry point ---------- */

void FPInstallMagnifyHandler(void *nsViewHandle, void *callback, void *context) {
    if (!nsViewHandle || !callback || !context) return;

    gMagnifyCallback = (FPMagnifyCallback)callback;
    NSView *view = (__bridge NSView *)nsViewHandle;
    objc_setAssociatedObject(view,
                             kFPMagnifyContextKey,
                             [NSValue valueWithPointer:context],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    /* Swizzle -magnifyWithEvent: on the *concrete* class of the passed view
       so we don't affect every NSView in the process. */
    Class viewClass = object_getClass((__bridge id)nsViewHandle);
    NSNumber *isSwizzled = objc_getAssociatedObject((id)viewClass,
                                                     kFPMagnifySwizzledClassKey);
    if (isSwizzled.boolValue) return;

    Method original = class_getInstanceMethod(viewClass, @selector(magnifyWithEvent:));
    Method replacement = class_getInstanceMethod([NSView class], @selector(fp_magnifyWithEvent:));

    if (original && replacement) {
        method_exchangeImplementations(original, replacement);
        objc_setAssociatedObject((id)viewClass,
                                 kFPMagnifySwizzledClassKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (replacement) {
        /* The class (or its parents) didn't override magnifyWithEvent: yet.
           Just add our implementation directly. */
        if (class_addMethod(viewClass,
                            @selector(magnifyWithEvent:),
                            method_getImplementation(replacement),
                            method_getTypeEncoding(replacement))) {
            objc_setAssociatedObject((id)viewClass,
                                     kFPMagnifySwizzledClassKey,
                                     @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

void FPUninstallMagnifyHandler(void *nsViewHandle) {
    if (!nsViewHandle) return;
    NSView *view = (__bridge NSView *)nsViewHandle;
    objc_setAssociatedObject(view, kFPMagnifyContextKey, nil, OBJC_ASSOCIATION_ASSIGN);
}
