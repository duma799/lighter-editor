#import <AppKit/AppKit.h>

#define LITE_XL_PLUGIN_ENTRYPOINT
#include "lite_xl_plugin_api.h"

static int l_pick_folder(lua_State *L) {
    @autoreleasepool {
        __block NSString *chosen = nil;

        void (^show)(void) = ^{
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            panel.title                   = @"Open Project Folder";
            panel.message                 = @"Choose the folder to open as your project";
            panel.prompt                  = @"Open";
            panel.canChooseFiles          = NO;
            panel.canChooseDirectories    = YES;
            panel.allowsMultipleSelection = NO;
            panel.canCreateDirectories    = YES;

            if ([panel runModal] == NSModalResponseOK && panel.URLs.count > 0) {
                chosen = panel.URLs[0].path;
            }
        };

        if ([NSThread isMainThread]) {
            show();
        } else {
            dispatch_sync(dispatch_get_main_queue(), show);
        }

        if (chosen) {
            lua_pushstring(L, chosen.UTF8String);
        } else {
            lua_pushnil(L);
        }
    }
    return 1;
}

static const luaL_Reg lib[] = {
    { "pick_folder", l_pick_folder },
    { NULL, NULL }
};

int luaopen_lite_xl_fspicker(lua_State *L, void *XL) {
    lite_xl_plugin_init(XL);
    luaL_newlib(L, lib);
    return 1;
}
