// emcc -O3 --no-entry -s TOTAL_STACK=65536 -s INITIAL_MEMORY=262144 -o polygon_rast.wasm polygon_rast.c
#include <emscripten/emscripten.h>
#include <stdint.h>

#define PIX_BUF_SIZE (180 * 200 * 4)
static uint8_t pix_buf[PIX_BUF_SIZE];
EMSCRIPTEN_KEEPALIVE uint8_t *get_pix_buf() { return pix_buf; }

#define PT_BUF_SIZE (256 * 2)
static float pt_buf[PT_BUF_SIZE];
EMSCRIPTEN_KEEPALIVE float *get_pt_buf() { return pt_buf; }

EMSCRIPTEN_KEEPALIVE void rasterize_fill(int w, int h, int n,
  float r, float g, float b, float opacity, float t)
{
  // Clear texture
  for (int i = 0; i < w * h * 4; i++) pix_buf[i] = 0;
}

EMSCRIPTEN_KEEPALIVE void rasterize_outline(int w, int h, int n,
  float r, float g, float b)
{
  for (int i = 0; i < n; i++) {
    int x = (int)pt_buf[i * 2 + 0];
    int y = (int)pt_buf[i * 2 + 1];
    if (x >= 0 && x < w && y >= 0 && y < h) {
      pix_buf[(y * w + x) * 4 + 0] = (int)(r * 255);
      pix_buf[(y * w + x) * 4 + 1] = (int)(g * 255);
      pix_buf[(y * w + x) * 4 + 2] = (int)(b * 255);
      pix_buf[(y * w + x) * 4 + 3] = 255;
    }
  }
}
