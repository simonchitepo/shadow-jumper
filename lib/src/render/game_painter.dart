import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/math_structs.dart';

// ===============================
// Painter (UPDATED: pixel-art enemies)
// ===============================

class GamePainter extends CustomPainter {
  GamePainter({
    required this.viewSize,
    required this.cam,
    required this.level,
    required this.solids,
    required this.shadowPolys,
    required this.goal,
    required this.player,
    required this.playerInShadow,
    required this.light,
    required this.exposure,
    required this.state,
    required this.colors,
    required this.phys,

    // Enemies
    required this.enemies,

    // NEW: animation time (seconds)
    required this.timeSec,
  });

  final Size viewSize;
  final Vec2 cam;
  final Level? level;
  final List<RectD> solids;
  final List<List<Vec2>> shadowPolys;
  final RectD goal;
  final Player player;
  final bool playerInShadow;
  final Light light;
  final double exposure;
  final GameState state;
  final GameColors colors;
  final PhysConfig phys;

  final List<Enemy> enemies;

  // NEW
  final double timeSec;

  @override
  void paint(Canvas canvas, Size size) {
    final W = viewSize.width;
    final H = viewSize.height;

    // bg
    final bgPaint = Paint()..color = colors.bg;
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), bgPaint);

    if (level == null) return;

    canvas.save();
    canvas.translate(-cam.x, -cam.y);

    // light radial gradient
    final rectView = Rect.fromLTWH(cam.x, cam.y, W, H);
    final shader = RadialGradient(
      colors: [colors.lightCore, colors.lightFade],
      stops: const [0.0, 1.0],
    ).createShader(
      Rect.fromCircle(center: Offset(light.x, light.y), radius: light.radius),
    );
    final lightPaint = Paint()..shader = shader;
    canvas.drawRect(rectView, lightPaint);

    // shadows
    final shadowPaint = Paint()..color = colors.shadow;
    for (final poly in shadowPolys) {
      final path = Path()..moveTo(poly[0].x, poly[0].y);
      for (int i = 1; i < poly.length; i++) {
        path.lineTo(poly[i].x, poly[i].y);
      }
      path.close();
      canvas.drawPath(path, shadowPaint);
    }

    // solids
    final worldPaint = Paint()..color = colors.world;
    for (final s in solids) {
      canvas.drawRect(Rect.fromLTWH(s.x, s.y, s.w, s.h), worldPaint);
    }

    // edges
    final edgePaint = Paint()
      ..color = colors.worldEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final s in solids) {
      canvas.drawRect(
        Rect.fromLTWH(s.x + 0.5, s.y + 0.5, s.w - 1, s.h - 1),
        edgePaint,
      );
    }

    // goal
    final goalPaint = Paint()..color = colors.goal;
    canvas.drawRect(Rect.fromLTWH(goal.x, goal.y, goal.w, goal.h), goalPaint);

    final goalInnerPaint = Paint()..color = colors.goalInner;
    canvas.drawRect(
      Rect.fromLTWH(goal.x + 7, goal.y + 10, goal.w - 14, goal.h - 20),
      goalInnerPaint,
    );

    // enemies (behind player)
    _drawEnemiesPixel(canvas);

    // player
    _drawBloxHuman(
      canvas,
      x: player.x,
      y: player.y,
      w: player.w.toDouble(),
      h: player.h.toDouble(),
      inShadow: playerInShadow,
    );

    // optional: tiny enemy markers
    _drawEnemyBadges(canvas);

    canvas.restore();

    // exposure wash
    if (exposure > 0.0) {
      final alpha = clampDouble(exposure, 0, 1) * 0.12;
      final p = Paint()..color = Colors.white.withOpacity(alpha);
      canvas.drawRect(Rect.fromLTWH(0, 0, W, H), p);
    }
  }

  // ============================================================
  // Pixel sprites
  // ============================================================

  // Palette char mapping:
  // '.' = transparent
  // 'K' = near-black
  // 'D' = dark
  // 'M' = mid
  // 'L' = light
  // 'R' = red (eyes)
  // 'P' = purple glow/core
  // 'O' = orange/red
  // 'Y' = yellow
  // 'W' = white highlight
  //
  // The goal is "game dev market" vibe: blocky silhouette + neon eyes.

  // Light Seeker: small horned imp with red eyes (idle + chase)
  static const _seekerIdle = <String>[
    "....KKKK....",
    "...KDDDDK...",
    "..KDDDDDDK..",
    "..KDKRRKDK..",
    ".KDDKRRKDDK.",
    ".KDDDDDDDDK.",
    ".KDDDKDDDDK.",
    "..KDDDDDDK..",
    "...KDDDDK...",
    "....KDDK....",
    "....K..K....",
    "....K..K....",
  ];

  static const _seekerChase = <String>[
    "....KKKK....",
    "...KDDDDK...",
    "..KDDDDDDK..",
    "..KDRRRRDK..",
    ".KDDRRRRDDK.",
    ".KDDDDDDDDK.",
    ".KDDDKDDDDK.",
    "..KDDDDDDK..",
    "...KDDDDK...",
    "....KDDK....",
    "...KK..KK...",
    "....K..K....",
  ];

  // Shadow Leech: floating blob with purple core (blink frame)
  static const _leechA = <String>[
    "....PPPP....",
    "..PPDDDDPP..",
    ".PDDDDDDDDP.",
    ".PDDP..PDDP.",
    "PDDP.PP.PDDP",
    "PDD..PP..DDP",
    ".PDDP..PDDP.",
    ".PDDDDDDDDP.",
    "..PPDDDDPP..",
    "....PPPP....",
  ];

  static const _leechB = <String>[
    "....PPPP....",
    "..PPDDDDPP..",
    ".PDDDDDDDDP.",
    ".PDDP..PDDP.",
    "PDDP.PP.PDDP",
    "PDD..RR..DDP",
    ".PDDP..PDDP.",
    ".PDDDDDDDDP.",
    "..PPDDDDPP..",
    "....PPPP....",
  ];

  // Falling Stalker: hanging demon head (armed) and a "drop" frame
  static const _stalkerHang = <String>[
    ".....K......",
    ".....K......",
    "....KKK.....",
    "...KDDDK....",
    "..KDDDDDK...",
    "..KDRR RDK..",
    ".KDDDDDDDDK.",
    ".KDDKDDKDDK.",
    "..KDDDDDDK..",
    "...KDDDDK...",
    "....KDDK....",
    "....K..K....",
  ];

  static const _stalkerDrop = <String>[
    "..OOOOOOOO..",
    ".OODDDDDDOO.",
    "OODDRRRRDDOO",
    "OODDDDDDDDOO",
    "OODDKDDKDDOO",
    ".OODDDDDDOO.",
    "..OOODDDOO..",
    "...OO..OO...",
    "...OO..OO...",
    "...OO..OO...",
    "....O..O....",
    "....O..O....",
  ];

  void _drawEnemiesPixel(Canvas canvas) {
    if (enemies.isEmpty) return;

    for (final e in enemies) {
      final r = Rect.fromLTWH(e.x, e.y, e.w, e.h);

      // tiny "alive" jitter - keep pixel vibe (very small)
      final jitter = 0.4 * math.sin(timeSec * 10.0 + e.x * 0.02);
      final rr = r.shift(Offset(jitter, 0));

      // glow color per enemy type (soft aura behind pixels)
      final glow = switch (e.type) {
        EnemyType.lightSeeker => const Color(0xFFFF2B2B),
        EnemyType.shadowLeech => const Color(0xFFB061FF),
        EnemyType.fallingStalker => const Color(0xFFFF7A2A),
      };

      // intensity: seeker glows more when chasing; leech pulses; stalker glows when armed
      final glowIntensity = switch (e.type) {
        EnemyType.lightSeeker => (e.chasing ? 1.2 : 0.75),
        EnemyType.shadowLeech => (0.85 + 0.25 * (0.5 + 0.5 * math.sin(timeSec * 3.0))),
        EnemyType.fallingStalker => (e.armed && !e.dropping ? 0.9 : 0.6),
      };

      _drawSoftGlow(canvas, rr, glow, glowIntensity);

      // choose sprite frame
      final sprite = _spriteForEnemy(e);
      _drawPixelSprite(canvas, rr, sprite, _paletteForEnemy(e));

      // Leech radius ring (still useful gameplay feedback, keep it subtle)
      if (e.type == EnemyType.shadowLeech) {
        final ringAlpha = 0.08 + 0.06 * (0.5 + 0.5 * math.sin(timeSec * 2.6));
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color.fromRGBO(176, 97, 255, 1).withOpacity(ringAlpha);
        canvas.drawCircle(rr.center, e.leechRadius, ring);
      }

      // Stalker tether line (pixel-ish line)
      if (e.type == EnemyType.fallingStalker && e.armed && !e.dropping) {
        final tether = Paint()
          ..color = Colors.black.withOpacity(0.25)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(
          Offset(rr.center.dx, rr.top),
          Offset(rr.center.dx, rr.top - 22),
          tether,
        );
      }
    }
  }

  List<String> _spriteForEnemy(Enemy e) {
    switch (e.type) {
      case EnemyType.lightSeeker:
      // chase frame when chasing (redder eyes)
        return e.chasing ? _seekerChase : _seekerIdle;

      case EnemyType.shadowLeech:
      // blink/flash eyes frame
        final t = (timeSec * 3.0).floor();
        return (t % 6 == 0) ? _leechB : _leechA;

      case EnemyType.fallingStalker:
      // use hang sprite when armed/not dropping, else drop sprite
        return (e.armed && !e.dropping) ? _stalkerHang : _stalkerDrop;
    }
  }

  Map<String, Color> _paletteForEnemy(Enemy e) {
    // Shared neutrals
    const k = Color.fromRGBO(10, 10, 12, 1);   // K
    const d = Color.fromRGBO(32, 32, 42, 1);   // D
    const m = Color.fromRGBO(70, 70, 90, 1);   // M
    const l = Color.fromRGBO(120, 120, 150, 1);// L
    const w = Color.fromRGBO(235, 235, 245, 1);// W

    switch (e.type) {
      case EnemyType.lightSeeker:
        return {
          'K': k,
          'D': const Color.fromRGBO(20, 20, 28, 1),
          'M': const Color.fromRGBO(45, 45, 60, 1),
          'L': const Color.fromRGBO(85, 85, 110, 1),
          'R': const Color.fromRGBO(255, 40, 40, 1),
          'W': w,
        };

      case EnemyType.shadowLeech:
        return {
          'K': k,
          'D': const Color.fromRGBO(40, 22, 58, 1),
          'M': const Color.fromRGBO(85, 45, 120, 1),
          'P': const Color.fromRGBO(176, 97, 255, 1),
          'R': const Color.fromRGBO(255, 70, 190, 1), // flash eye
          'W': w,
        };

      case EnemyType.fallingStalker:
        return {
          'K': k,
          'D': const Color.fromRGBO(60, 20, 20, 1),
          'O': const Color.fromRGBO(255, 95, 35, 1),
          'Y': const Color.fromRGBO(255, 215, 80, 1),
          'R': const Color.fromRGBO(255, 50, 50, 1),
          'W': w,
        };
    }
  }

  void _drawSoftGlow(Canvas canvas, Rect r, Color color, double intensity) {
    final p = Paint()
      ..color = color.withOpacity(0.10 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(10 * intensity), const Radius.circular(14)),
      p,
    );
  }

  void _drawPixelSprite(
      Canvas canvas,
      Rect bounds,
      List<String> sprite,
      Map<String, Color> palette,
      ) {
    if (sprite.isEmpty) return;

    final rows = sprite.length;
    final cols = sprite[0].length;

    // Pixel size fitted to bounds. Use floor to keep crisp “block” feel.
    final pxW = (bounds.width / cols).floorToDouble().clamp(1.0, 99.0);
    final pxH = (bounds.height / rows).floorToDouble().clamp(1.0, 99.0);
    final px = math.min(pxW, pxH);

    final drawW = cols * px;
    final drawH = rows * px;

    // Center sprite in bounds
    final ox = bounds.left + (bounds.width - drawW) / 2;
    final oy = bounds.top + (bounds.height - drawH) / 2;

    // Optional: subtle outline by drawing black behind non-transparent pixels (cheap)
    final outline = Paint()..color = Colors.black.withOpacity(0.35);

    for (int y = 0; y < rows; y++) {
      final row = sprite[y];
      for (int x = 0; x < cols; x++) {
        final ch = row[x];
        if (ch == '.') continue;

        final color = palette[ch];
        if (color == null) continue;

        final rx = ox + x * px;
        final ry = oy + y * px;
        final rect = Rect.fromLTWH(rx, ry, px, px);

        // outline pass: draw slightly inflated black first
        canvas.drawRect(rect.inflate(0.35), outline);

        // actual pixel
        final p = Paint()..color = color;
        canvas.drawRect(rect, p);
      }
    }
  }

  // ============================================================
  // Existing helper: enemy badges
  // ============================================================

  void _drawEnemyBadges(Canvas canvas) {
    const maxConsiderDist = 180.0;
    final px = player.x + player.w / 2;
    final py = player.y;

    int shown = 0;
    for (final e in enemies) {
      if (shown >= 3) break;
      final ex = e.x + e.w / 2;
      final ey = e.y + e.h / 2;
      final d = math.sqrt((px - ex) * (px - ex) + (py - ey) * (py - ey));
      if (d > maxConsiderDist) continue;

      final c = switch (e.type) {
        EnemyType.lightSeeker => const Color.fromRGBO(255, 60, 60, 0.95),
        EnemyType.shadowLeech => const Color.fromRGBO(176, 97, 255, 0.95),
        EnemyType.fallingStalker => const Color.fromRGBO(255, 150, 60, 0.95),
      };

      final p = Paint()..color = c;
      final ox = (shown - 1) * 8.0;
      canvas.drawCircle(Offset(player.x + player.w / 2 + ox, player.y - 10), 3.2, p);
      shown++;
    }
  }

  // ============================================================
  // Player drawing (unchanged from your file)
  // ============================================================

  void _drawBloxHuman(
      Canvas canvas, {
        required double x,
        required double y,
        required double w,
        required double h,
        required bool inShadow,
      }) {
    final won = (state == GameState.win);
    final dead = (state == GameState.lose);

    final bodyCol = dead
        ? const Color.fromRGBO(255, 90, 90, 0.95)
        : won
        ? const Color.fromRGBO(120, 220, 255, 0.95)
        : inShadow
        ? const Color.fromRGBO(90, 255, 150, 0.95)
        : const Color.fromRGBO(255, 200, 90, 0.95);

    const edgeCol = Color.fromRGBO(0, 0, 0, 0.30);

    final headH = (h * 0.24).floorToDouble();
    final torsoH = (h * 0.34).floorToDouble();
    final legH = h - headH - torsoH;

    final headW = (w * 0.72).floorToDouble();
    final torsoW = (w * 0.78).floorToDouble();
    final armW = math.max(6.0, (w * 0.20).floorToDouble());
    final armH = (torsoH * 0.92).floorToDouble();
    final legW = math.max(7.0, (w * 0.30).floorToDouble());

    final cx = x + w / 2;

    final head = Rect.fromLTWH(cx - headW / 2, y, headW, headH);
    final torso = Rect.fromLTWH(cx - torsoW / 2, y + headH + 2, torsoW, torsoH);

    final armL = Rect.fromLTWH(torso.left - armW - 2, torso.top + 2, armW, armH);
    final armR = Rect.fromLTWH(torso.right + 2, torso.top + 2, armW, armH);

    final bob = clampDouble((player.vx.abs() / phys.maxRun), 0, 1) * 2;
    final legY = torso.top + torso.height + 2 + (player.grounded ? bob : 0);

    const legGap = 3.0;
    final legL = Rect.fromLTWH(cx - legGap / 2 - legW, legY, legW, legH - 2);
    final legR = Rect.fromLTWH(cx + legGap / 2, legY, legW, legH - 2);

    final fill = Paint()..color = bodyCol;
    canvas.drawRect(head, fill);
    canvas.drawRect(torso, fill);
    canvas.drawRect(armL, fill);
    canvas.drawRect(armR, fill);
    canvas.drawRect(legL, fill);
    canvas.drawRect(legR, fill);

    final stroke = Paint()
      ..color = edgeCol
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(head.deflate(0.5), stroke);
    canvas.drawRect(torso.deflate(0.5), stroke);
    canvas.drawRect(armL.deflate(0.5), stroke);
    canvas.drawRect(armR.deflate(0.5), stroke);
    canvas.drawRect(legL.deflate(0.5), stroke);
    canvas.drawRect(legR.deflate(0.5), stroke);

    // face
    final face = Paint()..color = const Color.fromRGBO(0, 0, 0, 0.35);
    final eyeY = head.top + head.height * 0.40;
    canvas.drawRect(Rect.fromLTWH(head.left + head.width * 0.26, eyeY, 4, 6), face);
    canvas.drawRect(Rect.fromLTWH(head.left + head.width * 0.66, eyeY, 4, 6), face);
    canvas.drawRect(
      Rect.fromLTWH(
        head.left + head.width * 0.44,
        head.top + head.height * 0.62,
        head.width * 0.18,
        3,
      ),
      face,
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}