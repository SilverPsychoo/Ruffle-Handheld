/* NextUI-only SDL2 display adapter, experimental pending a physical Brick test.
 * Keeps the frozen executable and cursor shim unchanged. No GL calls are
 * intercepted: Ruffle resizes its own renderer through its SDL event handler.
 * ARM64 build (maintainers only, Zig 0.14.1):
 * zig cc -target aarch64-linux-gnu.2.17 -shared -fPIC -O2 -s -Wall -Wextra
 * -Werror -Wl,-z,relro,-z,now -o
 * port/rufflehandheld/rufflehandheld/runtime/libruffle_nextui_display.aarch64.so
 * tools/ruffle_nextui_display.c -ldl
 * Activation requires explicit RUFFLE_NEXTUI_DISPLAY=1 plus LD_PRELOAD.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Public SDL2 event ABI on ARM64 and x86_64. SDL is resolved at runtime, so
 * this adapter does not bundle another SDL or depend on development headers.
 * https://github.com/libsdl-org/SDL/blob/SDL2/include/SDL_events.h */
typedef struct SDL_Window SDL_Window;
typedef struct {
    uint32_t type, timestamp, windowID;
    uint8_t event, padding1, padding2, padding3;
    int32_t data1, data2;
} WindowEvent;
typedef union {
    uint32_t type;
    WindowEvent window;
    uint8_t padding[56];
    uint64_t alignment;
} Event;
_Static_assert(sizeof(Event) == 56, "SDL2 event ABI");
_Static_assert(sizeof(WindowEvent) == 24, "SDL2 window event ABI");

static int (*real_poll)(Event *);
static SDL_Window *(*current_window)(void);
static void (*drawable_size)(SDL_Window *, int *, int *);
static void (*window_size)(SDL_Window *, int *, int *);
static uint32_t (*window_id)(SDL_Window *);
static uint32_t (*ticks)(void);
static int initialized, enabled;
static SDL_Window *last_window;
static uint32_t last_id;
static int last_width, last_height;

static void initialize(void) {
    if (initialized) return;
    initialized = 1;
    real_poll = (int (*)(Event *))dlsym(RTLD_NEXT, "SDL_PollEvent");
    const char *setting = getenv("RUFFLE_NEXTUI_DISPLAY");
    if (!setting || strcmp(setting, "1")) return;
    current_window = (SDL_Window *(*)(void))dlsym(RTLD_NEXT, "SDL_GL_GetCurrentWindow");
    drawable_size = (void (*)(SDL_Window *, int *, int *))dlsym(RTLD_NEXT, "SDL_GL_GetDrawableSize");
    window_size = (void (*)(SDL_Window *, int *, int *))dlsym(RTLD_NEXT, "SDL_GetWindowSize");
    window_id = (uint32_t (*)(SDL_Window *))dlsym(RTLD_NEXT, "SDL_GetWindowID");
    ticks = (uint32_t (*)(void))dlsym(RTLD_NEXT, "SDL_GetTicks");
    enabled = real_poll && current_window && drawable_size && window_size && window_id;
    if (!enabled) fprintf(stderr, "[nextui-display] required SDL2 APIs unavailable; passthrough\n");
    else fprintf(stderr, "[nextui-display] hook active; awaiting current GL window\n");
}

int SDL_PollEvent(Event *event) {
    initialize();
    if (!real_poll) return 0;
    int result = real_poll(event);
    if (enabled && result && event && event->type == 0x200 &&
        (event->window.event == 5 || event->window.event == 6)) {
        /* Recheck after the consumer receives a real resize. A backend may
         * report logical dimensions even if the drawable did not change. */
        last_window = NULL;
    }
    /* Never consume, rewrite or reorder real input/window/quit events. Query
     * dimensions once the real queue is drained, before the next draw. */
    if (!enabled || result || !event) return result;
    SDL_Window *window = current_window();
    if (!window) {
        last_window = NULL;
        last_id = 0;
        return 0;
    }
    uint32_t id = window_id(window);
    int width = 0, height = 0, logical_width = 0, logical_height = 0;
    drawable_size(window, &width, &height);
    window_size(window, &logical_width, &logical_height);
    /* A temporarily unavailable/minimized surface must not resize to zero. */
    if (!id || width <= 0 || height <= 0) return 0;
    if (window == last_window && id == last_id &&
        width == last_width && height == last_height) return 0;
    last_window = window;
    last_id = id;
    last_width = width;
    last_height = height;
    memset(event, 0, sizeof(*event));
    event->window.type = 0x200;  /* SDL_WINDOWEVENT */
    event->window.timestamp = ticks ? ticks() : 0;
    event->window.windowID = id;
    event->window.event = 5;     /* SDL_WINDOWEVENT_RESIZED, not SIZE_CHANGED */
    event->window.data1 = width;
    event->window.data2 = height;
    fprintf(stderr, "[nextui-display] window=%dx%d drawable=%dx%d; resize event=%dx%d\n",
            logical_width, logical_height, width, height, width, height);
    return 1;
}
