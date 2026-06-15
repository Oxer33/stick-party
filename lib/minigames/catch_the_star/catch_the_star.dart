import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'catch_render.dart';

/// Star Catcher — INTERCEPT FALLING STARS, READ THE CROSSINGS, DODGE BOMBS.
///
/// OBJECTIVE: bank the MOST stars before the clock runs out (or be first to the
/// [_targetScore] target). The HUD shows your live count and the objective.
///
/// CORE (one-touch, position-is-everything — but now it is INTERCEPTION):
/// items no longer fall straight down a fixed column. Each one spawns at the TOP
/// of your lane and travels on an ANGLED path — it slides diagonally across the
/// lane as it falls. So you cannot camp under a spawn point: you must read where
/// a star WILL cross the catch line and slide your basket to that INTERCEPT POINT
/// in time. A catch is still PURE OVERLAP at the catch line — the item is caught
/// only if your basket mouth is under it as it crosses — so there is no
/// tap-to-grab and no luck.
///
/// THE READ (the rework — crossing conflicts):
///  * Items spawn in CROSSING PAIRS. A STAR launches from one wall heading
///    inward and a BOMB launches from the other, the two angled paths converging
///    so they reach the catch line near the SAME x at nearly the SAME moment. To
///    take the star you must commit your basket to that shared intercept early —
///    then bail late if the bomb is the one that actually arrives over you. Flail
///    and you mistime the cross and eat the bomb; read it and you thread it.
///  * A faint TRAJECTORY HINT draws each item's path down to its predicted
///    intercept marker on the catch line, so the read is legible — you are
///    threading a telegraphed crossing, not guessing.
///  * BOMBS punish hard: catching one costs points, STUNS the basket for
///    [_stunSec] (it ignores your drag and coasts to a halt) and drops a star —
///    so eating a bomb both bleeds score and leaves you helpless mid-cross.
///  * GOLD stars are rarer and worth [_goldPoints]; normal stars [_starPoints].
///  * The field RAMPS: items fall faster, cross steeper, spawn denser and the
///    bomb ratio climbs as the round wears on (readable open → frantic finish). A
///    basket has movement INERTIA (accelerates toward your finger, decelerates,
///    capped at [_basketMaxSpeed]) so committing to a far intercept then bailing
///    off a converging bomb is a real skill, not a tap.
///
/// ANTI-INCIDENTAL: because catching is overlap-only at the line AND the targets
/// arrive off-axis on crossing paths, sitting still or sweeping blindly catches
/// almost nothing and walks under bombs. You must READ each crossing, commit to
/// the star's intercept and slide OFF the bomb's. Reading crossings + precise,
/// timed positioning is the entire skill.
///
/// 1–4 players: each player owns a lane (their [PlayerZone]) with its own angled
/// stream of crossing stars + bombs, fed by the SAME calibrated ramp, so it is a
/// fair simultaneous race.
///
/// BOTS play the same interception game: each frame a bot computes the INTERCEPT
/// x of the nearest catchable star (where it will cross the line) and steers
/// there, UNLESS a bomb's intercept is the imminent threat near its basket, in
/// which case it bails. [BotProfile] gates the read: a weak bot reacts late,
/// MISREADS the crossing (commits to the bomb's intercept, or fails to bail) and
/// eats bombs; a strong bot threads the cross. A human who reads better
/// out-catches a weak CPU — a real, beatable 1+CPU contest.
///
/// The round runs to [_timeLimit] (or ends early once someone reaches
/// [_targetScore]) and resolves via [finishByScore]; it can never stall.
class CatchTheStar extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'catch_the_star',
        name: 'Star Catcher',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'DRAG',
      );

  // ── Round tuning (no magic numbers inline) ─────────────────────────────────
  static const double _timeLimit = 32;
  static const int _targetScore = 30; // first to this ends the round early

  // ── Item kinds + worth ───────────────────────────────────────────────────────
  static const int _starPoints = 1;
  static const int _goldPoints = 3;
  static const int _bombPenalty = 2; // points lost on catching a bomb

  // ── Catch geometry (normalized; per-lane the catch is overlap-only) ──────────
  // The catch line sits this far down each lane; the basket mouth is this wide.
  static const double _catchLineFrac = 0.84; // y of catch line within a lane
  static const double _basketHalfWidth = 0.085; // half basket mouth (norm x)
  static const double _itemHalfWidth = 0.05; // half item width for overlap
  // A catch counts when the item centre is within (basketHalf + itemHalf) of the
  // basket centre AS the item crosses the line. Pure overlap — no tap, no snap.
  static double get _catchOverlap => _basketHalfWidth + _itemHalfWidth;

  // ── Basket control (inertia makes precise positioning a skill) ───────────────
  static const double _basketAccel = 18.0; // accel toward target (1/sec^2-ish)
  static const double _basketDamp = 9.0; // velocity damping per sec
  static const double _basketMaxSpeed = 3.6; // cap on basket speed (norm/sec)
  static const double _stunSec = 0.9; // basket frozen after catching a bomb
  static const double _laneInset = 0.06; // keep basket off the lane walls

  // ── Falling-field ramp (calibrated: readable open → frantic finish) ──────────
  // Fall speed (normalized lane-heights per second) and spawn cadence both ramp
  // with elapsed time; the bomb ratio climbs too so the gauntlet thickens.
  static const double _fallSpeedStart = 0.34; // norm/sec at t=0
  static const double _fallSpeedEnd = 0.78; // norm/sec at the end
  static const double _spawnEveryStart = 1.15; // s between crossings (per lane)
  static const double _spawnEveryEnd = 0.52; // floor on spawn interval
  static const double _spawnWarmupSec = 0.7; // first drop delayed (read time)
  static const double _bombRatioStart = 0.18; // lone-drop bomb odds early
  static const double _bombRatioEnd = 0.42; // lone-drop bomb odds at the finish
  static const double _goldRatio = 0.12; // of the NON-bomb drops, gold odds
  static const double _spawnXMargin = 0.12; // keep spawn launch off the walls

  // ── Angled paths + crossing conflicts (the rework) ───────────────────────────
  // Each item slides sideways as it falls. The drift is expressed as a target
  // intercept on the catch line: the item is launched from one side of the lane
  // and aimed to cross the line at [interceptX], so its horizontal speed follows
  // from the time it takes to fall. Crossing PAIRS share an intercept so a star
  // and a bomb converge — the central read.
  static const double _crossChanceStart = 0.45; // odds a drop is a crossing PAIR
  static const double _crossChanceEnd = 0.80; // crossings dominate the finish
  static const double _crossWindowSec = 0.22; // bomb lags the star into the line
  static const double _interceptInset = 0.22; // keep shared intercepts off walls
  static const double _minLaunchSpreadFrac = 0.34; // lane-frac between launches
  // The converging bomb lands THIS far (× the catch overlap) to the side of the
  // star's intercept: just outside the basket mouth, so a precise reader who is
  // ON the star's crossing point catches it AND the bomb lands beside them — the
  // crossing is a tight, legible read, not an unavoidable double-hit. A flailer
  // who is off the mark is the one who drifts under the converging bomb.
  static const double _crossBombOffsetFrac = 1.35;
  // A lone (non-paired) item still slides: it launches off one wall and angles
  // toward a random interior intercept, so even singles must be intercepted.
  static const double _loneDriftMin = 0.18; // min interior intercept offset
  static const double _loneDriftMax = 0.42; // max interior intercept offset

  // ── Climax: BOMB STORM finish (the unmistakable peak) ────────────────────────
  // In the last [_stormSec] the spawn cadence tightens, crossings are guaranteed
  // and the bomb ratio is pinned high — a frantic read-heavy finish. A one-shot
  // cue announces it.
  static const double _stormSec = 7.0;
  static const double _stormSpawnEvery = 0.42; // very dense crossings in storm
  static const double _stormBombRatio = 0.5; // half the lone drops are bombs

  // ── Comeback: a subtle catch-up for trailing players ───────────────────────
  // A player below the leader gets a slightly wider effective basket mouth,
  // scaled by how far behind they are (capped). The leader gets the base width,
  // so a strong player still wins; a struggling kid stays in the shouting.
  static const double _comebackMaxBonus = 0.03; // max extra half-width (norm)
  static const int _comebackRefGap = 8; // score gap earning the full bonus

  // ── Juice tuning ───────────────────────────────────────────────────────────
  static const double _slowMoSec = 0.20; // gold-catch hit-stop length
  static const double _slowMoScale = 0.3; // time scale during slow-mo
  static const double _flashSec = 0.4; // basket flash decay
  static const int _bgStarCount = 80; // parallax background stars

  // ── Render sizing / palette ──────────────────────────────────────────────────
  static const Color _starGlow = Color(0xFFFFD24A);
  static const Color _goldBody = Color(0xFFFFE070);
  static const Color _bombColor = Color(0xFFE5484D);

  late Juice _juice;
  final List<_Lane> _lanes = <_Lane>[];

  // Fixed parallax background field (positions + packed depth/phase seeds).
  final List<Offset> _bgStars = <Offset>[];
  final List<double> _bgSeeds = <double>[];

  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for shimmer/spin
  bool _stormAnnounced = false; // the BOMB STORM cue fired once
  bool _finishFired = false; // one-shot winner banner latch
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _spawnLanes();
    _seedBackground();
    begin();
  }

  void _spawnLanes() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final zone = _zoneFor(p.id, i, count);
      _lanes.add(_Lane(
        playerId: p.id,
        displayNumber: p.id + 1,
        color: Color(p.colorArgb),
        zone: zone,
        basketX: zone.center.dx,
        targetX: zone.center.dx,
        // Stagger the first drop so lanes don't pulse in lockstep.
        spawnTimer: _spawnWarmupSec + ctx.rng.range(0, _spawnEveryStart),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// The slice of the arena a player's basket lives in. Prefer the real
  /// [PlayerZone]; fall back to an even split so the game still works if a
  /// context arrives without a matching zone for a player id.
  Rect _zoneFor(int id, int index, int count) {
    final zone = ctx.zones.forPlayer(id);
    if (zone != null) return zone.normRect;
    final w = 1.0 / count;
    return Rect.fromLTRB(index * w, 0, (index + 1) * w, 1);
  }

  /// A fixed field of background stars with a depth/phase packed per star: the
  /// integer part of the seed is a phase, the fractional part is the parallax
  /// depth (0 = far/dim/small, 1 = near/bright/big). Deterministic via the rng.
  void _seedBackground() {
    for (var i = 0; i < _bgStarCount; i++) {
      _bgStars.add(Offset(ctx.rng.next(), ctx.rng.next()));
      final phase = ctx.rng.intRange(0, 7).toDouble();
      final depth = ctx.rng.range(0.05, 0.99);
      _bgSeeds.add(phase + depth);
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final lane = _laneOf(input.playerId);
    if (lane == null) return;
    switch (input.phase) {
      case InputPhase.down:
      case InputPhase.holdTick:
        // A press or drag aims the basket at the touch x; a positionless per-frame
        // tick (normPos == Offset.zero) carries no new target. The basket EASES to
        // it with inertia in [_steerBaskets] — there is no tap-to-grab.
        if (input.normPos != Offset.zero) _aimBasket(lane, input.normPos);
      case InputPhase.up:
        break;
    }
  }

  /// Aim a human basket's target at [normPos.dx] (full-screen), clamped into that
  /// player's lane so a basket can only roam its own column.
  void _aimBasket(_Lane lane, Offset normPos) {
    if (!normPos.dx.isFinite) return;
    lane.targetX = _clampX(lane.zone, normPos.dx);
  }

  /// Clamp a normalized x into [zone] with a small inset so the basket never sits
  /// exactly on a lane wall.
  double _clampX(Rect zone, double x) =>
      x.clamp(zone.left + _laneInset, zone.right - _laneInset);

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _maybeAnnounceStorm();
    _driveBots(sdt);
    _steerBaskets(sdt);
    for (final lane in _lanes) {
      _spawnTick(lane, sdt);
      _stepItems(lane, sdt);
      lane.tick(dt);
    }

    if (_elapsed >= _timeLimit || _someoneReachedTarget()) _finish();
  }

  bool _someoneReachedTarget() {
    for (final lane in _lanes) {
      if (scoreOf(lane.playerId).toInt() >= _targetScore) return true;
    }
    return false;
  }

  // ── Falling-field ramp ────────────────────────────────────────────────────────

  /// 0..1 progress through the round, used to ramp speed / density / bomb ratio.
  double get _ramp => (_elapsed / _timeLimit).clamp(0.0, 1.0);

  /// True once the round enters its final BOMB STORM window.
  bool get _inStorm => _elapsed >= _timeLimit - _stormSec;

  double get _fallSpeed =>
      _fallSpeedStart + (_fallSpeedEnd - _fallSpeedStart) * _ramp;

  double get _spawnEvery => _inStorm
      ? _stormSpawnEvery
      : _spawnEveryStart + (_spawnEveryEnd - _spawnEveryStart) * _ramp;

  double get _bombRatio => _inStorm
      ? _stormBombRatio
      : _bombRatioStart + (_bombRatioEnd - _bombRatioStart) * _ramp;

  /// Odds the next drop is a crossing PAIR (star + converging bomb). Ramps up so
  /// the read-heavy crossings dominate the finish; pinned ON in the storm.
  double get _crossChance => _inStorm
      ? 1.0
      : _crossChanceStart + (_crossChanceEnd - _crossChanceStart) * _ramp;

  /// Fire the one-shot BOMB STORM cue the moment the storm begins: a banner, a
  /// shake and a red burst so every kid knows the dodge-heavy finish is on.
  void _maybeAnnounceStorm() {
    if (_stormAnnounced || !_inStorm) return;
    _stormAnnounced = true;
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.42);
    _juice.popup(center, 'BOMB STORM!', _bombColor, size: 44);
    _juice.shake.medium();
    _juice.particles.burst(
      at: center,
      count: 22,
      color: _bombColor,
      speed: 340,
      size: 7,
      life: 0.8,
    );
  }

  void _spawnTick(_Lane lane, double dt) {
    if (_elapsed < _spawnWarmupSec) return;
    lane.spawnTimer -= dt;
    if (lane.spawnTimer > 0) return;
    lane.spawnTimer = _spawnEvery;
    if (ctx.rng.chance(_crossChance)) {
      _dropCrossing(lane);
    } else {
      _dropLone(lane);
    }
  }

  /// Time (s) an item needs to fall from the top of [zone] to the catch line at
  /// the current ramped fall speed. Drives the sideways speed so a launch lands
  /// on its chosen intercept exactly at the line.
  double _timeTopToLine() {
    final dropFrac = _catchLineFrac; // top→line as a fraction of lane height
    final speed = _fallSpeed; // lane-heights per second
    return speed <= 0 ? 1.0 : dropFrac / speed;
  }

  /// Launch one item that slides from [launchX] (at the lane top) to cross the
  /// catch line at [interceptX]. Its horizontal velocity is solved from the fall
  /// time so the geometry is exact and the trajectory hint is honest. A positive
  /// [extraDelaySec] starts it above the lane so it arrives that much later.
  void _launch(_Lane lane, _ItemKind kind, double launchX, double interceptX,
      {double extraDelaySec = 0}) {
    final z = lane.zone;
    final tToLine = _timeTopToLine();
    // Sideways speed in normalized x per second (world units, not lane-relative).
    final vx = tToLine <= 0 ? 0.0 : (interceptX - launchX) / tToLine;
    lane.items.add(_Item(
      kind: kind,
      x: launchX,
      // Start higher (above the top) so it reaches the line extraDelaySec later.
      y: z.top - extraDelaySec * _fallSpeed * z.height,
      vx: vx,
      interceptX: interceptX,
      spin: ctx.rng.range(0, math.pi * 2),
    ));
  }

  /// A crossing PAIR: a STAR and a BOMB launched from OPPOSITE walls of the lane,
  /// their angled paths converging near the SAME point on the catch line so they
  /// visibly cross (an X). The bomb aims JUST to the side of the star's intercept
  /// (by [_crossBombOffsetFrac] of the catch overlap — outside the basket mouth)
  /// and is launched slightly higher so it lags the star into the line by
  /// [_crossWindowSec]. The read: park on the star's exact crossing point and the
  /// bomb lands beside you; drift off it and you slide under the bomb instead.
  void _dropCrossing(_Lane lane) {
    final z = lane.zone;
    final inset = z.width * _interceptInset;
    // The bomb sits this far to one side of the star's intercept (lane-relative
    // so narrow split lanes scale it down with the rest of the geometry).
    final offset = _catchOverlap * _crossBombOffsetFrac;
    // Pick the star's intercept so both it and the offset bomb intercept stay
    // inside the playable band.
    final shared = ctx.rng
        .range(z.left + inset + offset, z.right - inset - offset)
        .clamp(z.left + inset, z.right - inset);
    final bombSign = shared <= z.center.dx ? 1.0 : -1.0; // push bomb toward centre
    final bombIntercept =
        (shared + bombSign * offset).clamp(z.left + inset, z.right - inset);

    final margin = z.width * _spawnXMargin;
    final spread = z.width * _minLaunchSpreadFrac;
    final starLeft = ctx.rng.next() < 0.5;
    final starLaunch = (starLeft ? shared - spread : shared + spread)
        .clamp(z.left + margin, z.right - margin);
    // Bomb launches from the OPPOSITE wall to the star so the paths cross.
    final bombLaunch = (starLeft ? bombIntercept + spread : bombIntercept - spread)
        .clamp(z.left + margin, z.right - margin);

    final starKind =
        ctx.rng.chance(_goldRatio) ? _ItemKind.gold : _ItemKind.star;
    _launch(lane, starKind, starLaunch, shared);
    _launch(lane, _ItemKind.bomb, bombLaunch, bombIntercept,
        extraDelaySec: _crossWindowSec);
  }

  /// A lone (non-paired) item still ANGLES: it launches off one wall and slides
  /// to a random interior intercept, so even singles demand interception rather
  /// than camping. It is a bomb at the ramped [_bombRatio], else a star (gold at
  /// [_goldRatio]).
  void _dropLone(_Lane lane) {
    final z = lane.zone;
    final margin = z.width * _spawnXMargin;
    final fromLeft = ctx.rng.next() < 0.5;
    final launchX = fromLeft ? z.left + margin : z.right - margin;
    final drift = z.width * ctx.rng.range(_loneDriftMin, _loneDriftMax);
    final interceptX = (fromLeft ? launchX + drift : launchX - drift)
        .clamp(z.left + margin, z.right - margin);
    final _ItemKind kind;
    if (ctx.rng.chance(_bombRatio)) {
      kind = _ItemKind.bomb;
    } else if (ctx.rng.chance(_goldRatio)) {
      kind = _ItemKind.gold;
    } else {
      kind = _ItemKind.star;
    }
    _launch(lane, kind, launchX, interceptX);
  }

  /// Advance every item along its ANGLED path, resolving a catch/miss exactly
  /// once as it crosses the catch line. Catching is PURE OVERLAP at the line — the
  /// basket mouth must be under the item's actual (drifted) x — so there is no way
  /// to luck into a star by camping a column.
  void _stepItems(_Lane lane, double dt) {
    final lineY = _catchLineYNorm(lane.zone);
    final survivors = <_Item>[];
    final fall = _fallSpeed * lane.zone.height; // lane-relative fall distance
    for (final item in lane.items) {
      final prevY = item.y;
      item.y += fall * dt;
      item.x += item.vx * dt; // diagonal translation

      if (!item.resolved && prevY <= lineY && item.y >= lineY) {
        item.resolved = true;
        if (_overlapsBasket(lane, item)) {
          _onCatch(lane, item);
          continue; // caught item leaves the field
        }
      }
      if (item.y > lane.zone.bottom + lane.zone.height * 0.1) continue; // gone
      // Bounce a stray off the side walls so an angled miss doesn't fly out of
      // the lane before reaching the line (keeps the path inside the column).
      if (item.x < lane.zone.left && item.vx < 0) item.vx = -item.vx;
      if (item.x > lane.zone.right && item.vx > 0) item.vx = -item.vx;
      survivors.add(item);
    }
    lane.items
      ..clear()
      ..addAll(survivors);
  }

  /// True when [item] is horizontally within the basket's (comeback-scaled) mouth
  /// at the moment it crosses the catch line. This is the ONLY way a catch happens.
  bool _overlapsBasket(_Lane lane, _Item item) =>
      (item.x - lane.basketX).abs() <= _overlapFor(lane);

  /// Effective catch overlap for [lane]: the base mouth plus a subtle comeback
  /// bonus for a player trailing the leader (scaled by the gap, capped). The
  /// leader (and a fresh 0–0 round) gets exactly the base, so better players win.
  double _overlapFor(_Lane lane) {
    final lead = _leaderScore();
    if (lead <= 0) return _catchOverlap;
    final behind = lead - scoreOf(lane.playerId).toInt();
    if (behind <= 0) return _catchOverlap;
    final t = (behind / _comebackRefGap).clamp(0.0, 1.0);
    return _catchOverlap + _comebackMaxBonus * t;
  }

  /// Resolve an item the basket actually overlapped at the line:
  ///  * STAR / GOLD → bank its worth, flash + sparks (+ slow-mo on gold).
  ///  * BOMB → PENALTY: lose points (floored at 0), STUN the basket, drop a star,
  ///    and a shake/red flash so the punishment is unmistakable.
  void _onCatch(_Lane lane, _Item item) {
    final at = _toPixels(Offset(item.x, _catchLineYNorm(lane.zone)));
    switch (item.kind) {
      case _ItemKind.bomb:
        _resolveBombHit(lane, at);
      case _ItemKind.gold:
        _resolveStarCatch(lane, at, _goldPoints, gold: true);
      case _ItemKind.star:
        _resolveStarCatch(lane, at, _starPoints, gold: false);
    }
  }

  void _resolveStarCatch(_Lane lane, Offset at, int worth,
      {required bool gold}) {
    addScore(lane.playerId, worth);
    lane.flash = _flashSec;
    final color = gold ? _goldBody : lane.color;
    _juice.popup(at, '+$worth', color, size: gold ? 34 : 28);
    _juice.hit(at, color, sparks: gold ? 16 : 9);
    if (gold) {
      _juice.particles.burst(
        at: at,
        count: 14,
        color: _starGlow,
        speed: 300,
        size: 6,
        life: 0.7,
      );
      _juice.hitStop.trigger(_slowMoSec, scale: _slowMoScale);
      _juice.shake.light();
    }
  }

  /// A bomb in the basket: subtract the penalty (never below 0), stun the basket
  /// so it ignores input and slides to a halt, and emit a clear punish beat.
  void _resolveBombHit(_Lane lane, Offset at) {
    final cur = scoreOf(lane.playerId).toInt();
    final lost = math.min(cur, _bombPenalty);
    if (lost > 0) setScore(lane.playerId, cur - lost);
    lane.stun = _stunSec;
    lane.targetX = lane.basketX; // drop the steer; it coasts to rest
    _juice.popup(
      at,
      lost > 0 ? '-$lost' : 'BOOM!',
      _bombColor,
      size: 32,
    );
    _juice.particles.burst(
      at: at,
      count: 18,
      color: _bombColor,
      speed: 360,
      size: 6,
      life: 0.7,
    );
    _juice.shake.medium();
    _juice.flashScreen(_bombColor, strength: 0.35);
  }

  /// Glide every basket toward its target x with INERTIA: accelerate toward the
  /// target, damp the velocity, cap the speed, and clamp into the lane. A stunned
  /// basket ignores its target (it just coasts to a halt) so eating a bomb really
  /// costs control. Bots get the same physics (their target is set in
  /// [_driveBots]) so they cannot teleport onto an intercept either.
  void _steerBaskets(double dt) {
    if (dt <= 0) return;
    for (final lane in _lanes) {
      // Stunned: no steering force, just damp to a stop.
      final toTarget = lane.stun > 0 ? 0.0 : (lane.targetX - lane.basketX);
      var v = lane.basketVel + toTarget * _basketAccel * dt;
      v -= v * (_basketDamp * dt).clamp(0.0, 1.0);
      if (v > _basketMaxSpeed) v = _basketMaxSpeed;
      if (v < -_basketMaxSpeed) v = -_basketMaxSpeed;
      final nextX = lane.basketX + v * dt;
      final clamped = _clampX(lane.zone, nextX);
      if (clamped != nextX) v = 0; // hit a wall: kill the velocity
      lane.basketVel = v;
      lane.basketX = clamped;
    }
  }

  // ── Bots ──────────────────────────────────────────────────────────────────────

  /// Bots play the SAME interception game: each frame a bot computes the INTERCEPT
  /// x of the nearest catchable star (where it will cross the line) and steers
  /// there — UNLESS a bomb is about to reach the line near the basket, in which
  /// case it bails to that bomb's far side. [BotProfile] gates skill: the bot only
  /// re-reads on its reaction clock (weak bots react late), an [errorRate] roll
  /// makes it MISREAD the crossing (commit to the bomb's intercept as if a star,
  /// or fail to bail), and below-perfect [accuracy] adds aim slop so it can just
  /// miss the cross. So a weak bot eats bombs and whiffs while a sharp bot threads
  /// — and a reading human can out-catch a weak CPU.
  void _driveBots(double dt) {
    for (final lane in _lanes) {
      final clock = lane.clock;
      if (clock == null) continue;
      if (lane.stun > 0) continue; // stunned bots can't steer either

      // Re-read the field only when the reaction clock fires (keeps weak bots
      // sluggish + beatable); between reads it keeps gliding to its last target.
      if (clock.tick(dt)) {
        clock.arm(ctx.botProfile, ctx.rng);
        lane.targetX = _botPickTargetX(lane);
      }
    }
  }

  /// Decide where a bot wants its basket: bail an imminent bomb's intercept if one
  /// threatens, otherwise track the nearest descending star's INTERCEPT.
  /// Difficulty colors the read of the crossing.
  double _botPickTargetX(_Lane lane) {
    final profile = ctx.botProfile;
    final misread = ctx.rng.chance(profile.errorRate);

    final bomb = _nearestThreateningBomb(lane);
    // A competent read bails an imminent bomb's intercept; a misread ignores it
    // (or, in the no-star branch below, even commits to it).
    if (bomb != null && !misread) {
      return _dodgeXFrom(lane, _interceptOf(lane, bomb));
    }

    final star = _nearestDescendingStar(lane);
    if (star == null) {
      // Nothing to chase: a misread bot may even drift onto a bomb's intercept.
      if (misread && bomb != null) {
        return _clampX(lane.zone, _interceptOf(lane, bomb));
      }
      return lane.basketX; // hold position
    }
    // Aim at the star's INTERCEPT, with accuracy slop so a weak bot can just miss
    // the overlap, and a misread can send it the wrong way entirely.
    final target = _interceptOf(lane, star);
    final slop = (1.0 - profile.accuracy.clamp(0.0, 1.0)) * _catchOverlap * 2.2;
    var aim = target + ctx.rng.jitter(slop);
    if (misread) aim = target + ctx.rng.sign() * _catchOverlap * 3.0;
    return _clampX(lane.zone, aim);
  }

  /// Where [item] will cross the catch line on its angled path: project its x by
  /// its horizontal velocity over the time it still needs to reach the line. For
  /// a (legacy) straight drop this is just its current x.
  double _interceptOf(_Lane lane, _Item item) {
    final lineY = _catchLineYNorm(lane.zone);
    final fall = _fallSpeed * lane.zone.height;
    if (fall <= 0) return item.x;
    final tToLine = (lineY - item.y) / fall;
    if (tToLine <= 0) return item.x;
    return item.x + item.vx * tToLine;
  }

  /// The lowest (closest to the line) star still descending toward the catch line.
  _Item? _nearestDescendingStar(_Lane lane) {
    final lineY = _catchLineYNorm(lane.zone);
    _Item? best;
    var bestY = -1.0;
    for (final item in lane.items) {
      if (item.kind == _ItemKind.bomb || item.resolved) continue;
      if (item.y > lineY) continue; // already past the line
      if (item.y > bestY) {
        bestY = item.y;
        best = item;
      }
    }
    return best;
  }

  /// A bomb close enough to the catch line (within [_botBombLeadFrac] of the lane)
  /// AND whose INTERCEPT is near the basket's current x — i.e. the kind of bomb a
  /// real player would slide to bail. Returns the most imminent such bomb, or null.
  _Item? _nearestThreateningBomb(_Lane lane) {
    final lineY = _catchLineYNorm(lane.zone);
    final lead = lane.zone.height * _botBombLeadFrac;
    _Item? best;
    var bestY = -1.0;
    for (final item in lane.items) {
      if (item.kind != _ItemKind.bomb || item.resolved) continue;
      if (item.y > lineY || item.y < lineY - lead) continue;
      // Only a bomb whose intercept is roughly over the basket is worth bailing.
      if ((_interceptOf(lane, item) - lane.basketX).abs() > _catchOverlap * 1.4) {
        continue;
      }
      if (item.y > bestY) {
        bestY = item.y;
        best = item;
      }
    }
    return best;
  }

  static const double _botBombLeadFrac = 0.55; // lookahead for bomb bailing

  /// Slide to the side of [bombX] that stays inside the lane — far enough that the
  /// basket mouth clears the bomb's intercept.
  double _dodgeXFrom(_Lane lane, double bombX) {
    final z = lane.zone;
    final step = _catchOverlap * 2.2;
    final left = bombX - step;
    final right = bombX + step;
    // Prefer whichever side keeps the basket in-lane and is the shorter move.
    final leftOk = left >= z.left + _laneInset;
    final rightOk = right <= z.right - _laneInset;
    if (leftOk && rightOk) {
      return (lane.basketX <= bombX) ? left : right;
    }
    if (leftOk) return left;
    if (rightOk) return right;
    return _clampX(z, bombX); // pinned (very narrow lane); best effort
  }

  // ── Finish ──────────────────────────────────────────────────────────────────

  void _finish() {
    if (status == MiniGameStatus.finished) return;
    // Signature climax: a one-shot celebratory banner in the winner's color as
    // the round resolves. Latched so it fires exactly once.
    if (!_finishFired) {
      _finishFired = true;
      _juice.bigBanner('WINNER!', color: _leaderColor() ?? _goldBody);
    }
    finishByScore();
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    _juice.applyWorldTransform(canvas);

    CatchRenderer.drawBackground(canvas, size);
    CatchRenderer.drawBackgroundStars(
        canvas, size, _bgStars, _bgSeeds, _animClock);
    CatchRenderer.drawVignette(canvas, size);

    _drawLanes(canvas);

    CatchRenderer.drawHud(
      canvas,
      size,
      _timeLimit - _elapsed,
      _leaderColor(),
      _leaderScore(),
      _targetScore,
    );

    _juice.render(canvas);
    canvas.restore();

    _juice.renderOverlay(canvas, size);
  }

  void _drawLanes(Canvas canvas) {
    final laneCount = _lanes.length;
    for (final lane in _lanes) {
      final zonePx = _rectToPixels(lane.zone);
      final lineNormY = _catchLineYNorm(lane.zone);
      final lineY = _toPixels(Offset(0, lineNormY)).dy;
      CatchRenderer.drawLane(
        canvas,
        zonePx,
        lineY,
        lane.color,
        lane.displayNumber,
        score: scoreOf(lane.playerId).toInt(),
        multiPlayer: laneCount > 1,
      );

      // Faint trajectory hints FIRST (under the items) so each angled path reads
      // as a line down to its predicted intercept marker on the catch line — the
      // legible read that makes the crossing threadable, not guesswork.
      for (final item in lane.items) {
        if (item.resolved || item.y > lineNormY) continue;
        final from = _toPixels(Offset(item.x, item.y));
        final ix =
            _interceptOf(lane, item).clamp(lane.zone.left, lane.zone.right);
        final to = _toPixels(Offset(ix, lineNormY));
        CatchRenderer.drawTrajectoryHint(
          canvas,
          from,
          to,
          isBomb: item.kind == _ItemKind.bomb,
          gold: item.kind == _ItemKind.gold,
          t: _animClock,
          minSide: _minSide,
        );
      }

      // Falling items: clearly distinct + telegraphed (bombs read RED with a fuse,
      // gold stars glow brighter, normal stars are warm). Their comet trail
      // streams opposite their travel direction so the angle reads.
      for (final item in lane.items) {
        final center = _toPixels(Offset(item.x, item.y));
        final r = _itemHalfWidth * _minSide;
        CatchRenderer.drawItem(
          canvas,
          center,
          r,
          isBomb: item.kind == _ItemKind.bomb,
          gold: item.kind == _ItemKind.gold,
          spin: item.spin + _animClock * 1.4,
          t: _animClock,
          velDir: _velDirPixels(item),
        );
      }

      // The basket at the catch line, sized to its (comeback-scaled) mouth.
      final basketPx = _toPixels(Offset(lane.basketX, lineNormY));
      CatchRenderer.drawBasket(
        canvas,
        basketPx,
        _overlapFor(lane) * _minSide,
        lane.color,
        flash: lane.flashFill(_flashSec),
        stun: lane.stunFill(_stunSec),
        t: _animClock,
      );
    }
  }

  // ── Small helpers ────────────────────────────────────────────────────────────

  double get _minSide => math.min(_lastSize.width, _lastSize.height);

  /// The item's travel direction in PIXEL space (vx is normalized x/sec, the fall
  /// is normalized y/sec); used to orient its comet trail along the angle.
  Offset _velDirPixels(_Item item) {
    final dx = item.vx * _lastSize.width;
    final dy = _fallSpeed * _lastSize.height; // always downward
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0 || !len.isFinite) return const Offset(0, 1);
    return Offset(dx / len, dy / len);
  }

  /// Normalized y of the catch line within [zone].
  double _catchLineYNorm(Rect zone) => zone.top + zone.height * _catchLineFrac;

  _Lane? _laneOf(int id) {
    for (final lane in _lanes) {
      if (lane.playerId == id) return lane;
    }
    return null;
  }

  /// Current leader's color (null on a fresh round with no points yet).
  Color? _leaderColor() {
    _Lane? best;
    var bestScore = 0;
    for (final lane in _lanes) {
      final s = scoreOf(lane.playerId).toInt();
      if (s > bestScore) {
        bestScore = s;
        best = lane;
      }
    }
    return best?.color;
  }

  int _leaderScore() {
    var best = 0;
    for (final lane in _lanes) {
      best = math.max(best, scoreOf(lane.playerId).toInt());
    }
    return best;
  }

  Offset _toPixels(Offset norm) =>
      Offset(norm.dx * _lastSize.width, norm.dy * _lastSize.height);

  Rect _rectToPixels(Rect r) => Rect.fromLTRB(
        r.left * _lastSize.width,
        r.top * _lastSize.height,
        r.right * _lastSize.width,
        r.bottom * _lastSize.height,
      );

  /// Test-only view of a lane's basket x so deterministic tests can assert it
  /// stays clamped to its zone and tracks intercepts. Not used by gameplay/render.
  @visibleForTesting
  double? basketXForTest(int id) => _laneOf(id)?.basketX;

  /// Test-only: the catch line y (normalized) for a player's lane, so a test can
  /// drive a basket exactly onto an intercept at the line. Not used by gameplay.
  @visibleForTesting
  double? catchLineYForTest(int id) {
    final lane = _laneOf(id);
    return lane == null ? null : _catchLineYNorm(lane.zone);
  }

  /// Test-only: the INTERCEPT x (where it will cross the catch line) of the lowest
  /// descending STAR (gold or normal) in a lane, or null if none. Lets a
  /// deterministic test position a basket on the next star's intercept to prove
  /// reading beats flailing. Because paths are angled, this is the projected
  /// crossing x — NOT the spawn x. Not used by gameplay/render.
  @visibleForTesting
  double? nextStarXForTest(int id) {
    final lane = _laneOf(id);
    if (lane == null) return null;
    final star = _nearestDescendingStar(lane);
    return star == null ? null : _interceptOf(lane, star);
  }

  /// Test-only: the INTERCEPT x of the lowest descending BOMB in a lane, or null.
  /// Lets a test confirm a flailing player slides under a bomb's crossing. Not
  /// used by gameplay.
  @visibleForTesting
  double? nextBombXForTest(int id) {
    final lane = _laneOf(id);
    if (lane == null) return null;
    final lineY = _catchLineYNorm(lane.zone);
    _Item? best;
    var bestY = -1.0;
    for (final item in lane.items) {
      if (item.kind != _ItemKind.bomb || item.resolved) continue;
      if (item.y > lineY) continue;
      if (item.y > bestY) {
        bestY = item.y;
        best = item;
      }
    }
    return best == null ? null : _interceptOf(lane, best);
  }
}

/// What a falling item is. A bomb PENALIZES; a star/gold rewards.
enum _ItemKind { star, gold, bomb }

/// A single falling item in a lane, now travelling on an ANGLED path: it falls at
/// the lane's fall speed while sliding sideways at [vx] toward [interceptX] on the
/// catch line. Round-scoped mutable state (allowed by [MiniGameBase]).
class _Item {
  final _ItemKind kind;
  double x; // normalized 0..1, drifts sideways as it falls
  double y; // normalized 0..1, increases as it falls
  double vx; // normalized x per second (sideways drift; +right, -left)
  final double interceptX; // predicted crossing x on the catch line (render hint)
  final double spin; // render-only base spin phase
  bool resolved = false; // catch/miss decided at the line exactly once

  _Item({
    required this.kind,
    required this.x,
    required this.y,
    this.vx = 0,
    double? interceptX,
    this.spin = 0,
  }) : interceptX = interceptX ?? x;
}

/// Per-player lane: the basket it controls (with inertia), its angled falling
/// stream, color, optional bot reaction clock and the round-scoped flash + stun
/// timers. Mutable for the duration of one round (allowed by [MiniGameBase]).
class _Lane {
  final int playerId;
  final int displayNumber;
  final Color color;
  final Rect zone; // this player's column (normalized)
  final ReactionClock? clock;
  final List<_Item> items = <_Item>[];

  double basketX; // normalized 0..1 basket centre x
  double targetX; // where the basket is easing toward (clamped to [zone])
  double basketVel = 0; // basket velocity (norm/sec) — gives inertia
  double spawnTimer; // seconds until the next crossing/drop
  double flash = 0; // seconds of catch flash remaining
  double stun = 0; // seconds of bomb stun remaining

  _Lane({
    required this.playerId,
    required this.displayNumber,
    required this.color,
    required this.zone,
    required this.basketX,
    required this.targetX,
    required this.spawnTimer,
    this.clock,
  });

  /// Advance render/state timers on real time.
  void tick(double dt) {
    if (flash > 0) flash = math.max(0, flash - dt);
    if (stun > 0) stun = math.max(0, stun - dt);
  }

  /// Flash brightness in 0..1 (1 = just caught), for the renderer.
  double flashFill(double total) =>
      total <= 0 ? 0 : (flash / total).clamp(0.0, 1.0);

  /// Stun fill in 0..1 (1 = just bombed), for the renderer.
  double stunFill(double total) =>
      total <= 0 ? 0 : (stun / total).clamp(0.0, 1.0);
}
