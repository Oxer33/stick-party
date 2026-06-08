import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'bumper_fx.dart';
import 'bumper_render.dart';

/// Bumper Balls — neon knockout. Every player is a glowing bumper ball on a
/// circular platform and shoves rivals off the edge.
///
/// CONTROL (the heart of it — full player agency, one touch; mirrors Sumo):
///  * There is NO rotating idle arrow. The aim ALWAYS tracks the nearest
///    opponent, so a tap or charged bump always strikes straight at it — the
///    player picks WHEN and HOW HARD, never WHERE-by-timing-a-sweep.
///  * Quick TAP  → a small nudge straight toward the nearest opponent
///    (positioning / pressure), or a panic save toward the centre when bots
///    auto-target the edge.
///  * HOLD then release → a charge meter fills; releasing fires a powerful bump
///    toward the nearest opponent (power ∝ charge). While charging, a telegraph
///    points at the target so the player sees exactly where the bump will land.
///  Nothing is auto-fired: the player still decides every shove.
///
/// Feel: a slick-but-grippy floor so bumps carry without instantly ejecting an
/// idle ball; elastic caroms (PushArena) plus a speed- and head-on-scaled
/// knockback bonus, so a fast square hit flings a rival much further than a
/// graze. Squash & stretch on impact, impact spark rings, motion trails, and a
/// platform that slowly shrinks after a grace period so matches always resolve.
///
/// Bots get a short warmup before they engage, then approach an opponent with a
/// light nudge and commit a charged shove only when close; near the edge they
/// save themselves toward the centre. [BotProfile] governs timing, charge and
/// aim error so they read as deliberate, not random — and never eject an idle
/// player in the first several seconds.
class BumperBalls extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'bumper_balls',
        name: 'Bumper Balls',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP / HOLD',
      );

  // ── Arena / sim tuning ──────────────────────────────────────────────────────
  // Device-tuned (matched to Sumo Smash) for a ~8-25s match: small bodies + big
  // ring + grippy floor + a weak base bump so a single hit never instantly
  // ejects an idle ball; ring-outs come from positioning + charged bumps near
  // the edge.
  static const double _timeLimit = 35;
  static const double _ringRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.05; // glossy bumper footprint
  static const double _ringFriction = 0.95; // grippy so bumps don't slide off
  static const double _ringRestitution = 0.92; // lively caroms, not chaotic
  static const double _spawnRadiusFactor = 0.55;

  // ── Aim + charge control tuning (mirrors Sumo) ──────────────────────────────
  // No idle sweep: the aim always tracks the nearest opponent (see
  // [_tickBallStates] / [_aimAtNearest]), so a tap/charge strikes straight at it.
  static const double _chargeTimeSec = 0.6; // hold time to full charge
  static const double _cooldownSec = 0.24; // snappy recovery between bumps
  static const double _dashBase = 1.4; // quick tap = a small nudge
  static const double _dashCharge = 3.8; // full hold = a strong launch
  static const double _selfPushback = 0.08; // recoil opposite the bump
  static const double _trailLifeSec = 0.2;
  static const double _maxSpeedRef = 700.0; // speed mapped to full trail/stretch

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef = 700.0; // speed mapped to full knockback
  static const double _contactBonusScale = 0.28; // bonus impulse / attacker speed
  static const double _headOnExtra = 0.85; // extra multiplier for a head-on hit
  static const double _heavyHitSpeed = 380.0; // above → heavy shake + hit-stop
  static const double _squashOnHit = 0.42; // squash amount stamped on impact
  static const double _squashDecayPerSec = 3.2; // how fast squash relaxes
  static const double _impactRingLifeSec = 0.32;
  static const double _impactRingMaxFactor = 2.4; // ring max radius / body R

  // ── Shrinking platform (sudden death) tuning ────────────────────────────────
  // The shrink does the late-game work: it starts after a grace period (so an
  // idle player is safe early) then closes decisively, forcing contact so a
  // match converges by ~20-24s instead of grinding to the time limit. Reaches
  // the floor at delay + (1-floor)/perSec ~ 9 + 0.56/0.044 ~ 22s, after which a
  // tight ring leaves accurate bots no safe edge to camp.
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.44; // floor as fraction of initial R
  static const double _shrinkPerSec = 0.044; // fraction of initial R per second

  // ── Climax (sudden death) tuning ────────────────────────────────────────────
  // The final ~28% of the match collapses the platform far faster with a SUDDEN
  // DEATH banner, so the round visibly ramps to a finish.
  static const double _suddenDeathFrac = 0.72; // enters at this share of time
  static const double _suddenDeathShrinkMul = 2.4; // shrink speed multiplier
  static const double _suddenDeathFloorMul = 0.82; // tighter floor in sudden death

  // ── Star pickup (chaos) tuning ──────────────────────────────────────────────
  static const double _starRadiusFactor = 0.6; // star R / body R
  static const double _starFirstSpawnSec = 4.0;
  static const double _starRespawnSec = 7.5;
  static const double _starLifeSec = 6.0;
  static const double _starAppearPerSec = 3.0;
  static const double _starSpinPerSec = 3.2;
  static const double _starSpawnSpreadFactor = 0.42;
  static const double _buffSec = 4.0; // buff duration
  static const double _buffDashMul = 1.8; // bump magnitude × this while buffed
  static const Color _starColor = Color(0xFFFFE45C);

  // ── Ring-out tuning ─────────────────────────────────────────────────────────
  static const double _koPopLift = 0.06; // extra popup lift / body R
  static const double _ringOutGraceFactor = 1.02; // detect just past current R

  // ── Bot tuning (mirrors Sumo's fair model) ──────────────────────────────────
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botCloseRangeFactor = 4.2; // approach vs shove threshold
  static const double _botEdgeBackoff = 0.62; // dist/ring above → retreat inward
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip bump while already fast
  static const double _botSaveCharge = 0.5; // charge used to save off the edge
  static const double _botApproachCharge = 0.06; // light nudge to close distance
  static const double _botShoveChargeMin = 0.25; // close-range charged shove min
  static const double _botShoveChargeMax = 0.55; // close-range charged shove max

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
  final Map<int, BallState> _ball = <int, BallState>{};
  final List<int> _eliminationOrder = <int>[];
  final Set<int> _eliminated = <int>{};
  final List<ImpactRing> _impacts = <ImpactRing>[];

  late StarController _stars;
  bool _suddenDeathAnnounced = false;

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
    _stars = StarController(
      radius: _bodyRadius * _starRadiusFactor,
      firstSpawnSec: _starFirstSpawnSec,
      respawnSec: _starRespawnSec,
      lifeSec: _starLifeSec,
      appearPerSec: _starAppearPerSec,
      spinPerSec: _starSpinPerSec,
      spawnSpreadFactor: _starSpawnSpreadFactor,
    );

    // The arena's own ring-falloff must NOT cull balls: this game owns
    // elimination via [_detectRingOuts] against the *shrinking* radius so the KO
    // juice, impact ring and elimination order all fire. If the arena culled at
    // [_ringRadius] it would silently kill (alive=false) any ball launched out
    // before the platform shrinks, and [_detectRingOuts] would then skip it.
    // Use a radius beyond the screen so the arena never falls a ball off.
    _arena = PushArena(
      center: _center,
      ringRadius: _size.width + _size.height,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies();
    _seedMotes();
    begin();
  }

  /// Place one ball per player evenly on a spawn circle, with its aim pointing
  /// toward the centre so the very first bump is sensible, plus a bot clock.
  void _buildBodies() {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * _spawnRadiusFactor;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Start at +90° (bottom) so player 0 spawns in their own bottom zone and
      // 2-player duels face off north/south up the tall portrait screen.
      final angle = (i / count) * math.pi * 2 + math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _arena.add(Body(id: p.id, pos: pos, radius: _bodyRadius));

      final towardCenter = math.atan2(_center.dy - pos.dy, _center.dx - pos.dx);
      _ball[p.id] = BallState(aim: towardCenter);
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

  // ── Input: hold to charge + aim, release to bump (mirrors Sumo) ─────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final s = _ball[input.playerId];
    final body = _bodyOf(input.playerId);
    if (s == null || body == null || !body.alive) return;

    switch (input.phase) {
      case InputPhase.down:
        if (s.ready) s.charging = true; // lock aim, begin charging
      case InputPhase.up:
        if (s.charging) {
          s.charging = false;
          // Fire straight at the nearest opponent (never a stale swept angle).
          final aim = _aimAtNearest(input.playerId) ?? s.aim;
          _commitDash(input.playerId, body, aim, s.charge);
          s.charge = 0;
        }
      case InputPhase.holdTick:
        break; // charge accrues in update() for frame-rate independence
    }
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
    _stars.tick(dt, _arena.aliveBodies.length, ctx.rng, _center,
        _currentRingRadius);

    _arena.update(sdt);

    _collectStars();
    _resolveContacts();
    _detectRingOuts();
    _resolveOutcome();
  }

  /// True once the match has entered its climax (sudden death) window.
  bool get _isSuddenDeath => _elapsed >= _timeLimit * _suddenDeathFrac;

  // ── Per-frame ball state ─────────────────────────────────────────────────────

  /// Aim always tracks the nearest opponent (no idle sweep — a tap/charge
  /// strikes straight at it), fill charge while held, relax squash, age trail
  /// and recover cooldown — all frame-rate independent.
  void _tickBallStates(double dt) {
    for (final entry in _ball.entries) {
      final s = entry.value;
      if (_isAlive(entry.key)) {
        final a = _aimAtNearest(entry.key);
        if (a != null) s.aim = a;
        if (s.charging) {
          s.charge = math.min(1.0, s.charge + dt / _chargeTimeSec);
        }
      }
      s.tick(dt, _squashDecayPerSec);
    }
  }

  /// Angle from a ball to the nearest alive opponent, or null when none remain
  /// (e.g. the last ball standing) — then the aim simply holds its last heading.
  double? _aimAtNearest(int playerId) {
    final self = _bodyOf(playerId);
    final target = _nearestOpponentPos(playerId);
    if (self == null || target == null) return null;
    final d = target - self.pos;
    if (d.distance < 1e-6) return null;
    return math.atan2(d.dy, d.dx);
  }

  void _tickImpacts(double dt) {
    for (final r in _impacts) {
      r.life -= dt;
    }
    _impacts.removeWhere((r) => r.life <= 0);
  }

  // ── Bots: warmup, then approach-nudge / charged-shove (mirrors Sumo) ────────

  /// Bots act on their reaction clock with [BotProfile]-driven timing, charge
  /// and aim error. A warmup keeps them passive at the start so they never eject
  /// an idle human in the first beats of the round.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a beat first
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!_isAlive(id)) continue;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bots pick an aim + charge and commit a bump directly (no hold sim).
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final s = _ball[playerId];
    if (self == null || !self.alive || s == null || !s.ready) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final err = (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;

    // Near the edge: save self with a moderate bump back toward the centre.
    if (_isNearEdge(self)) {
      final aim = math.atan2(_center.dy - self.pos.dy, _center.dx - self.pos.dx);
      s.aim = aim;
      _commitDash(playerId, self, aim, _botSaveCharge);
      return;
    }

    // Don't waste a bump while already carrying lots of speed.
    if (self.vel.distance > _botCarrySpeed) return;

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;

    final to = targetPos - self.pos;
    final aim = math.atan2(to.dy, to.dx) + ctx.rng.jitter(err);
    // Far → a light nudge to close in; close → a charged shove into the rival.
    final charge = to.distance > _bodyRadius * _botCloseRangeFactor
        ? _botApproachCharge
        : (ctx.botProfile.accuracy *
                ctx.rng.range(_botShoveChargeMin, _botShoveChargeMax))
            .clamp(0.0, 1.0);
    s.aim = aim;
    _commitDash(playerId, self, aim, charge);
  }

  /// Shared bump commit: an aimed impulse of the given [charge] (0..1) in
  /// [aimAngle], a small self-recoil, cooldown, trail, a forward stretch hint
  /// and a directional spark telegraph. Used by humans and bots so the feel
  /// matches exactly.
  void _commitDash(int playerId, Body self, double aimAngle, double charge) {
    final s = _ball[playerId];
    if (s == null || !s.ready) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies every bump — the buffed ball hits
    // noticeably harder, the core of the chaos swing.
    final buffMul = s.buffed ? _buffDashMul : 1.0;
    final magnitude = _ringRadius * (_dashBase + _dashCharge * charge) * buffMul;
    _arena.impulse(playerId, dir * magnitude);
    _arena.impulse(playerId, -dir * magnitude * _selfPushback);

    s.fire(_cooldownSec);
    s.trail = DashTrail(dir: dir, life: _trailLifeSec);
    s.stretchDir = dir;

    final intensity = 0.5 + 0.5 * charge;
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: (6 + 8 * charge).round(),
      color: _colorOf(playerId),
      speed: 200 * intensity,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 120,
      life: 0.3,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: (3 + 4 * charge).round());
    if (charge > 0.6) _juice.shake.light();
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
    _impacts.add(ImpactRing(at: at, color: color, life: _impactRingLifeSec));
  }

  // ── Shrinking platform ──────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
    // Sudden death tightens the floor and speeds the collapse so the round ramps
    // unmistakably toward a finish in its final stretch.
    final sudden = _isSuddenDeath;
    final floor =
        _ringRadius * _minRingFactor * (sudden ? _suddenDeathFloorMul : 1.0);
    if (_currentRingRadius <= floor) return;
    final rate = _shrinkPerSec * (sudden ? _suddenDeathShrinkMul : 1.0);
    _currentRingRadius = (_currentRingRadius - _ringRadius * rate * dt)
        .clamp(floor, _ringRadius);
  }

  // ── Star pickup (chaos) ─────────────────────────────────────────────────────

  /// Any ball overlapping a ready star collects it: a brief bump buff + a burst
  /// + popup. The grabber gets a swingy edge — pure chaos for the table.
  void _collectStars() {
    final star = _stars.star;
    if (star == null || !star.ready) return;
    for (final b in _arena.aliveBodies) {
      if ((b.pos - star.pos).distance > b.radius + star.radius) continue;
      _ball[b.id]?.buff = _buffSec;
      _stars.consume();
      _spawnImpact(star.pos, _starColor);
      _juice.particles.burst(
        at: star.pos,
        count: 18,
        color: _starColor,
        speed: 280,
        size: 6,
        gravity: 120,
        life: 0.6,
      );
      _juice.hit(b.pos, _colorOf(b.id), sparks: 8);
      _juice.popup(
          b.pos.translate(0, -_bodyRadius * 1.8), 'POWER!', _starColor,
          size: 30);
      return;
    }
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
      // A fatter eject flourish: an extra outward spark fan + a punchier popup
      // so the knockout reads as a big moment kids cheer for.
      final outDir = _normalize(b.pos - _center);
      _juice.particles.burst(
        at: b.pos,
        count: 16,
        color: _colorOf(b.id),
        speed: 360,
        baseAngle: math.atan2(outDir.dy, outDir.dx),
        spread: math.pi * 0.9,
        size: 7,
        gravity: 220,
        life: 0.7,
      );
      _juice.popup(
        b.pos.translate(0, -_bodyRadius * (1.6 + _koPopLift)),
        'RING OUT!',
        _popupColor,
        size: 40,
      );
    }
  }

  // ── Outcome ──────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    final alive = _arena.aliveBodies;
    // Announce the climax exactly once with a shake + center popup; the
    // fast-shrink platform + banner then carry the moment.
    if (!_suddenDeathAnnounced && _isSuddenDeath && alive.length > 1) {
      _suddenDeathAnnounced = true;
      _juice.shake.medium();
      _juice.popup(_center.translate(0, -_currentRingRadius * 0.2),
          'SUDDEN DEATH', _popupColor,
          size: 38);
    }
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

    final star = _stars.star;
    if (star != null) BumperFx.drawStar(canvas, star);

    _drawBalls(canvas);
    _drawImpacts(canvas);

    if (_isSuddenDeath) {
      BumperFx.drawSuddenDeathBanner(
          canvas, size, _arena.aliveBodies.length > 1 ? 1.0 : 0.0, _animClock);
    }

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
      final ground = Offset(b.pos.dx, b.pos.dy + b.radius * 0.7);

      // Soft contact shadow under the ball, on the platform.
      BumperRenderer.drawContactShadow(canvas, ground, b.radius);

      // Player-colour ground id ring so each ball is always identifiable.
      BumperRenderer.drawIdRing(canvas, ground, b.radius, color, b.id + 1);

      // A pulsing gold aura while the star buff is active so the table sees who
      // is dangerous right now.
      if (state != null && state.buffed) {
        final pulse = 0.5 + 0.5 * math.sin(_animClock * 6.0);
        canvas.drawCircle(
          b.pos,
          b.radius * (1.5 + 0.18 * pulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = b.radius * 0.16
            ..color = _starColor
                .withValues(alpha: (0.45 + 0.35 * pulse).clamp(0.0, 1.0)),
        );
      }

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

      // No idle arrow. While charging, a telegraph points straight at the
      // nearest opponent (where the bump will land) with a charge ground-arc.
      if (state != null && state.charging) {
        BumperRenderer.drawAim(
          canvas,
          b.pos,
          b.radius,
          color,
          aim: state.aim,
          charge: state.charge,
        );
      }
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
