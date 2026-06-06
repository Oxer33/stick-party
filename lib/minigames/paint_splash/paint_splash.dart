import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/fx/particles.dart';
import '../../core/constants.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/area_fill_grid.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'paint_render.dart';

/// Numeric tuning — no magic numbers inline. Times in seconds; positions and
/// speeds are in normalized 0..1 arena space unless noted.
class _Tuning {
  static const int cols = 30;
  static const int rows = 38;
  static const double timeLimit = 30;

  // Reticle motion.
  static const double baseSpeed = 0.46; // units/sec drift
  static const double speedJitter = 0.10; // ± spawn speed variation

  // Splat sizing. The base radius grows when the reticle is moving slowly (a
  // steady hand lays down more paint) and with the rapid-tap combo.
  static const double splatRadiusBase = 0.072;
  static const double slowSpeedRef = 0.46; // speed at/above → no slow bonus
  static const double slowSplatBonus = 0.6; // +60% radius at a dead stop
  static const double comboSplatBonus = 0.10; // +radius per combo step
  static const double splatRadiusMax = 0.16; // hard cap so it stays readable

  // Combo: splats chained within the window grow the multiplier; it decays.
  static const double comboWindowSec = 0.6; // chain within this to keep combo
  static const int comboMax = 6; // cap on the combo step
  static const double comboFlashSec = 0.18; // recent-splat reticle flash

  // Charge readout weighting (slow-aim vs combo) for the reticle ring.
  static const double chargeSlowWeight = 0.55;
  static const double chargeComboWeight = 0.45;

  // Bot accuracy: an off-target splat is jittered by up to this (norm units),
  // scaled down by accuracy so better bots place paint where they aim.
  static const double botAimJitter = 0.14;

  // Visual stamp budget: only the most recent stamps are drawn crisply on top
  // of the baked coverage tint, which protects render cost in long games.
  static const int maxStamps = 64;

  // Particle feel.
  static const int dropletCountBase = 10;
  static const int dropletPerCombo = 2;
  static const double dropletSpeed = 320; // px/s
  static const double dropletGravity = 520;
  static const double dropletLife = 0.55;
  static const double dropletSizeBase = 6;
  static const double dropletSizePerRadius = 30; // size add / normalized radius

  // Stamp sheen dry-out time.
  static const double sheenDrySec = 1.2;
}

/// A player's paint reticle that drifts and bounces inside the unit square.
/// Position and velocity are in normalized 0..1 arena space. Mutable,
/// round-scoped value.
class _Reticle {
  final int playerId;
  final Color color;
  final bool isRoller; // visual tool variety (odd ids use a roller)
  Offset pos;
  Offset vel;
  final ReactionClock? clock;

  int combo = 0; // current chain step (0 = none)
  double sinceSplat = 1e9; // seconds since the last splat (for chaining)
  double flash = 0; // recent-splat flash timer (visual)

  _Reticle({
    required this.playerId,
    required this.color,
    required this.isRoller,
    required this.pos,
    required this.vel,
    this.clock,
  });

  /// 0..1 charge: how big the next splat will be from slow-aim + combo.
  double get charge {
    final speed = vel.distance;
    final slow = (1.0 - (speed / _Tuning.slowSpeedRef)).clamp(0.0, 1.0);
    final comboPart = (combo / _Tuning.comboMax).clamp(0.0, 1.0);
    return (_Tuning.chargeSlowWeight * slow +
            _Tuning.chargeComboWeight * comboPart)
        .clamp(0.0, 1.0);
  }

  /// Move and reflect off the four walls. [dt] is sim seconds.
  void advance(double dt) {
    var nx = pos.dx + vel.dx * dt;
    var ny = pos.dy + vel.dy * dt;
    var vx = vel.dx;
    var vy = vel.dy;
    if (nx < 0) {
      nx = -nx;
      vx = -vx;
    } else if (nx > 1) {
      nx = 2 - nx;
      vx = -vx;
    }
    if (ny < 0) {
      ny = -ny;
      vy = -vy;
    } else if (ny > 1) {
      ny = 2 - ny;
      vy = -vy;
    }
    pos = Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
    vel = Offset(vx, vy);
  }

  /// Advance timers (combo decay + flash). [dt] is real seconds.
  void tickTimers(double dt) {
    sinceSplat += dt;
    if (sinceSplat > _Tuning.comboWindowSec && combo > 0) combo = 0;
    if (flash > 0) flash = math.max(0, flash - dt);
  }
}

/// A drawn paint stamp recorded when a splat lands, so the renderer can paint a
/// crisp irregular blob (with drips/droplets) on top of the baked coverage
/// tint. Round-scoped; capped to [_Tuning.maxStamps].
class _Stamp {
  final Offset pos; // normalized 0..1
  final double radius; // normalized
  final Color color;
  final int seed; // deterministic visual variation
  double age = 0; // seconds since it landed (drives sheen/droplet fade)

  _Stamp({
    required this.pos,
    required this.radius,
    required this.color,
    required this.seed,
  });
}

/// Paint Splash — a splatter-paint turf war on an [AreaFillGrid].
///
/// Each player owns a reticle that bounces around the arena. One tap fires a
/// SPLAT of paint at the reticle (last writer wins, so you paint right over a
/// rival's territory). The player covering the most cells when
/// [_Tuning.timeLimit] elapses wins; score is the owned-cell count, resolved
/// via [finishByScore].
///
/// Depth (still one-touch):
///  * A steady hand pays off: the slower the reticle is moving, the bigger the
///    splat — time your tap as it grazes a wall.
///  * Rapid splats build a combo that grows the splat radius and the droplet
///    burst, then decays if you stall.
///  * Contested cells are overwritten on contact (last writer wins), so a late
///    splat over a leader's turf swings the score.
///
/// Bots splat on a [ReactionClock]; their [BotProfile] accuracy decides how
/// close to the reticle the paint actually lands and [errorRate] makes them
/// occasionally fling a wasted, off-target blob.
class PaintSplash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'paint_splash',
        name: 'Paint Splash',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  late AreaFillGrid _grid;
  final List<_Reticle> _reticles = <_Reticle>[];
  final List<_Stamp> _stamps = <_Stamp>[];
  double _elapsed = 0;
  int _splatSeq = 0; // monotonically increasing seed source for stamps
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _grid = AreaFillGrid(cols: _Tuning.cols, rows: _Tuning.rows);
    _spawnReticles();
    begin();
  }

  void _spawnReticles() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Spread starts across the arena; randomized drift direction + speed.
      final start = Offset(ctx.rng.range(0.15, 0.85), (i + 0.5) / count);
      final angle = ctx.rng.range(0, math.pi * 2);
      final speed = _Tuning.baseSpeed + ctx.rng.jitter(_Tuning.speedJitter);
      final vel = Offset(math.cos(angle), math.sin(angle)) * speed;
      _reticles.add(_Reticle(
        playerId: p.id,
        color: Color(p.colorArgb),
        isRoller: p.id.isOdd,
        pos: start,
        vel: vel,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    final r = _reticleOf(input.playerId);
    if (r != null) _splat(r, r.pos);
  }

  /// Lay paint for [r] centered at [at] (normalized). Updates the combo, paints
  /// the grid (last writer wins), records a visual stamp and fires juice scaled
  /// by the splat size + combo.
  void _splat(_Reticle r, Offset at) {
    if (!at.dx.isFinite || !at.dy.isFinite) return;

    // Chained-within-window splats grow the combo (else it has already reset).
    if (r.sinceSplat <= _Tuning.comboWindowSec) {
      r.combo = math.min(_Tuning.comboMax, r.combo + 1);
    }
    r.sinceSplat = 0;
    r.flash = _Tuning.comboFlashSec;

    final radius = _splatRadius(r);
    _grid.paintCircle(r.playerId, at, radius);
    _recordStamp(at, radius, r.color);
    _burstDroplets(at, radius, r.color, r.combo);
  }

  /// Splat radius from the base size, the slow-aim bonus and the combo, capped.
  double _splatRadius(_Reticle r) {
    final speed = r.vel.distance;
    final slow = (1.0 - (speed / _Tuning.slowSpeedRef)).clamp(0.0, 1.0);
    final radius = _Tuning.splatRadiusBase *
        (1.0 +
            _Tuning.slowSplatBonus * slow +
            _Tuning.comboSplatBonus * r.combo);
    return radius.clamp(_Tuning.splatRadiusBase, _Tuning.splatRadiusMax);
  }

  void _recordStamp(Offset at, double radius, Color color) {
    _stamps.add(_Stamp(
      pos: at,
      radius: radius,
      color: color,
      seed: _splatSeq++,
    ));
    // Keep only the most recent stamps drawn crisply (the rest live on as the
    // baked coverage tint), protecting render cost in long games.
    if (_stamps.length > _Tuning.maxStamps) {
      _stamps.removeRange(0, _stamps.length - _Tuning.maxStamps);
    }
  }

  /// A burst of paint droplets + impact feel. Bigger combos throw more droplets
  /// and a touch more shake/hit-stop.
  void _burstDroplets(Offset at, double radius, Color color, int combo) {
    final px = _toPixels(at);
    final count = _Tuning.dropletCountBase + combo * _Tuning.dropletPerCombo;
    _juice.particles.burst(
      at: px,
      count: count,
      color: color,
      speed: _Tuning.dropletSpeed *
          (0.8 + 0.2 * (radius / _Tuning.splatRadiusMax)),
      size: _Tuning.dropletSizeBase + radius * _Tuning.dropletSizePerRadius,
      gravity: _Tuning.dropletGravity,
      life: _Tuning.dropletLife,
      shape: ParticleShape.circle,
    );
    _juice.hitStop.trigger(Feel.hitStopDefaultSec);
    if (combo >= _Tuning.comboMax - 1) {
      _juice.shake.medium();
    } else {
      _juice.shake.light();
    }
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    for (final r in _reticles) {
      r.advance(sdt);
      r.tickTimers(dt);
    }
    for (final s in _stamps) {
      s.age += dt;
    }
    _driveBots(sdt);

    if (_elapsed >= _Tuning.timeLimit) _finish();
  }

  /// Bots splat on their reaction cadence, painting at the reticle. An
  /// occasional deliberate error flings the paint off-target (wasted splat);
  /// otherwise the placement tightens toward the reticle as accuracy rises.
  void _driveBots(double dt) {
    for (final r in _reticles) {
      final clock = r.clock;
      if (clock == null) continue;
      if (!clock.tick(dt)) continue;
      clock.arm(ctx.botProfile, ctx.rng);

      var target = r.pos;
      // Aim error shrinks with accuracy; a deliberate mistake adds a big miss.
      final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
      var jitter = _Tuning.botAimJitter * (1.0 - acc);
      if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        jitter += _Tuning.botAimJitter;
      }
      if (jitter > 0) {
        target = Offset(
          (r.pos.dx + ctx.rng.jitter(jitter)).clamp(0.0, 1.0),
          (r.pos.dy + ctx.rng.jitter(jitter)).clamp(0.0, 1.0),
        );
      }
      _splat(r, target);
    }
  }

  /// Score = covered cell count, then rank highest-first.
  void _finish() {
    if (status == MiniGameStatus.finished) return;
    for (final p in ctx.players) {
      setScore(p.id, _grid.coverageOf(p.id));
    }
    _juice.confetti(_lastSize);
    finishByScore();
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    PaintRenderer.drawBackground(canvas, size);
    _drawCoverage(canvas, size);
    _drawStamps(canvas, size);
    _drawReticles(canvas, size);
    _drawCoverageBars(canvas, size);

    _juice.render(canvas);
    canvas.restore();
  }

  /// Baked coverage under-layer (a soft tint per owned cell) so total territory
  /// reads clearly behind the crisp stamps.
  void _drawCoverage(Canvas canvas, Size size) {
    final colorById = <int, Color>{
      for (final p in ctx.players) p.id: Color(p.colorArgb),
    };
    PaintRenderer.drawCoverageTint(
      canvas,
      size,
      _Tuning.cols,
      _Tuning.rows,
      (col, row) {
        final owner = _grid.ownerAt(col, row);
        if (owner == kEmptyCell) return null;
        return colorById[owner];
      },
    );
  }

  /// The recent crisp blobs on top, oldest first so newer paint overlaps older.
  void _drawStamps(Canvas canvas, Size size) {
    if (_stamps.isEmpty) return;
    final minSide = math.min(size.width, size.height);
    for (final s in _stamps) {
      final center = _toPixelsIn(s.pos, size);
      final radiusPx = s.radius * minSide;
      // Sheen fades over ~sheenDrySec; droplet ring fades over the round.
      final wet = (1.0 - s.age / _Tuning.sheenDrySec).clamp(0.0, 1.0);
      final age01 = (s.age / _Tuning.timeLimit).clamp(0.0, 1.0);
      PaintRenderer.drawSplat(
        canvas,
        center,
        radiusPx,
        s.color,
        seed: s.seed,
        wet: wet,
        age01: age01,
      );
    }
  }

  void _drawReticles(Canvas canvas, Size size) {
    for (final r in _reticles) {
      final pulse = r.flash <= 0
          ? 0.0
          : (r.flash / _Tuning.comboFlashSec).clamp(0.0, 1.0);
      PaintRenderer.drawReticle(
        canvas,
        size,
        _toPixelsIn(r.pos, size),
        r.color,
        charge: r.charge,
        isRoller: r.isRoller,
        pulse: pulse,
      );
    }
  }

  /// Live coverage % bars; the current leader's bar glows.
  void _drawCoverageBars(Canvas canvas, Size size) {
    if (_reticles.isEmpty) return;
    var leaderId = _reticles.first.playerId;
    var leaderFrac = -1.0;
    for (final r in _reticles) {
      final f = _grid.fractionOf(r.playerId);
      if (f > leaderFrac) {
        leaderFrac = f;
        leaderId = r.playerId;
      }
    }
    final entries = <({Color color, double fraction, bool isLeader})>[
      for (final r in _reticles)
        (
          color: r.color,
          fraction: _grid.fractionOf(r.playerId),
          isLeader: r.playerId == leaderId && leaderFrac > 0,
        ),
    ];
    PaintRenderer.drawCoverageBars(canvas, size, entries);
  }

  // ── Small helpers ────────────────────────────────────────────────────────────

  _Reticle? _reticleOf(int id) {
    for (final r in _reticles) {
      if (r.playerId == id) return r;
    }
    return null;
  }

  Offset _toPixels(Offset norm) => _toPixelsIn(norm, _lastSize);

  Offset _toPixelsIn(Offset norm, Size size) =>
      Offset(norm.dx * size.width, norm.dy * size.height);
}
