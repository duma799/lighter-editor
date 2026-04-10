// Lighter native folder picker
// Calls NSOpenPanel directly — no subprocess, no AppleScript.
// Compile with: make (see Makefile)
// Lua API: require "lighter.native.fspicker"
//   fspicker.pick_folder()  -> string path | nil (if cancelled)

#import <AppKit/AppKit.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

// pick_folder() -> string or nil
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

// Module init — called by require "lighter.native.fspicker"
// Lua converts dots to underscores for the C symbol name.
int luaopen_lighter_native_fspicker(lua_State *L) {
    luaL_newlib(L, lib);
    return 1;
}
