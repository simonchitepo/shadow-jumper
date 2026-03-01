import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'rng.dart';
import 'helpers.dart';
import 'math_structs.dart';
import 'constants.dart';

// ===============================
// Level Generation (UPDATED)
// - Caps blocker/column heights based on player jump capability
// - Keeps early obstacles/platforms reachable
// ===============================

Level generateLevel(
    int index0, {
      required int playerH,

      /// Optional: if you want the generator to be physically correct, pass these
      /// from your PhysConfig (game.dart). If you don't pass them, safe defaults are used.
      double jumpVel = 730,
      double gravity = 1700,
    }) {
  final levelNum = index0 + 1;
  final rng = Mulberry32(hashLevelSeed(index0));

  final t = (levelNum - 1) / (TOTAL_LEVELS - 1); // 0..1
  final w = (1700 + 2600 * t).floorToDouble();
  final h = (980 + 380 * t).floorToDouble();

  final platformCount = (7 + 13 * t + rng.next() * 3).floor();
  final blockerCount = (3 + 9 * t + rng.next() * 2).floor();

  final verticality = 0.30 + 0.50 * t;

  // Player jump apex (in px) from kinematics: v^2 / (2g)
  // Use a conservative margin so generated obstacles remain climbable.
  final jumpApex = (jumpVel * jumpVel) / (2.0 * gravity);
  final safeClimb = clampDouble(jumpApex * 0.90, 120, 175); // conservative, tune if needed

  // Blocker height caps scale a bit with level, but never exceed what is reachable.
  // If you want *all* blockers always climbable: keep hard cap near safeClimb.
  final blockerMaxH = clampDouble(safeClimb + 12 + 18 * t, 140, 190);

  // Thin columns later are allowed to be taller, but still capped to avoid "impossible walls".
  final columnMaxH = clampDouble(safeClimb + 40 + 45 * t, 180, 260);

  final orbit = Orbit(
    cx: w * (0.45 + 0.10 * (rng.next() - 0.5)),
    cy: h * (0.40 + 0.14 * (rng.next() - 0.5)),
    rx: 220 + 520 * t + rng.next() * 160,
    ry: 160 + 420 * t + rng.next() * 140,
    speed: 0.45 + 1.05 * t + rng.next() * 0.35,
    phase: rng.next() * math.pi * 2,
  );

  final lightRadius = 900 + 420 * t + rng.next() * 140;

  final groundY = h - 120;

  final start = StartPos(140, groundY - playerH - 6);

  RectD goalRect = RectD(
    w - 200,
    200 + (1 - t) * 140 + rng.next() * 70,
    46,
    70,
  );

  final startKeep = RectD(start.x - 120, start.y - 220, 420, 520);
  final goalKeep = RectD(goalRect.x - 180, goalRect.y - 180, 420, 420);

  final all = <RectD>[];

  bool overlapsAny(RectD r, List<RectD> list, {double pad = 0}) {
    final rr = pad != 0 ? expandRect(r, pad) : r;
    for (final s in list) {
      final ss = pad != 0 ? expandRect(s, pad) : s;
      if (rectsOverlap(rr, ss)) return true;
    }
    return false;
  }

  bool inKeepout(RectD r) => rectsOverlap(r, startKeep) || rectsOverlap(r, goalKeep);

  double snap(double v, double step) => (v / step).roundToDouble() * step;

  bool tryAddRect(RectD Function() makeRect, int attempts, {double pad = 8}) {
    for (int i = 0; i < attempts; i++) {
      final r = makeRect();
      if (r.w <= 0 || r.h <= 0) continue;
      if (r.x < -500 || r.y < -500 || r.x + r.w > w + 500 || r.y + r.h > h + 600) continue;
      if (inKeepout(r)) continue;
      if (overlapsAny(r, all, pad: pad)) continue;
      all.add(r);
      return true;
    }
    return false;
  }

  // Ground
  all.add(RectD(-400, groundY, w + 800, 520));

  // ===============================
  // Critical path (UPDATED)
  // Limit vertical steps to be reachable (maxUp derived from jump apex)
  // ===============================
  final steps = (8 + 8 * t).floor();
  double px = 240;
  double py = groundY - (150 + rng.next() * 60);

  final maxDx = 240 + 90 * t;

  // Ensure upward steps never exceed climbability (with margin).
  // Keep it under safeClimb rather than letting verticality push too high.
  final maxUp = clampDouble(safeClimb * 0.85, 95, 160);
  final maxDown = 160 + 100 * verticality;

  for (int i = 0; i < steps; i++) {
    final stepW = 170 + rng.next() * 130;
    final stepH = 22 + rng.next() * 10;

    final dx = 150 + rng.next() * (maxDx - 150);
    final dy = (rng.next() < 0.55) ? -(rng.next() * maxUp) : (rng.next() * maxDown);

    px = clampDouble(px + dx, 220, w - 620);
    py = clampDouble(py + dy, 160, groundY - 140);

    final rx = snap(px, 10);
    final ry = snap(py, 10);

    final r = RectD(rx, ry, snap(stepW, 10), snap(stepH, 2));

    if (overlapsAny(r, all, pad: 10) || inKeepout(r)) {
      bool placed = false;
      for (final off in [-40, -20, 20, 40, -60, 60]) {
        final rr = RectD(r.x, clampDouble(r.y + off, 140, groundY - 140), r.w, r.h);
        if (!overlapsAny(rr, all, pad: 10) && !inKeepout(rr)) {
          all.add(rr);
          px = rr.x;
          py = rr.y;
          placed = true;
          break;
        }
      }
      if (!placed) continue;
    } else {
      all.add(r);
    }
  }

  // Landing platform near goal
      {
    final land = RectD(
      goalRect.x - (220 + rng.next() * 80),
      clampDouble(goalRect.y + goalRect.h + (90 + rng.next() * 60), 180, groundY - 160),
      260 + rng.next() * 140,
      24,
    );

    bool placed = false;
    for (final off in [0, -30, 30, -60, 60, -90, 90]) {
      final rr = RectD(
        snap(land.x, 10),
        clampDouble(snap(land.y + off, 10), 140, groundY - 140),
        snap(land.w, 10),
        land.h,
      );
      if (!overlapsAny(rr, all, pad: 10) && !inKeepout(rr)) {
        all.add(rr);
        placed = true;
        break;
      }
    }
    if (!placed) {
      goalRect = RectD(
        goalRect.x,
        clampDouble(goalRect.y, 160, groundY - 240),
        goalRect.w,
        goalRect.h,
      );
    }
  }

  // Extra platforms
  for (int i = 0; i < platformCount; i++) {
    final ok = tryAddRect(() {
      final pw = 120 + rng.next() * (220 + 80 * t);
      final ph = 18 + rng.next() * 14;
      final x = 180 + rng.next() * (w - 420);
      final y = 160 + rng.next() * (groundY - 260);
      return RectD(snap(x, 10), snap(y, 10), snap(pw, 10), snap(ph, 2));
    }, 80, pad: 12);
    if (!ok) break;
  }

  // ===============================
  // Blockers (UPDATED)
  // - Height is now capped based on safeClimb
  // ===============================
  for (int i = 0; i < blockerCount; i++) {
    final ok = tryAddRect(() {
      final bw = 70 + rng.next() * (80 + 60 * t);

      // Old: final bh = 70 + rng.next() * (160 + 170 * t);
      // New: generate then clamp
      final raw = 70 + rng.next() * (120 + 90 * t);
      final bh = clampDouble(raw, 70, blockerMaxH);

      final x = 260 + rng.next() * (w - 520);
      final y = 210 + rng.next() * (groundY - 360);
      return RectD(snap(x, 10), snap(y, 10), snap(bw, 10), snap(bh, 10));
    }, 110, pad: 16);
    if (!ok) break;
  }

  // Teaching block (UPDATED)
  // Make it always climbable by tying to blockerMaxH rather than fixed 160.
      {
    final teachH = clampDouble(140, 100, blockerMaxH);
    final base = RectD(520, groundY - teachH, 120, teachH);
    if (!overlapsAny(base, all, pad: 10) && !inKeepout(base)) {
      all.add(base);
    } else {
      for (final dx in [40, 80, 120, -40, -80, -120]) {
        final r = RectD(base.x + dx, base.y, base.w, base.h);
        if (!overlapsAny(r, all, pad: 10) && !inKeepout(r)) {
          all.add(r);
          break;
        }
      }
    }
  }

  // ===============================
  // Thin columns later (UPDATED)
  // - Still adds difficulty, but avoids impossible vertical walls
  // ===============================
  if (t > 0.55) {
    final n = 1 + (2 + 2.5 * t).floor();
    for (int i = 0; i < n; i++) {
      final ok = tryAddRect(() {
        final cw = 40 + rng.next() * 26;

        // Old: final ch = 220 + rng.next() * 260;  (could go huge)
        // New: clamp to columnMaxH
        final raw = 180 + rng.next() * (170 + 140 * t);
        final ch = clampDouble(raw, 160, columnMaxH);

        final x = 480 + rng.next() * (w - 960);
        final y = 240 + rng.next() * (groundY - 520);
        return RectD(snap(x, 10), snap(y, 10), snap(cw, 2), snap(ch, 10));
      }, 120, pad: 18);
      if (!ok) break;
    }
  }

  all.sort((a, b) {
    final dy = a.y.compareTo(b.y);
    return dy != 0 ? dy : a.x.compareTo(b.x);
  });

  return Level(
    name: "Level $levelNum",
    num: levelNum,
    world: WorldSize(w, h),
    start: start,
    goal: goalRect,
    light: LevelLight(radius: lightRadius, orbit: orbit),
    solids: all,
  );
}