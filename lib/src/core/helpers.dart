import 'dart:math';
import 'package:flutter/material.dart';
import 'math_structs.dart';

import 'dart:math' as math;
// ===============================
// Helpers
// ===============================

double clampDouble(double v, double a, double b) => math.max(a, math.min(b, v));
int clampInt(int v, int a, int b) => math.max(a, math.min(b, v));
double lerp(double a, double b, double t) => a + (b - a) * t;

bool rectsOverlap(RectD a, RectD b) {
  return a.x < b.x + b.w &&
      a.x + a.w > b.x &&
      a.y < b.y + b.h &&
      a.y + a.h > b.y;
}

RectD expandRect(RectD r, double pad) => RectD(r.x - pad, r.y - pad, r.w + pad * 2, r.h + pad * 2);

bool pointInPoly(Vec2 pt, List<Vec2> poly) {
  bool inside = false;
  for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i].x, yi = poly[i].y;
    final xj = poly[j].x, yj = poly[j].y;
    final intersect = ((yi > pt.y) != (yj > pt.y)) &&
        (pt.x < (xj - xi) * (pt.y - yi) / ((yj - yi) + 1e-12) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}


