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

/// Sumo Smash: every player is a puck on a circular ring. Tapping dashes you
/// toward the centroid of the remaining opponents to shove them off. The last
/// puck still on the ring wins; if time runs out, the puck closest to the
/// center wins.
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

  // ── Tuning (no magic numbers inline) ───────────────────────────────────────
  static const double _timeLimit = 35;
  static const double _ringRadiusFactor = 0.42;
  static const double _bodyRadiusFactor = 0.045;
  static const double _ringFriction = 0.965;
  static const double _ringRestitution = 0.92;
  static const double _dashPerSecond = 4.0; // impulse magnitude ≈ ring*4 /sec
  static const double _dashSelfPushback = 0.12; // recoil away from target
  static const double _figureScale = 0.95;
  static const double _ragdollFlingScale = 0.4;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;

  /// Stick avatar per player id (purely cosmetic, follows its body).
  final Map<int, StickFigure> _figures = <int, StickFigure>{};

  /// Bot reaction clocks per bot player id.
  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};

  /// Players eliminated, in the order they fell off (first out → first here).
  final List<int> _eliminationOrder = <int>[];

  /// Ids already turned into ragdolls so we only fling once.
  final Set<int> _ragdolled = <int>{};

  late Size _size;
  late Offset _center;
  late double _ringRadius;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _center = Offset(_size.width / 2, _size.height / 2);
    final minSide = math.min(_size.width, _size.height);
    _ringRadius = minSide * _ringRadiusFactor;
    final bodyRadius = minSide * _bodyRadiusFactor;

    _arena = PushArena(
      center: _center,
      ringRadius: _ringRadius,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies(bodyRadius);
    begin();
  }

  /// Place one puck per player evenly on a smaller spawn circle.
  void _buildBodies(double bodyRadius) {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * 0.55;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final angle = (i / count) * math.pi * 2 - math.pi / 2;
      final pos = _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _arena.add(Body(id: p.id, pos: pos, radius: bodyRadius));

      final facing = pos.dx <= _center.dx ? 1.0 : -1.0;
      _figures[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_figureScale),
        style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)),
        facing: facing,
      )..setLoco(LocoState.idle);

      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _act(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(dt);
    _arena.update(sdt);

    _syncFigures(sdt);
    _detectEliminations();
    _resolveOutcome();
  }

  /// Each bot dashes toward its nearest opponent on its reaction clock.
  void _driveBots(double dt) {
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!_isAlive(id)) continue;
      if (entry.value.tick(dt)) {
        _act(id);
        entry.value.arm(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Dash impulse: toward the centroid of the OTHER alive players.
  void _act(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null || !self.alive) return;

    final target = _opponentCentroid(playerId);
    if (target == null) return;

    final dir = _normalize(target - self.pos);
    if (dir == Offset.zero) return;

    final magnitude = _ringRadius * _dashPerSecond;
    _arena.impulse(playerId, dir * magnitude);
    // Tiny recoil so a clean shove also costs the attacker some footing.
    _arena.impulse(playerId, -dir * magnitude * _dashSelfPushback);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }
    _juice.hit(self.pos, Color(_colorOf(playerId)), sparks: 5);
  }

  /// Centroid of all alive opponents of [playerId], or null if none remain.
  Offset? _opponentCentroid(int playerId) {
    var sum = Offset.zero;
    var n = 0;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      sum += b.pos;
      n++;
    }
    if (n == 0) return null;
    return sum / n.toDouble();
  }

  /// Advance avatars and keep their loco state in sync with puck speed.
  void _syncFigures(double dt) {
    const runSpeed = 40.0;
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null && body.alive && !fig.isRagdoll) {
        fig.setLoco(body.vel.distance > runSpeed ? LocoState.run : LocoState.idle);
      }
      fig.update(dt);
    }
  }

  /// Record newly fallen pucks, KO juice + ragdoll fling, once each.
  void _detectEliminations() {
    for (final b in _arena.bodies) {
      if (b.alive || _ragdolled.contains(b.id)) continue;
      _ragdolled.add(b.id);
      _eliminationOrder.add(b.id);

      final color = Color(_colorOf(b.id));
      _juice.ko(b.pos, color);

      final fig = _figures[b.id];
      if (fig != null) {
        final fling = _normalize(b.pos - _center) * _ringRadius * _ragdollFlingScale;
        final groundY = b.pos.dy + b.radius * 2;
        fig.enterRagdoll(_figureRoot(b), groundY, fling);
      }
    }
  }

  /// Finish when one (or zero) puck remains, or when time expires.
  void _resolveOutcome() {
    final alive = _arena.aliveBodies;
    if (alive.length <= 1) {
      _finishBySurvival(alive);
      return;
    }
    if (_elapsed >= _timeLimit) {
      _finishByCenterProximity(alive);
    }
  }

  /// Survivors first (closest-to-center best), then reverse elimination order.
  void _finishBySurvival(List<Body> alive) {
    final survivors = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    final order = <int>[
      ...survivors,
      ..._eliminationOrder.reversed,
    ];
    finishByOrder(_dedupeAllPlayers(order));
  }

  /// Time-out ranking: all remaining alive ranked by closeness to center.
  void _finishByCenterProximity(List<Body> alive) {
    final ranked = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    final order = <int>[
      ...ranked,
      ..._eliminationOrder.reversed,
    ];
    finishByOrder(_dedupeAllPlayers(order));
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawBackground(canvas, size);
    _drawRing(canvas);
    _drawBodies(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

  // ── Rendering helpers ───────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0E1320);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawRing(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFF1B2438);
    canvas.drawCircle(_center, _ringRadius, fill);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF35E0FF);
    canvas.drawCircle(_center, _ringRadius, edge);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x3335E0FF);
    canvas.drawCircle(_center, _ringRadius * 0.6, inner);
  }

  void _drawBodies(Canvas canvas) {
    for (final b in _arena.bodies) {
      final fig = _figures[b.id];
      if (fig == null) continue;
      if (fig.isRagdoll) {
        fig.render(canvas, b.pos);
        continue;
      }
      if (!b.alive) continue;
      _drawPuckShadow(canvas, b);
      fig.render(canvas, _figureRoot(b));
    }
  }

  /// A faint puck disc under the stick figure to read as a sumo platform piece.
  void _drawPuckShadow(Canvas canvas, Body b) {
    final paint = Paint()
      ..color = Color(_colorOf(b.id)).withValues(alpha: 0.25);
    canvas.drawCircle(b.pos, b.radius, paint);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Color(_colorOf(b.id));
    canvas.drawCircle(b.pos, b.radius, ring);
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// Stick feet anchor: bottom of the puck so the figure stands on it.
  Offset _figureRoot(Body b) => Offset(b.pos.dx, b.pos.dy + b.radius);

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

  int _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return p.colorArgb;
    }
    return 0xFFFFFFFF;
  }

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
