import 'dart:math';
import 'package:flutter/material.dart';

// ===============================
// Game State
// ===============================

enum GameState { run, win, lose, pause }
enum RetryMode { safe, fast }

// ===============================
// Enemies
// ===============================

enum EnemyType { lightSeeker, shadowLeech, fallingStalker }

class Enemy {
  Enemy({
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final EnemyType type;

  double x, y;
  double w, h;

  // Movement
  double vx = 0;
  double vy = 0;

  // ---- Light Seeker ----
  double minX = 0;
  double maxX = 0;
  bool chasing = false;

  // ---- Shadow Leech ----
  double leechRadius = 90;
  double leechDrainPerSec = 0.55;
  double knockCooldown = 0;

  // ---- Falling Stalker ----
  double homeX = 0;
  double homeY = 0;
  bool armed = true;
  bool dropping = false;
  double resetT = 0;

  RectD get rect => RectD(x, y, w, h);
}

// ===============================
// Banner UI
// ===============================

class BannerModel {
  BannerModel({
    required this.title,
    required this.body,
    required this.hint,
    required this.buttons,
    this.bodyWidget,
  });

  final String title;
  final String body;
  final String hint;
  final List<BannerButton> buttons;
  final Widget? bodyWidget;
}

class BannerButton {
  BannerButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

// ===============================
// Physics
// ===============================

class PhysConfig {
  const PhysConfig({
    required this.gravity,
    required this.maxFall,
    required this.runAccel,
    required this.airAccel,
    required this.maxRun,
    required this.groundFriction,
    required this.airFriction,
    required this.jumpVel,
    required this.jumpCut,
    required this.coyote,
    required this.jumpBuffer,
  });

  final double gravity;
  final double maxFall;
  final double runAccel;
  final double airAccel;
  final double maxRun;
  final double groundFriction;
  final double airFriction;
  final double jumpVel;
  final double jumpCut;
  final double coyote;
  final double jumpBuffer;
}

// ===============================
// Exposure
// ===============================

class ExposureConfig {
  const ExposureConfig({
    required this.gainPerSec,
    required this.losePerSec,
    required this.failAt,
  });

  final double gainPerSec;
  final double losePerSec;
  final double failAt;
}

// ===============================
// Camera
// ===============================

class CameraConfig {
  const CameraConfig({
    required this.smooth,
    required this.lookAhead,
    required this.yBias,
  });

  final double smooth;
  final double lookAhead;
  final double yBias;
}

// ===============================
// Colors
// ===============================

class GameColors {
  const GameColors({
    required this.bg,
    required this.world,
    required this.worldEdge,
    required this.shadow,
    required this.lightCore,
    required this.lightFade,
    required this.goal,
    required this.goalInner,
  });

  final Color bg;
  final Color world;
  final Color worldEdge;
  final Color shadow;
  final Color lightCore;
  final Color lightFade;
  final Color goal;
  final Color goalInner;
}

// ===============================
// Math structs
// ===============================

class Vec2 {
  double x;
  double y;
  Vec2(this.x, this.y);
}

class RectD {
  final double x, y, w, h;
  const RectD(this.x, this.y, this.w, this.h);

  RectD copy() => RectD(x, y, w, h);
}

class Orbit {
  double cx, cy, rx, ry, speed, phase;

  Orbit({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.speed,
    required this.phase,
  });

  Orbit copy() => Orbit(
    cx: cx,
    cy: cy,
    rx: rx,
    ry: ry,
    speed: speed,
    phase: phase,
  );
}

class Light {
  double x, y;
  double radius;
  Orbit orbit;

  Light({
    required this.x,
    required this.y,
    required this.radius,
    required this.orbit,
  });

  static Light zero() => Light(
    x: 0,
    y: 0,
    radius: 0,
    orbit: Orbit(
      cx: 0,
      cy: 0,
      rx: 0,
      ry: 0,
      speed: 0,
      phase: 0,
    ),
  );
}

class WorldSize {
  final double w, h;
  const WorldSize(this.w, this.h);
}

class StartPos {
  final double x, y;
  const StartPos(this.x, this.y);
}

class LevelLight {
  final double radius;
  final Orbit orbit;
  const LevelLight({
    required this.radius,
    required this.orbit,
  });
}

class Level {
  final String name;
  final int num;
  final WorldSize world;
  final StartPos start;
  final RectD goal;
  final LevelLight light;
  final List<RectD> solids;

  const Level({
    required this.name,
    required this.num,
    required this.world,
    required this.start,
    required this.goal,
    required this.light,
    required this.solids,
  });
}

// ===============================
// Player
// ===============================

class Player {
  double x, y;
  final int w, h;
  double vx, vy;

  bool grounded = false;
  double coyoteT = 0;
  double jumpBufT = 0;
  bool jumpWasHeld = false;

  Player({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.vx,
    required this.vy,
  });
}