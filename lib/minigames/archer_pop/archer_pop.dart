import 'dart:math' as math;
import 'dart:ui';

import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/aim_sweep.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';

/// Numeric tuning — no magic numbers inline.
class _Tuning {
  static const double timeLimit = 30;
  static const double gravity = 60; // gentle arc on arrows
  static const double arrowSpeed = 640;
  static const double arrowLife = 3;
  static const double targetRadius = 22;
  static const double spawnEvery = 0.9; // seconds between balloon spawns
  static const int maxTargets = 7;
  static const double balloonSpeed = 70; // px/s drift
  static const double bowSweep = 0.55; // half-band radians
  static const double sweepSpeed = 1.9;
  static const double aimTolerance = 0.16; // bot aim cone (radians)
  static const double edgeInset = 96;
  static const double bowReach = 26; // px from base to arrow spawn
  static const double bobRate = 2.4; // balloon wobble rad/s
}

/// A floating balloon target drifting across the field.
class _Target {
  Offset pos;
  final Offset vel;
  final Color color;
  double bob; // phase for vertical wobble
  _Target({
    required this.pos,
    required this.vel,
    required this.color,
    this.bob = 0,
  });
}

/// An in-flight arrow.
class _Arrow {
  Offset pos;
  Offset vel;
  final int ownerId;
  final Color color;
  double life;
  _Arrow({
    required this.pos,
    required this.vel,
    required this.ownerId,
    required this.color,
    this.life = _Tuning.arrowLife,
  });
}

/// One archer anchored at a player edge with a sweeping bow.
class _Archer {
  final int playerId;
  final Color color;
  final Offset base;
  final double facing;
  final AimSweep bow;
  final StickFigure figure;
  ReactionClock? clock;
  _Archer({
    required this.playerId,
    required this.color,
    required this.base,
    required this.facing,
    required this.bow,
    required this.figure,
    this.clock,
  });
}

/// Archer Pop: tap to loose an arrow along a sweeping aim at drifting balloons.
/// Most balloons popped at the time limit wins.
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

  late Juice _juice;
  final List<_Archer> _archers = <_Archer>[];
  final List<_Arrow> _arrows = <_Arrow>[];
  final List<_Target> _targets = <_Target>[];
  double _elapsed = 0;
  double _spawnTimer = 0;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildArchers();
    _spawnTarget(); // start with one on field
    begin();
  }

  void _buildArchers() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final base = _basePos(i, count, arena);
      final toCenter = Offset(arena.width / 2, arena.height / 2) - base;
      final center = math.atan2(toCenter.dy, toCenter.dx);
      final facing = toCenter.dx >= 0 ? 1.0 : -1.0;
      final bow = AimSweep(
        minAngle: center - _Tuning.bowSweep,
        maxAngle: center + _Tuning.bowSweep,
        speed: _Tuning.sweepSpeed,
        angle: center,
      );
      final figure = StickFigure(
        style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)),
        facing: facing,
      )..setLoco(LocoState.idle);
      _archers.add(_Archer(
        playerId: p.id,
        color: Color(p.colorArgb),
        base: base,
        facing: facing,
        bow: bow,
        figure: figure,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  Offset _basePos(int index, int count, Size arena) {
    final inset = _Tuning.edgeInset;
    final w = arena.width, h = arena.height;
    switch (count) {
      case 1:
        return Offset(w * 0.5, h - inset);
      case 2:
        return index == 0
            ? Offset(w * 0.5, h - inset)
            : Offset(w * 0.5, inset);
      case 3:
        return [
          Offset(w * 0.5, h - inset),
          Offset(inset, inset),
          Offset(w - inset, inset),
        ][index];
      default:
        return [
          Offset(inset, h - inset),
          Offset(w - inset, h - inset),
          Offset(inset, inset),
          Offset(w - inset, inset),
        ][index];
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _release(input.playerId);
  }

  void _release(int id) {
    final archer = _archerOf(id);
    if (archer == null) return;
    final dir = archer.bow.direction;
    final muzzle = archer.base + dir * _Tuning.bowReach;
    _arrows.add(_Arrow(
      pos: muzzle,
      vel: dir * _Tuning.arrowSpeed,
      ownerId: id,
      color: archer.color,
    ));
  }

  _Archer? _archerOf(int id) {
    for (final a in _archers) {
      if (a.playerId == id) return a;
    }
    return null;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    for (final a in _archers) {
      a.bow.update(sdt);
      a.figure.update(dt);
    }
    _spawnTick(sdt);
    _stepTargets(sdt);
    _driveBots(dt);
    _stepArrows(sdt);
    _checkEnd();
  }

  void _spawnTick(double dt) {
    _spawnTimer += dt;
    if (_spawnTimer >= _Tuning.spawnEvery &&
        _targets.length < _Tuning.maxTargets) {
      _spawnTimer = 0;
      _spawnTarget();
    }
  }

  void _spawnTarget() {
    final a = ctx.arena;
    // Enter from a random side, drift across the mid field.
    final fromLeft = ctx.rng.chance(0.5);
    final y = ctx.rng.range(a.height * 0.2, a.height * 0.8);
    final x = fromLeft ? -_Tuning.targetRadius : a.width + _Tuning.targetRadius;
    final vx = (fromLeft ? 1 : -1) * _Tuning.balloonSpeed;
    final palette = ctx.players[ctx.rng.intRange(0, ctx.players.length)];
    _targets.add(_Target(
      pos: Offset(x, y),
      vel: Offset(vx, ctx.rng.range(-12, 12)),
      color: Color(palette.colorArgb),
      bob: ctx.rng.range(0, kTau),
    ));
  }

  void _stepTargets(double dt) {
    final a = ctx.arena;
    final survivors = <_Target>[];
    for (final t in _targets) {
      final bob = t.bob + dt * _Tuning.bobRate;
      final drift = Offset(0, math.sin(bob) * 8 * dt);
      final pos = t.pos + t.vel * dt + drift;
      const pad = 60.0;
      final gone = pos.dx < -pad || pos.dx > a.width + pad;
      if (gone) continue;
      survivors.add(_Target(pos: pos, vel: t.vel, color: t.color, bob: bob));
    }
    _targets
      ..clear()
      ..addAll(survivors);
  }

  /// Bots loose when the bow points near any live target.
  void _driveBots(double dt) {
    for (final a in _archers) {
      final clock = a.clock;
      if (clock == null) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldRelease(a)) {
        _release(a.playerId);
      }
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  bool _botShouldRelease(_Archer archer) {
    if (_targets.isEmpty) return false;
    final tol = _Tuning.aimTolerance / math.max(ctx.botProfile.accuracy, 0.25);
    for (final t in _targets) {
      final to = t.pos - archer.base;
      final wanted = math.atan2(to.dy, to.dx);
      if ((wrapAngle(archer.bow.angle - wanted)).abs() <= tol) {
        return true;
      }
    }
    return ctx.rng.chance(ctx.botProfile.errorRate * 0.4);
  }

  void _stepArrows(double dt) {
    final survivors = <_Arrow>[];
    for (final s in _arrows) {
      final vel = s.vel + Offset(0, _Tuning.gravity * dt);
      final pos = s.pos + vel * dt;
      final life = s.life - dt;
      final hit = _popTarget(pos);
      if (hit != null) {
        _registerPop(s.ownerId, hit);
        continue;
      }
      if (life <= 0 || _outOfBounds(pos)) continue;
      survivors.add(_Arrow(
          pos: pos, vel: vel, ownerId: s.ownerId, color: s.color, life: life));
    }
    _arrows
      ..clear()
      ..addAll(survivors);
  }

  _Target? _popTarget(Offset pos) {
    for (final t in _targets) {
      if ((t.pos - pos).distance <= _Tuning.targetRadius) return t;
    }
    return null;
  }

  void _registerPop(int shooterId, _Target target) {
    addScore(shooterId, 1);
    final shooter = _archerOf(shooterId);
    final color = shooter?.color ?? target.color;
    _juice.hit(target.pos, color);
    _juice.popup(target.pos, '+1', color, size: 24);
    _targets.remove(target);
  }

  bool _outOfBounds(Offset p) {
    final a = ctx.arena;
    const pad = 80.0;
    return p.dx < -pad ||
        p.dy < -pad ||
        p.dx > a.width + pad ||
        p.dy > a.height + pad;
  }

  void _checkEnd() {
    if (_elapsed >= _Tuning.timeLimit) {
      _juice.confetti(ctx.arena);
      finishByScore();
    }
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);
    _drawField(canvas, size);
    for (final t in _targets) {
      _drawTarget(canvas, t);
    }
    for (final a in _archers) {
      _drawArcher(canvas, a);
    }
    for (final s in _arrows) {
      _drawArrow(canvas, s);
    }
    _juice.render(canvas);
    canvas.restore();
  }

  void _drawField(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1726));
  }

  void _drawTarget(Canvas canvas, _Target t) {
    final body = Paint()..color = t.color;
    // Balloon bulb.
    canvas.drawCircle(t.pos, _Tuning.targetRadius, body);
    // Highlight.
    canvas.drawCircle(
      t.pos + const Offset(-7, -7),
      _Tuning.targetRadius * 0.3,
      Paint()..color = const Color(0x66FFFFFF),
    );
    // String tail.
    final tail = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(
      t.pos + Offset(0, _Tuning.targetRadius),
      t.pos + Offset(0, _Tuning.targetRadius + 16),
      tail,
    );
  }

  void _drawArcher(Canvas canvas, _Archer a) {
    a.figure.render(canvas, a.base);
    // Bow line indicating current aim.
    final dir = a.bow.direction;
    final tip = a.base + dir * 30;
    final bowPaint = Paint()
      ..color = a.color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a.base, tip, bowPaint);
  }

  void _drawArrow(Canvas canvas, _Arrow s) {
    final dir = s.vel.distance > 0 ? s.vel / s.vel.distance : const Offset(1, 0);
    final tail = s.pos - dir * 14;
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, s.pos, paint);
  }
}
