// cc -O2 -DJC_VORONOI_IMPLEMENTATION -x c jc_voronoi/jc_voronoi.h -c -o jc_voronoi.o
// cc -Ijc_voronoi % jc_voronoi.o && ./a.out

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jc_voronoi.h"

#ifndef M_PI
#define M_PI 3.141592653589793
#endif

struct edge_vertex {
  float x, y;
  uint32_t endpoint_id;
  uint32_t vertex_id;
};

static int cmp_vertex(const void *_a, const void *_b)
{
  const struct edge_vertex *a = (const struct edge_vertex *)_a;
  const struct edge_vertex *b = (const struct edge_vertex *)_b;
  if (fabsf(a->x - b->x) < 1e-6) {
    return a->y < b->y ? -1 : 1;
  } else {
    return a->x < b->x ? -1 : 1;
  }
}

int main()
{
  const int n = 100;
  jcv_point points[n];

  for (int i = 0; i < n; i++) {
    float phi = (float)M_PI * 2 * i / n;
    points[i].x = 1.7f * cosf(phi) + 1.0f * cosf(2 * phi);
    points[i].y = 1.7f * sinf(phi) - 0.2f * sinf(3 * phi);
  }

  jcv_diagram diagram;
  memset(&diagram, 0, sizeof(jcv_diagram));
  jcv_diagram_generate(n, points, &(jcv_rect){{-10.0f, -10.0f}, {10.0f, 10.0f}}, NULL, &diagram);

  struct edge_vertex v[n * 6];
  int n_e = 0;

  const jcv_edge* edge = jcv_diagram_get_edges(&diagram);
  while (edge != NULL) {
    v[n_e * 2 + 0] = (struct edge_vertex){ edge->pos[0].x, edge->pos[0].y, n_e * 2 + 0, 0 };
    v[n_e * 2 + 1] = (struct edge_vertex){ edge->pos[1].x, edge->pos[1].y, n_e * 2 + 1, 0 };
    n_e++;
    edge = jcv_diagram_get_next_edge(edge);
  }

  qsort(v, n_e * 2, sizeof(struct edge_vertex), cmp_vertex);
  int n_v = 0;
  float last_x = NAN, last_y = NAN;
  for (int i = 0; i < n_e * 2; i++) {
    if (i == 0 ||
      fabsf(v[i].x - last_x) > 1e-6 ||
      fabsf(v[i].y - last_y) > 1e-6
    ) {
      printf("%d %f %f\n", n_v, v[i].x, v[i].y);
      last_x = v[i].x;
      last_y = v[i].y;
      n_v++;
    }
    v[i].vertex_id = n_v - 1;
  }

  // Put edge vertices back to order
  for (int i = 0; i < n_e * 2; i++) {
    int j = v[i].endpoint_id;
    if (i != j) {
      struct edge_vertex t = v[i]; v[i] = v[j]; v[j] = t;
      i--;
    }
  }

  for (int i = 0; i < n_e; i++) {
    float x1, y1, x2, y2;
    printf("Segment((%.4f, %.4f), (%.4f, %.4f)),\n",
      v[i * 2 + 0].x, v[i * 2 + 0].y,
      v[i * 2 + 1].x, v[i * 2 + 1].y);
    printf("  %u %u\n", (unsigned)v[i * 2 + 0].vertex_id, (unsigned)v[i * 2 + 1].vertex_id);
  }

  return 0;
}
