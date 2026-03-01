import 'dart:math';
import 'package:flutter/material.dart';


// ===============================
// Deterministic RNG (mulberry32 + hashLevelSeed)
// ===============================

class Mulberry32 {
  int t;
  Mulberry32(this.t);

  double next() {
    t = (t + 0x6D2B79F5) & 0xFFFFFFFF;
    int r = _imul(t ^ (t >>> 15), 1 | t);
    r ^= r + _imul(r ^ (r >>> 7), 61 | r);
    final out = ((r ^ (r >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
    return out;
  }

  int _imul(int a, int b) {
    // 32-bit multiply emulation
    return (a * b) & 0xFFFFFFFF;
  }
}

int hashLevelSeed(int i) {
  int x = ((i + 1) * 2654435761) & 0xFFFFFFFF;
  x ^= (x << 13) & 0xFFFFFFFF;
  x ^= (x >>> 17);
  x ^= (x << 5) & 0xFFFFFFFF;
  return x & 0xFFFFFFFF;
}

