import 'dart:math' as math;
import 'dart:ui';

import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../engine/helpers/area_fill_grid.dart';
import '../../art/fx/juice.dart';

/// A player's paint reticle that drifts and bounces inside the unit square.
/// Position and velocity are in normalized 0..1 arena space.
class _Reticle {
  final int playerId;
  final Color color;
  Offset pos;
  Offset vel;
  final ReactionClock? clock;

  _Reticle({
    required this.playerId,
    required this.color,
    required this.pos,
    required this.vel,
    this.clock,
  });

  /// Move and reflect off the four walls. [dt] is real seconds.
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
}

/// Paint Splash — coverage battle on an [AreaFillGrid].
///
/// Each player owns a reticle that bounces around the arena. Tapping splats a
/// circle of paint at the reticle (last writer wins, so you can paint over
/// rivals). The player covering the most cells when [_timeLimit] elapses wins.
/// Score equals owned-cell count, resolved via [finishByScore].
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

  static const int _cols = 32;
  static const int _rows = 40;
  static const double _timeLimit = 30;
  static const double _splatRadius = 0.085; // normalized grid radius per splat
  static const double _baseSpeed = 0.45; // reticle speed (units/sec)

  late Juice _juice;
  late AreaFillGrid _grid;
  final List<_Reticle> _reticles = [];
  double _elapsed = 0;
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _grid = AreaFillGrid(cols: _cols, rows: _rows);
    _spawnReticles();
    begin();
  }

  void _spawnReticles() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Spread starts across the arena; randomized drift direction.
      final start = Offset(
        ctx.rng.range(0.15, 0.85),
        (i + 0.5) / count,
      );
      final angle = ctx.rng.range(0, math.pi * 2);
      final vel = Offset(math.cos(angle), math.sin(angle)) * _baseSpeed;
      _reticles.add(_Reticle(
        playerId: p.id,
        color: Color(p.colorArgb),
        pos: start,
        vel: vel,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _splatFor(input.playerId);
  }

  /// Paint at the reticle owned by [id] and flash a hit there.
  void _splatFor(int id) {
    for (final r in _reticles) {
      if (r.playerId == id) {
        _grid.paintCircle(id, r.pos, _splatRadius);
        _juice.hit(_toPixels(r.pos), r.color, sparks: 6);
        return;
      }
    }
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    for (final r in _reticles) {
      r.advance(sdt);
    }
    _driveBots(sdt);

    if (_elapsed >= _timeLimit) _finish();
  }

  /// Bots splat on their reaction cadence, painting wherever the reticle is.
  /// An occasional error wastes a splat (paints a bit off-target).
  void _driveBots(double dt) {
    for (final r in _reticles) {
      if (r.clock == null) continue;
      if (!r.clock!.tick(dt)) continue;
      r.clock!.arm(ctx.botProfile, ctx.rng);

      var target = r.pos;
      if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        target = Offset(
          (r.pos.dx + ctx.rng.jitter(0.12)).clamp(0.0, 1.0),
          (r.pos.dy + ctx.rng.jitter(0.12)).clamp(0.0, 1.0),
        );
      }
      _grid.paintCircle(r.playerId, target, _splatRadius);
      _juice.hit(_toPixels(target), r.color, sparks: 4);
    }
  }

  /// Score = covered cell count, then rank highest-first.
  void _finish() {
    if (status == MiniGameStatus.finished) return;
    for (final p in ctx.players) {
      setScore(p.id, _grid.coverageOf(p.id));
    }
    finishByScore();
  }

  // ---- Rendering ------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawCells(canvas, size);
    _drawBorder(canvas, size);
    for (final r in _reticles) {
      _drawReticle(canvas, r);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawCells(Canvas canvas, Size size) {
    final cw = size.width / _cols;
    final ch = size.height / _rows;
    final paint = Paint();
    final colorById = {
      for (final p in ctx.players) p.id: Color(p.colorArgb),
    };
    _grid.forEachCell((col, row, owner) {
      if (owner == kEmptyCell) return;
      paint.color = (colorById[owner] ?? const Color(0xFF888888))
          .withValues(alpha: 0.85);
      // Slight overdraw avoids hairline gaps between cells.
      canvas.drawRect(
          Rect.fromLTWH(col * cw, row * ch, cw + 0.5, ch + 0.5), paint);
    });
  }

  void _drawBorder(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33FFFFFF);
    canvas.drawRect(Offset.zero & size, border);
  }

  void _drawReticle(Canvas canvas, _Reticle r) {
    final c = _toPixels(r.pos);
    final radius = math.min(_lastSize.width, _lastSize.height) * 0.04;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = r.color;
    canvas.drawCircle(c, radius, ring);
    final dot = Paint()..color = r.color;
    canvas.drawCircle(c, radius * 0.3, dot);
  }

  Offset _toPixels(Offset norm) =>
      Offset(norm.dx * _lastSize.width, norm.dy * _lastSize.height);
}
