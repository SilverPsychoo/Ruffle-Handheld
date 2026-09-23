/* Host-only SDL stand-in: tests event delivery, not real ARM/GPU execution. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct SDL_Window { int unused; } SDL_Window;
typedef union {
    struct { uint32_t type, timestamp, id; uint8_t event, p1,p2,p3; int32_t w,h; } window;
    uint8_t bytes[56];
    uint64_t alignment;
} Event;
static SDL_Window window;
static int width=1024, height=768, have_window=1, queued=1;
static int resize_queued;
static uint32_t id=7;
int SDL_PollEvent(Event *e) {
    if (!queued) return 0;
    if (e) {
        memset(e,0,sizeof(*e));
        e->window.type=resize_queued ? 0x200 : 0x650;
        if (resize_queued) { e->window.event=5; e->window.id=id; e->window.w=640; e->window.h=480; }
        queued=0; resize_queued=0;
    }
    return 1;
}
SDL_Window *SDL_GL_GetCurrentWindow(void) { return have_window ? &window : NULL; }
void SDL_GL_GetDrawableSize(SDL_Window *w,int *x,int *y) { (void)w; *x=width; *y=height; }
void SDL_GetWindowSize(SDL_Window *w,int *x,int *y) { (void)w; *x=640; *y=480; }
uint32_t SDL_GetWindowID(SDL_Window *w) { (void)w; return id; }
uint32_t SDL_GetTicks(void) { return 42; }
void probe_dimensions(int w,int h) { width=w; height=h; }
void probe_window(int present) { have_window=present; }
void probe_id(uint32_t value) { id=value; }
void probe_queue(void) { queued=1; }
void probe_resize(void) { queued=1; resize_queued=1; }

#ifdef PROBE_MAIN
/* Compiled separately to ensure LD_PRELOAD interposes the shared backend. */
#error Build this file as a shared library only
#endif
