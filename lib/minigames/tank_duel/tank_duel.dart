import 'dart:math' as math;
import 'dart:ui';

import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/aim_sweep.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';

/// One tank: a body anchored near a player's screen edge with a sweeping
/// barrel. Mutable round state only (lives one round).
class _Tank {
  final int playerId;
  final Color color;
  final Offset base; // muzzle pivot in arena px
  final double facing; // +1 fires rightward bias, -1 leftward
  final AimSweep barrel;
  int hits = 0;
  double flash = 0; // hit flash timer
  ReactionClock? clock; // null for human seats

  _Tank({
    required this.playerId,
    required this.color,
    required this.base,
    required this.facing,
    required this.barrel,
    this.clock,
  });
}

/// One in-flight shell.
class _Shell {
  Offset pos;
  Offset vel;
  final int ownerId;
  final Color color;
  double life;
  _Shell({
    required this.pos,
    required this.vel,
    required this.ownerId,
    required this.color,
    this.life = _Tuning.shellLife,
  });
}

/// Numeric tuning — no magic numbers inline.
class _Tuning {
  static const double timeLimit = 40;
  static const int hitsToWin = 3;
  static const double gravity = 320; // px/s^2 on shells
  static const double shellSpeed = 560; // launch px/s
  static const double shellLife = 4; // seconds before fizzle
  static const double shellRadius = 7;
  static const double tankRadius = 26;
  static const double barrelLen = 40;
  static const double barrelSweep = 0.5; // half-band radians
  static const double sweepSpeed = 1.7;
  static const double flashSec = 0.18;
  static const double aimTolerance = 0.18; // bot "good aim" cone (radians)
  static const double edgeInset = 90; // px from arena edge to tank base
}

/// Tank Duel: tap to fire a gravity-arced shell from a sweeping barrel.
/// First to 3 hits, or most hits at the time limit.
class TankDuel extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tank_duel',
        name: 'Tank Duel',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  late Juice _juice;
  final List<_Tank> _tanks = <_Tank>[];
  final List<_Shell> _shells = <_Shell>[];
  double _elapsed = 0;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildTanks();
    begin();
  }

  void _buildTanks() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final base = _basePos(i, count, arena);
      // Barrel points from the tank toward arena center, sweeping a band.
      final toCenter = Offset(arena.width / 2, arena.height / 2) - base;
      final center = math.atan2(toCenter.dy, toCenter.dx);
      final facing = toCenter.dx >= 0 ? 1.0 : -1.0;
      final barrel = AimSweep(
        minAngle: center - _Tuning.barrelSweep,
        maxAngle: center + _Tuning.barrelSweep,
        speed: _Tuning.sweepSpeed,
        angle: center,
      );
      _tanks.add(_Tank(
        playerId: p.id,
        color: Color(p.colorArgb),
        base: base,
        facing: facing,
        barrel: barrel,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Evenly distribute tanks around the arena perimeter by seat index.
  Offset _basePos(int index, int count, Size arena) {
    final inset = _Tuning.edgeInset;
    final w = arena.width, h = arena.height;
    // Spread along the bottom for 1, opposite edges for 2, corners for 3-4.
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
    _fire(input.playerId);
  }

  void _fire(int id) {
    final tank = _tankOf(id);
    if (tank == null) return;
    final dir = tank.barrel.direction;
    final muzzle = tank.base + dir * _Tuning.barrelLen;
    _shells.add(_Shell(
      pos: muzzle,
      vel: dir * _Tuning.shellSpeed,
      ownerId: id,
      color: tank.color,
    ));
  }

  _Tank? _tankOf(int id) {
    for (final t in _tanks) {
      if (t.playerId == id) return t;
    }
    return null;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    for (final t in _tanks) {
      t.barrel.update(sdt);
      if (t.flash > 0) t.flash = (t.flash - dt).clamp(0, _Tuning.flashSec);
    }
    _driveBots(dt);
    _stepShells(sdt);
    _checkEnd();
  }

  /// Bots fire when their barrel roughly points at any opponent.
  void _driveBots(double dt) {
    for (final t in _tanks) {
      final clock = t.clock;
      if (clock == null) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldFire(t)) {
        _fire(t.playerId);
      }
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  bool _botShouldFire(_Tank shooter) {
    // Accuracy widens/narrows the acceptable aim cone; low accuracy may still
    // fire wildly (errorRate) so bots are not perfectly passive.
    final tol = _Tuning.aimTolerance / math.max(ctx.botProfile.accuracy, 0.25);
    for (final other in _tanks) {
      if (other.playerId == shooter.playerId) continue;
      final to = other.base - shooter.base;
      final wanted = math.atan2(to.dy, to.dx);
      if ((wrapAngle(shooter.barrel.angle - wanted)).abs() <= tol) {
        return true;
      }
    }
    return ctx.rng.chance(ctx.botProfile.errorRate * 0.5);
  }

  void _stepShells(double dt) {
    final survivors = <_Shell>[];
    for (final s in _shells) {
      final vel = s.vel + Offset(0, _Tuning.gravity * dt);
      final pos = s.pos + vel * dt;
      final life = s.life - dt;
      final hitId = _hitTank(pos, s.ownerId);
      if (hitId != null) {
        _registerHit(hitId, s.ownerId, pos);
        continue; // shell consumed
      }
      if (life <= 0 || _outOfBounds(pos)) continue;
      survivors.add(_Shell(
          pos: pos, vel: vel, ownerId: s.ownerId, color: s.color, life: life));
    }
    _shells
      ..clear()
      ..addAll(survivors);
  }

  int? _hitTank(Offset pos, int ownerId) {
    for (final t in _tanks) {
      if (t.playerId == ownerId) continue;
      if ((t.base - pos).distance <= _Tuning.tankRadius + _Tuning.shellRadius) {
        return t.playerId;
      }
    }
    return null;
  }

  void _registerHit(int victimId, int shooterId, Offset at) {
    final victim = _tankOf(victimId);
    final shooter = _tankOf(shooterId);
    if (victim == null || shooter == null) return;
    victim.hits += 1;
    victim.flash = _Tuning.flashSec;
    addScore(shooterId, 1);
    _juice.hit(at, shooter.color);
    _juice.popup(at, '+1', shooter.color, size: 24);
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
    final reachedTarget =
        _tanks.any((t) => scoreOf(t.playerId) >= _Tuning.hitsToWin);
    if (reachedTarget || _elapsed >= _Tuning.timeLimit) {
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
    for (final t in _tanks) {
      _drawTank(canvas, t);
    }
    for (final s in _shells) {
      _drawShell(canvas, s);
    }
    _juice.render(canvas);
    canvas.restore();
  }

  void _drawField(Canvas canvas, Size size) {
    final ground = Paint()..color = const Color(0xFF10141C);
    canvas.drawRect(Offset.zero & size, ground);
  }

  void _drawTank(Canvas canvas, _Tank t) {
    final flashK = (t.flash / _Tuning.flashSec).clamp(0.0, 1.0);
    final body = Paint()
      ..color = Color.lerp(t.color, const Color(0xFFFFFFFF), flashK * 0.6)!;
    // Hull.
    final hull = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: t.base,
          width: _Tuning.tankRadius * 2.2,
          height: _Tuning.tankRadius * 1.4),
      const Radius.circular(8),
    );
    canvas.drawRRect(hull, body);
    // Turret dome.
    canvas.drawCircle(t.base, _Tuning.tankRadius * 0.7, body);
    // Barrel.
    final dir = t.barrel.direction;
    final muzzle = t.base + dir * _Tuning.barrelLen;
    final barrelPaint = Paint()
      ..color = const Color(0xFFE8EEF6)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(t.base, muzzle, barrelPaint);
    // Hit pips.
    _drawPips(canvas, t);
  }

  void _drawPips(Canvas canvas, _Tank t) {
    final pip = Paint();
    const gap = 14.0;
    final y = t.base.dy + _Tuning.tankRadius + 12;
    for (var i = 0; i < _Tuning.hitsToWin; i++) {
      final filled = i < t.hits;
      pip.color = filled ? t.color : const Color(0x33FFFFFF);
      final cx = t.base.dx - gap + i * gap;
      canvas.drawCircle(Offset(cx, y), 4, pip);
    }
  }

  void _drawShell(Canvas canvas, _Shell s) {
    final glow = Paint()
      ..color = s.color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(s.pos, _Tuning.shellRadius * 1.6, glow);
    canvas.drawCircle(s.pos, _Tuning.shellRadius, Paint()..color = s.color);
  }
}
