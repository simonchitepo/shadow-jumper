import 'dart:async' show scheduleMicrotask;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Audio
import 'package:audioplayers/audioplayers.dart';

import '../core/constants.dart';
import '../core/helpers.dart';
import '../core/level_generation.dart';
import '../core/math_structs.dart';
import '../render/game_painter.dart';
import '../ui/hud_widgets.dart';
import '../ui/options_panel.dart';
import '../../widgets/desktop_ad_banner.dart';

// ============================================================
// Game (UPDATED):
// - Resume progress (save/load current level)
// - Double jump (one air-jump per airtime; resets on landing)
// - Enemies (NO POWERUPS):
//   1) Light Seeker (patrol -> chase forever; contact = death)
//   2) Shadow Leech (shadow unsafe radius + contact knockback)
//   3) Falling Stalker (drops when you pass; resets)
// - Scary music (looping BGM via audioplayers)
// IMPORTANT:
// - Enemy / EnemyType MUST be defined ONLY ONCE in your project.
//   This file expects Enemy and EnemyType from ../core/math_structs.dart
// ============================================================

class ShadowJumperGame extends StatefulWidget {
  const ShadowJumperGame({super.key});

  @override
  State<ShadowJumperGame> createState() => _ShadowJumperGameState();
}

class _ShadowJumperGameState extends State<ShadowJumperGame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ---------- Config ----------
  static const phys = PhysConfig(
    gravity: 1700,
    maxFall: 1500,
    runAccel: 5200,
    airAccel: 3600,
    maxRun: 340,
    groundFriction: 0.82,
    airFriction: 0.94,
    jumpVel: 730,
    jumpCut: 0.52,
    coyote: 0.11,
    jumpBuffer: 0.12,
  );

  static const exposureCfg = ExposureConfig(
    gainPerSec: 0.70,
    losePerSec: 0.90,
    failAt: 1.0,
  );

  static const cameraCfg = CameraConfig(
    smooth: 0.12,
    lookAhead: 110,
    yBias: 60,
  );

  static const colors = GameColors(
    bg: Color(0xFF101016),
    world: Color(0xFF2F2F36),
    worldEdge: Color.fromRGBO(255, 255, 255, 0.08),
    shadow: Color.fromRGBO(0, 0, 0, 0.86),
    lightCore: Color.fromRGBO(255, 255, 220, 0.55),
    lightFade: Color.fromRGBO(0, 0, 0, 0.0),
    goal: Color.fromRGBO(120, 220, 255, 0.92),
    goalInner: Color.fromRGBO(0, 0, 0, 0.32),
  );

  // ---------- Persistence ----------
  static const String saveKeyUnlocked = "shadow_jumper_unlocked_v1";
  static const String saveKeySettings = "shadow_jumper_settings_v1";
  static const String saveKeyCurrentLevel = "shadow_jumper_current_level_v1";

  int unlocked = 1;

  // ---------- Settings ----------
  GameSettings settings = const GameSettings();

  // ---------- Game state ----------
  GameState state = GameState.pause;
  int deaths = 0;
  int levelIndex = 0; // 0-based
  double exposure = 0.0;
  RetryMode retryMode = RetryMode.safe;

  bool helpHidden = false;

  // ---------- Runtime / world ----------
  Size viewSize = const Size(800, 600);

  Level? level;
  List<RectD> solids = [];
  List<RectD> casters = [];
  List<List<Vec2>> shadowPolys = [];
  RectD goal = const RectD(0, 0, 0, 0);
  Light light = Light.zero();

  // Camera in world coords
  final Vec2 cam = Vec2(0, 0);

  // Player
  final Player player = Player(
    x: 0,
    y: 0,
    w: 26,
    h: 48,
    vx: 0,
    vy: 0,
  );

  // ---------- Enemies ----------
  final math.Random _rng = math.Random();
  final List<Enemy> enemies = [];

  // Leech effect accumulator (set in _updateEnemies, consumed in _updateExposure)
  double _leechExtraExposurePerSec = 0.0;

  // ---------- Double Jump ----------
  bool _doubleJumpAvailable = true;

  // ---------- Audio (BGM) ----------
  final AudioPlayer _bgm = AudioPlayer();
  bool _bgmReady = false;

  // ---------- Loop ----------
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _acc = 0.0;
  static const double fixed = 1 / 60;
  static const double maxAcc = 0.20;

  // For painter animations
  double _timeSec = 0.0;

  // ---------- Input ----------
  final FocusNode _focusNode = FocusNode(debugLabel: "shadow_jumper_focus");
  final Map<LogicalKeyboardKey, bool> _keys = {};
  final Map<LogicalKeyboardKey, bool> _pressed = {};

  // Touch buttons (hold)
  bool tLeft = false;
  bool tRight = false;
  bool tJumpHeld = false;
  bool tJumpPressedEdge = false;

  bool _winScheduled = false;

  bool get isTouchPlatform {
    final p = defaultTargetPlatform;
    return (p == TargetPlatform.android || p == TargetPlatform.iOS);
  }

  bool get showTouchUI => settings.touchControlsEnabled && isTouchPlatform;

  // Banner overlay
  BannerModel? banner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bootstrap();

    // Start scary music (loop). On web, autoplay may be blocked until user interaction.
    scheduleMicrotask(() async {
      try {
        await _bgm.setReleaseMode(ReleaseMode.loop);
        await _bgm.play(
          AssetSource('audio/scary.mp3'),
          volume: 0.65,
        );
        _bgmReady = true;
      } catch (_) {
        _bgmReady = false;
      }
    });

    _ticker = createTicker(_onTick)..start();

    // Ensure desktop focus reliably.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focusNode.hasFocus) _focusNode.requestFocus();
    });
  }

  Future<void> _bootstrap() async {
    await _loadUnlocked();
    await _loadSettings();

    retryMode = settings.retryMode;

    final resume = await _loadCurrentLevel();
    _loadLevel(resume);

    _showStartBanner();

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focusNode.dispose();
    _bgm.dispose();
    super.dispose();
  }

  // Pause & clear keys on lifecycle changes (prevents "stuck key")
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.inactive ||
        appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.detached) {
      _clearInput();
      if (state == GameState.run) _togglePause(forcePause: true);
    }
  }

  void _clearInput() {
    _keys.clear();
    _pressed.clear();
    tLeft = false;
    tRight = false;
    tJumpHeld = false;
    tJumpPressedEdge = false;
  }

  Future<void> _loadUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(saveKeyUnlocked) ?? 1;
    unlocked = clampInt(v, 1, TOTAL_LEVELS);
  }

  Future<void> _saveUnlocked(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(saveKeyUnlocked, clampInt(v, 1, TOTAL_LEVELS));
  }

  Future<int> _loadCurrentLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(saveKeyCurrentLevel);
    final maxPlayable = math.max(0, unlocked - 1);
    return clampInt(v ?? 0, 0, maxPlayable);
  }

  Future<void> _saveCurrentLevel(int index0) async {
    final prefs = await SharedPreferences.getInstance();
    final v = clampInt(index0, 0, TOTAL_LEVELS - 1);
    await prefs.setInt(saveKeyCurrentLevel, v);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(saveKeySettings);
    if (raw == null || raw.isEmpty) return;

    // Format: "touch=1;hint=0;retry=fast"
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) map[kv[0].trim()] = kv[1].trim();
    }

    settings = settings.copyWith(
      touchControlsEnabled: (map['touch'] ?? '1') == '1',
      showHudHint: (map['hint'] ?? '1') == '1',
      retryMode: (map['retry'] ?? 'safe') == 'fast' ? RetryMode.fast : RetryMode.safe,
    );

    retryMode = settings.retryMode;
    helpHidden = !settings.showHudHint;
  }

  Future<void> _saveSettings(GameSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        "touch=${s.touchControlsEnabled ? 1 : 0};hint=${s.showHudHint ? 1 : 0};retry=${s.retryMode == RetryMode.fast ? 'fast' : 'safe'}";
    await prefs.setString(saveKeySettings, raw);
  }

  // ---------- Tick loop ----------
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final frameDt = clampDouble(dt, 0, 0.05);
    _acc = clampDouble(_acc + frameDt, 0, maxAcc);

    _timeSec = elapsed.inMicroseconds / 1e6;

    _updateLight(_timeSec);
    _rebuildShadows();

    while (_acc >= fixed) {
      // Global hotkeys (desktop)
      if (_consumePressed(LogicalKeyboardKey.keyP)) _togglePause();
      if (_consumePressed(LogicalKeyboardKey.keyF)) _toggleRetryMode();
      if (_consumePressed(LogicalKeyboardKey.keyR)) _restartLevel();

      if (_consumePressed(LogicalKeyboardKey.escape)) {
        if (state == GameState.run) _togglePause();
        else if (state == GameState.pause) _togglePause();
      }

      if (_consumePressed(LogicalKeyboardKey.keyO)) {
        if (state == GameState.run) _togglePause(forcePause: true);
        _openOptions();
      }

      if (_consumePressed(LogicalKeyboardKey.keyN) && state == GameState.win) {
        _nextLevel();
      }

      _handleQuickJumpKeys();

      if (state == GameState.run) {
        _updatePlayer(fixed);
        _updateEnemies(fixed);   // sets _leechExtraExposurePerSec
        _updateExposure(fixed);  // consumes _leechExtraExposurePerSec
        _checkWin();
      }

      _updateCamera(fixed);
      _acc -= fixed;
    }

    if (mounted) setState(() {});
  }

  // ---------- UI helpers ----------
  void _hideHelpOnce() {
    if (helpHidden) return;
    helpHidden = true;
  }

  void _showBanner(BannerModel b) => banner = b;
  void _hideBanner() => banner = null;

  void _showStartBanner() {
    state = GameState.pause;
    _showBanner(
      BannerModel(
        title: "SHADOW JUMPER",
        body: "Reach the goal while staying in the shadow.",
        hint: "Unlocked: $unlocked / $TOTAL_LEVELS",
        buttons: [
          BannerButton(
            label: "Play",
            onTap: () async {
              state = GameState.run;
              _hideBanner();
              _hideHelpOnce();

              // Resume/try BGM (web autoplay workaround)
              if (_bgmReady) {
                _bgm.resume();
              } else {
                scheduleMicrotask(() async {
                  try {
                    await _bgm.setReleaseMode(ReleaseMode.loop);
                    await _bgm.play(
                      AssetSource('audio/scary.mp3'),
                      volume: 0.65,
                    );
                    _bgmReady = true;
                  } catch (_) {}
                });
              }

              await _saveCurrentLevel(levelIndex);
              if (mounted) setState(() {});
            },
          ),
          BannerButton(label: "Options", onTap: _openOptions),
          BannerButton(label: "Restart", onTap: _restartLevel),
        ],
      ),
    );
  }

  void _showPauseBanner() {
    state = GameState.pause;
    _showBanner(
      BannerModel(
        title: "PAUSED",
        body: "Tap Play to resume.",
        hint: "",
        buttons: [
          BannerButton(
            label: "Play",
            onTap: () async {
              state = GameState.run;
              _hideBanner();
              _hideHelpOnce();
              if (_bgmReady) _bgm.resume();
              await _saveCurrentLevel(levelIndex);
              if (mounted) setState(() {});
            },
          ),
          BannerButton(label: "Options", onTap: _openOptions),
          BannerButton(label: "Restart", onTap: _restartLevel),
        ],
      ),
    );
  }

  void _openOptions() {
    state = GameState.pause;
    _showBanner(
      BannerModel(
        title: "OPTIONS",
        body: "",
        bodyWidget: OptionsPanel(
          settings: settings,
          unlocked: unlocked,
          totalLevels: TOTAL_LEVELS,
          retryMode: retryMode,
          onChanged: (next) async {
            settings = next;
            retryMode = settings.retryMode;
            helpHidden = !settings.showHudHint;
            await _saveSettings(settings);
            if (mounted) setState(() {});
          },
        ),
        hint:
        "Keys: P pause · O options · R restart · F retry mode · A/D or Left/Right move · Space jump",
        buttons: [
          BannerButton(
            label: "Close",
            onTap: _showPauseBanner,
          ),
        ],
      ),
    );
    setState(() {});
  }

  // ---------- Input ----------
  void _onKey(RawKeyEvent e) {
    final key = e.logicalKey;
    if (e is RawKeyDownEvent) {
      if ((_keys[key] ?? false) == false) _pressed[key] = true; // edge
      _keys[key] = true;
    } else if (e is RawKeyUpEvent) {
      _keys[key] = false;
    }
  }

  bool _isDown(LogicalKeyboardKey k) => _keys[k] ?? false;

  bool _consumePressed(LogicalKeyboardKey k) {
    final v = _pressed[k] ?? false;
    _pressed[k] = false;
    return v;
  }

  int _quickIndexForKey(LogicalKeyboardKey k) {
    final order = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.equal,
    ];
    return order.indexOf(k);
  }

  void _handleQuickJumpKeys() {
    for (final entry in _pressed.entries.toList()) {
      if (entry.value != true) continue;
      final idx = _quickIndexForKey(entry.key);
      if (idx != -1) {
        _pressed[entry.key] = false;
        _tryJumpToLevel(idx);
      }
    }
  }

  bool _left() =>
      _isDown(LogicalKeyboardKey.arrowLeft) ||
          _isDown(LogicalKeyboardKey.keyA) ||
          tLeft;

  bool _right() =>
      _isDown(LogicalKeyboardKey.arrowRight) ||
          _isDown(LogicalKeyboardKey.keyD) ||
          tRight;

  bool _jumpHeld() =>
      _isDown(LogicalKeyboardKey.arrowUp) ||
          _isDown(LogicalKeyboardKey.keyW) ||
          _isDown(LogicalKeyboardKey.space) ||
          tJumpHeld;

  bool _jumpPressed() {
    final k = _consumePressed(LogicalKeyboardKey.arrowUp) ||
        _consumePressed(LogicalKeyboardKey.keyW) ||
        _consumePressed(LogicalKeyboardKey.space);
    final t = tJumpPressedEdge;
    tJumpPressedEdge = false;
    return k || t;
  }

  // ---------- Level control ----------
  void _loadLevel(int index0) {
    levelIndex = clampInt(index0, 0, TOTAL_LEVELS - 1);

    level = generateLevel(
      levelIndex,
      playerH: player.h,
      jumpVel: phys.jumpVel,
      gravity: phys.gravity,
    );

    solids = level!.solids.map((r) => r.copy()).toList();
    casters = solids;
    goal = level!.goal.copy();

    light = Light(
      x: level!.light.orbit.cx,
      y: level!.light.orbit.cy,
      radius: level!.light.radius,
      orbit: level!.light.orbit.copy(),
    );

    player.x = level!.start.x;
    player.y = level!.start.y;
    player.vx = 0;
    player.vy = 0;
    player.grounded = false;
    player.coyoteT = 0;
    player.jumpBufT = 0;
    player.jumpWasHeld = false;

    _doubleJumpAvailable = true;
    _leechExtraExposurePerSec = 0.0;

    _winScheduled = false;

    // Resolve overlap
    for (int k = 0; k < 20; k++) {
      final pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
      bool hit = false;
      for (final s in solids) {
        if (rectsOverlap(pr, s)) {
          hit = true;
          break;
        }
      }
      if (!hit) break;
      player.y -= 20;
    }

    exposure = 0.0;

    enemies.clear();
    _spawnEnemiesForLevel();

    state = GameState.run;
    _hideBanner();
    _saveCurrentLevel(levelIndex);
  }

  void _restartLevel() => _loadLevel(levelIndex);

  void _nextLevel() {
    final next = clampInt(levelIndex + 1, 0, TOTAL_LEVELS - 1);
    _loadLevel(next);
  }

  Future<void> _winLevel() async {
    if (!mounted) return;
    if (state == GameState.win) return;

    state = GameState.win;

    final newUnlocked = math.max(unlocked, levelIndex + 2);
    if (newUnlocked != unlocked) {
      unlocked = clampInt(newUnlocked, 1, TOTAL_LEVELS);
      await _saveUnlocked(unlocked);
    }

    final resumeIdx = clampInt(levelIndex + 1, 0, math.max(0, unlocked - 1));
    await _saveCurrentLevel(resumeIdx);

    _showBanner(
      BannerModel(
        title: "LEVEL CLEAR",
        body: "Next level unlocked.",
        hint: "Unlocked: $unlocked / $TOTAL_LEVELS",
        buttons: [
          BannerButton(label: "Next", onTap: _nextLevel),
          BannerButton(label: "Replay", onTap: _restartLevel),
          BannerButton(label: "Options", onTap: _openOptions),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  void _killPlayer(String reason) {
    if (state != GameState.run) return;

    state = GameState.lose;
    deaths += 1;

    if (retryMode == RetryMode.fast) {
      _loadLevel(levelIndex);
      return;
    }

    _showBanner(
      BannerModel(
        title: "YOU DIED",
        body: reason,
        hint: "Tip: stay behind blockers — shadows are safe (unless a leech is near).",
        buttons: [
          BannerButton(label: "Retry", onTap: _restartLevel),
          BannerButton(label: "Options", onTap: _openOptions),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  void _togglePause({bool forcePause = false}) {
    if (forcePause) {
      if (state == GameState.run) _showPauseBanner();
      if (_bgmReady) _bgm.pause();
      return;
    }

    if (state == GameState.pause) {
      state = GameState.run;
      _hideBanner();
      _hideHelpOnce();
      _saveCurrentLevel(levelIndex);
      if (_bgmReady) _bgm.resume();
      setState(() {});
    } else if (state == GameState.run) {
      _showPauseBanner();
      if (_bgmReady) _bgm.pause();
      setState(() {});
    }
  }

  void _toggleRetryMode() {
    retryMode = (retryMode == RetryMode.safe) ? RetryMode.fast : RetryMode.safe;
    settings = settings.copyWith(retryMode: retryMode);
    _saveSettings(settings);
    if (mounted) setState(() {});
  }

  void _tryJumpToLevel(int slotIndex) {
    if (state == GameState.pause) return;

    final page = _isDown(LogicalKeyboardKey.shiftLeft) || _isDown(LogicalKeyboardKey.shiftRight)
        ? 1
        : 0;
    final base = page * 12;
    final targetLevel = base + slotIndex + 1; // 1-based
    if (targetLevel <= unlocked) _loadLevel(targetLevel - 1);
  }

  // ---------- Light update ----------
  void _updateLight(double timeSec) {
    final o = light.orbit;
    final a = timeSec * o.speed + o.phase;
    light.x = o.cx + math.cos(a) * o.rx;
    light.y = o.cy + math.sin(a * 0.93) * o.ry;
  }

  // ---------- Shadows ----------
  List<Vec2> _getShadowPoly(RectD rect, Vec2 lightPos) {
    final corners = <Vec2>[
      Vec2(rect.x, rect.y),
      Vec2(rect.x + rect.w, rect.y),
      Vec2(rect.x + rect.w, rect.y + rect.h),
      Vec2(rect.x, rect.y + rect.h),
    ];
    const far = 2600.0;
    final projected = corners.map((c) {
      final ang = math.atan2(c.y - lightPos.y, c.x - lightPos.x);
      return Vec2(c.x + math.cos(ang) * far, c.y + math.sin(ang) * far);
    }).toList();

    return [
      corners[0],
      corners[1],
      corners[2],
      corners[3],
      projected[3],
      projected[2],
      projected[1],
      projected[0],
    ];
  }

  void _rebuildShadows() {
    if (level == null) return;
    shadowPolys = casters.map((s) => _getShadowPoly(s, Vec2(light.x, light.y))).toList();
  }

  bool _playerInShadow() {
    final pts = <Vec2>[
      Vec2(player.x + player.w * 0.5, player.y + player.h * 0.25),
      Vec2(player.x + player.w * 0.5, player.y + player.h * 0.65),
      Vec2(player.x + player.w * 0.5, player.y + player.h * 0.98),
    ];
    for (final poly in shadowPolys) {
      for (final p in pts) {
        if (pointInPoly(p, poly)) return true;
      }
    }
    return false;
  }

  // ---------- Enemy spawning ----------
  void _spawnEnemiesForLevel() {
    if (level == null) return;
    if (solids.isEmpty) return;

    final plats = solids.where((s) => s.w >= 140 && s.h >= 18).toList();
    if (plats.isEmpty) return;

    // 1) Light Seeker
    final p1 = plats[_rng.nextInt(plats.length)];
    enemies.add(_makeLightSeekerOnPlatform(p1));

    // 2) Shadow Leech
    final p2 = plats[_rng.nextInt(plats.length)];
    enemies.add(_makeShadowLeechNearPlatform(p2));

    // 3) Falling Stalker
    final p3 = plats[_rng.nextInt(plats.length)];
    enemies.add(_makeFallingStalkerAbovePlatform(p3));
  }

  Enemy _makeLightSeekerOnPlatform(RectD plat) {
    const w = 26.0, h = 34.0;
    final e = Enemy(
      type: EnemyType.lightSeeker,
      x: plat.x + 18.0,
      y: plat.y - h,
      w: w,
      h: h,

    );

    e.minX = plat.x + 8.0;
    e.maxX = plat.x + plat.w - 8.0 - w;
    e.vx = 90.0;
    e.chasing = false;
    return e;
  }

  Enemy _makeShadowLeechNearPlatform(RectD plat) {
    const w = 28.0, h = 28.0;

    final x = (plat.x + plat.w * (0.25 + _rng.nextDouble() * 0.5)).toDouble();
    final y = (plat.y - h - 6.0).toDouble();

    final e = Enemy(
      type: EnemyType.shadowLeech,
      x: x,
      y: y,
      w: w,
      h: h,

    );

    e.leechRadius = 95.0;
    e.leechDrainPerSec = 0.60;
    e.knockCooldown = 0.0;
    return e;
  }

  Enemy _makeFallingStalkerAbovePlatform(RectD plat) {
    const w = 26.0, h = 34.0;

    final double x = (plat.x + plat.w * (0.2 + _rng.nextDouble() * 0.6)).toDouble();
    final double homeY = math.max(0.0, plat.y - 240.0).toDouble();

    final e = Enemy(
      type: EnemyType.fallingStalker,
      x: x,
      y: homeY,
      w: w,
      h: h,
    );

    e.homeX = x;
    e.homeY = homeY;
    e.armed = true;
    e.dropping = false;
    e.resetT = 0.0;
    return e;
  }

  // ---------- Enemy updates ----------
  void _updateEnemies(double dt) {
    if (level == null) return;

    _leechExtraExposurePerSec = 0.0;

    final pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());

    for (final e in enemies) {
      switch (e.type) {
        case EnemyType.lightSeeker:
          _updateLightSeeker(e, dt, pr);
          break;
        case EnemyType.shadowLeech:
          _updateShadowLeech(e, dt, pr);
          break;
        case EnemyType.fallingStalker:
          _updateFallingStalker(e, dt, pr);
          break;
      }
    }
  }

  void _updateLightSeeker(Enemy e, double dt, RectD pr) {
    final dx = (player.x - e.x).abs();
    final dy = (player.y - e.y).abs();

    // once triggered, chase forever
    if (!e.chasing && dx < 220.0 && dy < 140.0) {
      e.chasing = true;
    }

    const patrolSpeed = 90.0;
    const chaseSpeed = 170.0;

    if (!e.chasing) {
      if (e.vx == 0) e.vx = patrolSpeed;
      e.x += e.vx * dt;

      if (e.x < e.minX) {
        e.x = e.minX;
        e.vx = patrolSpeed;
      }
      if (e.x > e.maxX) {
        e.x = e.maxX;
        e.vx = -patrolSpeed;
      }
    } else {
      final dir = (player.x + player.w / 2) > (e.x + e.w / 2) ? 1.0 : -1.0;
      e.vx = dir * chaseSpeed;
      e.x += e.vx * dt;
    }

    if (rectsOverlap(pr, e.rect)) {
      _killPlayer("The Light Seeker caught you.");
    }
  }

  void _updateShadowLeech(Enemy e, double dt, RectD pr) {
    e.knockCooldown = math.max(0.0, e.knockCooldown - dt);

    final cx = e.x + e.w / 2.0;
    final cy = e.y + e.h / 2.0;
    final px = player.x + player.w / 2.0;
    final py = player.y + player.h / 2.0;

    final dist = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
    if (dist <= e.leechRadius) {
      _leechExtraExposurePerSec = math.max(_leechExtraExposurePerSec, e.leechDrainPerSec);
    }

    // contact knockback
    if (rectsOverlap(pr, e.rect) && e.knockCooldown <= 0.0) {
      final dir = (px > cx) ? 1.0 : -1.0;
      player.vx += dir * 520.0;
      player.vy = -260.0;
      e.knockCooldown = 0.45;
    }
  }

  void _updateFallingStalker(Enemy e, double dt, RectD pr) {
    if (!e.armed) {
      e.resetT -= dt;
      if (e.resetT <= 0.0) {
        e.armed = true;
        e.dropping = false;
        e.x = e.homeX;
        e.y = e.homeY;
        e.vx = 0.0;
        e.vy = 0.0;
      }
      return;
    }

    final px = player.x + player.w / 2.0;
    final ex = e.x + e.w / 2.0;

    // trigger when player passes under its x-range
    if (!e.dropping && (px - ex).abs() < 55.0 && player.y > e.y) {
      e.dropping = true;
      e.vy = 0.0;
    }

    if (e.dropping) {
      e.vy += 2800.0 * dt;
      e.y += e.vy * dt;

      // hit a platform -> "land" then reset later
      final er = e.rect;
      for (final s in solids) {
        if (rectsOverlap(er, s)) {
          e.y = s.y - e.h;
          e.vy = 0.0;
          e.armed = false;
          e.resetT = 1.2;
          break;
        }
      }

      // hit player -> kill
      if (rectsOverlap(pr, e.rect)) {
        _killPlayer("A Falling Stalker crushed you.");
      }

      // safety reset if it falls out of world
      if (level != null && e.y > level!.world.h + 400.0) {
        e.armed = false;
        e.resetT = 0.6;
      }
    }
  }

  // ---------- Exposure ----------
  void _updateExposure(double dt) {
    final inShadow = _playerInShadow();

    if (inShadow) {
      exposure -= exposureCfg.losePerSec * dt;
      // leech makes shadow unsafe in its radius
      exposure += _leechExtraExposurePerSec * dt;
    } else {
      exposure += exposureCfg.gainPerSec * dt;
    }

    exposure = clampDouble(exposure, 0, 1);

    if (exposure >= exposureCfg.failAt) {
      _killPlayer("You stayed in the light too long.");
    }
  }

  // ---------- Win ----------
  void _checkWin() {
    if (_winScheduled) return;
    final pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
    if (rectsOverlap(pr, goal)) {
      _winScheduled = true;
      scheduleMicrotask(() async {
        _winScheduled = false;
        if (state == GameState.run) await _winLevel();
      });
    }
  }

  // ---------- Collision ----------
  void _moveAndCollide(double dx, double dy) {
    final steps = math.max(1, ((dx.abs() + dy.abs()) / 18).ceil());
    final sx = dx / steps;
    final sy = dy / steps;

    for (int i = 0; i < steps; i++) {
      // X
      player.x += sx;
      var pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
      for (final s in solids) {
        if (!rectsOverlap(pr, s)) continue;
        if (sx > 0) {
          player.x = s.x - player.w;
        } else if (sx < 0) {
          player.x = s.x + s.w;
        }
        player.vx = 0.0;
        pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
      }

      // Y
      player.y += sy;
      pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
      for (final s in solids) {
        if (!rectsOverlap(pr, s)) continue;
        if (sy > 0) {
          player.y = s.y - player.h;
          player.vy = 0.0;
          player.grounded = true;
        } else if (sy < 0) {
          player.y = s.y + s.h;
          player.vy = 0.0;
        }
        pr = RectD(player.x, player.y, player.w.toDouble(), player.h.toDouble());
      }
    }
  }

  // ---------- Player update ----------
  void _updatePlayer(double dt) {
    final wasGrounded = player.grounded;

    player.coyoteT = math.max(0.0, player.coyoteT - dt);
    player.jumpBufT = math.max(0.0, player.jumpBufT - dt);

    final jHeld = _jumpHeld();
    final jPressed = _jumpPressed();
    final jReleased = player.jumpWasHeld && !jHeld;
    player.jumpWasHeld = jHeld;

    if (jPressed) {
      player.jumpBufT = phys.jumpBuffer;
      if (state == GameState.run) _hideHelpOnce();
    }

    final move = (_left() ? -1 : 0) + (_right() ? 1 : 0);
    if (move != 0 && state == GameState.run) _hideHelpOnce();

    final accel = wasGrounded ? phys.runAccel : phys.airAccel;
    player.vx += move * accel * dt;
    player.vx = clampDouble(player.vx, -phys.maxRun, phys.maxRun);

    if (move == 0) {
      player.vx *= wasGrounded ? phys.groundFriction : phys.airFriction;
      if (player.vx.abs() < 2) player.vx = 0.0;
    }

    player.vy += phys.gravity * dt;
    player.vy = math.min(player.vy, phys.maxFall);

    player.grounded = false;
    _moveAndCollide(player.vx * dt, player.vy * dt);

    if (player.grounded) {
      player.coyoteT = phys.coyote;
      _doubleJumpAvailable = true; // reset on landing
    }

    final baseJumpVel = phys.jumpVel;
    final doubleJumpVel = phys.jumpVel * 1.05;

    // First jump (ground/coyote)
    if (player.jumpBufT > 0 && (player.grounded || player.coyoteT > 0)) {
      player.vy = -baseJumpVel;
      player.jumpBufT = 0.0;
      player.coyoteT = 0.0;
      player.grounded = false;

      // after takeoff, you get exactly one mid-air jump
      _doubleJumpAvailable = true;
    }

    // Double jump (once per airtime)
    if (player.jumpBufT > 0 &&
        !player.grounded &&
        player.coyoteT <= 0.0 &&
        _doubleJumpAvailable) {
      player.vy = -doubleJumpVel;
      player.jumpBufT = 0.0;
      _doubleJumpAvailable = false;
    }

    if (jReleased && player.vy < 0) player.vy *= phys.jumpCut;

    // Falling death
    if (level != null && player.y > level!.world.h + 520) {
      _killPlayer("You fell.");
    }

    if (level != null) {
      player.x = clampDouble(player.x, -260, level!.world.w + 260);
    }
  }

  // ---------- Camera ----------
  void _updateCamera(double dt) {
    final viewW = viewSize.width;
    final viewH = viewSize.height;

    final look = clampDouble(player.vx / phys.maxRun, -1, 1) * cameraCfg.lookAhead;
    final targetX = player.x + player.w / 2 - viewW / 2 + look;
    final targetY = player.y + player.h / 2 - viewH / 2 + cameraCfg.yBias;

    final t = 1.0 - math.pow(1.0 - cameraCfg.smooth, dt * 60).toDouble();
    cam.x = lerp(cam.x, targetX, t);
    cam.y = lerp(cam.y, targetY, t);

    if (level != null) {
      cam.x = clampDouble(cam.x, 0, math.max(0, level!.world.w - viewW));
      cam.y = clampDouble(cam.y, 0, math.max(0, level!.world.h - viewH));
    }
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    // Give HUD a bounded width (prevents unconstrained flex/layout issues)
    final hudWidth = clampDouble(MediaQuery.of(context).size.width * 0.36, 190, 280);

    return LayoutBuilder(
      builder: (context, constraints) {
        viewSize = Size(constraints.maxWidth, constraints.maxHeight);

        return RawKeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKey: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              if (!_focusNode.hasFocus) _focusNode.requestFocus();

              // Web autoplay workaround (try start BGM on first user gesture)
              if (!_bgmReady) {
                scheduleMicrotask(() async {
                  try {
                    await _bgm.setReleaseMode(ReleaseMode.loop);
                    await _bgm.play(
                      AssetSource('audio/scary.mp3'),
                      volume: 0.65,
                    );
                    _bgmReady = true;
                  } catch (_) {}
                });
              }
            },
            // Optional: tap to jump buffer if touch UI disabled
            onTap: () {
              if (isTouchPlatform && !showTouchUI && state == GameState.run) {
                player.jumpBufT = phys.jumpBuffer;
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GamePainter(
                      viewSize: viewSize,
                      cam: cam,
                      level: level,
                      solids: solids,
                      shadowPolys: shadowPolys,
                      goal: goal,
                      player: player,
                      playerInShadow: _playerInShadow(),
                      light: light,
                      exposure: exposure,
                      state: state,
                      colors: colors,
                      phys: phys,

                      enemies: enemies,
                      timeSec: _timeSec,
                    ),
                  ),
                ),

                // HUD
                Positioned(
                  left: 12,
                  top: 12 + topPad,
                  child: SizedBox(
                    width: hudWidth,
                    child: HudMini(
                      levelNum: level?.num ?? 1,
                      totalLevels: TOTAL_LEVELS,
                      deaths: deaths,
                      exposure: exposure,
                      showHint: !helpHidden && settings.showHudHint,
                    ),
                  ),
                ),

                // Pause + Options
                Positioned(
                  right: 12,
                  top: 12 + topPad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PauseButton(onTap: _togglePause),
                      const SizedBox(height: 10),
                      SquareIconButton(
                        tooltip: "Options",
                        onTap: () {
                          if (state == GameState.run) _togglePause(forcePause: true);
                          _openOptions();
                        },
                        child: const Icon(Icons.tune, size: 20),
                      ),
                    ],
                  ),
                ),

                // Touch controls
                if (showTouchUI)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(14, 14, 14, 14 + botPad),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              TouchBtn(
                                label: "←",
                                onDown: () => setState(() => tLeft = true),
                                onUp: () => setState(() => tLeft = false),
                              ),
                              const SizedBox(width: 12),
                              TouchBtn(
                                label: "→",
                                onDown: () => setState(() => tRight = true),
                                onUp: () => setState(() => tRight = false),
                              ),
                            ],
                          ),
                          TouchBtn(
                            label: "↑",
                            big: true,
                            onDown: () => setState(() {
                              tJumpHeld = true;
                              tJumpPressedEdge = true;
                            }),
                            onUp: () => setState(() => tJumpHeld = false),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Banner overlay
                if (banner != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.60),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.52),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.55),
                                blurRadius: 40,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                banner!.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (banner!.bodyWidget != null) ...[
                                banner!.bodyWidget!,
                              ] else ...[
                                Text(
                                  banner!.body,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14, height: 1.45),
                                ),
                              ],
                              if (banner!.buttons.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: banner!.buttons
                                      .map<Widget>((b) => _BannerBtn(label: b.label, onTap: b.onTap))
                                      .toList(),
                                ),
                              ],
                              if (banner!.hint.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  banner!.hint,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Desktop ad banner (Windows only)
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 90,
                      child: DesktopAdBanner(height: 90),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BannerBtn extends StatelessWidget {
  const _BannerBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}