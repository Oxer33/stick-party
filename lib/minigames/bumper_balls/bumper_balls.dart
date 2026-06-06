import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'bumper_render.dart';

/// Bumper Balls — neon knockout. Every player is a glowing bumper ball on a
/// circular platform. One tap is a BURST-DASH along the ball's current drift
/// (or straight at the platform center when it is idle), letting players carom
/// off rivals and knock them off the edge.
///
/// Depth (still one-touch):
///  * Dash cooldown with a readable charge ring; the ball never stalls because
///    an idle tap fires inward toward the center.
///  * Elastic carom (PushArena) plus a speed- and head-on-scaled knockback
///    bonus, so a fast, square hit flings a rival much further than a graze.
///  * Squash & stretch: balls stretch along their heading at speed and flatten
///    on impact, with impact spark rings stamped at each new contact.
///  * The platform slowly shrinks after a grace period (sudden death) so
///    matches always converge; a glowing red danger band marks the edge.
///  * Ring-out = elimination: pop burst + brief slow-mo (hit-stop) + shake +
///    "RING OUT!" popup. Last ball on the platform wins; on the time limit the
///    survivors are ranked by distance to center.
///
/// Bots dash toward the nearest rival but shove back toward the center when
/// they are near the edge (self-preservation); [BotProfile] governs timing and
/// aim error so they read as deliberate, not random.
class BumperBalls extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'bumper_balls',
        name: 'Bumper Balls',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Arena / sim tuning (no magic numbers inline) ────────────────────────────
  static const double _timeLimit = 35;
  static const double _ringRadiusFactor = 0.42;
  static const double _bodyRadiusFactor = 0.052; // glossy bumper footprint
  static const double _ringFriction = 0.965; // slick floor (long glides)
  static const double _ringRestitution = 0.97; // very bouncy caroms
  static const double _spawnRadiusFactor = 0.5;

  // ── Dash tuning ─────────────────────────────────────────────────────────────
  static const double _dashPerSecond = 3.2; // base impulse ≈ ring*3.2 /sec
  static const double _dashCooldownSec = 0.34;
  static const double _nearStillSpeed = 22.0; // below → aim toward center
  static const double _maxSpeedRef = 700.0; // speed mapped to full trail/stretch
  static const double _trailLifeSec = 0.2;

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef = 620.0; // speed mapped to full knockback
  static const double _contactBonusScale = 0.38; // bonus impulse / attacker speed
  static const double _headOnExtra = 0.85; // extra multiplier for a head-on hit
  static const double _heavyHitSpeed = 380.0; // above → heavy shake + hit-stop
  static const double _squashOnHit = 0.42; // squash amount stamped on impact
  static const double _squashDecayPerSec = 3.2; // how fast squash relaxes
  static const double _impactRingLifeSec = 0.32;
  static const double _impactRingMaxFactor = 2.4; // ring max radius / body R

  // ── Shrinking platform (sudden death) tuning ────────────────────────────────
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.5; // floor as fraction of initial R
  static const double _shrinkPerSec = 0.024; // fraction of initial R per second

  // ── Ring-out tuning ─────────────────────────────────────────────────────────
  static const double _koPopLift = 0.06; // extra popup lift / body R
  static const double _ringOutGraceFactor = 1.02; // detect just past current R

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botEdgeBackoff = 0.55; // dist/ring above → retreat inward
  static const double _botAimErrorRad = 0.7; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip dash while already this fast

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFF5FE0FF); // neon platform rim accent
  static const Color _popupColor = Color(0xFFFF5A78);
  static const int _ambientMotes = 26;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for ambient pulse (never scaled)

  late Size _size;
  late Offset _center;
  late double _ringRadius; // initial (max) radius — also the arena's radius
  late double _currentRingRadius; // shrinking radius for ring-out + visuals
  late double _bodyRadius;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, _BallState> _ball = <int, _BallState>{};
  final List<int> _eliminationOrder = <int>[];
  final Set<int> _eliminated = <int>{};
  final List<_ImpactRing> _impacts = <_ImpactRing>[];

  /// Ambient energy mote positions (deterministic; drift handled at render).
  final List<Offset> _motes = <Offset>[];

  /// Pairs (encoded keys) overlapping last frame, so a contact fires its
  /// knockback bonus + impact spark exactly once per impact.
  final Set<int> _contactPairs = <int>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _center = Offset(_size.width / 2, _size.height / 2);
    final minSide = math.min(_size.width, _size.height);
    _ringRadius = minSide * _ringRadiusFactor;
    _currentRingRadius = _ringRadius;
    _bodyRadius = minSide * _bodyRadiusFactor;

    _arena = PushArena(
      center: _center,
      ringRadius: _ringRadius,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies();
    _seedMotes();
    begin();
  }

  /// Place one ball per player evenly on a spawn circle + dash state + bot clock.
  void _buildBodies() {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * _spawnRadiusFactor;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final angle = (i / count) * math.pi * 2 - math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _arena.add(Body(id: p.id, pos: pos, radius: _bodyRadius));
      _ball[p.id] = _BallState();
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  void _seedMotes() {
    final rng = ctx.rng;
    for (var i = 0; i < _ambientMotes; i++) {
      _motes.add(Offset(rng.range(0, _size.width), rng.range(0, _size.height)));
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _tryDash(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _tickBallStates(dt);
    _tickImpacts(dt);
    _driveBots(dt);
    _shrinkRing(dt);

    _arena.update(sdt);

    _resolveContacts();
    _detectRingOuts();
    _resolveOutcome();
  }

  // ── Dash ─────────────────────────────────────────────────────────────────────

  void _tickBallStates(double dt) {
    for (final s in _ball.values) {
      s.tick(dt, _squashDecayPerSec);
    }
  }

  void _tickImpacts(double dt) {
    for (final r in _impacts) {
      r.life -= dt;
    }
    _impacts.removeWhere((r) => r.life <= 0);
  }

  /// Human tap: burst along the ball's heading; if nearly still, fire straight
  /// at the platform center so the ball never stalls. Off cooldown only.
  void _tryDash(int playerId) {
    final self = _bodyOf(playerId);
    final state = _ball[playerId];
    if (self == null || !self.alive || state == null || !state.ready) return;

    _commitDash(playerId, self, _dashDirFor(self));
  }

  /// Bots dash on their reaction clock with [BotProfile]-driven timing, aim
  /// error and edge self-preservation so they read as deliberate bumpers.
  void _driveBots(double dt) {
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!_isAlive(id)) continue;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final state = _ball[playerId];
    if (self == null || !self.alive || state == null || !state.ready) return;

    // Deliberate hesitation (mistake), scaled by difficulty.
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return;

    // Self-preservation: when near the edge, shove back toward the center.
    if (_isNearEdge(self)) {
      var inward = _normalize(_center - self.pos);
      if (inward == Offset.zero) inward = const Offset(0, -1);
      _commitDash(playerId, self, inward);
      return;
    }

    // Don't waste a dash while already carrying lots of speed.
    if (self.vel.distance > _botCarrySpeed) return;

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;

    var dir = _normalize(targetPos - self.pos);
    if (dir == Offset.zero) dir = const Offset(0, -1);
    // Aim jitter: more error at low accuracy.
    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;
    final a = math.atan2(dir.dy, dir.dx) + ctx.rng.jitter(err);
    _commitDash(playerId, self, Offset(math.cos(a), math.sin(a)));
  }

  /// Burst-dash direction: the ball's drift heading, or toward the center when
  /// it is nearly still (so a tap is always meaningful).
  Offset _dashDirFor(Body self) {
    if (self.vel.distance >= _nearStillSpeed) {
      final dir = _normalize(self.vel);
      if (dir != Offset.zero) return dir;
    }
    var inward = _normalize(_center - self.pos);
    if (inward == Offset.zero) inward = const Offset(0, -1);
    return inward;
  }

  /// Shared dash commit: impulse, cooldown, trail, a forward stretch hint and a
  /// directional spark telegraph. Used by humans and bots so the feel matches.
  void _commitDash(int playerId, Body self, Offset dir) {
    final state = _ball[playerId];
    if (state == null || !state.ready) return;

    final magnitude = _ringRadius * _dashPerSecond;
    _arena.impulse(playerId, dir * magnitude);

    state.fire(_dashCooldownSec);
    state.trail = _DashTrail(dir: dir, life: _trailLifeSec);
    state.stretchDir = dir;

    // Directional spark telegraph behind the burst.
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: 7,
      color: _colorOf(playerId),
      speed: 200,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 120,
      life: 0.3,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: 4);
  }

  bool _isNearEdge(Body b) =>
      (b.pos - _center).distance > _currentRingRadius * _botEdgeBackoff;

  /// Nearest alive opponent's position, or null when none remain.
  Offset? _nearestOpponentPos(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return null;
    Offset? best;
    var bestDist = double.infinity;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      final d = (b.pos - self.pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = b.pos;
      }
    }
    return best;
  }

  // ── Contact knockback (speed + head-on scaling) ─────────────────────────────

  /// Detect newly-touching alive pairs; apply a bonus shove to the slower ball
  /// scaled by the attacker's speed and how head-on the hit is, plus squash and
  /// an impact spark ring. Tracked so each contact fires exactly once.
  void _resolveContacts() {
    final alive = _arena.aliveBodies;
    final current = <int>{};
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        final a = alive[i];
        final b = alive[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        final minDist = a.radius + b.radius;
        if (dist >= minDist) continue;

        final key = _pairKey(a.id, b.id);
        current.add(key);
        if (_contactPairs.contains(key)) continue; // already counted

        _applyKnockback(a, b, delta, dist);
      }
    }
    _contactPairs
      ..clear()
      ..addAll(current);
  }

  void _applyKnockback(Body a, Body b, Offset delta, double dist) {
    final normal = dist > 1e-6 ? delta / dist : const Offset(1, 0);
    final attacker = a.vel.distance >= b.vel.distance ? a : b;
    final victim = identical(attacker, a) ? b : a;
    // Normal points from attacker toward victim.
    final toVictim = identical(attacker, a) ? normal : -normal;

    final speed = attacker.vel.distance;
    final at = Offset.lerp(a.pos, b.pos, 0.5) ?? a.pos;

    // Always stamp an impact spark + squash, even on gentle taps.
    _spawnImpact(at, _colorOf(attacker.id));
    _ball[a.id]?.bump(_squashOnHit, -normal);
    _ball[b.id]?.bump(_squashOnHit, normal);

    if (speed < 1) {
      _juice.shake.light();
      return;
    }

    final attackerDir = attacker.vel / speed;
    final headOn = (attackerDir.dx * toVictim.dx + attackerDir.dy * toVictim.dy)
        .clamp(0.0, 1.0);
    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.4);
    final bonus = _ringRadius *
        _contactBonusScale *
        speedFactor *
        (1.0 + _headOnExtra * headOn);
    _arena.impulse(victim.id, toVictim * bonus);

    if (speed >= _heavyHitSpeed) {
      _juice.hit(at, _colorOf(attacker.id), sparks: 12);
      _juice.shake.medium();
    } else {
      _juice.particles.burst(
        at: at,
        count: 6,
        color: _colorOf(attacker.id),
        speed: 200,
        size: 4,
        life: 0.32,
      );
      _juice.shake.light();
    }
  }

  void _spawnImpact(Offset at, Color color) {
    _impacts.add(_ImpactRing(at: at, color: color, life: _impactRingLifeSec));
  }

  // ── Shrinking platform ──────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
    final floor = _ringRadius * _minRingFactor;
    if (_currentRingRadius <= floor) return;
    _currentRingRadius = (_currentRingRadius - _ringRadius * _shrinkPerSec * dt)
        .clamp(floor, _ringRadius);
  }

  // ── Ring-out detection (uses the shrinking radius) ──────────────────────────

  /// Mark any ball whose center has left the *current* (shrinking) platform as
  /// eliminated and fire the KO sequence (pop + slow-mo + shake + popup) once
  /// each. The arena only culls at its own larger radius, so we own this.
  void _detectRingOuts() {
    final edge = _currentRingRadius * _ringOutGraceFactor;
    for (final b in _arena.bodies) {
      if (!b.alive || _eliminated.contains(b.id)) continue;
      if ((b.pos - _center).distance <= edge) continue;

      b.alive = false;
      b.vel = Offset.zero;
      _eliminated.add(b.id);
      _eliminationOrder.add(b.id);

      _juice.ko(b.pos, _colorOf(b.id));
      _spawnImpact(b.pos, _colorOf(b.id));
      _juice.popup(
        b.pos.translate(0, -_bodyRadius * (1.6 + _koPopLift)),
        'RING OUT!',
        _popupColor,
        size: 34,
      );
    }
  }

  // ── Outcome ──────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    final alive = _arena.aliveBodies;
    if (alive.length <= 1) {
      _finishRanked(alive);
      return;
    }
    if (_elapsed >= _timeLimit) {
      _finishRanked(alive);
    }
  }

  /// Survivors first (closest-to-center best), then reverse elimination order.
  void _finishRanked(List<Body> alive) {
    final ranked = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    finishByOrder(_dedupeAllPlayers([
      ...ranked,
      ..._eliminationOrder.reversed,
    ]));
  }

  // ── Render ────────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    BumperRenderer.drawBackground(canvas, size, _center, _ringRadius);
    BumperRenderer.drawAmbientMotes(canvas, _motes, _animClock);
    BumperRenderer.drawPlatform(
      canvas,
      _center,
      _currentRingRadius,
      accent: _accent,
      dangerPulse: _dangerPulse(),
      t: _animClock,
    );

    _drawBalls(canvas);
    _drawImpacts(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

  /// Danger band pulse: brighter as the platform shrinks + a steady throb.
  double _dangerPulse() {
    final shrink =
        1.0 - (_currentRingRadius / _ringRadius).clamp(_minRingFactor, 1.0);
    final throb = 0.5 + 0.5 * math.sin(_animClock * 4.0);
    return (0.35 + shrink + 0.25 * throb).clamp(0.0, 1.0);
  }

  void _drawBalls(Canvas canvas) {
    for (final b in _arena.aliveBodies) {
      final state = _ball[b.id];
      final color = _colorOf(b.id);
      final speed = b.vel.distance;
      final speedFrac = (speed / _maxSpeedRef).clamp(0.0, 1.0);
      final heading = _normalize(b.vel);

      // Soft contact shadow under the ball, on the platform.
      BumperRenderer.drawContactShadow(
          canvas, Offset(b.pos.dx, b.pos.dy + b.radius * 0.7), b.radius);

      // Motion trail behind a recent dash / fast drift.
      final trail = state?.trail;
      if (trail != null) {
        BumperRenderer.drawTrail(
            canvas, b.pos, trail.dir, b.radius, color, trail.strength, speedFrac);
      } else if (speedFrac > 0.25 && heading != Offset.zero) {
        BumperRenderer.drawTrail(
            canvas, b.pos, heading, b.radius, color, 0.6, speedFrac);
      }

      // Speed-stretch combined with a relaxing impact squash.
      final stretch = speedFrac * 0.28 + (state?.squash ?? 0);
      final stretchDir = state?.stretchDir ??
          (heading == Offset.zero ? const Offset(1, 0) : heading);
      final lookDir = heading == Offset.zero ? const Offset(0, 1) : heading;

      BumperRenderer.drawBall(
        canvas,
        b.pos,
        b.radius,
        color,
        squash: stretch,
        stretchDir: stretchDir,
        lookDir: lookDir,
        ready: state?.ready ?? true,
        displayNumber: b.id + 1,
      );
    }
  }

  void _drawImpacts(Canvas canvas) {
    final maxR = _bodyRadius * _impactRingMaxFactor;
    for (final r in _impacts) {
      BumperRenderer.drawImpactRing(canvas, r.at, maxR, r.color, r.progress);
    }
  }

  // ── Small pure helpers ────────────────────────────────────────────────────────

  Body? _bodyOf(int id) {
    for (final b in _arena.bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  bool _isAlive(int id) => _bodyOf(id)?.alive ?? false;

  double _distToCenter(int id) {
    final b = _bodyOf(id);
    return b == null ? double.infinity : (b.pos - _center).distance;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  /// Stable order-independent key for a pair of player ids (0..3).
  static int _pairKey(int a, int b) => a < b ? a * 8 + b : b * 8 + a;

  /// Ensure every player id appears exactly once, preserving [order] first.
  List<int> _dedupeAllPlayers(List<int> order) {
    final seen = <int>{};
    final result = <int>[];
    for (final id in order) {
      if (seen.add(id)) result.add(id);
    }
    for (final p in ctx.players) {
      if (seen.add(p.id)) result.add(p.id);
    }
    return result;
  }

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}

/// Per-player ball bookkeeping: dash cooldown, impact squash, stretch heading
/// and the active trail. Mutable round-scoped state (allowed for one round).
class _BallState {
  double _cooldown = 0; // seconds remaining until ready
  double squash = 0; // current squash amount (relaxes toward 0)
  Offset stretchDir = const Offset(1, 0); // axis the squash/stretch acts along
  _DashTrail? trail;

  bool get ready => _cooldown <= 0;

  void tick(double dt, double squashDecayPerSec) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (squash != 0) {
      final relax = squashDecayPerSec * dt;
      squash = squash > 0
          ? math.max(0, squash - relax)
          : math.min(0, squash + relax);
    }
    if (trail != null) {
      trail!.life -= dt;
      if (trail!.life <= 0) trail = null;
    }
  }

  void fire(double cooldownSec) => _cooldown = cooldownSec;

  /// Stamp an impact squash flattening along [dir] (kept as the larger of the
  /// current and new magnitude so rapid double-hits still read).
  void bump(double amount, Offset dir) {
    if (amount.abs() > squash.abs()) {
      squash = -amount.abs(); // negative = flatten on impact
      if (dir != Offset.zero) stretchDir = dir;
    }
  }
}

/// A short-lived directional trail anchor for a dash / fast drift.
class _DashTrail {
  final Offset dir;
  double life;
  final double maxLife;
  _DashTrail({required this.dir, required this.life}) : maxLife = life;

  /// 0..1 trail strength (fades over its life).
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}

/// A short-lived expanding impact spark ring stamped at a collision/KO point.
class _ImpactRing {
  final Offset at;
  final Color color;
  double life;
  final double maxLife;
  _ImpactRing({required this.at, required this.color, required this.life})
      : maxLife = life;

  /// 0..1 animation progress (0 = just spawned, 1 = done).
  double get progress => maxLife <= 0 ? 1 : (1 - life / maxLife).clamp(0.0, 1.0);
}
