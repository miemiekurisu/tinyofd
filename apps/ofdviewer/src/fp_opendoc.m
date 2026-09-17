/*
 * fp_opendoc.m — Finder / LaunchServices "open this document" bridge.
 *
 * LCL's Cocoa widgetset never forwards application:openFile: or
 * application:openURLs: to the application, so double-clicking an .ofd in
 * Finder, or "Open With > TinyOFD Viewer", would start the app and show an
 * empty window. This file hooks those two delegate methods on whatever object
 * LCL installed as the NSApplication delegate, queues the resulting file paths,
 * and lets the Pascal side drain them from its own main-thread timer.
 *
 * Why a queue instead of a direct callback: the events can arrive before the
 * LCL main form exists (during launch), and re-entering LCL from inside an
 * AppKit delegate callback during launch is exactly the kind of re-entrancy
 * that has bitten this app before. A queue drained by a TTimer keeps every
 * OpenOFD call on the LCL main thread, in LCL's own call context.
 *
 * Both entry points are hooked because modern macOS delivers document opens as
 * openURLs: while openFile: is still used for legacy/`-a` launches.
 *
 * Pascal side:
 *   FPInstallOpenDocHandler();                 once, after Application.Initialize
 *   while FPPopOpenDocPath(buf, SizeOf(buf)) <> 0 do OpenOFD(buf);
 */

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <string.h>

#define FP_OPENDOC_MAX 32
#define FP_OPENDOC_PATHLEN 4096

static char gOpenPaths[FP_OPENDOC_MAX][FP_OPENDOC_PATHLEN];
static int gOpenHead = 0;
static int gOpenCount = 0;
static BOOL gHandlerInstalled = NO;
static IMP gOriginalOpenFileIMP = NULL;
static IMP gOriginalOpenURLsIMP = NULL;

static id gSelfSentinel = nil;   /* only used to key the "installed" flag */

/* Queue one path (UTF-8). Silently drops when the queue is full: the caller is
   LaunchServices delivering a burst of files, and a stuck document open must
   never block app start. */
static void FPQueuePath(NSString *path) {
    const char *utf8;
    int slot;

    if (path == nil) return;
    utf8 = [path UTF8String];
    if (utf8 == NULL) return;
    if (gOpenCount >= FP_OPENDOC_MAX) return;

    slot = (gOpenHead + gOpenCount) % FP_OPENDOC_MAX;
    strncpy(gOpenPaths[slot], utf8, FP_OPENDOC_PATHLEN - 1);
    gOpenPaths[slot][FP_OPENDOC_PATHLEN - 1] = '\0';
    gOpenCount++;
}

static void FPQueueURL(NSURL *url) {
    NSString *path;

    if (url == nil) return;
    if (![url isFileURL]) {
        /* Non-file URLs (mailto:, http:) are not documents we can open. */
        return;
    }
    path = [url path];
    FPQueuePath(path);
}

/* ---------- delegate replacements ---------- */

static BOOL fp_application_openFile(id self, SEL _cmd, NSApplication *app, NSString *path) {
    (void)self; (void)app;
    FPQueuePath(path);
    /* Forward to LCL's own implementation if it had one, so nothing LCL does
       (e.g. dock badge / document menu bookkeeping) is lost. */
    if (gOriginalOpenFileIMP)
        return ((BOOL (*)(id, SEL, NSApplication *, NSString *))gOriginalOpenFileIMP)
            (self, _cmd, app, path);
    return YES;
}

static void fp_application_openURLs(id self, SEL _cmd, NSApplication *app, NSArray *urls) {
    NSUInteger i;
    (void)self; (void)app;
    for (i = 0; i < [urls count]; i++)
        FPQueueURL([urls objectAtIndex:i]);
    if (gOriginalOpenURLsIMP)
        ((void (*)(id, SEL, NSApplication *, NSArray *))gOriginalOpenURLsIMP)
            (self, _cmd, app, urls);
}

/* ---------- public C entry points ---------- */

void FPInstallOpenDocHandler(void) {
    id delegate;
    Class cls;
    Method m;

    if (gHandlerInstalled) return;

    /* NSApp is the shared-application INSTANCE global, nil before LCL creates
       the application object (and a class method like +sharedApplication must
       never be messaged through it - that raises unrecognized selector). When
       it or its delegate is missing the caller retries from the timer. */
    delegate = [NSApp delegate];
    if (delegate == nil) return;

    cls = object_getClass(delegate);
    if (cls == Nil) return;

    m = class_getInstanceMethod(cls, @selector(application:openFile:));
    if (m) {
        gOriginalOpenFileIMP = method_getImplementation(m);
        method_setImplementation(m, (IMP)fp_application_openFile);
    } else {
        /* B, @, self, _cmd, NSApplication*, NSString* */
        class_addMethod(cls, @selector(application:openFile:),
                        (IMP)fp_application_openFile, "c@:@@");
    }

    m = class_getInstanceMethod(cls, @selector(application:openURLs:));
    if (m) {
        gOriginalOpenURLsIMP = method_getImplementation(m);
        method_setImplementation(m, (IMP)fp_application_openURLs);
    } else {
        /* v, @, self, _cmd, NSApplication*, NSArray* */
        class_addMethod(cls, @selector(application:openURLs:),
                        (IMP)fp_application_openURLs, "v@:@@");
    }

    gHandlerInstalled = YES;
    gSelfSentinel = delegate;   /* keep a strong-ish reference for debugging */
}

/* Number of queued paths the Pascal side has not drained yet (diagnostics). */
int FPPendingOpenDocCount(void) {
    return gOpenCount;
}

int FPIsOpenDocHandlerInstalled(void) {
    return gHandlerInstalled ? 1 : 0;
}

/* Pops the oldest queued path into buf (NUL-terminated). Returns 1 when a path
   was returned, 0 when the queue is empty. bufLen is the caller's buffer size. */
int FPPopOpenDocPath(char *buf, int bufLen) {
    if (buf == NULL || bufLen <= 0) return 0;
    if (gOpenCount <= 0) return 0;

    strncpy(buf, gOpenPaths[gOpenHead], (size_t)bufLen - 1);
    buf[bufLen - 1] = '\0';
    gOpenPaths[gOpenHead][0] = '\0';
    gOpenHead = (gOpenHead + 1) % FP_OPENDOC_MAX;
    gOpenCount--;
    return 1;
}
