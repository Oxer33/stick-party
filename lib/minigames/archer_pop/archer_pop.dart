import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'archer_fx.dart';
import 'archer_render.dart';

/// Target Range — precision archery. (Keeps the legacy `archer_pop` id; the old
/// "auto-sweep + tap to fire" balloon spam is gone.)
///
/// OBJECTIVE (obvious from the scene + HUD): score the MOST points by hitting
/// TARGET balloons before your LIMITED QUIVER ([_quiver] arrows) runs dry or the
/// round ends. Ammo + score + a "HIT TARGETS / AVOID BOMBS" objective sit over
/// every player so the goal is unmistakable. Every arrow must count.
///
/// CORE — one-touch, you AIM each shot (no auto-aim, no sweep):
///  * **DRAG to aim, RELEASE to loose.** Press in your zone and drag BACK like a
///    slingshot: the pull *direction* sets the launch angle (you loose opposite
///    the pull) and the pull *length* sets the power. A live trajectory + power
///    gauge preview the arc while you hold. Release looses a gravity-arced arrow.
///  * **A bare tap looses NOTHING.** A press-release with (almost) no drag is
///    below [_minPower] — the bow simply relaxes, no arrow spent. You cannot
///    clear a target by incidentally tapping; you must deliberately draw + aim.
///    And an arrow only scores by physically *colliding* with a target — nothing
///    is snapped onto a balloon for you.
///
/// INTERPOSING DIFFICULTY (genuinely resists a spammer):
///  * **Targets MOVE** — every balloon drifts + bobs, and a crosswind pushes
///    arrows in flight (a top banner telegraphs it) so you must lead the shot.
///  * **BARRIERS** — some targets sit behind a solid wall; a flat shot is eaten
///    by the wall, you must ARC the arrow up and over.
///  * **BOMB decoys (black)** — hitting one SUBTRACTS points, so loosing in a
///    random direction is punished, not free.
///  * **GOLD targets** — worth a burst of points but small + short-lived, so the
///    big score goes to whoever aims fast + precisely.
///  * **Calibrated ramp** — targets get faster + smaller and bombs more common
///    as the quiver drains, so the back half is a real test.
///
/// A blind spammer looses arrows in random directions: it burns the whole quiver
/// fast, sails most shots wide, and splatters bombs for NEGATIVE points — it
/// scores low/negative. A player who aims, prioritizes gold, avoids bombs and
/// conserves ammo scores high. (Proven by a deterministic test.)
///
/// BOTS: aim by SOLVING a launch angle + power onto the best live target (gold
/// first, never a bomb on purpose) then perturbing it by a [BotProfile] accuracy
/// error — easy bots scatter wide, waste arrows and clip bombs; hard bots place
/// arrows on gold. A real, beatable 1+CPU contest. Always finishes (ammo-out or
/// the time limit) and never throws for 1..4 players.
class ArcherPop extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'archer_pop',
        name: 'Target Range',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'DRAG',
      );

  // ── Round / scoring tuning (no magic numbers inline) ────────────────────────
  // Hard ceiling; the round usually ends when every quiver is empty (~25-40s of
  // deliberate shooting), the timer only bites if players sit on their ammo.
  static const double _timeLimit = 40;
  static const int _quiver = 14; // arrows per player — the scarce resource
  static const int _plainPoints = 2; // points for a plain target
  static const int _goldPoints = 6; // points for the small/brief gold target
  static const int _bombPenalty = 3; // points SUBTRACTED for hitting a bomb
  static const double _comboWindowSec = 2.2; // hits within this keep the combo
  static const int _maxCombo = 5; // multiplier cap

  // ── Ballistics tuning ───────────────────────────────────────────────────────
  static const double _gravity = 320; // px/s^2 on arrows (a readable arc)
  static const double _speedMin = 360; // launch px/s at minimum usable power
  static const double _speedMax = 980; // launch px/s at full draw
  static const double _arrowLife = 3.6; // seconds before an arrow fizzles
  static const int _trailSamples = 10; // trail points kept per arrow
  static const double _outOfBoundsPad = 90;
  static const double _stuckLifeSec = 0.45; // ground/edge stick fade
  static const double _burstSec = 0.28; // target pop animation length

  // ── Aim / drag tuning ───────────────────────────────────────────────────────
  static const double _baseScaleRef = 520; // arena minSide → scale 1
  static const double _figureScale = 1.7; // readable archer bodies
  static const double _edgeInsetFactor = 0.10; // edge inset / min(arena side)
  static const double _muzzleReach = 26; // bow-hand → arrow spawn (× scale)
  static const double _looseFadeSec = 0.18; // loose-flash decay
  // Drag distance (fraction of min arena side) that maps to FULL power; a longer
  // pull past this is clamped. Short enough that a real draw is easy on a phone.
  static const double _maxDragFrac = 0.28;
  // The anti-incidental-clear gate: a release whose power is below this is NOT a
  // shot — a bare tap / micro-drag relaxes the bow and spends no arrow.
  static const double _minPower = 0.16;

  // ── Target field tuning ─────────────────────────────────────────────────────
  static const double _spawnEvery = 0.85; // seconds between spawns
  static const int _maxTargets = 7;
  static const int _initialTargets = 4; // seeded so the field reads instantly
  static const double _driftMin = 18; // px/s base lateral drift
  static const double _driftMax = 42;
  static const double _riseMin = 10; // gentle vertical wander
  static const double _riseMax = 30;
  static const double _windShareOnTarget = 0.18; // wind drift on targets
  static const double _bobRate = 2.0; // sway rad/s
  static const double _bobSway = 9; // px lateral sway amplitude rate
  static const double _radiusPlainMin = 20;
  static const double _radiusPlainMax = 30;
  static const double _radiusGold = 15; // gold = small + hard
  static const double _radiusBomb = 24;
  static const double _goldLifeSec = 3.4; // gold self-pops (brief) if not hit
  static const double _bombChanceBase = 0.16; // bomb share early
  static const double _bombChanceMax = 0.34; // bomb share late (ramp)
  static const double _goldChanceBase = 0.10; // gold share early
  static const double _goldChanceMax = 0.18; // gold share late (ramp)
  static const double _shieldChance = 0.32; // a (non-gold) target is shielded
  static const double _fieldTopFrac = 0.20; // targets live below this (× h)
  static const double _fieldBottomFrac = 0.66; // …and above this (× h)
  static const double _sparkleRate = 3.0; // gold glint spin rad/s

  // ── Barrier tuning ──────────────────────────────────────────────────────────
  // A shielded target gets a solid wall on the field side facing the NEAREST
  // archer, so a flat line is blocked and the shot must be arced over it.
  static const double _barrierW = 84; // wall width (× scale)
  static const double _barrierH = 16; // wall thickness (× scale)
  static const double _barrierGap = 30; // wall sits this far toward the shooter

  // ── Wind tuning ─────────────────────────────────────────────────────────────
  static const double _windMax = 64; // peak crosswind px/s
  static const double _windChangeSec = 4.0;
  static const double _windEaseRate = 2.0;
  static const int _windStreakCount = 22;

  // ── Difficulty ramp ───────────────────────────────────────────────────────-
  // The round's challenge scales with how much of the (shared) quiver has been
  // spent: targets speed up + shrink, bombs + gold grow more common. 0 → 1.
  static const double _rampDriftMul = 0.7; // +70% drift at full ramp
  static const double _rampShrink = 0.78; // ×radius at full ramp
  static const double _rampSpawnMul = 0.7; // spawn interval × this at full ramp

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botAimErrorRad = 0.5; // steady angular error at acc 0
  static const double _botFlinchRad = 0.22; // fresh per-shot angular flinch
  static const double _botPowerError = 0.32; // power error at accuracy 0
  static const double _botArcCandidates = 13; // arc-solve angle samples
  static const int _botArcSteps = 36; // arc-solve sim steps
  static const double _botArcDt = 0.05; // arc-solve sim step
  static const double _botGoldBias = 0.55; // gold target distance discount
  // A low-accuracy bot sometimes loses track and aims at NOTHING (a wild loose),
  // and may even mistake a bomb for a target — both waste arrows like a human
  // who shoots carelessly, keeping easy bots beatable.
  static const double _botWildChance = 0.45; // share of errorRate → wild loose
  static const double _botBombMistake = 0.6; // errorRate × this → may pick bomb

  // ── Climax (final-quiver) tuning ─────────────────────────────────────────────
  static const double _frenzyAmmoFrac = 0.7; // entered after this share spent

  // ── Visuals / ambient ───────────────────────────────────────────────────────
  static const double _horizonFactor = 0.40;
  static const int _cloudCount = 5;
  static const Color _muzzlePuff = Color(0xFFFFF0C4);
  static const Color _comboColor = Color(0xFFFFD24A);
  static const Color _bombColor = Color(0xFFFF5A52);

  late Juice _juice;
  late Size _size;
  late double _scale;
  late double _horizonY;
  late Offset _sun;
  late double _maxDragPx;

  final List<_Archer> _archers = <_Archer>[];
  final List<_Arrow> _arrows = <_Arrow>[];
  final List<_Target> _targets = <_Target>[];
  final List<Offset> _clouds = <Offset>[];
  final List<Offset> _windAnchors = <Offset>[];

  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for ambient/flash
  double _spawnTimer = 0;
  bool _frenzyAnnounced = false;
  bool _winnerCheered = false;

  // Wind: a single crosswind value eased toward a fresh random target.
  double _windX = 0;
  double _windTarget = 0;
  double _windTimer = 0;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    final minSide = math.min(_size.width, _size.height);
    _scale = (minSide / _baseScaleRef).clamp(0.7, 1.7);
    _maxDragPx = minSide * _maxDragFrac;
    _horizonY = _size.height * _horizonFactor;
    _sun = Offset(_size.width * 0.74, _size.height * 0.16);

    _buildArchers();
    _seedAmbient();
    _retargetWind();
    for (var i = 0; i < _initialTargets; i++) {
      _spawnTarget(seeded: true);
    }
    begin();
  }

  // ── World construction ──────────────────────────────────────────────────────

  void _buildArchers() {
    final count = ctx.players.length;
    final proportions = StickProportions.hero.scaled(_figureScale);
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final side = _sideFor(i, count);
      final base = _basePos(side);
      final inward = -side.outward;
      // Resting aim points into the field (used for the idle preview + as the
      // start angle before the player draws).
      final center = math.atan2(inward.dy, inward.dx);
      final facing = inward.dx >= 0 ? 1.0 : -1.0;
      final figure = StickFigure(
        proportions: proportions,
        style: _styleFor(Color(p.colorArgb)),
        facing: facing,
        aimAngle: center,
      )..setLoco(LocoState.idle);
      _archers.add(_Archer(
        playerId: p.id,
        color: Color(p.colorArgb),
        base: base,
        side: side,
        facing: facing,
        restAngle: center,
        figure: figure,
        ammo: _quiver,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.45,
        gradientBottom: 0.55,
        smearAlpha: 0.22,
      );

  ArcherSide _sideFor(int index, int count) {
    switch (count) {
      case 1:
        return ArcherSide.bottom;
      case 2:
        return index == 0 ? ArcherSide.bottom : ArcherSide.top;
      case 3:
        return [ArcherSide.bottom, ArcherSide.left, ArcherSide.right][index];
      default:
        return [
          ArcherSide.bottom,
          ArcherSide.top,
          ArcherSide.left,
          ArcherSide.right,
        ][index];
    }
  }

  Offset _basePos(ArcherSide side) {
    final w = _size.width, h = _size.height;
    final inset = math.min(w, h) * _edgeInsetFactor + 30 * _scale;
    return switch (side) {
      ArcherSide.bottom => Offset(w * 0.5, h - inset),
      ArcherSide.top => Offset(w * 0.5, inset),
      ArcherSide.left => Offset(inset, h * 0.6),
      ArcherSide.right => Offset(w - inset, h * 0.6),
    };
  }

  void _seedAmbient() {
    for (var i = 0; i < _cloudCount; i++) {
      _clouds.add(Offset(
        ctx.rng.range(0, _size.width),
        ctx.rng.range(_size.height * 0.05, _horizonY * 0.7),
      ));
    }
    for (var i = 0; i < _windStreakCount; i++) {
      _windAnchors.add(Offset(
        ctx.rng.range(0, _size.width),
        ctx.rng.range(_horizonY * 0.2, _size.height * 0.92),
      ));
    }
  }

  // ── Input: DRAG to aim, RELEASE to loose ─────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final archer = _archerOf(input.playerId);
    if (archer == null) return;

    switch (input.phase) {
      case InputPhase.down:
        // Begin a draw anchored at the touch point. The aim/power are derived
        // from how far + which way the finger then drags from here.
        archer.dragStart = _toArena(input.normPos);
        archer.dragNow = archer.dragStart;
        archer.drawing = true;
      case InputPhase.holdTick:
        // A move sample carries a position; a positionless per-frame tick
        // (normPos == Offset.zero) just means the finger is still down.
        if (archer.drawing && input.normPos != Offset.zero) {
          archer.dragNow = _toArena(input.normPos);
        }
      case InputPhase.up:
        if (!archer.drawing) return;
        final shot = _resolveDraw(archer);
        archer.drawing = false;
        archer.dragStart = null;
        archer.dragNow = null;
        // THE GATE: only a deliberate draw (power ≥ _minPower) looses. A bare
        // tap relaxes the bow and spends no arrow — you cannot clear a target by
        // an incidental press.
        if (shot != null) _loose(input.playerId, shot.angle, shot.power);
    }
  }

  /// Map a full-screen 0..1 touch into arena pixels.
  Offset _toArena(Offset norm) =>
      Offset(norm.dx * _size.width, norm.dy * _size.height);

  /// Resolve the current draw to an aim (angle + power), or null when the pull
  /// is below the usable threshold (a tap, not a shot). Slingshot feel: you
  /// loose OPPOSITE the pull, and the pull length sets power.
  _Shot? _resolveDraw(_Archer a) {
    final start = a.dragStart, now = a.dragNow;
    if (start == null || now == null) return null;
    final pull = start - now; // launch is opposite the drag
    final dist = pull.distance;
    if (dist < 1e-3) return null;
    final power = (dist / _maxDragPx).clamp(0.0, 1.0);
    if (power < _minPower) return null; // ← anti-incidental-clear gate
    return _Shot(math.atan2(pull.dy, pull.dx), power);
  }

  double _speedFor(double power) =>
      lerpD(_speedMin, _speedMax, power.clamp(0.0, 1.0));

  /// Loose an arrow at [angle] with [power]. Shared by human releases and bot
  /// decisions so feel + ballistics stay identical. Consumes one arrow.
  void _loose(int id, double angle, double power) {
    final archer = _archerOf(id);
    if (archer == null || archer.ammo <= 0) return;
    archer.ammo -= 1;
    final dir = Offset(math.cos(angle), math.sin(angle));
    archer.aimAngle = angle;
    archer.aimPower = power.clamp(0.0, 1.0);
    final muzzle = _muzzleOf(archer);
    final speed = _speedFor(power);
    _arrows.add(_Arrow(
      pos: muzzle,
      vel: dir * speed,
      ownerId: id,
      color: archer.color,
    ));
    archer.loose = _looseFadeSec;
    final baseAngle = angle;
    _juice.particles.burst(
      at: muzzle,
      count: 5,
      color: _muzzlePuff,
      speed: 170,
      baseAngle: baseAngle,
      spread: math.pi * 0.45,
      size: 4,
      gravity: 120,
      life: 0.26,
    );
    _juice.hitStop.trigger(0.02);
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _stepWind(sdt);
    for (final a in _archers) {
      // While drawing, the live aim/power follow the finger so the preview reads.
      final shot = a.drawing ? _resolveDraw(a) : null;
      if (shot != null) {
        a.aimAngle = shot.angle;
        a.aimPower = shot.power;
      } else if (a.drawing) {
        // Drawing but under threshold: show the rest aim at low power.
        a.aimPower = 0;
      }
      a.figure.aimAngle = a.aimAngle;
      a.figure.update(dt);
      a.tickTimers(dt, _looseFadeSec);
    }
    _spawnTick(sdt);
    _stepTargets(sdt);
    _driveBots(dt);
    _stepArrows(sdt);
    _announceFrenzy();
    _checkEnd();
  }

  /// 0 → 1 difficulty ramp from the share of the (combined) quiver spent.
  double get _ramp {
    final total = _archers.length * _quiver;
    if (total <= 0) return 0;
    var spent = 0;
    for (final a in _archers) {
      spent += _quiver - a.ammo;
    }
    return (spent / total).clamp(0.0, 1.0);
  }

  bool get _isFrenzy => _ramp >= _frenzyAmmoFrac;

  void _announceFrenzy() {
    if (_frenzyAnnounced || !_isFrenzy) return;
    _frenzyAnnounced = true;
    _juice.shake.medium();
    _juice.popup(Offset(_size.width / 2, _size.height * 0.28), 'LAST ARROWS!',
        _comboColor,
        size: 34);
  }

  // ── Wind ──────────────────────────────────────────────────────────────────

  void _stepWind(double dt) {
    _windTimer -= dt;
    if (_windTimer <= 0) _retargetWind();
    final rate = (dt / _windChangeSec).clamp(0.0, 1.0);
    _windX = lerpD(_windX, _windTarget, rate * _windEaseRate);
  }

  void _retargetWind() {
    _windTarget = ctx.rng.range(-_windMax, _windMax);
    _windTimer = _windChangeSec * ctx.rng.range(0.8, 1.4);
  }

  // ── Target spawning + motion ─────────────────────────────────────────────────

  void _spawnTick(double dt) {
    _spawnTimer += dt;
    final every = lerpD(_spawnEvery, _spawnEvery * _rampSpawnMul, _ramp);
    if (_spawnTimer >= every && _targets.length < _maxTargets) {
      _spawnTimer = 0;
      _spawnTarget();
    }
  }

  void _spawnTarget({bool seeded = false}) {
    final w = _size.width, h = _size.height;
    final ramp = _ramp;
    // Bomb + gold shares grow with the ramp. Roll bomb first, then gold.
    final bombChance = lerpD(_bombChanceBase, _bombChanceMax, ramp);
    final goldChance = lerpD(_goldChanceBase, _goldChanceMax, ramp);
    _TargetKind kind;
    if (ctx.rng.chance(bombChance)) {
      kind = _TargetKind.bomb;
    } else if (ctx.rng.chance(goldChance)) {
      kind = _TargetKind.gold;
    } else {
      kind = _TargetKind.plain;
    }
    final shrink = lerpD(1.0, _rampShrink, ramp);
    final radius = switch (kind) {
      _TargetKind.gold => _radiusGold * shrink,
      _TargetKind.bomb => _radiusBomb,
      _TargetKind.plain =>
        ctx.rng.range(_radiusPlainMin, _radiusPlainMax) * shrink,
    };
    // Targets live in a horizontal band across the upper-middle of the field.
    final x = ctx.rng.range(w * 0.12, w * 0.88);
    final y = ctx.rng.range(h * _fieldTopFrac, h * _fieldBottomFrac);
    final driftMag = lerpD(_driftMin, _driftMax, ramp) *
        lerpD(1.0, 1 + _rampDriftMul, ramp);
    final drift = driftMag * ctx.rng.sign();
    final rise = ctx.rng.range(_riseMin, _riseMax) * ctx.rng.sign();
    // Only plain targets can be shielded by a barrier (gold stays a pure speed
    // test; a bomb behind a wall would be unfair to avoid).
    final shielded =
        kind == _TargetKind.plain && ctx.rng.chance(_shieldChance);
    final palette = ctx.players[ctx.rng.intRange(0, ctx.players.length)];
    final color = switch (kind) {
      _TargetKind.gold => _comboColor,
      _TargetKind.bomb => _bombColor,
      _TargetKind.plain => Color(palette.colorArgb),
    };
    _targets.add(_Target(
      pos: Offset(x, y),
      vel: Offset(drift, rise),
      radius: radius,
      color: color,
      kind: kind,
      shielded: shielded,
      bob: ctx.rng.range(0, kTau),
      ttl: kind == _TargetKind.gold ? _goldLifeSec : double.infinity,
    ));
  }

  void _stepTargets(double dt) {
    final survivors = <_Target>[];
    for (final t in _targets) {
      if (t.popT > 0) {
        t.popT -= dt / _burstSec;
        if (t.popT > 0) survivors.add(t);
        continue;
      }
      // Gold is brief: it self-pops (floats away) when its time is up.
      if (t.ttl.isFinite) {
        t.ttl -= dt;
        if (t.ttl <= 0) continue;
      }
      t.bob += dt * _bobRate;
      final sway = math.sin(t.bob) * _bobSway * dt;
      final dx = t.vel.dx + _windX * _windShareOnTarget;
      var np = t.pos + Offset(dx, t.vel.dy) * dt + Offset(sway, 0);
      // Bounce gently off the field band edges so targets stay on screen.
      final loX = t.radius * 1.5, hiX = _size.width - t.radius * 1.5;
      final loY = _size.height * _fieldTopFrac * 0.6;
      final hiY = _size.height * (_fieldBottomFrac + 0.06);
      var vx = t.vel.dx, vy = t.vel.dy;
      if (np.dx < loX) {
        np = Offset(loX, np.dy);
        vx = vx.abs();
      } else if (np.dx > hiX) {
        np = Offset(hiX, np.dy);
        vx = -vx.abs();
      }
      if (np.dy < loY) {
        np = Offset(np.dx, loY);
        vy = vy.abs();
      } else if (np.dy > hiY) {
        np = Offset(np.dx, hiY);
        vy = -vy.abs();
      }
      t.pos = np;
      t.vel = Offset(vx, vy);
      t.sparkle += dt * _sparkleRate;
      t.barrier = t.shielded ? _barrierFor(t) : null;
      survivors.add(t);
    }
    _targets
      ..clear()
      ..addAll(survivors);
  }

  /// The wall for a shielded target: a slab placed [_barrierGap] toward the
  /// NEAREST archer, so a flat shot from that archer is blocked and must arc.
  Rect _barrierFor(_Target t) {
    final near = _nearestArcherTo(t.pos);
    final toShooter =
        near == null ? const Offset(0, 1) : (_muzzleOf(near) - t.pos);
    final d = toShooter.distance < 1e-3
        ? const Offset(0, 1)
        : toShooter / toShooter.distance;
    final center = t.pos + d * (t.radius + _barrierGap * _scale);
    final w = _barrierW * _scale, h = _barrierH * _scale;
    // Orient the slab broadside to the incoming line: wide across the shot.
    final horizontal = d.dy.abs() >= d.dx.abs();
    final rw = horizontal ? w : h;
    final rh = horizontal ? h : w;
    return Rect.fromCenter(center: center, width: rw, height: rh);
  }

  _Archer? _nearestArcherTo(Offset p) {
    _Archer? best;
    var bestD = double.infinity;
    for (final a in _archers) {
      final d = (a.base - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = a;
      }
    }
    return best;
  }

  // ── Bots: SOLVE an arc onto the best target, perturb by accuracy, loose ──────

  void _driveBots(double dt) {
    for (final a in _archers) {
      final clock = a.clock;
      if (clock == null) continue;
      if (a.ammo <= 0) continue;
      if (!clock.tick(dt)) continue;
      _botShoot(a);
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  /// A bot picks the best live target (gold weighted closer; bombs avoided, but
  /// a careless/low-accuracy bot may MISTAKE one), solves a launch angle + power
  /// that would hit it, then perturbs BOTH by an accuracy-scaled error so weak
  /// bots scatter wide + clip bombs + waste arrows, and strong bots land gold.
  void _botShoot(_Archer a) {
    final accuracy = ctx.botProfile.accuracy.clamp(0.2, 1.0);
    final miss = 1 - accuracy;
    final target = _botPickTarget(a);
    if (target == null) {
      // Nothing worth shooting: a wild loose, so a bot is never idle on ammo.
      if (ctx.rng.chance(ctx.botProfile.errorRate * _botWildChance)) {
        _loose(a.playerId, a.restAngle + ctx.rng.jitter(_botAimErrorRad),
            ctx.rng.range(_minPower, 1.0));
      }
      return;
    }
    final solved = _solveArc(a, target);
    if (solved == null) {
      if (ctx.rng.chance(ctx.botProfile.errorRate * _botWildChance)) {
        _loose(a.playerId, a.restAngle + ctx.rng.jitter(_botAimErrorRad),
            ctx.rng.range(_minPower, 1.0));
      }
      return;
    }
    final angErr =
        ctx.rng.jitter(miss * _botAimErrorRad) + ctx.rng.jitter(miss * _botFlinchRad);
    final powErr = ctx.rng.jitter(miss * _botPowerError);
    final power = (solved.power + powErr).clamp(_minPower, 1.0);
    _loose(a.playerId, solved.angle + angErr, power);
  }

  /// Choose a bot's intended target. Prefers gold (distance discounted), never
  /// *intends* a bomb — but a low-accuracy careless bot rolls a chance to grab
  /// the nearest thing regardless, which can be a bomb (a self-inflicted miss).
  _Target? _botPickTarget(_Archer a) {
    final origin = _muzzleOf(a);
    final careless =
        ctx.rng.chance(ctx.botProfile.errorRate * _botBombMistake);
    _Target? best;
    var bestCost = double.infinity;
    for (final t in _targets) {
      if (t.popT > 0) continue;
      if (t.kind == _TargetKind.bomb && !careless) continue;
      var cost = (t.pos - origin).distance;
      if (t.kind == _TargetKind.gold) cost *= _botGoldBias; // chase the prize
      if (cost < bestCost) {
        bestCost = cost;
        best = t;
      }
    }
    return best;
  }

  /// Solve a launch (angle, power) whose gravity+wind arc lands closest to
  /// [target] from [a]'s muzzle. Samples a fan of angles × a few powers and
  /// simulates each lightly. Returns null if nothing comes close (e.g. a wall
  /// fully blocks every line at this range).
  _Shot? _solveArc(_Archer a, _Target target) {
    final origin = _muzzleOf(a);
    final inward = -a.side.outward;
    final center = math.atan2(inward.dy, inward.dx);
    _Shot? best;
    var bestMiss = double.infinity;
    final n = _botArcCandidates.toInt();
    for (var i = 0; i < n; i++) {
      final ang = center + lerpD(-1.1, 1.1, i / (n - 1));
      for (final power in const [0.45, 0.65, 0.85, 1.0]) {
        final miss = _simMiss(origin, ang, power, target);
        if (miss < bestMiss) {
          bestMiss = miss;
          best = _Shot(ang, power);
        }
      }
    }
    // Reachable only if some arc gets within a forgiving margin of the target.
    return bestMiss <= target.radius * 3 ? best : null;
  }

  /// Lightly simulate an arc and return the closest approach distance to
  /// [target] (a big penalty if a barrier eats the arrow first). The target is
  /// LED along its own drift over the flight so a moving balloon is actually
  /// solved for — the difference between a thoughtful shot and a hopeful one.
  double _simMiss(Offset origin, double angle, double power, _Target target) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    var pos = origin;
    var vel = dir * _speedFor(power);
    // Track where the target will be, drifting as it does in _stepTargets.
    var tpos = target.pos;
    final tvel = target.vel + Offset(_windX * _windShareOnTarget, 0);
    final wall =
        target.shielded ? target.barrier ?? _barrierFor(target) : null;
    var closest = double.infinity;
    for (var s = 0; s < _botArcSteps; s++) {
      vel = vel + Offset(_windX * _botArcDt, _gravity * _botArcDt);
      pos = pos + vel * _botArcDt;
      tpos = tpos + tvel * _botArcDt;
      // A wall between shooter and target eats a flat shot (forces an arc).
      if (wall != null && wall.contains(pos)) return 1e6;
      final d = (pos - tpos).distance;
      if (d < closest) closest = d;
      if (_outOfBounds(pos)) break;
    }
    return closest;
  }

  // ── Arrows ──────────────────────────────────────────────────────────────────

  void _stepArrows(double dt) {
    final survivors = <_Arrow>[];
    for (final s in _arrows) {
      if (s.stuck > 0) {
        s.stuck -= dt / _stuckLifeSec;
        if (s.stuck > 0) survivors.add(s);
        continue;
      }
      final vel = s.vel + Offset(_windX * dt, _gravity * dt);
      final pos = s.pos + vel * dt;
      final life = s.life - dt;

      // A barrier stops the arrow dead (no pop) — the core "arc over me" wall.
      if (_hitsBarrier(s.pos, pos)) {
        s.stuckAt(pos, vel);
        survivors.add(s);
        continue;
      }

      final hit = _hitTarget(s.pos, pos);
      if (hit != null) {
        _registerHit(s.ownerId, hit);
        continue; // arrow consumed
      }
      if (life <= 0 || _outOfBounds(pos)) {
        if (life <= 0) _shrugMiss(s.ownerId);
        if (!_outOfBounds(pos)) {
          s.stuckAt(pos, vel);
          survivors.add(s);
        }
        continue;
      }
      s.advance(pos, vel, life, _trailSamples);
      survivors.add(s);
    }
    _arrows
      ..clear()
      ..addAll(survivors);
  }

  /// True when the arrow's step segment crosses a shielded target's wall.
  bool _hitsBarrier(Offset from, Offset to) {
    for (final t in _targets) {
      if (!t.shielded || t.popT > 0) continue;
      final wall = t.barrier;
      if (wall != null && _segHitsRect(from, to, wall)) return true;
    }
    return false;
  }

  /// First live target the arrow's step segment intersects (segment vs circle),
  /// so a fast arrow cannot tunnel through a small target between frames.
  _Target? _hitTarget(Offset from, Offset to) {
    for (final t in _targets) {
      if (t.popT > 0) continue;
      if (_segHitsCircle(from, to, t.pos, t.radius)) return t;
    }
    return null;
  }

  /// Award (or subtract) for a hit: plain/gold add ×combo; a BOMB subtracts a
  /// flat penalty and breaks the combo. Fires the burst + popup + charm.
  void _registerHit(int shooterId, _Target target) {
    final archer = _archerOf(shooterId);
    if (archer == null) return;
    target.popT = 1.0;

    if (target.kind == _TargetKind.bomb) {
      // A bomb is a self-inflicted blow: subtract, reset combo, shrug + a red
      // pop so loosing carelessly visibly hurts.
      addScore(shooterId, -_bombPenalty);
      archer.combo = 0;
      archer.comboTimer = 0;
      archer.streak = 0;
      _juice.particles.burst(
        at: target.pos,
        count: 16,
        color: _bombColor,
        speed: 300,
        size: 6,
        gravity: 420,
        life: 0.5,
      );
      _juice.shake.medium();
      _juice.popup(target.pos.translate(0, -target.radius), '-$_bombPenalty',
          _bombColor,
          size: 26);
      if (!archer.figure.actionPlaying) archer.figure.hurt();
      return;
    }

    // Combo: hits inside the window stack the multiplier; else reset to 1.
    if (archer.comboTimer > 0) {
      archer.combo = (archer.combo + 1).clamp(1, _maxCombo);
    } else {
      archer.combo = 1;
    }
    archer.comboTimer = _comboWindowSec;
    archer.streak += 1;

    final gold = target.kind == _TargetKind.gold;
    final unit = gold ? _goldPoints : _plainPoints;
    final gained = unit * archer.combo;
    addScore(shooterId, gained);

    if (archer.combo >= 3 || gold) archer.figure.special();

    final popColor = gold ? _comboColor : archer.color;
    _juice.particles.burst(
      at: target.pos,
      count: gold ? 20 : 12,
      color: popColor,
      speed: gold ? 320 : 240,
      size: gold ? 7 : 5,
      gravity: 420,
      life: gold ? 0.6 : 0.45,
    );
    if (gold) {
      _juice.bigMoment(target.pos, archer.color, banner: 'GOLD!');
    } else {
      _juice.shake.light();
      if (archer.combo >= 3) _juice.hitStop.trigger(0.05, scale: 0.2);
    }
    final label = archer.combo >= 2 ? '+$gained  x${archer.combo}' : '+$gained';
    _juice.popup(
      target.pos.translate(0, -target.radius),
      label,
      popColor,
      size: gold ? 30 : 24,
    );
  }

  bool _outOfBounds(Offset p) {
    const pad = _outOfBoundsPad;
    return p.dx < -pad ||
        p.dy < -pad ||
        p.dx > _size.width + pad ||
        p.dy > _size.height + pad;
  }

  // ── End condition ───────────────────────────────────────────────────────────

  void _checkEnd() {
    final outOfAmmo = _archers.every((a) => a.ammo <= 0);
    // When the quivers are dry, let the last arrows finish flying before ending.
    final settled = _arrows.every((s) => s.stuck > 0);
    if (_elapsed >= _timeLimit || (outOfAmmo && settled)) {
      _cheerWinner();
      _juice.confetti(_size);
      finishByScore();
    }
  }

  void _cheerWinner() {
    if (_winnerCheered || _archers.isEmpty) return;
    _winnerCheered = true;
    _Archer? best;
    for (final a in _archers) {
      if (best == null || scoreOf(a.playerId) > scoreOf(best.playerId)) {
        best = a;
      }
    }
    best?.figure.victory();
  }

  // ── Geometry helpers (mirror ArcherRenderer) ────────────────────────────────

  Offset _muzzleOf(_Archer a) {
    final view = _viewOf(a);
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    return ArcherRenderer.bowAnchor(view) + dir * (_muzzleReach * _scale);
  }

  _Archer? _archerOf(int id) {
    for (final a in _archers) {
      if (a.playerId == id) return a;
    }
    return null;
  }

  void _shrugMiss(int id) {
    final archer = _archerOf(id);
    if (archer == null || archer.figure.actionPlaying) return;
    archer.figure.hurt();
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    ArcherRenderer.drawRange(
      canvas,
      size,
      horizonY: _horizonY,
      sun: _sun,
      clouds: _clouds,
      t: _animClock,
    );
    ArcherRenderer.drawWindStreaks(
        canvas, size, _windAnchors, _windX, _animClock);

    // Barriers behind targets, then aim previews (under the archers), then
    // targets, then in-flight arrows, then archers + bows + HUD.
    for (final t in _targets) {
      if (t.barrier != null && t.popT <= 0) {
        ArcherRenderer.drawBarrier(canvas, t.barrier!, _scale);
      }
    }
    for (final a in _archers) {
      ArcherRenderer.drawAimPreview(canvas, _viewOf(a), _trajectoryFor(a));
    }
    for (final t in _targets) {
      ArcherRenderer.drawTarget(canvas, _targetView(t));
    }
    for (final s in _arrows) {
      ArcherRenderer.drawArrow(canvas, s.view());
    }
    for (final a in _archers) {
      final view = _viewOf(a);
      ArcherRenderer.drawArcherBody(canvas, a.figure, a.base);
      ArcherRenderer.drawBow(canvas, view);
      ArcherRenderer.drawComboBadge(canvas, view);
    }

    _juice.render(canvas);
    canvas.restore();

    // Screen-space overlays (after the world transform is restored): per-player
    // ammo + score + objective HUD, the wind banner, the climax banner + the
    // cinematic flash/banner from bigMoment.
    for (final a in _archers) {
      ArcherRenderer.drawHud(canvas, size, _hudView(a));
    }
    ArcherRenderer.drawWindBanner(canvas, size, _windX);
    if (_isFrenzy) {
      ArcherFx.drawFrenzyBanner(canvas, size, 1.0, _animClock);
    }
    _juice.renderOverlay(canvas, size);
  }

  /// A short list of arc points previewing where the current draw would send an
  /// arrow — only while the player is drawing with usable power.
  List<Offset> _trajectoryFor(_Archer a) {
    if (!a.drawing || a.aimPower < _minPower) return const <Offset>[];
    final origin = _muzzleOf(a);
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    var pos = origin;
    var vel = dir * _speedFor(a.aimPower);
    final pts = <Offset>[origin];
    const dt = 0.045;
    for (var i = 0; i < 16; i++) {
      vel = vel + Offset(_windX * dt, _gravity * dt);
      pos = pos + vel * dt;
      if (_outOfBounds(pos)) break;
      pts.add(pos);
    }
    return pts;
  }

  ArcherView _viewOf(_Archer a) => ArcherView(
        base: a.base,
        color: a.color,
        side: a.side,
        facing: a.facing,
        aimAngle: a.aimAngle,
        // The drawn-bow visual fills with the live pull while aiming; otherwise
        // the bow is relaxed (a loosed/idle archer shows no nocked arrow).
        draw: a.drawing ? a.aimPower : 0.0,
        combo: a.combo,
        scale: _scale,
        loose: (a.loose / _looseFadeSec).clamp(0.0, 1.0),
      );

  TargetView _targetView(_Target t) => TargetView(
        pos: t.pos,
        color: t.color,
        radius: t.radius,
        bobPhase: t.bob,
        popT: t.popT.clamp(0.0, 1.0),
        kind: switch (t.kind) {
          _TargetKind.gold => TargetKind.gold,
          _TargetKind.bomb => TargetKind.bomb,
          _TargetKind.plain => TargetKind.plain,
        },
        sparklePhase: t.sparkle,
        // Gold's brief life reads as a shrinking fuse ring (1 → 0).
        fuse: t.ttl.isFinite ? (t.ttl / _goldLifeSec).clamp(0.0, 1.0) : 1.0,
      );

  HudView _hudView(_Archer a) {
    final zone = ctx.zones.forPlayer(a.playerId)?.normRect ??
        const Rect.fromLTRB(0, 0, 1, 1);
    final rot = ctx.zones.forPlayer(a.playerId)?.rotationQuarters ?? 0;
    return HudView(
      zone: zone,
      rotationQuarters: rot,
      color: a.color,
      score: scoreOf(a.playerId),
      ammo: a.ammo,
      maxAmmo: _quiver,
      playerNumber: a.playerId + 1,
    );
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  // ── Geometry: segment vs circle / rect (no tunneling through small targets) ─

  static bool _segHitsCircle(Offset a, Offset b, Offset c, double r) {
    final ab = b - a;
    final lenSq = ab.distanceSquared;
    if (lenSq < 1e-6) return (a - c).distance <= r;
    var t = ((c - a).dx * ab.dx + (c - a).dy * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final closest = a + ab * t;
    return (closest - c).distance <= r;
  }

  static bool _segHitsRect(Offset a, Offset b, Rect r) {
    if (r.contains(a) || r.contains(b)) return true;
    // Test the segment against the four rect edges.
    final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
    return _segHitsSeg(a, b, tl, tr) ||
        _segHitsSeg(a, b, tr, br) ||
        _segHitsSeg(a, b, br, bl) ||
        _segHitsSeg(a, b, bl, tl);
  }

  static bool _segHitsSeg(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final d1 = cross(p3, p4, p1);
    final d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3);
    final d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  // ── Test seams (deterministic; no Flutter) ──────────────────────────────────

  /// The per-player quiver size (the scarce resource), exposed for tests.
  @visibleForTesting
  static int get debugQuiver => _quiver;

  /// Arrows currently in flight (for tests asserting shots were spent/landed).
  @visibleForTesting
  int get debugArrowCount => _arrows.length;

  /// Remaining ammo for a player (the scarce quiver).
  @visibleForTesting
  int debugAmmo(int id) => _archerOf(id)?.ammo ?? 0;

  /// Drive a full deliberate AIMED shot for [id] toward arena point [at] at the
  /// given [power], routed through the real input path (down→drag→up). Used by
  /// tests to model a skilled player. Returns true if an arrow was loosed.
  @visibleForTesting
  bool debugAimShotAt(int id, Offset at, {double power = 0.7}) {
    final a = _archerOf(id);
    if (a == null || a.ammo <= 0) return false;
    final origin = _muzzleOf(a);
    final solved = _solveArcPublic(a, at);
    final angle =
        solved?.angle ?? math.atan2(at.dy - origin.dy, at.dx - origin.dx);
    final usePower = solved?.power ?? power;
    final before = a.ammo;
    _driveDrag(id, angle, usePower);
    return a.ammo < before;
  }

  /// A solve helper exposed for the aim test (mirrors [_solveArc] against a free
  /// point rather than a target instance).
  _Shot? _solveArcPublic(_Archer a, Offset at) {
    final t = _Target(
      pos: at,
      vel: Offset.zero,
      radius: _radiusPlainMin,
      color: a.color,
      kind: _TargetKind.plain,
      shielded: false,
      bob: 0,
      ttl: double.infinity,
    );
    return _solveArc(a, t);
  }

  /// Model a skilled player taking the cleanest available shot: pick the nearest
  /// OPEN scoring target (its real motion is LED by the arc solver) and loose a
  /// solved arc straight at it through the real input path. Returns true if an
  /// arrow was loosed (false when no open target is up or ammo is dry). This is
  /// the aimer the anti-spam test pits against a blind spammer.
  @visibleForTesting
  bool debugShootNearestTarget(int id) {
    final a = _archerOf(id);
    if (a == null || a.ammo <= 0) return false;
    final origin = _muzzleOf(a);
    _Target? best;
    var bestD = double.infinity;
    for (final t in _targets) {
      if (t.popT > 0 || t.kind == _TargetKind.bomb || t.shielded) continue;
      final d = (t.pos - origin).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    if (best == null) return false;
    final solved = _solveArc(a, best);
    if (solved == null) return false; // no makeable shot — conserve the arrow
    final before = a.ammo;
    _driveDrag(id, solved.angle, solved.power);
    return a.ammo < before;
  }

  /// Synthesize a slingshot drag (down→drag→up) for [angle]/[power] routed
  /// through [onInput], so a test shot exercises the same gate a human does.
  void _driveDrag(int id, double angle, double power) {
    final a = _archerOf(id);
    if (a == null) return;
    final origin = _muzzleOf(a);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final pullPx = power.clamp(_minPower, 1.0) * _maxDragPx;
    final now = origin - dir * pullPx; // launch is opposite the pull
    onInput(PlayerInput(
        playerId: id, phase: InputPhase.down, normPos: _toNorm(origin)));
    onInput(PlayerInput(
        playerId: id, phase: InputPhase.holdTick, normPos: _toNorm(now)));
    onInput(PlayerInput(playerId: id, phase: InputPhase.up));
  }

  Offset _toNorm(Offset arena) =>
      Offset(arena.dx / _size.width, arena.dy / _size.height);

  /// Nearest live, OPEN (non-bomb, non-shielded) scoring target to a player's
  /// muzzle — the clean shot a skilled player takes. Used by the anti-spam test
  /// to model an aimer that prioritizes makeable shots over walled ones.
  @visibleForTesting
  Offset? debugNearestTargetTo(int id) {
    final a = _archerOf(id);
    if (a == null) return null;
    final origin = _muzzleOf(a);
    Offset? best;
    var bestD = double.infinity;
    for (final t in _targets) {
      if (t.popT > 0 || t.kind == _TargetKind.bomb || t.shielded) continue;
      final d = (t.pos - origin).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = t.pos;
      }
    }
    return best;
  }
}

/// A resolved shot: aim angle (radians) + power 0..1.
class _Shot {
  final double angle;
  final double power;
  const _Shot(this.angle, this.power);
}

/// Target kinds. Plain + gold SCORE; bomb SUBTRACTS.
enum _TargetKind { plain, gold, bomb }

/// One archer. Mutable round-scoped state (allowed for the duration of a round).
class _Archer {
  final int playerId;
  final Color color;
  final Offset base;
  final ArcherSide side;
  final double facing;
  final double restAngle; // resting aim into the field
  final StickFigure figure;
  final ReactionClock? clock; // null for human seats

  int ammo;
  double aimAngle;
  double aimPower = 0;
  bool drawing = false;
  Offset? dragStart; // arena px where the draw began
  Offset? dragNow; // arena px of the latest drag sample

  double loose = 0; // loose-flash timer
  int combo = 0;
  double comboTimer = 0;
  int streak = 0;

  _Archer({
    required this.playerId,
    required this.color,
    required this.base,
    required this.side,
    required this.facing,
    required this.restAngle,
    required this.figure,
    required this.ammo,
    this.clock,
  }) : aimAngle = restAngle;

  void tickTimers(double dt, double looseFadeSec) {
    if (loose > 0) loose = (loose - dt).clamp(0, looseFadeSec);
    if (comboTimer > 0) {
      comboTimer -= dt;
      if (comboTimer <= 0) {
        comboTimer = 0;
        combo = 0;
        streak = 0;
      }
    }
  }
}

/// One in-flight (or briefly stuck) arrow. Mutable round-scoped state.
class _Arrow {
  Offset pos;
  Offset vel;
  final int ownerId;
  final Color color;
  double life = ArcherPop._arrowLife;
  double stuck = 0; // 0 = flying, >0..1 = embedded fade
  final List<Offset> _trail = <Offset>[];

  _Arrow({
    required this.pos,
    required this.vel,
    required this.ownerId,
    required this.color,
  });

  void advance(Offset newPos, Offset newVel, double newLife, int maxTrail) {
    _trail.insert(0, pos);
    if (_trail.length > maxTrail) _trail.removeLast();
    pos = newPos;
    vel = newVel;
    life = newLife;
  }

  void stuckAt(Offset at, Offset lastVel) {
    pos = at;
    vel = lastVel;
    stuck = 1.0;
  }

  Offset get _dir =>
      vel.distance > 1e-3 ? vel / vel.distance : const Offset(1, 0);

  ArrowView view() => ArrowView(
        pos: pos,
        dir: _dir,
        color: color,
        trail: List<Offset>.unmodifiable(_trail),
        stuck: stuck.clamp(0.0, 1.0),
      );
}

/// One target balloon. Mutable round-scoped state.
class _Target {
  Offset pos;
  Offset vel;
  final double radius;
  final Color color;
  final _TargetKind kind;
  final bool shielded;
  double bob;
  double ttl; // gold self-pops when this hits 0; infinity otherwise
  double sparkle = 0;
  double popT = 0; // 0 = whole, 1 → 0 while bursting
  Rect? barrier; // computed each step for shielded targets

  _Target({
    required this.pos,
    required this.vel,
    required this.radius,
    required this.color,
    required this.kind,
    required this.shielded,
    required this.bob,
    required this.ttl,
  });
}
