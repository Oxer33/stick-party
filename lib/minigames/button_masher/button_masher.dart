import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';
import '../../core/math2.dart';
import '../../engine/helpers/tap_mash_meter.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'masher_render.dart';

/// Button Masher — a carnival "high striker" (test-your-strength) race. Every
/// player owns a strength tower; each tap swings their little stickman's hammer
/// onto the lever, kicks the puck a notch higher and lights up the next strength
/// level toward the bell at the top. Most height (≡ most taps) in the time
/// window wins.
///
/// Depth (still one-touch MASH):
///  * **Power band**: sustained, rhythmic mashing builds a per-player power
///    level that decays when you slack off. A tap's puck kick scales with power,
///    so a steady hammering run climbs far faster than a few stray slaps —
///    mashing *cadence* matters, not just the raw count.
///  * **Screen-filling feedback**: every tap throws a colored flash ring + a
///    spark burst off the lever, so a frantic finish reads as a fireworks storm.
///  * **Bell payoff**: the first time a puck tops out it rings the bell with a
///    "DING!" popup, a golden burst, hit-stop and a shake — a clear, juicy goal.
///
/// Bots mash on a [BotProfile]-driven cadence (harder tiers hammer faster and
/// steadier), so the towers feel like a real four-way scramble.
class ButtonMasher extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'button_masher',
        name: 'Button Masher',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'MASH',
      );

  // ── Round tuning (no magic numbers inline) ──────────────────────────────────
  static const double _timeLimit = 10;
  static const int _levels = 12; // lit strength rungs on each tower

  // ── Power band (rewards steady cadence) ─────────────────────────────────────
  static const double _powerPerTap = 0.16; // power gained per tap
  static const double _powerDecayPerSec = 0.85; // bleeds when you slack off
  static const double _powerKickBoost = 1.6; // +160% puck kick at full power

  // ── Puck climb ──────────────────────────────────────────────────────────────
  static const double _baseKickPerTap = 0.018; // puck height per tap at 0 power
  static const double _puckGravityPerSec = 0.16; // puck eases back down if idle
  static const double _puckSpringPerSec = 14.0; // puck chases its target height

  // ── Hammer swing (per tap) ──────────────────────────────────────────────────
  static const double _swingSec = 0.18; // one hammer down-stroke duration

  // ── Tap feedback ────────────────────────────────────────────────────────────
  static const double _flashLifeSec = 0.22; // tap flash ring life
  static const int _maxFlashes = 6; // flashes kept per striker

  // ── Bot mash cadence (sec/tap); harder bots mash faster + steadier ──────────
  static const double _botBaseInterval = 0.155;
  static const double _botAccuracyBonus = 0.075; // faster at high accuracy
  static const double _botJitterBase = 0.05; // sloppier at low accuracy

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for bg shimmer

  final Map<int, _Striker> _strikers = <int, _Striker>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;

    final proportions = _strikerProportions();
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    final footReach = proportions.thigh + proportions.shin;

    for (final p in ctx.players) {
      _strikers[p.id] = _Striker(
        slot: p,
        meter: TapMashMeter(tapImpulse: 1, maxValue: 1e9), // count-only meter
        figure: StickFigure(
          proportions: proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.idle),
        footReach: footReach,
        botInterval: _botInterval(),
        botJitter: _botJitter(),
      );
    }
    begin();
  }

  /// Stocky carnival build derived from the hero proportions — scaled up so the
  /// hammer-swinging striker reads clearly at the foot of its tower.
  StickProportions _strikerProportions() => StickProportions.hero.scaled(1.9);

  /// Bright player style: color fill, brightened outline, strong glow. We draw
  /// our own contact shadow so the figure's own ground shadow is disabled.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.28,
      );

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.05, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  /// Sloppier (more jitter) at low accuracy so weak bots stutter and strong
  /// bots stay metronomic.
  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.25;
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _tap(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(sdt);

    for (final s in _strikers.values) {
      _tickStriker(s, sdt);
      setScore(s.slot.id, s.meter.tapCount);
    }

    if (_elapsed >= _timeLimit) {
      finishByScore(); // most taps (≡ most height) wins
    }
  }

  void _tickStriker(_Striker s, double dt) {
    // Power decays so you must keep a steady cadence to stay strong.
    s.power = math.max(0.0, s.power - _powerDecayPerSec * dt);

    // Puck eases toward its target (taps push the target up; idle bleeds it).
    s.targetHeight = math.max(0.0, s.targetHeight - _puckGravityPerSec * dt);
    final follow = (1.0 - math.exp(-_puckSpringPerSec * dt)).clamp(0.0, 1.0);
    s.puckHeight += (s.targetHeight - s.puckHeight) * follow;
    s.peakHeight = math.max(s.peakHeight, s.puckHeight);

    // Hammer swing + tap-flash clocks.
    if (s.swing > 0) s.swing = math.max(0.0, s.swing - dt);
    for (final f in s.flashes) {
      f.life -= dt;
    }
    s.flashes.removeWhere((f) => f.life <= 0);
    s.sinceTap += dt;

    s.figure.update(dt);
  }

  // ── Tap → power + puck kick + swing + feedback ──────────────────────────────

  void _tap(int id) {
    final s = _strikers[id];
    if (s == null) return;

    s.meter.tap();
    s.sinceTap = 0;

    // Build power (capped), then kick the puck target scaled by current power.
    s.power = math.min(1.0, s.power + _powerPerTap);
    final kick = _baseKickPerTap * (1.0 + _powerKickBoost * s.power);
    s.targetHeight = math.min(1.0, s.targetHeight + kick);

    // Swing the hammer down-stroke + a chop drives the lever.
    s.swing = _swingSec;
    s.figure.attack(1);

    _spawnTapFeedback(s);
    _maybeRingBell(s);
  }

  /// Each tap = a flash ring + a small spark spray off the lever plate.
  void _spawnTapFeedback(_Striker s) {
    final base = _leverAnchor(s);
    final color = _colorOf(s.slot.id);
    s.flashes.add(_Flash(at: base, life: _flashLifeSec));
    if (s.flashes.length > _maxFlashes) s.flashes.removeAt(0);
    _juice.particles.burst(
      at: base,
      count: 4,
      color: color,
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.8,
      size: 4,
      gravity: 500,
      life: 0.3,
    );
  }

  /// The first time a puck tops out, ring the bell: golden burst + DING popup +
  /// hit-stop + shake. Fires once per striker per round.
  void _maybeRingBell(_Striker s) {
    if (s.belled || s.targetHeight < 1.0) return;
    s.belled = true;
    final bell = _bellAnchor(s);
    final color = _colorOf(s.slot.id);
    _juice.particles.burst(
      at: bell,
      count: 20,
      color: MasherRenderer.bellGold,
      speed: 360,
      spread: math.pi * 2,
      size: 7,
      gravity: 500,
      life: 0.7,
    );
    _juice.particles.burst(
      at: bell,
      count: 12,
      color: color,
      speed: 260,
      size: 5,
      life: 0.6,
    );
    _juice.popup(
      bell.translate(0, -_size.height * 0.04),
      'DING!',
      MasherRenderer.bellGold,
      size: 38,
    );
    _juice.shake.medium();
    _juice.hitStop.trigger(Feel.hitStopDefaultSec);
  }

  /// Bots mash on a cadence clock with [BotProfile]-driven interval + jitter, so
  /// they read as steady (hard) or sloppy (easy) without branching beyond "is
  /// this slot a bot?". The guard caps catch-up taps for huge frame steps.
  void _driveBots(double dt) {
    for (final s in _strikers.values) {
      if (!s.slot.isBot) continue;
      s.botClock += dt;
      var guard = 0;
      while (s.botClock >= s.nextTapAt && guard++ < 8) {
        s.botClock -= s.nextTapAt;
        _tap(s.slot.id);
        s.nextTapAt = _nextBotInterval(s);
      }
    }
  }

  double _nextBotInterval(_Striker s) =>
      math.max(0.04, s.botInterval + ctx.rng.jitter(s.botJitter));

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    MasherRenderer.drawBackground(canvas, size, _animClock);

    final lanes = _lanes(size);
    for (final p in ctx.players) {
      final s = _strikers[p.id];
      final lane = lanes[p.id];
      if (s == null || lane == null) continue;
      _drawStriker(canvas, s, lane);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawStriker(Canvas canvas, _Striker s, _Lane lane) {
    final color = _colorOf(s.slot.id);
    final tower = _Tower.of(lane);

    MasherRenderer.drawTower(
      canvas,
      tower.spec,
      color: color,
      levels: _levels,
      litFraction: s.puckHeight,
      number: s.slot.id + 1,
      glowPulse: 0.5 + 0.5 * math.sin(_animClock * 3.0 + s.slot.id),
    );
    MasherRenderer.drawPuck(
      canvas,
      tower.spec,
      heightFrac: s.puckHeight,
      color: color,
    );
    MasherRenderer.drawBell(
      canvas,
      tower.spec,
      color: color,
      rung: s.belled,
      glowPulse: 0.5 + 0.5 * math.sin(_animClock * 6.0 + s.slot.id),
    );

    // Tap flash rings over the lever plate (behind the striker so the figure
    // stays readable even during a frantic mash).
    for (final f in s.flashes) {
      final t = (f.life / _flashLifeSec).clamp(0.0, 1.0);
      MasherRenderer.drawTapFlash(canvas, f.at, t, color, tower.width);
    }

    // Striker stickman + hammer, standing to the left of the tower hardware and
    // swinging the hammer rightward onto the lever plate. Kept inside the lane.
    final feet = Offset(lane.center - tower.width * 0.66, lane.feet.dy);
    final root = Offset(feet.dx, feet.dy - s.footReach);
    MasherRenderer.drawContactShadow(canvas, feet, tower.width * 0.5);
    MasherRenderer.drawStriker(
      canvas,
      s.figure,
      root,
      hammerSwing: _swingPhase(s),
      hammerHead: tower.leverPlate,
      color: color,
      scale: tower.width,
    );

    // Power meter bar at the lane base.
    MasherRenderer.drawPowerBar(
      canvas,
      Offset(lane.center, lane.feet.dy + tower.width * 0.55),
      tower.width * 1.7,
      s.power,
      color,
    );
  }

  /// 0 (rest) → 1 (hammer slammed onto the plate) → 0 over a swing, eased so the
  /// down-stroke snaps and the recovery is gentle.
  double _swingPhase(_Striker s) {
    if (s.swing <= 0) return 0;
    final p = 1.0 - (s.swing / _swingSec).clamp(0.0, 1.0); // 0..1 through swing
    // Fast down to the plate by ~40% of the swing, then ease back up.
    return p < 0.4 ? easeOut(p / 0.4) : easeOut((1 - p) / 0.6);
  }

  // ── Layout ──────────────────────────────────────────────────────────────────

  /// One vertical lane per player, split evenly across the width.
  Map<int, _Lane> _lanes(Size size) {
    final players = ctx.players;
    final n = players.length;
    final result = <int, _Lane>{};
    final groundY = size.height * 0.86; // foot line
    for (var i = 0; i < n; i++) {
      final center = size.width * (i + 0.5) / n;
      final width = (size.width / n) * 0.5; // tower base width
      result[players[i].id] = _Lane(
        center: center,
        width: width,
        topY: size.height * 0.08,
        feet: Offset(center, groundY),
      );
    }
    return result;
  }

  Offset _leverAnchor(_Striker s) {
    final lane = _lanes(_size)[s.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height / 2);
    return _Tower.of(lane).leverPlate;
  }

  Offset _bellAnchor(_Striker s) {
    final lane = _lanes(_size)[s.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height * 0.1);
    return _Tower.of(lane).bell;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}

/// A player's vertical column of the arena. Pure layout value.
class _Lane {
  final double center; // x of the lane center
  final double width; // tower base width
  final double topY; // top of the playable column (bell sits near here)
  final Offset feet; // ground line under the striker

  const _Lane({
    required this.center,
    required this.width,
    required this.topY,
    required this.feet,
  });
}

/// Derived geometry of one high-striker tower. Wraps a [TowerSpec] (the value
/// the renderer consumes) plus a couple of sim-side anchors so render and sim
/// agree on where the lever plate and bell sit.
class _Tower {
  final TowerSpec spec;

  const _Tower(this.spec);

  factory _Tower.of(_Lane lane) {
    // Lever plate sits low (near the striker's knees) like a real high striker,
    // so the hammer swings down onto it and the rail climbs up from there.
    final plateY = lane.feet.dy - lane.width * 0.45;
    final topY = lane.topY + lane.width * 0.9; // leave room for the bell
    return _Tower(TowerSpec(
      center: lane.center,
      width: lane.width,
      railTop: topY,
      railBottom: plateY,
    ));
  }

  double get width => spec.width;
  Offset get leverPlate => spec.leverPlate;
  Offset get bell => spec.bell;
}

/// A short-lived tap flash ring over the lever. Mutable round-scoped state.
class _Flash {
  final Offset at;
  double life;
  _Flash({required this.at, required this.life});
}

/// Per-player tower state for one round. Mutable round-scoped state (allowed for
/// the duration of a single round).
class _Striker {
  final PlayerSlot slot;
  final TapMashMeter meter; // count-only; tapCount drives the score
  final StickFigure figure;
  final double footReach;
  final double botInterval;
  final double botJitter;

  double power = 0; // 0..1 cadence-built power
  double puckHeight = 0; // 0..1 current rendered puck height
  double targetHeight = 0; // 0..1 height the puck eases toward
  double peakHeight = 0; // best height reached (high-water mark)
  double swing = 0; // seconds of hammer down-stroke remaining
  bool belled = false; // rang the bell at least once
  double sinceTap = 1e9; // seconds since this striker's last tap

  // Bot cadence clock.
  double botClock = 0;
  double nextTapAt;

  final List<_Flash> flashes = <_Flash>[];

  _Striker({
    required this.slot,
    required this.meter,
    required this.figure,
    required this.footReach,
    required this.botInterval,
    required this.botJitter,
  }) : nextTapAt = botInterval;
}
