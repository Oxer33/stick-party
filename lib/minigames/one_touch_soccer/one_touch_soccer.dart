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

/// One-Touch Soccer: a rect-bounded pitch with a neutral ball (id -1) and one
/// puck per player. A tap lunges your puck at the ball. Even ids (or Team.a)
/// attack the RIGHT goal, odd ids (or Team.b) attack the LEFT goal. Scoring a
/// goal awards a point to every player on the scoring side and resets the ball.
/// Most goals when time expires wins.
class OneTouchSoccer extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'one_touch_soccer',
        name: 'One-Touch Soccer',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'TAP',
      );

  // ── Tuning ──────────────────────────────────────────────────────────────────
  static const double _timeLimit = 45;
  static const int _ballId = -1;
  static const double _pitchInsetFactor = 0.06;
  static const double _ballRadiusFactor = 0.03;
  static const double _playerRadiusFactor = 0.045;
  static const double _pitchFriction = 0.985;
  static const double _restitution = 0.85;
  static const double _lungePerSecond = 3.2;
  static const double _goalMouthFraction = 0.42; // of pitch height, centered
  static const double _figureScale = 0.9;

  late Juice _juice;
  late PushArena _arena;
  late Rect _pitch;
  double _elapsed = 0;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, StickFigure> _figures = <int, StickFigure>{};

  /// True if this player attacks the RIGHT goal (else the LEFT goal).
  final Map<int, bool> _attacksRight = <int, bool>{};

  late Body _ball;
  late double _ballRadius;
  Rect _goalMouth = Rect.zero; // vertical span both goals share
  double _leftLine = 0;
  double _rightLine = 0;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    final size = ctx.arena;
    final inset = math.min(size.width, size.height) * _pitchInsetFactor;
    _pitch = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final minSide = math.min(_pitch.width, _pitch.height);
    _ballRadius = minSide * _ballRadiusFactor;
    final playerRadius = minSide * _playerRadiusFactor;

    _arena = PushArena(
      center: _pitch.center,
      ringRadius: _pitch.shortestSide / 2, // unused in rect mode but required
      friction: _pitchFriction,
      restitution: _restitution,
      bounds: _pitch,
    );

    _computeGoals();
    _buildBall();
    _buildPlayers(playerRadius);
    begin();
  }

  void _computeGoals() {
    final mouthHeight = _pitch.height * _goalMouthFraction;
    final top = _pitch.center.dy - mouthHeight / 2;
    _goalMouth = Rect.fromLTRB(_pitch.left, top, _pitch.right, top + mouthHeight);
    // A goal counts once the ball center reaches the wall contact line.
    _leftLine = _pitch.left + _ballRadius;
    _rightLine = _pitch.right - _ballRadius;
  }

  void _buildBall() {
    _ball = Body(
      id: _ballId,
      pos: _pitch.center,
      vel: Offset.zero,
      radius: _ballRadius,
      mass: 0.6, // lighter than pucks so taps move it well
    );
    _arena.add(_ball);
  }

  void _buildPlayers(double playerRadius) {
    final players = ctx.players;
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      final attacksRight = _resolveSide(p);
      _attacksRight[p.id] = attacksRight;

      // Spawn each puck on its own defending half, stacked vertically.
      final defendLeft = attacksRight; // attack right ⇒ defend/start on left
      final sameSide =
          players.where((q) => _resolveSide(q) == attacksRight).toList();
      final indexOnSide = sameSide.indexWhere((q) => q.id == p.id);
      final lane = (indexOnSide + 1) / (sameSide.length + 1);
      final x = defendLeft
          ? _pitch.left + _pitch.width * 0.25
          : _pitch.right - _pitch.width * 0.25;
      final y = _pitch.top + _pitch.height * lane;
      _arena.add(Body(id: p.id, pos: Offset(x, y), radius: playerRadius));

      _figures[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_figureScale),
        style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)),
        facing: attacksRight ? 1.0 : -1.0,
      )..setLoco(LocoState.idle);

      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Even ids / Team.a attack right; odd ids / Team.b attack left.
  bool _resolveSide(PlayerSlot p) {
    if (p.team == Team.a) return true;
    if (p.team == Team.b) return false;
    return p.id.isEven;
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
    _checkGoals();

    if (_elapsed >= _timeLimit) {
      finishByScore();
    }
  }

  void _driveBots(double dt) {
    for (final entry in _botClocks.entries) {
      if (entry.value.tick(dt)) {
        _act(entry.key);
        entry.value.arm(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Lunge: impulse from the puck toward the ball.
  void _act(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return;
    final dir = _normalize(_ball.pos - self.pos);
    if (dir == Offset.zero) return;

    final magnitude = _pitch.width * _lungePerSecond;
    _arena.impulse(playerId, dir * magnitude);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }
  }

  void _syncFigures(double dt) {
    const runSpeed = 50.0;
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null) {
        fig.setLoco(
            body.vel.distance > runSpeed ? LocoState.run : LocoState.idle);
      }
      fig.update(dt);
    }
  }

  /// Award a goal when the ball reaches a goal line within the goal mouth.
  void _checkGoals() {
    final withinMouth =
        _ball.pos.dy >= _goalMouth.top && _ball.pos.dy <= _goalMouth.bottom;
    if (!withinMouth) return;

    if (_ball.pos.dx <= _leftLine) {
      // Scored on the LEFT goal ⇒ the RIGHT-attacking side scores.
      _scoreFor(attacksRight: true);
    } else if (_ball.pos.dx >= _rightLine) {
      // Scored on the RIGHT goal ⇒ the LEFT-attacking side scores.
      _scoreFor(attacksRight: false);
    }
  }

  void _scoreFor({required bool attacksRight}) {
    var scored = false;
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) {
        addScore(p.id, 1);
        scored = true;
      }
    }
    // In a 1-player / single-side roster no one owns the far goal; ignore.
    final color = scored ? _sideColor(attacksRight) : const Color(0xFFFFFFFF);
    _juice.ko(_ball.pos, color);
    _juice.popup(_pitch.center, 'GOAL!', color, size: 52);
    _resetBall();
  }

  void _resetBall() {
    _ball.pos = _pitch.center;
    _ball.vel = Offset.zero;
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawPitch(canvas, size);
    _drawGoals(canvas);
    _drawBall(canvas);
    _drawPlayers(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

  // ── Rendering ────────────────────────────────────────────────────────────────

  void _drawPitch(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0B3D1E));
    canvas.drawRect(_pitch, Paint()..color = const Color(0xFF1B7A3E));

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.65);
    canvas.drawRect(_pitch, line);

    // Center line + circle.
    canvas.drawLine(
      Offset(_pitch.center.dx, _pitch.top),
      Offset(_pitch.center.dx, _pitch.bottom),
      line,
    );
    canvas.drawCircle(_pitch.center, _pitch.shortestSide * 0.12, line);
  }

  void _drawGoals(Canvas canvas) {
    final goalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    // Left goal.
    goalPaint.color = const Color(0xFF4D9BFF);
    canvas.drawLine(
      Offset(_pitch.left, _goalMouth.top),
      Offset(_pitch.left, _goalMouth.bottom),
      goalPaint,
    );
    // Right goal.
    goalPaint.color = const Color(0xFFFF5A5A);
    canvas.drawLine(
      Offset(_pitch.right, _goalMouth.top),
      Offset(_pitch.right, _goalMouth.bottom),
      goalPaint,
    );
  }

  void _drawBall(Canvas canvas) {
    canvas.drawCircle(
        _ball.pos, _ball.radius, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
      _ball.pos,
      _ball.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF101522),
    );
    // Center dot to read as a football.
    canvas.drawCircle(
        _ball.pos, _ball.radius * 0.3, Paint()..color = const Color(0xFF101522));
  }

  void _drawPlayers(Canvas canvas) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      if (body == null) continue;
      _drawPuckShadow(canvas, body);
      entry.value.render(canvas, Offset(body.pos.dx, body.pos.dy + body.radius));
    }
  }

  void _drawPuckShadow(Canvas canvas, Body b) {
    canvas.drawCircle(
      b.pos,
      b.radius,
      Paint()..color = Color(_colorOf(b.id)).withValues(alpha: 0.3),
    );
  }

  // ── Pure helpers ──────────────────────────────────────────────────────────────

  Color _sideColor(bool attacksRight) {
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  Body? _bodyOf(int id) {
    for (final b in _arena.bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  int _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return p.colorArgb;
    }
    return 0xFFFFFFFF;
  }

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}
