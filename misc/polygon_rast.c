// emcc -O3 -DNDEBUG --no-entry -s TOTAL_STACK=65536 -s INITIAL_MEMORY=2097152 -o polygon_rast.wasm polygon_rast.c

#define _export

#if __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#undef _export
#define _export EMSCRIPTEN_KEEPALIVE
#endif

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define JC_VORONOI_IMPLEMENTATION
#include "jc_voronoi/jc_voronoi.h"

#define MAX_SIDE 200
#define N_PIXELS (180 * 200)

#define PIX_BUF_SIZE (N_PIXELS * 4)
static uint8_t pix_buf[PIX_BUF_SIZE];
_export uint8_t *get_pix_buf() { return pix_buf; }

#define PT_BUF_SIZE (256 * 2)
static float pt_buf[PT_BUF_SIZE];
_export float *get_pt_buf() { return pt_buf; }

static int cmp_float(const void *_a, const void *_b)
{
  float a = *(float *)_a, b = *(float *)_b;
  return a < b ? -1 : a > b ? 1 : 0;
}

static inline float snoise3(float x, float y, float z);

#ifdef TESTRUN
#include <stdio.h>
#define debug(...) printf(__VA_ARGS__)
#else
#define debug(...)
#endif

static inline void normalize3(float *x, float *y, float *z)
{
  float d = sqrtf(*x * *x + *y * *y + *z * *z);
  *x /= d; *y /= d; *z /= d;
}

static uint8_t jcv_myalloc_buf[131072 * 8];
static size_t jcv_myalloc_ptr;
static void *jcv_myalloc(void *_unused, size_t n)
{
  void *p = jcv_myalloc_buf + jcv_myalloc_ptr;
  debug("alloc %p %zu\n", p, n);
  jcv_myalloc_ptr += n;
  return p;
}
static void jcv_myfree(void *_unused, void *p)
{
  debug("free  %p\n", p);
}

_export void rasterize_fill(int w, int h, int n,
  float r, float g, float b, float opacity, int t)
{
  // Scratch space for Meijster's algorithm
  static unsigned G[N_PIXELS];
  static unsigned D[N_PIXELS];
  static float F[N_PIXELS];
  for (int i = 0; i < w * h; i++) G[i] = 0;
  #define G(_x, _y) (G[(_x) + (_y) * w])
  #define D(_x, _y) (D[(_x) + (_y) * w])
  #define F(_x, _y) (F[(_x) + (_y) * w])

  // Clear texture
  for (int i = 0; i < w * h * 4; i++) pix_buf[i] = 0;

  // http://alienryderflex.com/polygon_fill/
  static float xs[36];
  for (int y = 0; y < h; y++) {
    int n_xs = 0;
    float x1 = pt_buf[(n - 1) * 2 + 0];
    float y1 = pt_buf[(n - 1) * 2 + 1];
    for (int i = 0; i < n; i++) {
      float x0 = pt_buf[i * 2 + 0];
      float y0 = pt_buf[i * 2 + 1];
      if ((y0 < y && y1 >= y) || (y1 < y && y0 >= y)) {
        if (n_xs >= 36) { return; } // Extremely unlikely case where we just give up
        xs[n_xs++] = x0 + (y - y0) / (y1 - y0) * (x1 - x0);
      }
      x1 = x0;
      y1 = y0;
    }
    qsort(xs, n_xs, sizeof(float), cmp_float);
    for (int i = 0; i < n_xs - 1; i += 2) {
      if (xs[i] >= w) break;
      if (xs[i + 1] >= 0) {
        int x_start = (xs[i] < 0 ? 0 : (int)(xs[i] + 0.5f));
        int x_end = (xs[i + 1] > w - 1 ? w - 1 : (int)(xs[i + 1] + 0.5f));
        for (int x = x_start; x <= x_end; x++) {
          G(x, y) = w + h;
          float a = opacity * (0.85f + 0.15f * snoise3(x / 100.f, t / 720.f, y / 100.f));
          pix_buf[(y * w + x) * 4 + 0] = (int)(r * 255);
          pix_buf[(y * w + x) * 4 + 1] = (int)(g * 255);
          pix_buf[(y * w + x) * 4 + 2] = (int)(b * 255);
          pix_buf[(y * w + x) * 4 + 3] = (int)(a * 255);
        }
      }
    }
  }

  // Take the alpha channel as a flag because it is not sensible to set it as 0
  #define INSIDE(_x, _y) \
    ((_x) >= 0 && (_x) < w && (_y) >= 0 && (_y) < h && \
     pix_buf[((int)(_y) * w + (int)(_x)) * 4 + 3] > 0)

  // Meijster's algorithm
  #define min(_a, _b) ((_a) < (_b) ? (_a) : (_b))
  for (int x = 0; x < w; x++) {
    G(x, 0) = min(G(x, 0), 1);
    G(x, h - 1) = min(G(x, h - 1), 1);
    for (int y = 0; y < h; y++)
      G(x, y) = min(G(x, y), G(x, y - 1) + 1);
    for (int y = h - 1; y >= 0; y--)
      G(x, y) = min(G(x, y), G(x, y + 1) + 1);
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      unsigned d = (w + h) * (w + h);
      for (int i = 0; i < w; i++)
        d = min(d, (x - i) * (x - i) + G(i, y) * G(i, y));
      D(x, y) = d;
    }
  }

  // Medial axis from Voronoi diagram
  // Deduplication. To draw a pixel, mark G(x, y) as 1 and add the coordinates to `ma[n_ma++]`.
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) G(x, y) = 0;
  int n_ma = 0;
  static uint8_t ma[N_PIXELS][2];

  static jcv_diagram diagram;
  diagram = (jcv_diagram){0};
  jcv_diagram_generate_useralloc(
    n, (void *)pt_buf, &(jcv_rect){{-10, -10}, {10 + w, 10 + h}}, NULL,
    NULL, jcv_myalloc, jcv_myfree, &diagram);

  // NOTE: Edge filtering can also be done in total O(n log n) time by
  // building the node-edge graph of the Voronoi diagram and removing
  // all vertices connected to the infinite vertices. See `backups/highlight_test/main.c`
  // However as we already have the polygon's mask, we can just look it up!
  for (const jcv_edge* edge = jcv_diagram_get_edges(&diagram);
      edge != NULL;
      edge = jcv_diagram_get_next_edge(edge)
  ) {
    float x1 = edge->pos[0].x, y1 = edge->pos[0].y;
    float x2 = edge->pos[1].x, y2 = edge->pos[1].y;

    if (INSIDE(x1, y1) && INSIDE(x2, y2)) {
      // Trace line with Bresenham's Algorithm, working in fixed-point
      const int SUBPX = 4;
      int x1_fixed = (int)(x1 * (1 << SUBPX) + 0.5);
      int y1_fixed = (int)(y1 * (1 << SUBPX) + 0.5);
      int x2_fixed = (int)(x2 * (1 << SUBPX) + 0.5);
      int y2_fixed = (int)(y2 * (1 << SUBPX) + 0.5);

      int dx = abs(x2_fixed - x1_fixed);
      int dy = abs(y2_fixed - y1_fixed);
      int sx = (x2_fixed > x1_fixed) ? 1 : -1;
      int sy = (y2_fixed > y1_fixed) ? 1 : -1;

      int x = x1_fixed;
      int y = y1_fixed;
      int err = dx - dy;
      while (1) {
        int pixel_x = x >> SUBPX;
        int pixel_y = y >> SUBPX;
        if (pixel_x >= 0 && pixel_x < w && pixel_y >= 0 && pixel_y < h) {
          if (!G(pixel_x, pixel_y)) {
            G(pixel_x, pixel_y) = 1;
            ma[n_ma][0] = (uint8_t)pixel_x;
            ma[n_ma][1] = (uint8_t)pixel_y;
            n_ma++;
          }
        }
        if (x == x2_fixed && y == y2_fixed) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x += sx; }
        if (e2 <  dx) { err += dx; y += sy; }
      }
    }
  }

  jcv_diagram_free(&diagram);
  jcv_myalloc_ptr = 0;

  // F(P) = max_C (sqrt(D(C)^2 - (P-C)^2)),
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int f = 0;
      for (int i = 0; i < n_ma; i++) {
        int x1 = ma[i][0], y1 = ma[i][1];
        int f1 = D(x1, y1) - (x1-x)*(x1-x) - (y1-y)*(y1-y);
        if (f < f1) f = f1;
      }
      F(x, y) = sqrtf(f);
    }
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) debug("%5.1f", F(x, y));
    debug("\n");
  }

  // 2-D Gaussian blur on F
/*
sigma = 1
n = 3
sum = 0
for i = 0, 3 do
  sum = sum + math.exp(-i * i / (2 * sigma * sigma)) * (i == 0 and 1 or 2)
end
for i = 0, 3 do
  print(math.exp(-i * i / (2 * sigma * sigma)) / sum)
end
*/
  static float FF[200];
  for (int y = 0; y < h - 0; y++) {
    for (int x = 0; x < w - 0; x++) {
      FF[x] =
        0.399050279652450 * F(x, y) +
        0.242036229376110 * ((x < 1 ? 0 : F(x-1, y)) + (x >= w-1 ? 0 : F(x+1, y))) +
        0.054005582622414 * ((x < 2 ? 0 : F(x-2, y)) + (x >= w-2 ? 0 : F(x+2, y)));
    }
    for (int x = 0; x < w - 0; x++) F(x, y) = FF[x];
  }
  for (int x = 0; x < w - 0; x++) {
    for (int y = 0; y < h - 0; y++) {
      FF[y] =
        0.399050279652450 * F(x, y) +
        0.242036229376110 * ((y < 1 ? 0 : F(x, y-1)) + (y >= h-1 ? 0 : F(x, y+1))) +
        0.054005582622414 * ((y < 2 ? 0 : F(x, y-2)) + (y >= h-2 ? 0 : F(x, y+2)));
    }
    for (int y = 0; y < h - 0; y++) F(x, y) = FF[y];
  }

  // The light!
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      // Normal vector
      float gx = (
        (F(x+1, y-1) + 2 * F(x+1, y) + F(x+1, y+1)) -
        (F(x-1, y-1) + 2 * F(x-1, y) + F(x-1, y+1))
      ) / 4;
      float gy = (
        (F(x-1, y+1) + 2 * F(x, y+1) + F(x+1, y+1)) -
        (F(x-1, y-1) + 2 * F(x, y-1) + F(x+1, y-1))
      ) / 4;
      float nz = 1. / sqrtf(gx * gx + gy * gy + 1);
      float nx = -gx * nz, ny = -gy * nz;
      // Blinn-Phong specular lighting
      const float Lx = -1000, Ly = -1000, Lz = 400;
      float lx = Lx - x, ly = Ly - y, lz = Lz - F(x, y);
      normalize3(&lx, &ly, &lz);
      float vx = -x, vy = -y, vz = 1000 - F(x, y);
      normalize3(&vx, &vy, &vz);
      float hx = lx + vx, hy = ly + vy, hz = lz + vz;
      normalize3(&hx, &hy, &hz);
      float c = hx * nx + hy * ny + hz * nz;
      unsigned is_highlight = (INSIDE(x, y) && c > 0.95);
      debug("%2c", INSIDE(x, y) ? (is_highlight ? '#' : '*') : '.');
      // debug("%2c", INSIDE(x, y) ? (G(x, y) ? '#' : '*') : '.');
      if (is_highlight) {
        pix_buf[(y * w + x) * 4 + 0] = 255 - (255 - pix_buf[(y * w + x) * 4 + 0]) * .4;
        pix_buf[(y * w + x) * 4 + 1] = 255 - (255 - pix_buf[(y * w + x) * 4 + 1]) * .4;
        pix_buf[(y * w + x) * 4 + 2] = 255 - (255 - pix_buf[(y * w + x) * 4 + 2]) * .4;
        pix_buf[(y * w + x) * 4 + 3] = 255 - (255 - pix_buf[(y * w + x) * 4 + 3]) * .4;
      }
    }
    debug("\n");
  }
}

#ifdef TESTRUN
#include <string.h>

// cc polygon_rast.c -o /tmp/a.out -DTESTRUN -lm && /tmp/a.out

int main()
{
  float pt[] = {
    1, 1, 6, -0.5, 12, 1, 14, 3, 16, 11, 10, 17, 4, 5, 3, 9
// 10.0000,18.0000,12.0706,17.7274,14.0000,16.9282,15.6569,15.6569,16.9282,14.0000,17.7274,12.0706,18.0000,10.0000,17.7274,7.9294,16.9282,6.0000,15.6569,4.3431,14.0000,3.0718,12.0706,2.2726,10.0000,2.0000,7.9294,2.2726,6.0000,3.0718,4.3431,4.3431,3.0718,6.0000,2.2726,7.9294,2.0000,10.0000,2.2726,12.0706,3.0718,14.0000,4.3431,15.6569,6.0000,16.9282,7.9294,17.7274
/*
from math import *; print(','.join('%.4f,%.4f' % (10 + 8*sin(i/24*pi*2), 10 + 8*cos(i/24*pi*2)) for i in range(24)))
*/
  };
  int n = sizeof pt / sizeof pt[0];
  int scale = 3;
  for (int i = 0; i < n; i++) pt[i] *= scale;
  memcpy(pt_buf, pt, sizeof pt);
  rasterize_fill(20 * scale, 20 * scale, n / 2, 1, 1, 1, 1, 0);
  return 0;
}
#endif

_export void rasterize_outline(int w, int h, int n,
  float r, float g, float b)
{
  float x1 = pt_buf[(n - 1) * 2 + 0];
  float y1 = pt_buf[(n - 1) * 2 + 1];
  for (int i = 0; i < n; i++) {
    float x0 = pt_buf[i * 2 + 0];
    float y0 = pt_buf[i * 2 + 1];
    float dx = (x0 - x1) / 10;
    float dy = (y0 - y1) / 10;
    for (int k = 0; k < 10; x1 += dx, y1 += dy, k++) {
      int x = (int)(x1 + 0.5f);
      int y = (int)(y1 + 0.5f);
      if (x >= 0 && x < w && y >= 0 && y < h) {
        pix_buf[(y * w + x) * 4 + 0] = (int)(r * 255);
        pix_buf[(y * w + x) * 4 + 1] = (int)(g * 255);
        pix_buf[(y * w + x) * 4 + 2] = (int)(b * 255);
        pix_buf[(y * w + x) * 4 + 3] = 255;
      }
    }
    x1 = x0;
    y1 = y0;
  }
}

// https://github.com/stegu/perlin-noise/blob/a624f5a/src/simplexnoise1234.c

/* SimplexNoise1234, Simplex noise with true analytic
 * derivative in 1D to 4D.
 *
 * Author: Stefan Gustavson, 2003-2005
 * Contact: stefan.gustavson@liu.se
 *
 * This code was GPL licensed until February 2011.
 * As the original author of this code, I hereby
 * release it into the public domain.
 * Please feel free to use it for whatever you want.
 * Credit is appreciated where appropriate, and I also
 * appreciate being told where this code finds any use,
 * but you may do as you like.
 */

/*
 * This implementation is "Simplex Noise" as presented by
 * Ken Perlin at a relatively obscure and not often cited course
 * session "Real-Time Shading" at Siggraph 2001 (before real
 * time shading actually took off), under the title "hardware noise".
 * The 3D function is numerically equivalent to his Java reference
 * code available in the PDF course notes, although I re-implemented
 * it from scratch to get more readable code. The 1D, 2D and 4D cases
 * were implemented from scratch by me from Ken Perlin's text.
 *
 * This file has no dependencies on any other file, not even its own
 * header file. The header file is made for use by external code only.
 */

#define FASTFLOOR(x) ( ((int)(x)<=(x)) ? ((int)x) : (((int)x)-1) )

//---------------------------------------------------------------------
// Static data

/*
 * Permutation table. This is just a random jumble of all numbers 0-255,
 * repeated twice to avoid wrapping the index at 255 for each lookup.
 * This needs to be exactly the same for all instances on all platforms,
 * so it's easiest to just keep it as static explicit data.
 * This also removes the need for any initialisation of this class.
 *
 * Note that making this an int[] instead of a char[] might make the
 * code run faster on platforms with a high penalty for unaligned single
 * byte addressing. Intel x86 is generally single-byte-friendly, but
 * some other CPUs are faster with 4-aligned reads.
 * However, a char[] is smaller, which avoids cache trashing, and that
 * is probably the most important aspect on most architectures.
 * This array is accessed a *lot* by the noise functions.
 * A vector-valued noise over 3D accesses it 96 times, and a
 * float-valued 4D noise 64 times. We want this to fit in the cache!
 */
unsigned char perm[512] = {151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
  151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180 
};

//---------------------------------------------------------------------

/*
 * Helper functions to compute gradients-dot-residualvectors (1D to 4D)
 * Note that these generate gradients of more than unit length. To make
 * a close match with the value range of classic Perlin noise, the final
 * noise values need to be rescaled to fit nicely within [-1,1].
 * (The simplex noise functions as such also have different scaling.)
 * Note also that these noise functions are the most practical and useful
 * signed version of Perlin noise. To return values according to the
 * RenderMan specification from the SL noise() and pnoise() functions,
 * the noise values need to be scaled and offset to [0,1], like this:
 * float SLnoise = (noise(x,y,z) + 1.0) * 0.5;
 */

static inline float  grad3( int hash, float x, float y , float z ) {
    int h = hash & 15;     // Convert low 4 bits of hash code into 12 simple
    float u = h<8 ? x : y; // gradient directions, and compute dot product.
    float v = h<4 ? y : h==12||h==14 ? x : z; // Fix repeats at h = 12 to 15
    return ((h&1)? -u : u) + ((h&2)? -v : v);
}

// 3D simplex noise
static inline float snoise3(float x, float y, float z) {

// Simple skewing factors for the 3D case
#define F3 0.333333333
#define G3 0.166666667

  float n0, n1, n2, n3; // Noise contributions from the four corners

  // Skew the input space to determine which simplex cell we're in
  float s = (x+y+z)*F3; // Very nice and simple skew factor for 3D
  float xs = x+s;
  float ys = y+s;
  float zs = z+s;
  int i = FASTFLOOR(xs);
  int j = FASTFLOOR(ys);
  int k = FASTFLOOR(zs);

  float t = (float)(i+j+k)*G3; 
  float X0 = i-t; // Unskew the cell origin back to (x,y,z) space
  float Y0 = j-t;
  float Z0 = k-t;
  float x0 = x-X0; // The x,y,z distances from the cell origin
  float y0 = y-Y0;
  float z0 = z-Z0;

  // For the 3D case, the simplex shape is a slightly irregular tetrahedron.
  // Determine which simplex we are in.
  int i1, j1, k1; // Offsets for second corner of simplex in (i,j,k) coords
  int i2, j2, k2; // Offsets for third corner of simplex in (i,j,k) coords

/* This code would benefit from a backport from the GLSL version! */
  if(x0>=y0) {
    if(y0>=z0)
      { i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; } // X Y Z order
      else if(x0>=z0) { i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; } // X Z Y order
      else { i1=0; j1=0; k1=1; i2=1; j2=0; k2=1; } // Z X Y order
    }
  else { // x0<y0
    if(y0<z0) { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; } // Z Y X order
    else if(x0<z0) { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; } // Y Z X order
    else { i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; } // Y X Z order
  }

  // A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
  // a step of (0,1,0) in (i,j,k) means a step of (-c,1-c,-c) in (x,y,z), and
  // a step of (0,0,1) in (i,j,k) means a step of (-c,-c,1-c) in (x,y,z), where
  // c = 1/6.

  float x1 = x0 - i1 + G3; // Offsets for second corner in (x,y,z) coords
  float y1 = y0 - j1 + G3;
  float z1 = z0 - k1 + G3;
  float x2 = x0 - i2 + 2.0f*G3; // Offsets for third corner in (x,y,z) coords
  float y2 = y0 - j2 + 2.0f*G3;
  float z2 = z0 - k2 + 2.0f*G3;
  float x3 = x0 - 1.0f + 3.0f*G3; // Offsets for last corner in (x,y,z) coords
  float y3 = y0 - 1.0f + 3.0f*G3;
  float z3 = z0 - 1.0f + 3.0f*G3;

  // Wrap the integer indices at 256, to avoid indexing perm[] out of bounds
  int ii = i & 0xff;
  int jj = j & 0xff;
  int kk = k & 0xff;

  // Calculate the contribution from the four corners
  float t0 = 0.5f - x0*x0 - y0*y0 - z0*z0;
  if(t0 < 0.0f) n0 = 0.0f;
  else {
    t0 *= t0;
    n0 = t0 * t0 * grad3(perm[ii+perm[jj+perm[kk]]], x0, y0, z0);
  }

  float t1 = 0.5f - x1*x1 - y1*y1 - z1*z1;
  if(t1 < 0.0f) n1 = 0.0f;
  else {
    t1 *= t1;
    n1 = t1 * t1 * grad3(perm[ii+i1+perm[jj+j1+perm[kk+k1]]], x1, y1, z1);
  }

  float t2 = 0.5f - x2*x2 - y2*y2 - z2*z2;
  if(t2 < 0.0f) n2 = 0.0f;
  else {
    t2 *= t2;
    n2 = t2 * t2 * grad3(perm[ii+i2+perm[jj+j2+perm[kk+k2]]], x2, y2, z2);
  }

  float t3 = 0.5f - x3*x3 - y3*y3 - z3*z3;
  if(t3<0.0f) n3 = 0.0f;
  else {
    t3 *= t3;
    n3 = t3 * t3 * grad3(perm[ii+1+perm[jj+1+perm[kk+1]]], x3, y3, z3);
  }

  // Add contributions from each corner to get the final noise value.
  // The result is scaled to stay just inside [-1,1]
  return 72.0f * (n0 + n1 + n2 + n3);
}
