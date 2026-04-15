#import <AppKit/AppKit.h>

#define LITE_XL_PLUGIN_ENTRYPOINT
#include "lite_xl_plugin_api.h"

static int l_set_color(lua_State *L) {
    double r = lua_tonumber(L, 1) / 255.0;
    double g = lua_tonumber(L, 2) / 255.0;
    double b = lua_tonumber(L, 3) / 255.0;

    @autoreleasepool {
        void (^apply)(void) = ^{
            NSWindow *win = [[NSApplication sharedApplication] mainWindow];
            if (!win) {
                NSArray<NSWindow *> *windows = [NSApplication sharedApplication].windows;
                for (NSWindow *w in windows) {
                    if (w.isVisible) { win = w; break; }
                }
            }
            if (!win) return;

            win.titlebarAppearsTransparent = YES;
            win.backgroundColor = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];

            double lum = 0.299 * r + 0.587 * g + 0.114 * b;
            if (lum < 0.5) {
                win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            } else {
                win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            }
        };

        if ([NSThread isMainThread]) {
            apply();
        } else {
            dispatch_sync(dispatch_get_main_queue(), apply);
        }
    }
    return 0;
}

static const luaL_Reg lib[] = {
    { "set_color", l_set_color },
    { NULL, NULL }
};

int luaopen_lite_xl_titlebar(lua_State *L, void *XL) {
    lite_xl_plugin_init(XL);
    luaL_newlib(L, lib);
    return 1;
}
