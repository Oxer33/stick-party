import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'sumo_render.dart';

/// Sumo Smash — every player is a sumo wrestler in a circular dohyo. One tap is
/// a DASH/SHOVE toward the nearest alive opponent.
///
/// Depth (still one-touch):
///  * Dash cooldown with a readable cooldown ring; well-timed chained dashes
///    build a small momentum bonus that boosts the next shove.
///  * Knockback scales with the attacker's incoming speed and a head-on vs
///    glancing factor — heavier hits fling the victim (ragdoll) much further.
///  * The dohyo slowly shrinks after a grace period (sudden death) so matches
///    always resolve; a glowing danger band marks the edge.
///  * Ring-out = elimination: ragdoll fling + heavy hit-stop + burst + shake +
///    "RING OUT!" popup. Last wrestler standing wins; on the time limit the
///    survivors are ranked by distance to center.
///
/// Bots dash toward the nearest opponent but back off toward the center when
/// they are near the edge (self-preservation); [BotProfile] governs timing and
/// aim error so they feel deliberate, not random.
class SumoSmash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'sumo_smash',
        name: 'Sumo Smash',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Arena / sim tuning (no magic numbers inline) ───────────────────────────
  static const double _timeLimit = 35;
  static const double _ringRadiusFactor = 0.42;
  static const double _bodyRadiusFactor = 0.072; // chunky sumo footprint
  static const double _ringFriction = 0.955; // grippy clay
  static const double _ringRestitution = 0.86;
  static const double _spawnRadiusFactor = 0.55;

  // ── Dash / momentum tuning ──────────────────────────────────────────────────
  static const double _dashPerSecond = 4.4; // base impulse ≈ ring*4.4 /sec
  static const double _dashSelfPushback = 0.10; // recoil away from target
  static const double _dashCooldownSec = 0.35;
  static const double _momentumWindowSec = 0.30; // dash within this → +momentum
  static const double _momentumPerChain = 0.34; // momentum gained per good chain
  static const double _momentumDecayPerSec = 0.9; // bleed when not chaining
  static const double _momentumDashBoost = 0.6; // +60% impulse at full momentum
  static const double _trailLifeSec = 0.22;

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef = 600.0; // speed mapped to full knockback
  static const double _contactBonusScale = 0.55; // bonus impulse / attacker speed
  static const double _headOnExtra = 0.8; // extra multiplier for a head-on hit
  static const double _heavyHitSpeed = 360.0; // above → heavy shake + hit-stop

  // ── Shrinking ring (sudden death) tuning ────────────────────────────────────
  static const double _shrinkDelaySec = 10.0;
  static const double _minRingFactor = 0.46; // floor as fraction of initial R
  static const double _shrinkPerSec = 0.022; // fraction of initial R per second

  // ── Ring-out fling tuning ───────────────────────────────────────────────────
  static const double _flingBaseFactor = 0.45; // ragdoll fling / ring radius
  static const double _flingSpeedFactor = 0.5; // + share of victim speed

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botEdgeBackoff = 0.66; // dist/ring above → retreat
  static const double _botAimErrorRad = 0.6; // max aim jitter at accuracy 0
  static const double _botStrikeRange = 7.0; // commit only within range*bodyR
  static const double _botCarrySpeed = 90.0; // skip dash while already this fast
  static const double _figureScale = 1.85; // scaled-up sumo bodies
  static const double _torsoWiden = 2.1; // hefty torso
  static const double _limbWiden = 1.8; // hefty limbs

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFFFFC062); // dohyo rim accent
  static const int _dustMotes = 22;
  static const double _runSpeed = 38.0;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for breathing/dust (never scaled)

  late Size _size;
  late Offset _center;
  late double _ringRadius; // initial (max) radius — also the arena's radius
  late double _currentRingRadius; // shrinking radius used for ring-out + visuals
  late double _bodyRadius;
  late StickProportions _proportions;
  late double _footReach; // pelvis→foot length at rest (for grounding)

  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, _DashState> _dash = <int, _DashState>{};
  final List<int> _eliminationOrder = <int>[];
  final Set<int> _ragdolled = <int>{};

  /// Pairs (encoded keys) that were overlapping last frame, so a contact only
  /// fires its knockback bonus + juice once per impact.
  final Set<int> _contactPairs = <int>{};

  /// Ambient dust positions (deterministic; drift handled at render time).
  final List<Offset> _dust = <Offset>[];

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
    _proportions = _sumoProportions();
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = _proportions.thigh + _proportions.shin;

    _arena = PushArena(
      center: _center,
      ringRadius: _ringRadius,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies();
    _seedDust();
    begin();
  }

  /// Place one wrestler per player evenly on a spawn circle, build its figure
  /// (scaled-up, hefty stance, player color) + dash state + bot clock.
  void _buildBodies() {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * _spawnRadiusFactor;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final angle = (i / count) * math.pi * 2 - math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _arena.add(Body(id: p.id, pos: pos, radius: _bodyRadius));

      final facing = pos.dx <= _center.dx ? 1.0 : -1.0;
      _figures[p.id] = StickFigure(
        proportions: _proportions,
        style: _styleFor(Color(p.colorArgb)),
        facing: facing,
      )..setLoco(LocoState.idle);

      _dash[p.id] = _DashState();
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Hefty, wide sumo build derived from the hero proportions.
  StickProportions _sumoProportions() {
    final base = StickProportions.hero.scaled(_figureScale);
    return StickProportions(
      spine: base.spine,
      neck: base.neck,
      head: base.head,
      upperArm: base.upperArm,
      foreArm: base.foreArm,
      thigh: base.thigh,
      shin: base.shin,
      torsoWidth: base.torsoWidth * _torsoWiden,
      limbWidth: base.limbWidth * _limbWiden,
    );
  }

  /// Bright sumo style: player-color fill with a bright outline + strong glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.45),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0, // we draw our own soft contact shadow
        gradientBottom: 0.5,
        smearAlpha: 0.28,
      );

  void _seedDust() {
    final rng = ctx.rng;
    for (var i = 0; i < _dustMotes; i++) {
      _dust.add(Offset(
        rng.range(0, _size.width),
        rng.range(0, _size.height),
      ));
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

    _tickDashStates(dt);
    _driveBots(dt);
    _shrinkRing(dt);

    _arena.update(sdt);

    _resolveContacts();
    _syncFigures(sdt);
    _detectRingOuts();
    _resolveOutcome();
  }

  // ── Dash / momentum ─────────────────────────────────────────────────────────

  void _tickDashStates(double dt) {
    for (final s in _dash.values) {
      s.tick(dt, _momentumDecayPerSec);
    }
  }

  /// Human tap: dash toward the nearest opponent if off cooldown.
  void _tryDash(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null || !self.alive) return;
    if (!(_dash[playerId]?.ready ?? false)) return;

    final target = _nearestOpponentPos(playerId);
    if (target == null) return;
    var dir = _normalize(target - self.pos);
    if (dir == Offset.zero) dir = const Offset(0, -1);
    _commitDash(playerId, self, dir);
  }

  /// Bots dash on their reaction clock with [BotProfile]-driven timing, aim
  /// error, edge self-preservation and tactical spacing so they read as
  /// deliberate fighters rather than a metronomic pile-up.
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
    final state = _dash[playerId];
    if (self == null || !self.alive || state == null || !state.ready) return;

    // Deliberate hesitation (mistake), scaled by difficulty.
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return;

    final nearEdge = _isNearEdge(self);
    final targetPos = _nearestOpponentPos(playerId);

    // Self-preservation: when near the edge, shove back toward the center.
    if (nearEdge) {
      final inward = _normalize(_center - self.pos);
      if (inward != Offset.zero) _commitDash(playerId, self, inward);
      return;
    }
    if (targetPos == null) return;

    // Tactical spacing: only commit a shove when the target is within an
    // effective range, and don't waste a dash while already carrying speed.
    final toTarget = targetPos - self.pos;
    final range = toTarget.distance;
    final inRange = range <= _bodyRadius * _botStrikeRange;
    final alreadyFast = self.vel.distance > _botCarrySpeed;
    if (!inRange || alreadyFast) return;

    var dir = _normalize(toTarget);
    if (dir == Offset.zero) dir = const Offset(0, -1);
    // Aim jitter: more error at low accuracy.
    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;
    final a = math.atan2(dir.dy, dir.dx) + ctx.rng.jitter(err);
    _commitDash(playerId, self, Offset(math.cos(a), math.sin(a)));
  }

  /// Shared dash commit: momentum chaining, impulse + recoil, cooldown, trail,
  /// figure dash pose and a directional dust kick. Used by humans and bots so
  /// the feel stays identical.
  void _commitDash(int playerId, Body self, Offset dir) {
    final state = _dash[playerId];
    if (state == null || !state.ready) return;

    // Chained-within-window dashes grow momentum (decays otherwise).
    if (state.sinceDash <= _momentumWindowSec) {
      state.momentum = (state.momentum + _momentumPerChain).clamp(0.0, 1.0);
    }
    final boost = 1.0 + _momentumDashBoost * state.momentum;
    final magnitude = _ringRadius * _dashPerSecond * boost;

    _arena.impulse(playerId, dir * magnitude);
    _arena.impulse(playerId, -dir * magnitude * _dashSelfPushback);

    state.fire(_dashCooldownSec);
    state.trail = _DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }

    // Directional dust kick behind the push + a light spark telegraph.
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: 7,
      color: const Color(0xFFE7C58C),
      speed: 150,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 5,
      gravity: 200,
      life: 0.35,
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

  /// Detect newly-touching alive pairs; apply a bonus shove to the slower body
  /// scaled by the attacker's speed and how head-on the hit is, plus impact
  /// juice. Tracked so each contact fires exactly once.
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
    if (speed < 1) return;

    final attackerDir = attacker.vel / speed;
    final headOn =
        (attackerDir.dx * toVictim.dx + attackerDir.dy * toVictim.dy)
            .clamp(0.0, 1.0);
    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.4);
    final bonus = _ringRadius *
        _contactBonusScale *
        speedFactor *
        (1.0 + _headOnExtra * headOn);

    _arena.impulse(victim.id, toVictim * bonus);

    final at = Offset.lerp(a.pos, b.pos, 0.5) ?? a.pos;
    if (speed >= _heavyHitSpeed) {
      _juice.hit(at, _colorOf(attacker.id), sparks: 12);
      _juice.shake.medium();
    } else {
      _juice.particles.burst(
        at: at,
        count: 6,
        color: _colorOf(attacker.id),
        speed: 200,
        size: 5,
        life: 0.35,
      );
      _juice.shake.light();
    }
  }

  // ── Shrinking ring ──────────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
    final floor = _ringRadius * _minRingFactor;
    if (_currentRingRadius <= floor) return;
    _currentRingRadius =
        (_currentRingRadius - _ringRadius * _shrinkPerSec * dt)
            .clamp(floor, _ringRadius);
  }

  // ── Figures ─────────────────────────────────────────────────────────────────

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null && body.alive && !fig.isRagdoll) {
        fig.setLoco(
            body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle);
      }
      fig.update(dt);
    }
  }

  // ── Ring-out detection (uses the shrinking radius) ──────────────────────────

  /// Mark any wrestler whose center has left the *current* (shrinking) ring as
  /// eliminated, fling it as a ragdoll, and fire the KO sequence once each.
  void _detectRingOuts() {
    for (final b in _arena.bodies) {
      if (!b.alive || _ragdolled.contains(b.id)) continue;
      if ((b.pos - _center).distance <= _currentRingRadius) continue;

      // Eliminate (the arena only culls at its own larger radius).
      final outVel = b.vel;
      b.alive = false;
      b.vel = Offset.zero;
      _ragdolled.add(b.id);
      _eliminationOrder.add(b.id);

      _juice.ko(b.pos, _colorOf(b.id));
      _juice.popup(
          b.pos.translate(0, -_bodyRadius * 1.6), 'RING OUT!', _accent,
          size: 34);

      final fig = _figures[b.id];
      if (fig != null) {
        final outward = _normalize(b.pos - _center);
        final fling = outward * _ringRadius * _flingBaseFactor +
            outVel * _flingSpeedFactor;
        final groundY = b.pos.dy + b.radius * 2;
        fig.enterRagdoll(_figureRoot(b), groundY, fling);
      }
    }
  }

  // ── Outcome ─────────────────────────────────────────────────────────────────

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

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SumoRenderer.drawBackground(canvas, size, _center, _ringRadius);
    SumoRenderer.drawAmbientDust(canvas, _dust, _animClock);
    SumoRenderer.drawDohyo(
      canvas,
      _center,
      _currentRingRadius,
      accent: _accent,
      dangerPulse: _dangerPulse(),
    );

    _drawWrestlers(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

  /// Danger band pulse: brighter as the ring shrinks + a steady throb.
  double _dangerPulse() {
    final shrink =
        1.0 - (_currentRingRadius / _ringRadius).clamp(_minRingFactor, 1.0);
    final throb = 0.5 + 0.5 * math.sin(_animClock * 4.0);
    return (0.35 + shrink + 0.25 * throb).clamp(0.0, 1.0);
  }

  void _drawWrestlers(Canvas canvas) {
    for (final b in _arena.bodies) {
      final fig = _figures[b.id];
      if (fig == null) continue;

      // Ragdolled losers render their own self-anchored frame as they tumble
      // off; nothing else is drawn for them.
      if (fig.isRagdoll) {
        SumoRenderer.drawWrestler(canvas, fig, b.pos);
        continue;
      }
      if (!b.alive) continue;

      final feet = _feetOf(b);
      final color = _colorOf(b.id);
      final state = _dash[b.id];

      // Motion trail behind a recent dash (anchored at the body center).
      if (state?.trail != null) {
        final tr = state!.trail!;
        final from = tr.from;
        final to = tr.from + tr.dir * (_bodyRadius * 2.2);
        SumoRenderer.drawDashTrail(
            canvas, from, to, _bodyRadius, color, tr.strength);
      }

      SumoRenderer.drawContactShadow(canvas, feet, _bodyRadius);
      SumoRenderer.drawIdMarker(canvas, feet, _bodyRadius, color, b.id + 1);

      // Cooldown / momentum arc on the ground line.
      if (state != null) {
        SumoRenderer.drawCooldownArc(
          canvas,
          feet,
          _bodyRadius,
          state.cooldownFill(_dashCooldownSec),
          state.ready,
          color,
          state.momentum,
        );
      }

      // The wrestler, then the mawashi belt across the pelvis on top.
      SumoRenderer.drawWrestler(canvas, fig, _figureRoot(b));
      SumoRenderer.drawBelt(canvas, _pelvisOf(b), _bodyRadius, fig.facing, color);
    }
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// Ground line beneath a wrestler: bottom of the footprint disc it stands on.
  Offset _feetOf(Body b) => Offset(b.pos.dx, b.pos.dy + b.radius);

  /// Pelvis/render anchor for the figure. The skeleton anchors its pelvis here
  /// and legs drop ~[_footReach] below, so we lift the pelvis by [_footReach]
  /// to plant the feet on the footprint — the sumo stands on its base disc.
  Offset _figureRoot(Body b) =>
      Offset(b.pos.dx, b.pos.dy + b.radius - _footReach);

  /// The mawashi sits at the pelvis, i.e. the figure render root.
  Offset _pelvisOf(Body b) => _figureRoot(b);

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

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}

/// Per-player dash bookkeeping: cooldown, chain momentum and the active trail.
/// Mutable round-scoped state (allowed for the duration of one round).
class _DashState {
  double _cooldown = 0; // seconds remaining until ready
  double sinceDash = 1e9; // seconds since the last dash (for chaining)
  double momentum = 0; // 0..1 chain bonus
  _DashTrail? trail;

  bool get ready => _cooldown <= 0;

  /// Fraction of the cooldown already elapsed in 0..1 (1 = ready).
  double cooldownFill(double total) {
    if (total <= 0) return 1;
    return (1.0 - (_cooldown / total)).clamp(0.0, 1.0);
  }

  void tick(double dt, double momentumDecayPerSec) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    sinceDash += dt;
    // Momentum bleeds away once the chain window has clearly passed.
    if (momentum > 0) {
      momentum = math.max(0, momentum - momentumDecayPerSec * dt);
    }
    if (trail != null) {
      trail!.life -= dt;
      if (trail!.life <= 0) trail = null;
    }
  }

  void fire(double cooldownSec) {
    _cooldown = cooldownSec;
    sinceDash = 0;
  }
}

/// A short-lived directional trail anchor for a dash.
class _DashTrail {
  final Offset from;
  final Offset dir;
  double life;
  final double maxLife;
  _DashTrail({required this.from, required this.dir, required this.life})
      : maxLife = life;

  /// 0..1 trail strength (fades over its life).
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}
