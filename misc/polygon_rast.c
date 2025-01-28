// emcc -O3 --no-entry -s TOTAL_STACK=65536 -s INITIAL_MEMORY=262144 -o polygon_rast.wasm polygon_rast.c
#include <emscripten/emscripten.h>
#include <stdint.h>

#define PIX_BUF_SIZE (180 * 180 * 4)
static uint8_t pix_buf[PIX_BUF_SIZE];
EMSCRIPTEN_KEEPALIVE uint8_t *get_pix_buf() { return pix_buf; }

#define PT_BUF_SIZE (128 * 2)
static float pt_buf[PT_BUF_SIZE];
EMSCRIPTEN_KEEPALIVE float *get_pt_buf() { return pt_buf; }

EMSCRIPTEN_KEEPALIVE void rasterize_outline(int w, int h, int n)
{
  pix_buf[0] = pix_buf[1] = pix_buf[2] = pix_buf[3] = 255;
}
