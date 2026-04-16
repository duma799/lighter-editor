/*
 * pty.c — Native PTY plugin for Lighter's terminal emulator.
 *
 * Provides forkpty()-based pseudoterminal with resize support,
 * replacing the Python pty.spawn() workaround.
 *
 * Lua API:
 *   handle = pty.spawn(cmd_table, cwd, cols, rows)
 *   data   = pty.read(handle)          -- non-blocking, returns "" if nothing
 *   ok     = pty.write(handle, data)
 *   ok     = pty.resize(handle, cols, rows)
 *   alive  = pty.running(handle)
 *   pty.close(handle)
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>  /* forkpty() on macOS */

#define LITE_XL_PLUGIN_ENTRYPOINT
#include "lite_xl_plugin_api.h"

#define READ_BUF 16384
#define MAX_HANDLES 16

typedef struct {
    int   master_fd;
    pid_t child_pid;
    int   alive;
} PtyHandle;

static PtyHandle handles[MAX_HANDLES];
static int handle_count = 0;

static int find_slot(void) {
    /* reuse closed slots */
    for (int i = 0; i < handle_count; i++) {
        if (handles[i].master_fd == -1) return i;
    }
    if (handle_count < MAX_HANDLES) return handle_count++;
    return -1;
}

/* pty.spawn({"cmd", "arg1", ...}, cwd, cols, rows) -> handle_id */
static int l_spawn(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    const char *cwd  = luaL_optstring(L, 2, NULL);
    int cols = (int)luaL_optinteger(L, 3, 80);
    int rows = (int)luaL_optinteger(L, 4, 24);

    /* build argv */
    int argc = (int)lua_rawlen(L, 1);
    if (argc < 1) return luaL_error(L, "pty.spawn: command table is empty");

    char **argv = calloc(argc + 1, sizeof(char *));
    if (!argv) return luaL_error(L, "pty.spawn: out of memory");

    for (int i = 0; i < argc; i++) {
        lua_rawgeti(L, 1, i + 1);
        const char *s = lua_tostring(L, -1);
        argv[i] = s ? strdup(s) : NULL;
        lua_pop(L, 1);
    }
    argv[argc] = NULL;

    int slot = find_slot();
    if (slot < 0) {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return luaL_error(L, "pty.spawn: too many open PTYs");
    }

    /* set up window size */
    struct winsize ws = {
        .ws_row = (unsigned short)rows,
        .ws_col = (unsigned short)cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    int master_fd;
    pid_t pid = forkpty(&master_fd, NULL, NULL, &ws);

    if (pid < 0) {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return luaL_error(L, "pty.spawn: forkpty failed: %s", strerror(errno));
    }

    if (pid == 0) {
        /* child */
        if (cwd) chdir(cwd);
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        execvp(argv[0], argv);
        _exit(127);
    }

    /* parent */
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);

    /* non-blocking reads */
    int flags = fcntl(master_fd, F_GETFL, 0);
    fcntl(master_fd, F_SETFL, flags | O_NONBLOCK);

    handles[slot].master_fd = master_fd;
    handles[slot].child_pid = pid;
    handles[slot].alive     = 1;

    lua_pushinteger(L, slot);
    return 1;
}

static PtyHandle *get_handle(lua_State *L, int idx) {
    int id = (int)luaL_checkinteger(L, idx);
    if (id < 0 || id >= handle_count || handles[id].master_fd == -1) {
        luaL_error(L, "pty: invalid handle %d", id);
        return NULL;
    }
    return &handles[id];
}

/* check if child is still alive, reap if not */
static void reap_check(PtyHandle *h) {
    if (!h->alive) return;
    int status;
    pid_t r = waitpid(h->child_pid, &status, WNOHANG);
    if (r > 0 || (r < 0 && errno == ECHILD)) {
        h->alive = 0;
    }
}

/* pty.read(handle) -> string (may be empty) */
static int l_read(lua_State *L) {
    PtyHandle *h = get_handle(L, 1);
    if (!h) return 0;

    char buf[READ_BUF];
    ssize_t n = read(h->master_fd, buf, sizeof(buf));

    if (n > 0) {
        lua_pushlstring(L, buf, n);
    } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
        /* EOF or real error — check if child died */
        reap_check(h);
        lua_pushliteral(L, "");
    } else {
        /* EAGAIN — nothing available */
        lua_pushliteral(L, "");
    }
    return 1;
}

/* pty.write(handle, data) -> boolean */
static int l_write(lua_State *L) {
    PtyHandle *h = get_handle(L, 1);
    if (!h) return 0;
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    size_t written = 0;
    while (written < len) {
        ssize_t n = write(h->master_fd, data + written, len - written);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
            lua_pushboolean(L, 0);
            return 1;
        }
        written += n;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/* pty.resize(handle, cols, rows) -> boolean */
static int l_resize(lua_State *L) {
    PtyHandle *h = get_handle(L, 1);
    if (!h) return 0;
    int cols = (int)luaL_checkinteger(L, 2);
    int rows = (int)luaL_checkinteger(L, 3);

    struct winsize ws = {
        .ws_row = (unsigned short)rows,
        .ws_col = (unsigned short)cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    int r = ioctl(h->master_fd, TIOCSWINSZ, &ws);
    lua_pushboolean(L, r == 0);
    return 1;
}

/* pty.running(handle) -> boolean */
static int l_running(lua_State *L) {
    PtyHandle *h = get_handle(L, 1);
    if (!h) return 0;
    reap_check(h);
    lua_pushboolean(L, h->alive);
    return 1;
}

/* pty.close(handle) */
static int l_close(lua_State *L) {
    PtyHandle *h = get_handle(L, 1);
    if (!h) return 0;

    if (h->alive) {
        kill(h->child_pid, SIGHUP);
        kill(h->child_pid, SIGTERM);
        /* give it a moment then reap */
        usleep(50000);
        int status;
        waitpid(h->child_pid, &status, WNOHANG);
        h->alive = 0;
    }
    if (h->master_fd >= 0) {
        close(h->master_fd);
        h->master_fd = -1;
    }
    return 0;
}

static const luaL_Reg lib[] = {
    { "spawn",   l_spawn   },
    { "read",    l_read    },
    { "write",   l_write   },
    { "resize",  l_resize  },
    { "running", l_running },
    { "close",   l_close   },
    { NULL, NULL }
};

int luaopen_lite_xl_pty(lua_State *L, void *XL) {
    lite_xl_plugin_init(XL);
    luaL_newlib(L, lib);
    return 1;
}
