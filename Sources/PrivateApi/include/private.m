// This file exists purely because xcode doesn't like header only targets, SPM is fine with them
#import "private.h"

#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <string.h>

bool HyprspaceOrderDecorationAboveWindow(uint32_t decoration, uint32_t owner) {
    static int (*mainConnection)(void);
    static CGError (*getLevel)(int, uint32_t, int64_t *);
    static int32_t (*getSubLevel)(int, uint32_t);
    static CGError (*setLevel)(int, uint32_t, int);
    static CGError (*setSubLevel)(int, uint32_t, int);
    static CGError (*orderWindow)(int, uint32_t, int, uint32_t);
    static CGError (*isOrderedIn)(int, uint32_t, bool *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!skyLight) return;
        mainConnection = dlsym(skyLight, "SLSMainConnectionID");
        getLevel = dlsym(skyLight, "SLSGetWindowLevel");
        getSubLevel = dlsym(skyLight, "SLSGetWindowSubLevel");
        setLevel = dlsym(skyLight, "SLSSetWindowLevel");
        setSubLevel = dlsym(skyLight, "SLSSetWindowSubLevel");
        orderWindow = dlsym(skyLight, "SLSOrderWindow");
        isOrderedIn = dlsym(skyLight, "SLSWindowIsOrderedIn");
    });
    if (!decoration || !owner || !mainConnection || !getLevel || !getSubLevel ||
        !setLevel || !setSubLevel || !orderWindow || !isOrderedIn) return false;
    int connection = mainConnection();
    int64_t level = 0;
    bool visible = false;
    if (isOrderedIn(connection, owner, &visible) != kCGErrorSuccess || !visible ||
        getLevel(connection, owner, &level) != kCGErrorSuccess) return false;
    return setLevel(connection, decoration, (int)level) == kCGErrorSuccess &&
        setSubLevel(connection, decoration, getSubLevel(connection, owner)) == kCGErrorSuccess &&
        orderWindow(connection, decoration, 1, owner) == kCGErrorSuccess;
}


CGRect HyprspaceDecorationOwnerBounds(uint32_t owner) {
    static int (*mainConnection)(void);
    static CGError (*getBounds)(int, uint32_t, CGRect *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!skyLight) return;
        mainConnection = dlsym(skyLight, "SLSMainConnectionID");
        getBounds = dlsym(skyLight, "SLSGetWindowBounds");
    });
    CGRect bounds;
    if (!owner || !mainConnection || !getBounds ||
        getBounds(mainConnection(), owner, &bounds) != kCGErrorSuccess) return CGRectNull;
    return bounds;
}

static void (*decorationEventHandler)(uint32_t, uint32_t);
static void decorationWindowEvent(uint32_t event, void *data, size_t size, void *context) {
    if (!data || size < sizeof(uint32_t)) return;
    uint32_t window;
    memcpy(&window, data, sizeof(window));
    dispatch_async(dispatch_get_main_queue(), ^{
        if (decorationEventHandler) decorationEventHandler(window, event);
    });
}

bool HyprspaceObserveDecorationWindows(const uint32_t *windows, int count,
                                      void (*handler)(uint32_t, uint32_t)) {
    static int (*mainConnection)(void);
    static CGError (*requestNotifications)(int, const uint32_t *, int);
    static bool registered;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!skyLight) return;
        mainConnection = dlsym(skyLight, "SLSMainConnectionID");
        requestNotifications = dlsym(skyLight, "SLSRequestNotificationsForWindows");
        CGError (*registerNotification)(void *, uint32_t, void *) = dlsym(skyLight, "SLSRegisterNotifyProc");
        if (!registerNotification) return;
        // close, move, resize, hide. All carry a window ID as their payload.
        const uint32_t events[] = {804, 806, 807, 816};
        registered = true;
        for (int i = 0; i < 4; ++i) {
            if (registerNotification(decorationWindowEvent, events[i], NULL) != kCGErrorSuccess) registered = false;
        }
    });
    decorationEventHandler = handler;
    return registered && mainConnection && requestNotifications &&
        requestNotifications(mainConnection(), windows, count) == kCGErrorSuccess;
}
