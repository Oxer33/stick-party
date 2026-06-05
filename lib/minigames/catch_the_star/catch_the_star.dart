import 'dart:math' as math;
import 'dart:ui';

import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';

/// A player's fixed catcher anchored near their screen zone.
class _Catcher {
  final int playerId;
  final Color color;
  final Offset pos; // normalized 0..1 anchor
  final ReactionClock? clock;

  _Catcher({
    required this.playerId,
    required this.color,
    required this.pos,
    this.clock,
  });
}

/// Catch the Star — a single star wanders the arena; whoever snatches it when
/// it drifts within range of their catcher scores.
///
/// The star steers toward a roaming waypoint, re-picked every [_retargetSec]
/// (or on arrival). A tap snatches: if the star is within [_snatchRadius] of
/// that player's catcher, they score +1 (with a "+1" popup) and the star
/// respawns at a fresh point far from all catchers. Most catches at
/// [_timeLimit] wins via [finishByScore].
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

  static const double _timeLimit = 30;
  static const double _snatchRadius = 0.16; // normalized snatch distance
  static const double _starSpeed = 0.55; // units/sec
  static const double _retargetSec = 1.1;
  static const double _arriveDist = 0.04;

  late Juice _juice;
  final List<_Catcher> _catchers = [];
  Offset _star = const Offset(0.5, 0.5);
  Offset _target = const Offset(0.5, 0.5);
  double _elapsed = 0;
  double _retargetAcc = 0;
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _spawnCatchers();
    _star = _randomPoint();
    _target = _randomPoint();
    begin();
  }

  void _spawnCatchers() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      _catchers.add(_Catcher(
        playerId: p.id,
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

  Offset _randomPoint() =>
      Offset(ctx.rng.range(0.1, 0.9), ctx.rng.range(0.1, 0.9));

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _trySnatch(input.playerId);
  }

  /// Award a catch if the star is in range of [id]'s catcher.
  bool _trySnatch(int id) {
    for (final c in _catchers) {
      if (c.playerId != id) continue;
      if ((_star - c.pos).distance <= _snatchRadius) {
        addScore(id, 1);
        _juice.popup(_toPixels(_star), '+1', c.color, size: 30);
        _juice.hit(_toPixels(_star), c.color, sparks: 10);
        _star = _farRespawn();
        _target = _randomPoint();
        return true;
      }
      return false;
    }
    return false;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _moveStar(sdt);
    _driveBots(sdt);

    if (_elapsed >= _timeLimit) _finish();
  }

  /// Steer the star toward its waypoint; pick a new one on arrival or timeout.
  void _moveStar(double dt) {
    _retargetAcc += dt;
    final toTarget = _target - _star;
    if (toTarget.distance <= _arriveDist || _retargetAcc >= _retargetSec) {
      _target = _randomPoint();
      _retargetAcc = 0;
    }
    final dir =
        toTarget.distance < 1e-6 ? Offset.zero : toTarget / toTarget.distance;
    final next = _star + dir * (_starSpeed * dt);
    _star = Offset(next.dx.clamp(0.0, 1.0), next.dy.clamp(0.0, 1.0));
  }

  /// Bots snatch when the star is near their catcher, gated by reaction time
  /// and accuracy (a low-accuracy bot may fumble an in-range snatch).
  void _driveBots(double dt) {
    for (final c in _catchers) {
      if (c.clock == null) continue;
      final inRange = (_star - c.pos).distance <= _snatchRadius;
      if (!inRange) continue;
      if (!c.clock!.tick(dt)) continue;
      c.clock!.arm(ctx.botProfile, ctx.rng);
      if (ctx.rng.chance(ctx.botProfile.accuracy)) {
        _trySnatch(c.playerId);
      }
    }
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

  // ---- Rendering ------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawBorder(canvas, size);
    for (final c in _catchers) {
      _drawCatcher(canvas, c);
    }
    _drawStar(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawBorder(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33FFFFFF);
    canvas.drawRect(Offset.zero & size, border);
  }

  void _drawCatcher(Canvas canvas, _Catcher c) {
    final center = _toPixels(c.pos);
    final reach = _snatchRadius * math.min(_lastSize.width, _lastSize.height);
    // Snatch range ring (faint) + solid catcher dot.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = c.color.withValues(alpha: 0.35);
    canvas.drawCircle(center, reach, ring);
    final dot = Paint()..color = c.color;
    canvas.drawCircle(center, reach * 0.22, dot);
  }

  void _drawStar(Canvas canvas) {
    final center = _toPixels(_star);
    final r = math.min(_lastSize.width, _lastSize.height) * 0.045;
    final paint = Paint()..color = const Color(0xFFFFF1A8);
    canvas.drawPath(_starPath(center, r, r * 0.45, 5), paint);
    canvas.drawCircle(
        center, r * 0.28, Paint()..color = const Color(0xFFFFFFFF));
  }

  /// Build an [points]-point star path with the given outer/inner radii.
  Path _starPath(Offset c, double outer, double inner, int points) {
    final path = Path();
    final step = math.pi / points;
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * step;
      final p = Offset(c.dx + math.cos(a) * radius, c.dy + math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  Offset _toPixels(Offset norm) =>
      Offset(norm.dx * _lastSize.width, norm.dy * _lastSize.height);
}
