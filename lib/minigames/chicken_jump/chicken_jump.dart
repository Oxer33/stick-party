import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/lane_hopper.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'chicken_render.dart';

/// Numeric tuning — no magic numbers inline. Times in seconds, speeds px/s.
class _Tuning {
  // Round length. Comfortably under the test's 80s safety cap; the lava
  // escalation guarantees the round converges well before this.
  static const double timeLimit = 44;

  static const int platformCount = 16; // rungs in each player's tower
  static const double topInset = 96; // px from the top to the highest platform
  static const double bottomInset = 150; // px from the bottom to the lowest

  // Rising lava: engages quickly (no dead time at the start) and accelerates so
  // the round always resolves.
  static const double lavaRiseStart = 44; // px/s initial climb
  static const double lavaAccel = 7.5; // px/s^2 ramp
  static const double lavaStartGap = 12; // px the lava starts below the lowest

  static const double hopAnimSpeed = 16; // lane ease rate (snappy take-off)
  static const double jumpHoldSec = 0.22; // how long the jump pose shows
  static const double landHoldSec = 0.12; // brief squash on landing

  // Figure scaling tracks column width so 1..4 towers all read clearly.
  static const double figureScaleMin = 0.85; // narrow 4-up columns
  static const double figureScaleMax = 1.7; // single wide column
  static const double figureScaleLoColumn = 150; // column px at min scale
  static const double figureScaleHiColumn = 560; // column px at max scale
  static const double figureLiftExtra = 6; // raise feet above the platform top

  // Crumbling platforms: a rung the climber leaves begins to crumble and is
  // gone shortly after, so camping a single platform is impossible.
  static const double crumbleAfterSec = 0.9; // delay before a left rung falls
  static const double crumbleFallSec = 0.45; // crumble animation length
  static const int crumbleEveryN = 2; // only every Nth rung is crumbly

  // Danger / near-catch feel.
  static const double dangerGapPx = 150; // lava within this → danger glow ramps
  static const double nearCatchGapPx = 26; // lava this close → tension shake
  static const double nearCatchShakeGap = 0.55; // min seconds between tics

  // Bots time their hops with the reaction clock; they jump when the lava is
  // within a safety buffer of their rung, and occasionally fumble (errorRate).
  static const double botSafetyGapPx = 92; // base buffer before a bot hops
  static const double botBufferPerAccuracy = 1.1; // better bots keep more buffer

  // Elimination fling.
  static const double flingX = 130; // horizontal fling / figure scale
  static const double flingY = 200; // upward fling / figure scale

  // Scoring: survivors get a tower-height + survival bonus so they always
  // outrank the eliminated on score as well as placement.
  static const double survivePerSec = 2;
}

/// One climber: occupies a rung in its own tower and hops upward to outrun the
/// rising lava. Mutable, round-scoped value.
class _Climber {
  final int playerId;
  final Color color;
  final Rect column; // this player's vertical band
  final LaneSet rungs; // platform y-ladder (lane 0 = lowest)
  final double columnX; // horizontal track center
  final double figureScale;
  final double figureLift; // pelvis lift so feet plant on the rung top
  final Hopper hopper;
  final StickFigure figure;

  bool alive = true;
  double jumpHold = 0; // jump pose timer after a hop
  double landHold = 0; // squash timer after landing
  double standTimer = 0; // seconds standing on the current rung
  int topReached = 0; // highest rung touched (for ranking)
  double sinceShake = _Tuning.nearCatchShakeGap; // throttle near-catch shakes
  double lavaY = 0; // lava surface y for this column (rising = decreasing y)
  ReactionClock? clock;

  /// Per-rung crumble timer (seconds since it was triggered). Absent = solid.
  final Map<int, double> crumbling = <int, double>{};

  _Climber({
    required this.playerId,
    required this.color,
    required this.column,
    required this.rungs,
    required this.columnX,
    required this.figureScale,
    required this.figureLift,
    required this.hopper,
    required this.figure,
    this.clock,
  });

  /// Whether [lane] is a crumbly rung (every Nth, never the lowest or top).
  bool isCrumblyRung(int lane) =>
      lane > 0 && lane % _Tuning.crumbleEveryN == 0 && lane < rungs.count - 1;

  double rungYOf(int lane) => rungs.coordOf(lane);
  double visualRungY() => rungs.coordOfVisual(hopper.visualLane);
}

/// Chicken Jump — a vertical survival climb. Each player owns a neon tower of
/// platforms; one tap HOPS the climber up to the next rung. Lava floods up from
/// the bottom of every tower, accelerating so the round always converges. A
/// rung the climber leaves crumbles away, so you must keep climbing. Get caught
/// by the lava → ragdoll fling + KO and you're out. Last climber standing wins;
/// on the time limit the survivors are ranked by height reached.
///
/// Bots read the same rising lava and hop on a [BotProfile]-timed reaction
/// clock: better accuracy keeps a larger safety buffer, while [errorRate] makes
/// them occasionally hesitate and get caught — so they feel reactive, not
/// scripted.
class ChickenJump extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'chicken_jump',
        name: 'Chicken Jump',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  final List<_Climber> _climbers = <_Climber>[];
  final List<int> _eliminationOrder = <int>[]; // worst→best as they fall
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for ambient FX (never scaled)
  double _lavaSpeed = _Tuning.lavaRiseStart;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildTowers();
    begin();
  }

  // ── World build ─────────────────────────────────────────────────────────────

  void _buildTowers() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    final colW = arena.width / count;
    final lowestY = arena.height - _Tuning.bottomInset;
    final span = lowestY - _Tuning.topInset;
    final spacing = -(span / (_Tuning.platformCount - 1)); // negative = upward

    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final column = Rect.fromLTWH(colW * i, 0, colW, arena.height);
      final scale = _figureScaleFor(colW);
      final rungs = LaneSet(
        count: _Tuning.platformCount,
        start: lowestY,
        spacing: spacing,
        vertical: true,
      );
      final climber = _Climber(
        playerId: p.id,
        color: Color(p.colorArgb),
        column: column,
        rungs: rungs,
        columnX: column.center.dx,
        figureScale: scale,
        figureLift: _footReach(scale) + _Tuning.figureLiftExtra,
        hopper: Hopper(lane: 0, laneCount: _Tuning.platformCount),
        figure: StickFigure(
          proportions: StickProportions.hero.scaled(scale),
          style: _climberStyle(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.idle),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      );
      climber.lavaY = arena.height + _Tuning.lavaStartGap;
      _climbers.add(climber);
    }
  }

  /// Scale the climber to the column width so 1..4 towers all read clearly.
  double _figureScaleFor(double colW) {
    final t = ((colW - _Tuning.figureScaleLoColumn) /
            (_Tuning.figureScaleHiColumn - _Tuning.figureScaleLoColumn))
        .clamp(0.0, 1.0);
    return lerpD(_Tuning.figureScaleMin, _Tuning.figureScaleMax, t);
  }

  /// Pelvis→foot reach at rest (legs near-vertical), used to plant the feet.
  double _footReach(double scale) {
    final pr = StickProportions.hero.scaled(scale);
    return pr.thigh + pr.shin;
  }

  StickStyle _climberStyle(Color color) => StickStyle.hero.copyWith(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        rimAlpha: 0.26,
        shadowAlpha: 0.0, // we draw our own contact shadow
        smearAlpha: 0.26,
      );

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _jump(input.playerId);
  }

  void _jump(int id) {
    final c = _climberOf(id);
    if (c == null || !c.alive) return;
    final before = c.hopper.lane;
    c.hopper.hop(); // up one platform
    if (c.hopper.lane == before) return; // already at the top rung

    // The rung we leave begins to crumble if it is a crumbly type.
    if (c.isCrumblyRung(before)) {
      c.crumbling.putIfAbsent(before, () => 0);
    }
    c.standTimer = 0;
    c.topReached = math.max(c.topReached, c.hopper.lane);

    c.jumpHold = _Tuning.jumpHoldSec;
    if (!c.figure.isRagdoll) c.figure.setLoco(LocoState.jump);

    // Take-off dust at the rung we launched from.
    _juice.particles.burst(
      at: Offset(c.columnX, c.rungYOf(before)),
      count: 6,
      color: const Color(0xFFE8EEF6),
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.7,
      size: ChickenRenderer.dustSize * c.figureScale,
      gravity: 480,
      life: 0.3,
    );
  }

  _Climber? _climberOf(int id) {
    for (final c in _climbers) {
      if (c.playerId == id) return c;
    }
    return null;
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

    _lavaSpeed = _Tuning.lavaRiseStart + _Tuning.lavaAccel * _elapsed;

    _driveBots(dt);
    for (final c in _climbers) {
      _stepClimber(c, dt, sdt);
    }
    _checkEnd();
  }

  void _stepClimber(_Climber c, double dt, double sdt) {
    // Lava always rises (even for the dead, so the scene keeps escalating).
    c.lavaY -= _lavaSpeed * sdt;
    c.sinceShake += dt;

    if (!c.alive) {
      c.figure.update(dt);
      _tickCrumbles(c, dt);
      return;
    }

    c.hopper.update(sdt, speed: _Tuning.hopAnimSpeed);
    _tickPose(c, dt);
    _tickCrumbles(c, dt);

    // Standing too long on a crumbly rung starts it crumbling under you.
    if (c.hopper.settled) {
      c.standTimer += dt;
      if (c.isCrumblyRung(c.hopper.lane) &&
          c.standTimer >= _Tuning.crumbleAfterSec) {
        c.crumbling.putIfAbsent(c.hopper.lane, () => 0);
      }
    }

    c.figure.update(dt);
    _checkLava(c);
  }

  void _tickPose(_Climber c, double dt) {
    if (c.jumpHold > 0) {
      c.jumpHold -= dt;
      if (c.jumpHold <= 0 && c.hopper.settled) {
        // Land: brief squash then idle.
        c.landHold = _Tuning.landHoldSec;
        if (!c.figure.isRagdoll) c.figure.land();
        _landPuff(c);
      }
    } else if (c.landHold > 0) {
      c.landHold -= dt;
      if (c.landHold <= 0 && !c.figure.isRagdoll) {
        c.figure.setLoco(LocoState.idle);
      }
    }
  }

  void _landPuff(_Climber c) {
    _juice.particles.burst(
      at: Offset(c.columnX, c.visualRungY()),
      count: 5,
      color: const Color(0xFFD7E0EC),
      speed: 120,
      baseAngle: -math.pi / 2,
      spread: math.pi,
      size: ChickenRenderer.dustSize * c.figureScale * 0.8,
      gravity: 360,
      life: 0.26,
    );
  }

  /// Advance per-rung crumble timers; drop a rung once fully crumbled.
  ///
  /// A fully-crumbled rung must stay gone: we cap its timer at [total] (instead
  /// of removing the entry) so [_crumbleProgress] keeps returning 1 and the rung
  /// stays skipped in render. Removing it would make the entry absent, which
  /// reads as "solid" again and resurrects the dropped platform.
  void _tickCrumbles(_Climber c, double dt) {
    if (c.crumbling.isEmpty) return;
    final total = _Tuning.crumbleAfterSec + _Tuning.crumbleFallSec;
    c.crumbling.updateAll((lane, t) => math.min(total, t + dt));
  }

  void _checkLava(_Climber c) {
    final rungY = c.visualRungY();
    final gap = c.lavaY - rungY; // positive while the lava is still below

    // Tension: a near-catch nudges a light shake (throttled) for drama.
    if (gap <= _Tuning.nearCatchGapPx &&
        gap > 0 &&
        c.sinceShake >= _Tuning.nearCatchShakeGap) {
      _juice.shake.light();
      c.sinceShake = 0;
    }

    // Caught once the lava surface reaches the logical rung the climber owns.
    if (c.lavaY <= c.rungYOf(c.hopper.lane)) {
      _eliminate(c);
    }
  }

  // ── Bots ─────────────────────────────────────────────────────────────────────

  /// Bots hop on their reaction clock when the lava nears their rung. Better
  /// accuracy keeps a larger safety buffer; [errorRate] makes them hesitate.
  void _driveBots(double dt) {
    for (final c in _climbers) {
      final clock = c.clock;
      if (clock == null || !c.alive) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldJump(c)) {
        _jump(c.playerId);
      }
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  bool _botShouldJump(_Climber c) {
    final rungY = c.rungYOf(c.hopper.lane);
    final gap = c.lavaY - rungY; // positive while the lava is still below
    final buffer = _Tuning.botSafetyGapPx *
        (0.45 + _Tuning.botBufferPerAccuracy * ctx.botProfile.accuracy);
    // Also bail off a rung that is actively crumbling beneath the bot.
    final crumblingHere = c.crumbling.containsKey(c.hopper.lane);
    if (gap <= buffer || crumblingHere) {
      return !ctx.rng.chance(ctx.botProfile.errorRate);
    }
    return false;
  }

  // ── Elimination / outcome ────────────────────────────────────────────────────

  void _eliminate(_Climber c) {
    c.alive = false;
    _eliminationOrder.add(c.playerId);
    final rungY = c.visualRungY();
    final at = Offset(c.columnX, rungY);
    final away = ctx.rng.sign();
    c.figure.enterRagdoll(
      Offset(c.columnX, rungY - c.figureLift),
      rungY,
      Offset(away * _Tuning.flingX * c.figureScale,
          -_Tuning.flingY * c.figureScale),
    );
    _juice.ko(at, c.color);
    _juice.popup(Offset(c.columnX, rungY - 34), 'OUT!', c.color, size: 30);
  }

  void _checkEnd() {
    final alive = _climbers.where((c) => c.alive).toList();
    final timeUp = _elapsed >= _Tuning.timeLimit;
    if (alive.length > 1 && !timeUp) return;
    _finish(alive);
  }

  void _finish(List<_Climber> alive) {
    // Survival bonus first so a survivor always outranks the eliminated on
    // score as well as on placement.
    final surviveBonus =
        (_Tuning.platformCount + _Tuning.timeLimit * _Tuning.survivePerSec)
            .round();
    for (final c in _climbers) {
      setScore(c.playerId, c.topReached + (c.alive ? surviveBonus : 0));
    }
    // Survivors (highest rung first) rank above the eliminated; eliminated are
    // ordered most-recent-first (they lasted longest).
    final survivors = alive.toList()
      ..sort((a, b) => b.topReached.compareTo(a.topReached));
    final ranking = <int>[
      for (final c in survivors) c.playerId,
      ..._eliminationOrder.reversed,
    ];
    _juice.confetti(ctx.arena);
    finishByOrder(_dedupe(ranking));
  }

  /// Ensure every player id appears exactly once, preserving [order] first.
  List<int> _dedupe(List<int> order) {
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

  // ── Render ───────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    ChickenRenderer.drawBackground(canvas, size, _escalation());

    for (final c in _climbers) {
      _drawTower(canvas, c);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  /// 0..1 escalation, used for ambient heat — ramps with the lava speed.
  double _escalation() {
    final span = _Tuning.lavaAccel * _Tuning.timeLimit;
    if (span <= 0) return 0;
    return ((_lavaSpeed - _Tuning.lavaRiseStart) / span).clamp(0.0, 1.0);
  }

  void _drawTower(Canvas canvas, _Climber c) {
    final danger = _dangerLevel(c);

    ChickenRenderer.drawColumnBackdrop(
      canvas,
      c.column,
      c.color,
      _parallax(c),
      danger,
      c.alive,
    );

    // Platforms (skip a fully-dropped crumbled rung; pass crumble progress).
    for (var lane = 0; lane < c.rungs.count; lane++) {
      final crumble = _crumbleProgress(c, lane);
      if (crumble >= 1) continue; // gone
      ChickenRenderer.drawPlatform(
        canvas,
        Offset(c.columnX, c.rungYOf(lane)),
        c.column.width,
        c.color,
        crumbly: c.isCrumblyRung(lane),
        crumble: crumble,
        lit: lane == c.hopper.lane && c.alive,
      );
    }

    // Lava with a bubbling surface + embers, plus a danger glow as it nears.
    ChickenRenderer.drawLava(canvas, c.column, c.lavaY, _animClock, danger);

    // Climber contact shadow + figure.
    final rungY = c.visualRungY();
    if (!c.figure.isRagdoll) {
      ChickenRenderer.drawContactShadow(
        canvas,
        Offset(c.columnX, rungY),
        c.column.width * 0.22,
        c.alive,
      );
    }
    ChickenRenderer.drawClimber(
      canvas,
      c.figure,
      Offset(c.columnX, rungY - c.figureLift),
    );

    // Altitude indicator + player pip in the column corner.
    ChickenRenderer.drawAltitude(
      canvas,
      c.column,
      _heightFraction(c),
      c.color,
      c.alive,
    );
  }

  /// Parallax phase for a column: how far the climber has ascended (px), so the
  /// cave background drifts down as the climber rises.
  double _parallax(_Climber c) {
    final lowest = c.rungYOf(0);
    return (lowest - c.visualRungY()).clamp(0.0, c.column.height);
  }

  /// 0..1 how close the lava is to the climber's rung — drives the danger glow.
  double _dangerLevel(_Climber c) {
    if (!c.alive) return 0;
    final gap = c.lavaY - c.visualRungY();
    if (gap <= 0) return 1;
    return (1.0 - (gap / _Tuning.dangerGapPx)).clamp(0.0, 1.0);
  }

  /// 0..1 fraction of the tower climbed (for the altitude bar).
  double _heightFraction(_Climber c) {
    final maxLane = (c.rungs.count - 1).toDouble();
    if (maxLane <= 0) return 0;
    return (c.hopper.visualLane / maxLane).clamp(0.0, 1.0);
  }

  /// Crumble progress for [lane] in 0..1 (0 = solid, 1 = gone).
  double _crumbleProgress(_Climber c, int lane) {
    final t = c.crumbling[lane];
    if (t == null) return 0;
    if (t <= _Tuning.crumbleAfterSec) return 0; // still solid, just "armed"
    final fall = (t - _Tuning.crumbleAfterSec) / _Tuning.crumbleFallSec;
    return fall.clamp(0.0, 1.0);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}
