import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/aim_sweep.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'archer_fx.dart';
import 'archer_render.dart';

/// Archer Pop — every player is a stickman archer on a screen edge with a bow
/// that auto-sweeps an aiming arc. One tap LOOSES a gravity-arced arrow at the
/// balloons drifting up the field. Most balloons popped at the 30 s limit wins.
///
/// CONTROL (the heart of it — full agency, still one touch):
///  * The bow AIM sweeps an arc continuously at a learnable speed; the draw fills
///    toward the ends of the arc so the archer visibly nocks deeper.
///  * Quick TAP → loose immediately at the angle (and draw) the bow is showing.
///  * HOLD → the sweep slows to a crawl so you can settle the aim on a balloon;
///    the arrow looses the moment you RELEASE. A tap is a snap shot, a hold is a
///    led, careful shot — nothing is auto-aimed. (A one-frame down→up still
///    looses, so tap-to-fire is intact.) Release punches a string-snap, riser
///    kick, muzzle puff and a short hit-stop.
///
/// Depth:
///  * **Wind**: a slowly-varying crosswind drifts every arrow in flight; a top
///    banner + rushing streaks telegraph its heading + strength so a good archer
///    leads the shot. Bots read the wind and lead for it too.
///  * **Combo multiplier**: consecutive pops inside a window stack a multiplier
///    (x2, x3 …) for fat scores + a floating combo badge; a miss-timed lull lets
///    it lapse. A pop also feeds a hit-streak that grows the per-pop value.
///  * **Varied targets**: balloons come small/medium/large (smaller = worth
///    more), player-colored, bobbing and drifting; rare **golden** bonus
///    balloons are worth a burst of points with a metallic shine + sparkle.
///
/// FAIR BOTS: they loose when their swept aim lines up (accuracy-scaled cone)
/// with the wind-lead-corrected bearing to a live balloon, on a [ReactionClock]
/// cadence — but only after a warm-up grace, and with a [BotProfile] accuracy
/// error plus a per-shot flinch so easy bots genuinely MISS often and are
/// beatable. Always finishes on the time limit and never throws for 1..4
/// players.
class ArcherPop extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'archer_pop',
        name: 'Archer Pop',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Round / scoring tuning (no magic numbers inline) ────────────────────────
  static const double _timeLimit = 30;
  static const int _baseHitPoints = 1; // points for a plain pop (×combo ×streak)
  static const int _goldenPoints = 5; // points for a golden pop (×combo)
  static const double _comboWindowSec = 1.6; // pops within this keep the combo
  static const int _maxCombo = 6; // multiplier cap
  static const int _streakForBonus = 3; // hits/streak step that adds +1 value
  static const int _maxStreakBonus = 3; // cap on the streak value bonus

  // ── Ballistics tuning ───────────────────────────────────────────────────────
  static const double _gravity = 240; // px/s^2 on arrows (a readable arc)
  static const double _arrowSpeed = 760; // launch px/s
  static const double _arrowLife = 3.2; // seconds before an arrow fizzles
  static const int _trailSamples = 10; // trail points kept per arrow
  static const double _outOfBoundsPad = 90;
  static const double _stuckLifeSec = 0.5; // ground/edge stick fade
  static const double _burstSec = 0.28; // balloon pop animation length

  // ── Bow geometry / sweep tuning (mirrors ArcherRenderer so sim agrees) ──────
  static const double _baseScaleRef = 520; // arena minSide → scale 1
  static const double _figureScale = 1.7; // readable archer bodies
  static const double _edgeInsetFactor = 0.10; // edge inset / min(arena side)
  static const double _sweepHalfBand = 0.62; // half sweep arc (radians)
  static const double _sweepSpeed = 1.55; // sweep angular speed (rad/s) — learnable
  static const double _looseFadeSec = 0.18; // loose-flash decay
  static const double _muzzleReach = 28; // bow-hand → arrow spawn (× scale)

  // ── Balloon field tuning ────────────────────────────────────────────────────
  static const double _spawnEvery = 0.62; // seconds between spawns
  static const int _maxBalloons = 12;
  static const int _initialBalloons = 5; // seeded so the field reads instantly
  static const double _riseSpeedMin = 46; // px/s upward
  static const double _riseSpeedMax = 84;
  static const double _driftMax = 26; // px/s lateral wander
  static const double _windShareOnBalloon = 0.25; // wind drift on balloons
  static const double _bobRate = 2.2; // sway rad/s
  static const double _bobSway = 10; // px lateral sway amplitude rate
  static const double _radiusSmall = 16;
  static const double _radiusLarge = 30;
  static const double _goldenChance = 0.12; // share of spawns that are golden
  static const double _topMarginFrac = 0.10; // balloons gone above this (× h)
  static const double _sparkleRate = 3.0; // golden glint spin rad/s

  // ── Wind tuning ─────────────────────────────────────────────────────────────
  static const double _windMax = 70; // peak crosswind px/s
  static const double _windChangeSec = 4.0; // seconds to ease to a new target
  static const double _windEaseRate = 2.0; // ease multiplier toward target
  static const int _windStreakCount = 22;

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botBaseTolerance = 0.12; // good-aim cone at full accuracy
  static const double _botLeadSec = 0.32; // how far ahead bots lead a target
  static const double _botWildChance = 0.35; // share of errorRate → wild loose
  static const double _botGoldenBias = 1.6; // bots favor golden lineups

  // ── Climax (frenzy) tuning ──────────────────────────────────────────────────
  // The final ~30% of the round: balloons rush in faster, more of them are
  // golden, and a FRENZY banner throbs — a clear ramp where a trailing player
  // can still rack up a comeback off fat golden pops.
  static const double _frenzyFrac = 0.7; // enters at this share of the limit
  static const double _frenzySpawnMul = 0.5; // spawn interval × this in frenzy
  static const int _frenzyMaxBalloons = 16; // higher field cap in frenzy
  static const double _frenzyGoldenChance = 0.26; // golden share in frenzy

  // ── Visuals / ambient ───────────────────────────────────────────────────────
  static const double _horizonFactor = 0.40; // horizon Y / arena height
  static const int _cloudCount = 5;
  static const Color _muzzlePuff = Color(0xFFFFF0C4);
  static const Color _comboColor = Color(0xFFFFD24A);

  late Juice _juice;
  late Size _size;
  late double _scale;
  late double _horizonY;
  late Offset _sun;

  final List<_Archer> _archers = <_Archer>[];
  final List<_Arrow> _arrows = <_Arrow>[];
  final List<_Balloon> _balloons = <_Balloon>[];
  final List<Offset> _clouds = <Offset>[];
  final List<Offset> _windAnchors = <Offset>[];

  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for ambient/flash
  double _spawnTimer = 0;
  bool _frenzyAnnounced = false;

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
    _horizonY = _size.height * _horizonFactor;
    _sun = Offset(_size.width * 0.74, _size.height * 0.16);

    _buildArchers();
    _seedAmbient();
    _retargetWind();
    // Seed the field already spread vertically so every archer has nearby
    // targets at once; later balloons rise in from the bottom edge.
    for (var i = 0; i < _initialBalloons; i++) {
      _spawnBalloon(seeded: true);
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
      // Sweep band centered on the inward normal so the bow always aims into
      // the field, regardless of which edge the archer sits on.
      final inward = -side.outward;
      final center = math.atan2(inward.dy, inward.dx);
      final bow = AimSweep(
        minAngle: center - _sweepHalfBand,
        maxAngle: center + _sweepHalfBand,
        speed: _sweepSpeed,
        angle: center + ctx.rng.jitter(_sweepHalfBand * 0.6),
      );
      final facing = inward.dx >= 0 ? 1.0 : -1.0;
      final figure = StickFigure(
        proportions: proportions,
        style: _styleFor(Color(p.colorArgb)),
        facing: facing,
        aimAngle: bow.angle,
      )..setLoco(LocoState.idle);
      _archers.add(_Archer(
        playerId: p.id,
        color: Color(p.colorArgb),
        base: base,
        side: side,
        facing: facing,
        bow: bow,
        figure: figure,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Bright archer style: player-color fill, brightened outline, strong glow.
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

  /// Assign each seat to a screen edge: bottom, then top, then the sides.
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

  /// Stick-root anchor: inset from the assigned edge, centered along it.
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

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _loose(input.playerId);
  }

  /// Loose an arrow along the current sweep at the current draw. Shared by human
  /// taps and bot decisions so the feel + ballistics stay identical.
  void _loose(int id) {
    final archer = _archerOf(id);
    if (archer == null) return;
    final dir = archer.bow.direction;
    final muzzle = _muzzleOf(archer);
    // Draw scales launch speed slightly — a deeper nock flies a touch faster.
    final draw = _drawOf(archer);
    final speed = _arrowSpeed * (0.9 + 0.1 * draw);
    _arrows.add(_Arrow(
      pos: muzzle,
      vel: dir * speed,
      ownerId: id,
      color: archer.color,
    ));
    archer.loose = _looseFadeSec;
    // Release punch: a small forward puff of dust + a short hit-stop kiss.
    final baseAngle = math.atan2(dir.dy, dir.dx);
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
      a.bow.update(sdt);
      a.figure.aimAngle = a.bow.angle;
      a.figure.update(dt);
      a.tickTimers(dt, _looseFadeSec);
    }
    _spawnTick(sdt);
    _stepBalloons(sdt);
    _driveBots(dt);
    _stepArrows(sdt);
    _announceFrenzy();
    _checkEnd();
  }

  /// True once the round has entered its climax (frenzy) window.
  bool get _isFrenzy => _elapsed >= _timeLimit * _frenzyFrac;

  /// Announce the climax once (shake + center popup); the banner + faster rush
  /// of mostly-golden balloons then carry the moment.
  void _announceFrenzy() {
    if (_frenzyAnnounced || !_isFrenzy) return;
    _frenzyAnnounced = true;
    _juice.shake.medium();
    _juice.popup(Offset(_size.width / 2, _size.height * 0.28), 'FRENZY!',
        _comboColor,
        size: 38);
  }

  // ── Wind ──────────────────────────────────────────────────────────────────

  void _stepWind(double dt) {
    _windTimer -= dt;
    if (_windTimer <= 0) _retargetWind();
    // Ease the live wind toward its target for smooth gusts.
    final rate = (dt / _windChangeSec).clamp(0.0, 1.0);
    _windX = lerpD(_windX, _windTarget, rate * _windEaseRate);
  }

  void _retargetWind() {
    _windTarget = ctx.rng.range(-_windMax, _windMax);
    _windTimer = _windChangeSec * ctx.rng.range(0.8, 1.4);
  }

  // ── Balloon spawning + motion ───────────────────────────────────────────────

  void _spawnTick(double dt) {
    _spawnTimer += dt;
    // Frenzy: balloons rush in roughly twice as fast and the field holds more.
    final every = _isFrenzy ? _spawnEvery * _frenzySpawnMul : _spawnEvery;
    final cap = _isFrenzy ? _frenzyMaxBalloons : _maxBalloons;
    if (_spawnTimer >= every && _balloons.length < cap) {
      _spawnTimer = 0;
      _spawnBalloon();
    }
  }

  void _spawnBalloon({bool seeded = false}) {
    final w = _size.width, h = _size.height;
    // Frenzy mints far more golden balloons (fat points for a late comeback).
    final golden =
        ctx.rng.chance(_isFrenzy ? _frenzyGoldenChance : _goldenChance);
    // Smaller balloons are worth more; golden ones use a mid radius.
    final radius = golden
        ? (_radiusSmall + _radiusLarge) * 0.5
        : ctx.rng.range(_radiusSmall, _radiusLarge);
    // New balloons rise from just below the field; the initial seed is spread
    // up through the play area so the field reads full from the first frame.
    final x = ctx.rng.range(w * 0.1, w * 0.9);
    final y = seeded
        ? ctx.rng.range(_horizonY + radius * 2, h * 0.92)
        : h + radius * 1.5;
    final rise = ctx.rng.range(_riseSpeedMin, _riseSpeedMax);
    final drift = ctx.rng.range(-_driftMax, _driftMax);
    // Plain balloons take a random player accent; golden ones are gold-tinted.
    final palette = ctx.players[ctx.rng.intRange(0, ctx.players.length)];
    _balloons.add(_Balloon(
      pos: Offset(x, y),
      vel: Offset(drift, -rise),
      radius: radius,
      color: Color(palette.colorArgb),
      golden: golden,
      bob: ctx.rng.range(0, kTau),
    ));
  }

  void _stepBalloons(double dt) {
    final topGone = -_size.height * _topMarginFrac;
    final survivors = <_Balloon>[];
    for (final b in _balloons) {
      // Resolve a finishing pop animation, then drop it.
      if (b.popT > 0) {
        b.popT -= dt / _burstSec;
        if (b.popT > 0) survivors.add(b);
        continue;
      }
      b.bob += dt * _bobRate;
      // Lateral wander from its own drift plus a share of the wind.
      final sway = math.sin(b.bob) * _bobSway * dt;
      final dx = b.vel.dx + _windX * _windShareOnBalloon;
      b.pos = b.pos + Offset(dx, b.vel.dy) * dt + Offset(sway, 0);
      b.sparkle += dt * _sparkleRate;
      final offTop = b.pos.dy < topGone;
      final offSide =
          b.pos.dx < -b.radius * 2 || b.pos.dx > _size.width + b.radius * 2;
      if (offTop || offSide) continue; // floated away (no score)
      survivors.add(b);
    }
    _balloons
      ..clear()
      ..addAll(survivors);
  }

  // ── Bots: line up the lead-corrected bearing, then loose on cadence ─────────

  void _driveBots(double dt) {
    for (final a in _archers) {
      final clock = a.clock;
      if (clock == null) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldLoose(a)) _loose(a.playerId);
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  /// A bot looses when its live sweep angle is within an accuracy-scaled cone of
  /// the wind-lead-corrected bearing to a live balloon (golden balloons get a
  /// wider, more attractive cone). Low-accuracy bots also take occasional wild
  /// shots so they are never idle.
  bool _botShouldLoose(_Archer archer) {
    final accuracy = ctx.botProfile.accuracy.clamp(0.2, 1.0);
    final baseTol = _botBaseTolerance / accuracy;
    final origin = _muzzleOf(archer);
    for (final b in _balloons) {
      if (b.popT > 0) continue;
      // Lead: aim where the balloon (and wind-borne arrow) will be shortly.
      final lead =
          b.pos + (b.vel + Offset(_windX * _windShareOnBalloon, 0)) * _botLeadSec;
      final to = lead - origin;
      final wanted = math.atan2(to.dy, to.dx);
      final tol = b.golden ? baseTol * _botGoldenBias : baseTol;
      // Accuracy error nudges the wanted angle so good lineups still sometimes
      // miss at lower difficulties.
      final err = ctx.rng.jitter((1 - accuracy) * _sweepHalfBand * 0.5);
      if (wrapAngle(archer.bow.angle - (wanted + err)).abs() <= tol) {
        return true;
      }
    }
    return ctx.rng.chance(ctx.botProfile.errorRate * _botWildChance);
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
      // Gravity pulls down; wind drifts horizontally — the core skill.
      final vel = s.vel + Offset(_windX * dt, _gravity * dt);
      final pos = s.pos + vel * dt;
      final life = s.life - dt;

      final hit = _popTarget(pos);
      if (hit != null) {
        _registerPop(s.ownerId, hit);
        continue; // arrow consumed by the pop
      }
      if (life <= 0 || _outOfBounds(pos)) {
        // On-field arrows linger a moment (stuck fade); off-screen ones vanish.
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

  _Balloon? _popTarget(Offset pos) {
    for (final b in _balloons) {
      if (b.popT > 0) continue;
      if ((b.pos - pos).distance <= b.radius) return b;
    }
    return null;
  }

  /// Award points for a pop with combo multiplier + streak bonus, fire the burst
  /// + popups, and start the balloon's burst animation.
  void _registerPop(int shooterId, _Balloon target) {
    final archer = _archerOf(shooterId);
    if (archer == null) return;

    // Combo: pops inside the window stack the multiplier; else it resets to 1.
    if (archer.comboTimer > 0) {
      archer.combo = (archer.combo + 1).clamp(1, _maxCombo);
    } else {
      archer.combo = 1;
    }
    archer.comboTimer = _comboWindowSec;
    archer.streak += 1;

    // Streak bonus grows the per-pop value every few consecutive hits.
    final streakBonus =
        (archer.streak ~/ _streakForBonus).clamp(0, _maxStreakBonus);
    final unit = target.golden ? _goldenPoints : _baseHitPoints + streakBonus;
    final gained = unit * archer.combo;
    addScore(shooterId, gained);

    // Juice: a colored burst (golden gets a hotter, bigger one) + popups.
    final popColor = target.golden ? _comboColor : archer.color;
    _juice.particles.burst(
      at: target.pos,
      count: target.golden ? 20 : 12,
      color: popColor,
      speed: target.golden ? 320 : 240,
      size: target.golden ? 7 : 5,
      gravity: 420,
      life: target.golden ? 0.6 : 0.45,
    );
    _juice.shake.light();
    if (target.golden || archer.combo >= 3) {
      _juice.hitStop.trigger(0.05, scale: 0.2);
    }
    _juice.popup(
      target.pos.translate(0, -target.radius),
      archer.combo >= 2 ? '+$gained  x${archer.combo}' : '+$gained',
      popColor,
      size: target.golden ? 30 : 24,
    );

    // Start the balloon's burst animation (it self-removes after).
    target.popT = 1.0;
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
    if (_elapsed >= _timeLimit) {
      _juice.confetti(_size);
      finishByScore();
    }
  }

  // ── Geometry helpers (mirror ArcherRenderer) ────────────────────────────────

  /// Muzzle = the bow-hand anchor (renderer-shared) plus a short reach along the
  /// aim so the loosed arrow leaves where the drawn arrow visually sits.
  Offset _muzzleOf(_Archer a) {
    final view = _viewOf(a);
    final dir = a.bow.direction;
    return ArcherRenderer.bowAnchor(view) + dir * (_muzzleReach * _scale);
  }

  /// Draw amount 0..1 from the sweep progress: deepest nock toward the band ends
  /// (where the archer "holds" before reversing), shallow through the center.
  double _drawOf(_Archer a) {
    final p = a.bow.progress; // 0 at minAngle, 1 at maxAngle
    final fromCenter = (p - 0.5).abs() * 2.0; // 0 center → 1 at an end
    return fromCenter.clamp(0.0, 1.0);
  }

  _Archer? _archerOf(int id) {
    for (final a in _archers) {
      if (a.playerId == id) return a;
    }
    return null;
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

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

    // Aim guides first (under the archers), then balloons, then archers + bows.
    for (final a in _archers) {
      ArcherRenderer.drawAimGuide(canvas, _viewOf(a));
    }
    for (final b in _balloons) {
      ArcherRenderer.drawBalloon(canvas, _balloonView(b));
    }
    // In-flight arrows behind bodies so a loosed arrow reads leaving the bow.
    for (final s in _arrows) {
      ArcherRenderer.drawArrow(canvas, s.view());
    }
    for (final a in _archers) {
      final view = _viewOf(a);
      ArcherRenderer.drawArcherBody(canvas, a.figure, a.base);
      ArcherRenderer.drawBow(canvas, view);
      ArcherRenderer.drawComboBadge(canvas, view);
    }

    ArcherRenderer.drawWindBanner(canvas, size, _windX);
    if (_isFrenzy) {
      ArcherFx.drawFrenzyBanner(canvas, size, 1.0, _animClock);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  ArcherView _viewOf(_Archer a) => ArcherView(
        base: a.base,
        color: a.color,
        side: a.side,
        facing: a.facing,
        aimAngle: a.bow.angle,
        draw: _drawOf(a),
        combo: a.combo,
        scale: _scale,
        loose: (a.loose / _looseFadeSec).clamp(0.0, 1.0),
      );

  BalloonView _balloonView(_Balloon b) => BalloonView(
        pos: b.pos,
        color: b.color,
        radius: b.radius,
        bobPhase: b.bob,
        popT: b.popT.clamp(0.0, 1.0),
        golden: b.golden,
        sparklePhase: b.sparkle,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}

/// One archer. Mutable round-scoped state (allowed for the duration of a round).
class _Archer {
  final int playerId;
  final Color color;
  final Offset base; // stick-root anchor in arena px
  final ArcherSide side;
  final double facing;
  final AimSweep bow;
  final StickFigure figure;
  final ReactionClock? clock; // null for human seats

  double loose = 0; // loose-flash timer (string snap + riser kick)
  int combo = 0; // current multiplier (0 = none, then 1..max)
  double comboTimer = 0; // seconds left to keep the combo alive
  int streak = 0; // total consecutive pops (drives the value bonus)

  _Archer({
    required this.playerId,
    required this.color,
    required this.base,
    required this.side,
    required this.facing,
    required this.bow,
    required this.figure,
    this.clock,
  });

  void tickTimers(double dt, double looseFadeSec) {
    if (loose > 0) loose = (loose - dt).clamp(0, looseFadeSec);
    if (comboTimer > 0) {
      comboTimer -= dt;
      if (comboTimer <= 0) {
        // Combo + streak lapse together when the window closes.
        comboTimer = 0;
        combo = 0;
        streak = 0;
      }
    }
  }
}

/// One in-flight (or briefly stuck) arrow. Mutates along its arc; keeps a short
/// trail for the motion streak. Mutable round-scoped state.
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

  /// Embed where it died (on-field): stop advancing, start the stuck fade.
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

/// One floating balloon target. Mutable round-scoped state.
class _Balloon {
  Offset pos;
  final Offset vel; // base drift + rise (wind added at step time)
  final double radius;
  final Color color;
  final bool golden;
  double bob; // sway phase
  double sparkle = 0; // golden glint phase
  double popT = 0; // 0 = whole, 1 → 0 while bursting

  _Balloon({
    required this.pos,
    required this.vel,
    required this.radius,
    required this.color,
    required this.golden,
    required this.bob,
  });
}
