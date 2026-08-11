#include <SDL.h>
#define DPI_DLLISPEC
#include "svdpi.h"
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <vector>

namespace {
SDL_Window *window = nullptr;
SDL_Renderer *renderer = nullptr;
SDL_Texture *texture = nullptr;
int width = 0;
int height = 0;
int frame_skip = 1;
uint64_t frame_count = 0;
bool save_requested = false;

void pump_events() {
    if (!window)
        return;
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        // Closing the window is not a simulation stop condition.  Keep the
        // mandatory visual frontend present for the complete replay.
        if (event.type == SDL_QUIT)
            SDL_ShowWindow(window);
        if (event.type == SDL_KEYDOWN &&
            (event.key.keysym.sym == SDLK_F5 ||
             (event.key.keysym.sym == SDLK_s &&
              (event.key.keysym.mod & KMOD_CTRL))))
            save_requested = true;
    }
}
}

extern "C" void bucky_sdl_init(int w, int h) {
    width = w;
    height = h;
    if (const char *env = std::getenv("BUCKY_SDL_SKIP")) {
        const auto parsed = std::atoi(env);
        if (parsed > 0)
            frame_skip = parsed;
    }
    if (SDL_Init(SDL_INIT_VIDEO) != 0)
        return;
    window = SDL_CreateWindow("Bucky O'Hare - Verilator SDL",
                              SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                              width * 2, height * 2,
                              SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
    if (!window)
        return;
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer)
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    if (!renderer)
        return;
    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGB24,
                                SDL_TEXTUREACCESS_STREAMING, width, height);
}

extern "C" void bucky_sdl_frame(const svOpenArrayHandle rh,
                                const svOpenArrayHandle gh,
                                const svOpenArrayHandle bh,
                                int w, int h) {
    if (!window || !renderer || !texture || w != width || h != height)
        return;
    ++frame_count;
    const auto *r = static_cast<const unsigned char *>(svGetArrayPtr(rh));
    const auto *g = static_cast<const unsigned char *>(svGetArrayPtr(gh));
    const auto *b = static_cast<const unsigned char *>(svGetArrayPtr(bh));
    if (!r || !g || !b)
        return;
    pump_events();
    // Keep the required visible window alive and responsive, but allow long
    // deterministic replays to present periodically instead of blocking the
    // RTL on a host compositor/vsync for every native arcade frame.  PPM
    // capture is performed by the testbench independently of this throttle.
    if (frame_skip > 1 && (frame_count % static_cast<uint64_t>(frame_skip)) != 1)
        return;
    void *raw = nullptr;
    int pitch = 0;
    if (SDL_LockTexture(texture, nullptr, &raw, &pitch) != 0)
        return;
    auto *dst = static_cast<unsigned char *>(raw);
    for (int y = 0; y < height; ++y) {
        auto *row = dst + y * pitch;
        for (int x = 0; x < width; ++x) {
            const auto i = static_cast<std::size_t>(y) * width + x;
            row[x * 3 + 0] = r[i];
            row[x * 3 + 1] = g[i];
            row[x * 3 + 2] = b[i];
        }
    }
    SDL_UnlockTexture(texture);
    int out_w = 0, out_h = 0;
    SDL_GetRendererOutputSize(renderer, &out_w, &out_h);
    SDL_Rect dst_rect{0, 0, out_w, out_h};
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, nullptr, &dst_rect);
    SDL_RenderPresent(renderer);
}

extern "C" void bucky_sdl_pump() {
    pump_events();
}

extern "C" int bucky_sdl_take_save_request() {
    const bool requested = save_requested;
    save_requested = false;
    return requested ? 1 : 0;
}

extern "C" void bucky_sdl_done() {
    if (texture) SDL_DestroyTexture(texture);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    texture = nullptr;
    renderer = nullptr;
    window = nullptr;
    SDL_Quit();
}
