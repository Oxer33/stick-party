import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'catch_render.dart';

/// Catch the Star — a single glowing star wanders a night sky; each player has a
/// fixed catcher anchored in their screen zone and snatches with one tap.
///
/// Depth (still one-touch):
///  * The star steers smoothly toward a roaming waypoint (velocity + steering,
///    re-picked on arrival or timeout) so it curves rather than snapping, and
///    drags a fading comet trail behind it.
///  * A tap snatches: if the star is within [_snatchRadius] of that player's
///    catcher they score. Consecutive catches inside [_comboWindowSec] build a
///    combo that multiplies the award ("+N xC"), with a satisfying shockwave,
///    catcher flash and burst; the star then zips to a fresh point far from all
///    catchers (pop-in).
///  * Occasional GOLDEN bonus stars are worth [_bonusPoints] and a great catch
///    (golden, or a high combo) triggers a brief slow-mo (hit-stop) for impact.
///
/// Most catches at [_timeLimit] wins via [finishByScore]; the round always runs
/// to the limit so it can never stall.
///
/// Bots snatch when the star is in range, gated by their reaction clock; a
/// deliberate-mistake roll ([BotProfile.errorRate]) makes them whiff and the
/// remaining [BotProfile.accuracy] decides whether the in-range snatch lands, so
/// difficulty reads as deliberate rather than random.
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

  // ── Star motion tuning (normalized units / sec) ────────────────────────────
  // The star is a touch slower than a pure chase so the catchable window over a
  // catcher feels generous (you can still miss it), and its waypoints are biased
  // to FLY THROUGH catchers (see [_nextWaypoint]) so it constantly teases each
  // player instead of wandering empty sky — many more snatch chances, fairly
  // shared, which is what makes the round feel alive rather than sparse.
  static const double _maxSpeed = 0.52; // top speed
  static const double _goldenSpeedBoost = 1.18; // golden stars are friskier
  static const double _accel = 2.4; // steering acceleration
  static const double _retargetSec = 1.0; // force a new waypoint after this
  static const double _arriveDist = 0.05; // waypoint reached threshold
  static const double _margin = 0.1; // keep the star off the edges
  static const double _wallDamp = 0.4; // velocity kept on a wall bounce
  static const double _visitCatcherChance = 0.6; // waypoint aims near a catcher
  static const double _visitJitter = 0.12; // sweep offset around a visited zone

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
      _catchers.add(_Catcher(
        playerId: p.id,
        displayNumber: p.id + 1,
        color: Color(p.colorArgb),
        pos: _anchorFor(p.id, i, count),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Catcher anchor: prefer the player's zone center, else spread evenly.
  Offset _anchorFor(int id, int index, int count) {
    final zone = ctx.zones.forPlayer(id);
    if (zone != null) return zone.center;
    return Offset((index + 0.5) / count, index.isEven ? 0.8 : 0.2);
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

  /// Pick the star's next waypoint. Most of the time ([_visitCatcherChance]) it
  /// aims at a random catcher's zone with a small sweep offset so the star
  /// arcs *through* that catch zone (a real snatch chance) rather than parking on
  /// it; otherwise a free roam point keeps the path unpredictable. This is what
  /// turns the round from sparse wandering into a constant tease past every
  /// player — and it is identical for humans and bots, so it stays fair.
  Offset _nextWaypoint() {
    if (_catchers.isNotEmpty && ctx.rng.chance(_visitCatcherChance)) {
      final target = ctx.rng.pick(_catchers).pos;
      final jittered = target +
          Offset(ctx.rng.jitter(_visitJitter), ctx.rng.jitter(_visitJitter));
      return Offset(
        jittered.dx.clamp(_margin, 1 - _margin),
        jittered.dy.clamp(_margin, 1 - _margin),
      );
    }
    return _randomPoint();
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _trySnatch(input.playerId);
  }

  /// Award a catch if the star is in range of [id]'s catcher. Returns true on a
  /// successful snatch. Drives combo, popup, shockwave, flash and slow-mo.
  bool _trySnatch(int id) {
    final c = _catcherOf(id);
    if (c == null) return false;
    if ((_star - c.pos).distance > _snatchRadius) return false;

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
    // Aim straight back toward a catcher so the star re-enters the action fast
    // after popping in far away, instead of drifting through empty sky first.
    _target = _nextWaypoint();
    _golden = ctx.rng.chance(_goldenChance);
    _spawnPop = 1;
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

    _moveStar(sdt);
    _sampleTrail(sdt);
    _driveBots(sdt);
    _tickEffects(dt);

    if (_elapsed >= _timeLimit) _finish();
  }

  double _currentMaxSpeed() => _maxSpeed * (_golden ? _goldenSpeedBoost : 1.0);

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

  /// Bots snatch when the star is near their catcher, gated by reaction time;
  /// an [BotProfile.errorRate] roll fumbles the attempt outright, otherwise
  /// [BotProfile.accuracy] decides whether the in-range snatch actually lands.
  void _driveBots(double dt) {
    for (final c in _catchers) {
      final clock = c.clock;
      if (clock == null) continue;
      final inRange = (_star - c.pos).distance <= _snatchRadius;
      if (!inRange) continue;
      if (!clock.tick(dt)) continue;
      clock.arm(ctx.botProfile, ctx.rng);
      // Deliberate miss, scaled by difficulty.
      if (ctx.rng.chance(ctx.botProfile.errorRate)) continue;
      if (ctx.rng.chance(ctx.botProfile.accuracy)) {
        _trySnatch(c.playerId);
      }
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
    final reach = _snatchRadius * _minSide;
    final starPx = _toPixels(_star);
    for (final c in _catchers) {
      final center = _toPixels(c.pos);
      final inRange = (_star - c.pos).distance <= _snatchRadius;
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
    final r = _starRadiusFrac * _minSide;
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
}

/// Per-player catcher bookkeeping: fixed anchor, color, optional bot clock and
/// the round-scoped flash + combo state. Mutable for the duration of one round
/// (allowed by [MiniGameBase]).
class _Catcher {
  final int playerId;
  final int displayNumber;
  final Color color;
  final Offset pos; // normalized 0..1 anchor
  final ReactionClock? clock;

  double flash = 0; // seconds of snatch flash remaining
  int _combo = 0; // current combo count (1.. on a live chain)
  double _comboTimer = 0; // seconds left to keep the chain alive

  _Catcher({
    required this.playerId,
    required this.displayNumber,
    required this.color,
    required this.pos,
    this.clock,
  });

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
