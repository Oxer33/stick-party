import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'catch_render.dart';

/// Catch the Star — a single glowing star roams a night sky and EVERY player
/// chases it: you DRAG your net around your own zone to get under the star, then
/// TAP to snatch it. It is a shared, contested prize — first net there wins it,
/// so 1-4 players are racing for position, not waiting in a fixed slot.
///
/// Depth (still one-touch — drag to move, tap to grab):
///  * The star steers smoothly toward a free roaming waypoint (velocity +
///    steering, re-picked on arrival or timeout) so it curves rather than
///    snapping, drifting across the WHOLE arena instead of being fed to a
///    catcher — players must move to it. It drags a fading comet trail.
///  * Each player's net STEERS toward their latest drag point ([input.normPos]),
///    clamped to that player's zone so nobody reaches into a rival's slice. A TAP
///    (the [InputPhase.down]) also snatches: if the star is within [_snatchRadius]
///    of your net you score. Consecutive catches inside [_comboWindowSec] build a
///    combo that multiplies the award ("+N xC"), with a shockwave, net flash and
///    burst; the star keeps roaming (it teleports away on a catch so the next
///    chase starts fresh and nobody can camp the kill spot).
///  * Occasional GOLDEN bonus stars are worth [_bonusPoints] and a great catch
///    (golden, or a high combo) triggers a brief slow-mo (hit-stop) for impact.
///
/// Most catches at [_timeLimit] wins via [finishByScore]; the round always runs
/// to the limit so it can never stall.
///
/// Bots DRIVE their net toward the star (clamped to their zone) and TAP when it
/// is in range, gated by their reaction clock; a deliberate-mistake roll
/// ([BotProfile.errorRate]) makes them whiff and the remaining
/// [BotProfile.accuracy] decides whether the in-range snatch lands, so a weaker
/// bot is slower to the prize and a human can out-position it.
class CatchTheStar extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'catch_the_star',
        name: 'Catch the Star',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  // ── Round tuning (no magic numbers inline) ─────────────────────────────────
  static const double _timeLimit = 30;
  static const double _snatchRadius = 0.17; // normalized snatch distance

  // ── Climax: the GOLD RUSH flurry (the unmistakable peak near the end) ───────
  // In the last [_flurrySec] every fresh star is (almost) always golden, bigger
  // and worth its bonus — a frantic shouting finish where a trailing player can
  // still swing the round. A one-shot cue (banner + shake + burst) announces it.
  static const double _flurrySec = 7.0; // length of the end flurry
  static const double _flurryGoldenChance = 0.92; // golden odds during flurry
  static const double _flurryStarScale = 1.5; // mega-star radius multiplier
  static const double _flurrySpawnPopScale = 0.55; // faster respawns in flurry

  // ── Comeback: a subtle catch-up for trailing players ───────────────────────
  // A player below the leader gets a slightly wider effective snatch radius,
  // scaled by how far behind they are (capped). Kept gentle so a strong player
  // still usually wins, but a struggling kid stays in the shouting.
  static const double _comebackMaxBonus = 0.06; // max extra snatch radius (norm)
  static const int _comebackRefGap = 6; // score gap that earns the full bonus

  // ── Star motion tuning (normalized units / sec) ────────────────────────────
  // The star roams FREE — waypoints are random points across the whole arena, so
  // it never homes onto a player. It is a touch slower than a top-speed chase so
  // a net that positions well can get under it (you can still just miss it). This
  // is what makes the round a positioning RACE: the prize moves on its own and
  // everyone has to drive their net to it.
  static const double _maxSpeed = 0.52; // top speed
  static const double _goldenSpeedBoost = 1.18; // golden stars are friskier
  static const double _accel = 2.4; // steering acceleration
  static const double _retargetSec = 1.0; // force a new waypoint after this
  static const double _arriveDist = 0.05; // waypoint reached threshold
  static const double _margin = 0.1; // keep the star off the edges
  static const double _wallDamp = 0.4; // velocity kept on a wall bounce

  // ── Catcher (net) control tuning ────────────────────────────────────────────
  // A net eases toward its steer target (a human drag point, or a bot's chase
  // point) with a frame-rate-independent follow so a drag reads as a smooth glide
  // rather than a teleport. Bots cap their net travel so a weak bot can be
  // out-raced to the star by a human.
  static const double _netFollowPerSec = 16.0; // net → target ease speed
  static const double _botNetSpeed = 0.62; // bot net travel (units/sec)
  static const double _zoneInset = 0.02; // keep the net off the zone seam

  // ── Trail tuning ───────────────────────────────────────────────────────────
  static const double _trailSampleSec = 1 / 60; // sample cadence
  static const int _trailMaxPoints = 22; // comet length

  // ── Scoring / combo tuning ─────────────────────────────────────────────────
  static const int _basePoints = 1;
  static const int _bonusPoints = 3; // golden star award (pre-combo)
  static const double _goldenChance = 0.22; // chance a fresh star is golden
  static const double _comboWindowSec = 2.2; // chain window to keep a combo
  static const int _comboMax = 5; // multiplier cap
  static const int _greatComboThreshold = 3; // combo that earns slow-mo

  // ── Juice tuning ───────────────────────────────────────────────────────────
  static const double _slowMoSec = 0.22; // great-catch hit-stop length
  static const double _slowMoScale = 0.25; // time scale during slow-mo
  static const double _shockwaveSec = 0.45; // shockwave lifetime
  static const double _catcherFlashSec = 0.4; // catcher flash decay
  static const int _bgStarCount = 90; // parallax background stars

  // ── Render sizing (fractions of the min screen side) ───────────────────────
  static const double _starRadiusFrac = 0.05;
  static const double _shockwaveRadiusFrac = 0.26;
  static const Color _normalGlow = Color(0xFFFFD24A);
  static const Color _goldenGlow = Color(0xFFFF9E1B);
  static const Color _goldenBody = Color(0xFFFFE070);

  late Juice _juice;
  final List<_Catcher> _catchers = <_Catcher>[];
  final List<_Shockwave> _shockwaves = <_Shockwave>[];
  final List<Offset> _trail = <Offset>[]; // newest→oldest, normalized

  // Fixed parallax background field (positions + packed depth/phase seeds).
  final List<Offset> _bgStars = <Offset>[];
  final List<double> _bgSeeds = <double>[];

  Offset _star = const Offset(0.5, 0.5);
  Offset _vel = Offset.zero; // normalized units/sec
  Offset _target = const Offset(0.5, 0.5);
  bool _golden = false;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for shimmer/spin
  double _retargetAcc = 0;
  double _trailAcc = 0;
  double _spawnPop = 0; // 1 right after a teleport, decays to 0
  bool _flurryAnnounced = false; // the GOLD RUSH cue fired once
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _spawnCatchers();
    _seedBackground();
    _star = _randomPoint();
    _vel = Offset.zero;
    _target = _randomPoint();
    _golden = ctx.rng.chance(_goldenChance);
    _trail
      ..clear()
      ..add(_star);
    begin();
  }

  void _spawnCatchers() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final zone = _zoneFor(p.id, i, count);
      final start = zone.center;
      _catchers.add(_Catcher(
        playerId: p.id,
        displayNumber: p.id + 1,
        color: Color(p.colorArgb),
        zone: zone,
        pos: start,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// The slice of the arena a player's net is confined to. Prefer the real
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

  Offset _randomPoint() => Offset(
        ctx.rng.range(_margin, 1 - _margin),
        ctx.rng.range(_margin, 1 - _margin),
      );

  /// Pick the star's next waypoint: a free random point anywhere in the play
  /// area. It deliberately does NOT home onto any catcher, so the star is a
  /// neutral roaming prize that every player must chase down with their net —
  /// the source of the positioning race. Identical for the whole field, so fair.
  Offset _nextWaypoint() => _randomPoint();

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final c = _catcherOf(input.playerId);
    if (c == null) return;

    switch (input.phase) {
      case InputPhase.down:
        // A press both aims the net at the touch and tries to snatch right away,
        // so a quick tap exactly where the star is grabs it in one motion.
        _steerNet(c, input.normPos);
        _trySnatch(input.playerId);
      case InputPhase.holdTick:
        // Dragging glides the net toward the latest touch point; a positionless
        // per-frame tick (normPos == Offset.zero) carries no new target.
        if (input.normPos != Offset.zero) _steerNet(c, input.normPos);
      case InputPhase.up:
        break;
    }
  }

  /// Aim a human net's steering target at [normPos] (full-screen), clamped into
  /// that player's zone so a net can only roam its own slice of the arena.
  void _steerNet(_Catcher c, Offset normPos) {
    if (!normPos.dx.isFinite || !normPos.dy.isFinite) return;
    c.target = _clampToZone(c.zone, normPos);
  }

  /// Clamp a normalized point into [zone] with a tiny inset so the net centre
  /// never sits exactly on a zone seam.
  Offset _clampToZone(Rect zone, Offset p) => Offset(
        p.dx.clamp(zone.left + _zoneInset, zone.right - _zoneInset),
        p.dy.clamp(zone.top + _zoneInset, zone.bottom - _zoneInset),
      );

  /// Award a catch if the star is in range of [id]'s catcher. Returns true on a
  /// successful snatch. Drives combo, popup, shockwave, flash and slow-mo.
  bool _trySnatch(int id) {
    final c = _catcherOf(id);
    if (c == null) return false;
    if ((_star - c.pos).distance > _snatchRadiusFor(c)) return false;

    final wasGolden = _golden;
    final combo = c.registerCatch(_comboWindowSec, _comboMax);
    final award = (wasGolden ? _bonusPoints : _basePoints) * combo;
    addScore(id, award);

    _emitCatchJuice(c, award, combo, wasGolden);
    _respawnStar();
    return true;
  }

  void _emitCatchJuice(_Catcher c, int award, int combo, bool golden) {
    final at = _toPixels(_star);
    c.flash = _catcherFlashSec;

    final label = combo > 1 ? '+$award x$combo' : '+$award';
    final popColor = golden ? _goldenBody : c.color;
    _juice.popup(at, label, popColor, size: golden ? 38 : 30);

    final sparks = golden ? 18 : 11;
    _juice.hit(at, popColor, sparks: sparks);
    if (golden) {
      _juice.particles.burst(
        at: at,
        count: 16,
        color: _normalGlow,
        speed: 320,
        size: 6,
        life: 0.7,
      );
    }

    _shockwaves.add(_Shockwave(pos: _star, color: c.color, life: _shockwaveSec));

    // A great catch (golden, or a strong combo) earns a brief slow-mo + shake.
    if (golden || combo >= _greatComboThreshold) {
      _juice.hitStop.trigger(_slowMoSec, scale: _slowMoScale);
      _juice.shake.medium();
    }
  }

  /// Respawn far from all catchers (so nobody can camp) with a fresh waypoint,
  /// a possible golden upgrade and a pop-in. Velocity is re-aimed toward the new
  /// waypoint so the comet immediately reads as "zipping away".
  void _respawnStar() {
    _star = _farRespawn();
    // Pick a fresh free waypoint and aim the comet at it so the star immediately
    // reads as zipping away to a new spot the field now has to chase down.
    _target = _nextWaypoint();
    _golden = ctx.rng.chance(_goldenChanceNow());
    // Snappier pop-in during the flurry so goldens keep flooding the field.
    _spawnPop = _inFlurry ? _flurrySpawnPopScale : 1;
    final toTarget = _target - _star;
    _vel = toTarget.distance < 1e-6
        ? Offset.zero
        : (toTarget / toTarget.distance) * _currentMaxSpeed();
    _trail
      ..clear()
      ..add(_star);
    _trailAcc = 0;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _maybeAnnounceFlurry();
    _moveStar(sdt);
    _sampleTrail(sdt);
    _driveBots(sdt);
    _steerNets(sdt);
    _tickEffects(dt);

    if (_elapsed >= _timeLimit) _finish();
  }

  double _currentMaxSpeed() => _maxSpeed * (_golden ? _goldenSpeedBoost : 1.0);

  /// True once the round enters its final GOLD RUSH flurry window.
  bool get _inFlurry => _elapsed >= _timeLimit - _flurrySec;

  /// Golden odds for a freshly spawned star: the usual chance early, ramping to
  /// [_flurryGoldenChance] in the end flurry so the finish is a gold storm.
  double _goldenChanceNow() => _inFlurry ? _flurryGoldenChance : _goldenChance;

  /// Fire the one-shot GOLD RUSH cue the moment the flurry begins: a banner
  /// popup, a shake and a bright burst so every kid knows the big finish is on.
  void _maybeAnnounceFlurry() {
    if (_flurryAnnounced || !_inFlurry) return;
    _flurryAnnounced = true;
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.42);
    _juice.popup(center, 'GOLD RUSH!', _goldenBody, size: 46);
    _juice.shake.medium();
    _juice.particles.burst(
      at: center,
      count: 22,
      color: _goldenGlow,
      speed: 360,
      size: 7,
      life: 0.8,
    );
  }

  /// Effective snatch radius for [c]: the base reach plus a subtle comeback bonus
  /// for a player trailing the current leader (scaled by the gap, capped). The
  /// leader (and a fresh round at 0–0) gets exactly the base radius, so better
  /// players still win — laggards just get a slightly more forgiving window.
  double _snatchRadiusFor(_Catcher c) {
    final lead = _leaderScore();
    if (lead <= 0) return _snatchRadius;
    final behind = lead - scoreOf(c.playerId).toInt();
    if (behind <= 0) return _snatchRadius;
    final t = (behind / _comebackRefGap).clamp(0.0, 1.0);
    return _snatchRadius + _comebackMaxBonus * t;
  }

  /// Steer the star toward its waypoint with smooth acceleration + a speed cap,
  /// re-picking a waypoint on arrival or timeout, and softly bouncing off the
  /// playfield margins so it never sticks to an edge.
  void _moveStar(double dt) {
    if (dt <= 0) return;
    _retargetAcc += dt;
    final toTarget = _target - _star;
    if (toTarget.distance <= _arriveDist || _retargetAcc >= _retargetSec) {
      _target = _nextWaypoint();
      _retargetAcc = 0;
    }

    // Steering: accelerate toward the waypoint, clamp to max speed.
    final desired =
        toTarget.distance < 1e-6 ? Offset.zero : (toTarget / toTarget.distance);
    _vel += desired * (_accel * dt);
    final speed = _vel.distance;
    final maxSpeed = _currentMaxSpeed();
    if (speed > maxSpeed && speed > 0) _vel = _vel / speed * maxSpeed;

    var next = _star + _vel * dt;
    next = _bounceMargins(next);
    _star = next;
  }

  /// Reflect the star (and damp its velocity) when it reaches a margin so it
  /// stays inside the readable play area.
  Offset _bounceMargins(Offset p) {
    var x = p.dx;
    var y = p.dy;
    var vx = _vel.dx;
    var vy = _vel.dy;
    const lo = _margin;
    final hi = 1 - _margin;
    if (x < lo) {
      x = lo;
      vx = vx.abs() * _wallDamp;
    } else if (x > hi) {
      x = hi;
      vx = -vx.abs() * _wallDamp;
    }
    if (y < lo) {
      y = lo;
      vy = vy.abs() * _wallDamp;
    } else if (y > hi) {
      y = hi;
      vy = -vy.abs() * _wallDamp;
    }
    _vel = Offset(vx, vy);
    return Offset(x, y);
  }

  /// Append the star's position to the comet trail at a fixed cadence and trim
  /// it to the configured length (newest at index 0).
  void _sampleTrail(double dt) {
    _trailAcc += dt;
    if (_trailAcc < _trailSampleSec) return;
    _trailAcc = 0;
    _trail.insert(0, _star);
    if (_trail.length > _trailMaxPoints) {
      _trail.removeRange(_trailMaxPoints, _trail.length);
    }
  }

  /// Bots CHASE the star with their net and snatch when it is in range. Each
  /// frame the bot aims its net at the star's position (clamped to its own zone,
  /// so it can only contest the part of the arena it owns) and glides toward it
  /// at [_botNetSpeed] — a capped speed, so a faster human can beat a weak bot to
  /// the prize. When the star is within reach the bot taps on its reaction clock;
  /// an [BotProfile.errorRate] roll fumbles the attempt outright, otherwise
  /// [BotProfile.accuracy] decides whether the in-range snatch actually lands.
  void _driveBots(double dt) {
    for (final c in _catchers) {
      final clock = c.clock;
      if (clock == null) continue;

      // Drive the net toward the star (clamped to the bot's zone). Steering the
      // target each frame lets [_steerNets] glide the net smoothly like a human.
      c.target = _clampToZone(c.zone, _star);

      if ((_star - c.pos).distance > _snatchRadiusFor(c)) continue;
      if (!clock.tick(dt)) continue;
      clock.arm(ctx.botProfile, ctx.rng);
      // Deliberate miss, scaled by difficulty.
      if (ctx.rng.chance(ctx.botProfile.errorRate)) continue;
      if (ctx.rng.chance(ctx.botProfile.accuracy)) {
        _trySnatch(c.playerId);
      }
    }
  }

  /// Glide every net toward its steering target. Humans set the target by
  /// dragging ([_steerNet]); bots set it toward the star in [_driveBots]. A net
  /// eases with a frame-rate-independent follow so motion reads as a smooth slide
  /// rather than a snap, and stays clamped inside its owner's zone. Bot nets are
  /// additionally speed-capped so they can be out-raced.
  void _steerNets(double dt) {
    if (dt <= 0) return;
    final follow = (1.0 - math.exp(-_netFollowPerSec * dt)).clamp(0.0, 1.0);
    for (final c in _catchers) {
      final to = c.target - c.pos;
      Offset next;
      if (c.clock != null) {
        // Bot: capped travel toward the target so weak bots stay beatable.
        final step = _botNetSpeed * dt;
        next = to.distance <= step || to.distance < 1e-6
            ? c.target
            : c.pos + to / to.distance * step;
      } else {
        next = Offset(
          c.pos.dx + to.dx * follow,
          c.pos.dy + to.dy * follow,
        );
      }
      c.pos = _clampToZone(c.zone, next);
    }
  }

  /// Advance render-only effects on real (unscaled) time: catcher flashes,
  /// per-player combo timers, the spawn pop-in and expiring shockwaves.
  void _tickEffects(double dt) {
    for (final c in _catchers) {
      c.tick(dt);
    }
    if (_spawnPop > 0) {
      _spawnPop = math.max(0, _spawnPop - dt / _slowMoSec);
    }
    for (final s in _shockwaves) {
      s.life -= dt;
    }
    _shockwaves.removeWhere((s) => s.dead);
  }

  /// Respawn far from all catchers so a single player can't camp one spot.
  Offset _farRespawn() {
    var best = _randomPoint();
    var bestDist = -1.0;
    for (var i = 0; i < 6; i++) {
      final cand = _randomPoint();
      var nearest = double.infinity;
      for (final c in _catchers) {
        nearest = math.min(nearest, (cand - c.pos).distance);
      }
      if (nearest > bestDist) {
        bestDist = nearest;
        best = cand;
      }
    }
    return best;
  }

  void _finish() {
    if (status == MiniGameStatus.finished) return;
    finishByScore();
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    CatchRenderer.drawBackground(canvas, size);
    CatchRenderer.drawBackgroundStars(
        canvas, size, _bgStars, _bgSeeds, _animClock);
    CatchRenderer.drawVignette(canvas, size);

    _drawCatchers(canvas);
    _drawShockwaves(canvas);
    _drawStar(canvas);

    CatchRenderer.drawHud(
        canvas, size, _timeLimit - _elapsed, _leaderColor(), _leaderScore());

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawCatchers(Canvas canvas) {
    final starPx = _toPixels(_star);
    for (final c in _catchers) {
      final center = _toPixels(c.pos);
      // Draw the catcher at its effective reach so a trailing player's wider
      // comeback window is visible (and the in-range telegraph stays honest).
      final radius = _snatchRadiusFor(c);
      final reach = radius * _minSide;
      final inRange = (_star - c.pos).distance <= radius;
      // Hint line to a near-catch (drawn under the catcher art).
      if (inRange) {
        CatchRenderer.drawSnatchHint(canvas, center, starPx, c.color, 1.0);
      }
      CatchRenderer.drawCatcher(
        canvas,
        center,
        reach,
        c.color,
        c.displayNumber,
        flash: c.flashFill(_catcherFlashSec),
        armed: inRange ? 1.0 : 0.0,
        t: _animClock,
      );
    }
  }

  void _drawShockwaves(Canvas canvas) {
    final maxR = _shockwaveRadiusFrac * _minSide;
    for (final s in _shockwaves) {
      CatchRenderer.drawShockwave(
          canvas, _toPixels(s.pos), maxR, s.color, s.progress(_shockwaveSec));
    }
  }

  void _drawStar(Canvas canvas) {
    // During the GOLD RUSH the star swells into a readable mega-star.
    final r = _starRadiusFrac * _minSide * (_inFlurry ? _flurryStarScale : 1.0);
    final pulse = 0.5 + 0.5 * math.sin(_animClock * 5.0);
    final rot = _animClock * 0.7;
    CatchRenderer.drawCometTrail(
      canvas,
      [for (final p in _trail) _toPixels(p)],
      r,
      _golden ? _goldenGlow : _normalGlow,
      pulse: pulse,
    );
    CatchRenderer.drawStar(
      canvas,
      _toPixels(_star),
      r,
      pulse: pulse,
      golden: _golden,
      rot: rot,
      spawn: _spawnPop,
    );
  }

  // ── Small helpers ──────────────────────────────────────────────────────────

  double get _minSide => math.min(_lastSize.width, _lastSize.height);

  _Catcher? _catcherOf(int id) {
    for (final c in _catchers) {
      if (c.playerId == id) return c;
    }
    return null;
  }

  /// Current leader's color (null on a fresh round with no points yet).
  Color? _leaderColor() {
    _Catcher? best;
    var bestScore = 0;
    for (final c in _catchers) {
      final s = scoreOf(c.playerId).toInt();
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    return best?.color;
  }

  int _leaderScore() {
    var best = 0;
    for (final c in _catchers) {
      best = math.max(best, scoreOf(c.playerId).toInt());
    }
    return best;
  }

  Offset _toPixels(Offset norm) =>
      Offset(norm.dx * _lastSize.width, norm.dy * _lastSize.height);

  /// Test-only view of the roaming star's normalized position so deterministic
  /// tests can steer a net exactly onto it (the core chase mechanic). Not used
  /// by gameplay or rendering.
  @visibleForTesting
  Offset get starPosForTest => _star;

  /// Test-only view of a player's net position so tests can assert the net stays
  /// clamped inside its zone. Returns null for an unknown id. Not used by
  /// gameplay or rendering.
  @visibleForTesting
  Offset? netPosForTest(int id) => _catcherOf(id)?.pos;
}

/// Per-player catcher (net) bookkeeping: the zone it is confined to, its live
/// position + steering target, color, optional bot clock and the round-scoped
/// flash + combo state. Mutable for the duration of one round (allowed by
/// [MiniGameBase]).
class _Catcher {
  final int playerId;
  final int displayNumber;
  final Color color;
  final Rect zone; // this player's slice of the arena (normalized)
  final ReactionClock? clock;

  Offset pos; // normalized 0..1 net position (steered by drag / bot)
  Offset target; // where the net is gliding toward (clamped into [zone])
  double flash = 0; // seconds of snatch flash remaining
  int _combo = 0; // current combo count (1.. on a live chain)
  double _comboTimer = 0; // seconds left to keep the chain alive

  _Catcher({
    required this.playerId,
    required this.displayNumber,
    required this.color,
    required this.zone,
    required this.pos,
    this.clock,
  }) : target = pos;

  /// Register a successful catch: extend/grow the combo within its window and
  /// return the resulting multiplier (1..[max]).
  int registerCatch(double windowSec, int max) {
    _combo = (_comboTimer > 0 ? _combo + 1 : 1).clamp(1, max);
    _comboTimer = windowSec;
    return _combo;
  }

  /// Advance flash + combo timers on real time.
  void tick(double dt) {
    if (flash > 0) flash = math.max(0, flash - dt);
    if (_comboTimer > 0) {
      _comboTimer = math.max(0, _comboTimer - dt);
      if (_comboTimer == 0) _combo = 0;
    }
  }

  /// Flash brightness in 0..1 (1 = just snatched), for the renderer.
  double flashFill(double total) {
    if (total <= 0) return 0;
    return (flash / total).clamp(0.0, 1.0);
  }
}

/// A short-lived expanding snatch shockwave. Round-scoped mutable effect state.
class _Shockwave {
  final Offset pos; // normalized
  final Color color;
  double life;
  final double maxLife;

  _Shockwave({required this.pos, required this.color, required this.life})
      : maxLife = life;

  bool get dead => life <= 0;

  /// 0..1 progress (0 = just born, 1 = expired).
  double progress(double total) =>
      total <= 0 ? 1 : (1.0 - (life / total)).clamp(0.0, 1.0);
}
