import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/fx/particles.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/aim_sweep.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'tank_render.dart';

/// Tank Duel — every player owns a tank mounted on a screen edge with a turret
/// that auto-sweeps a firing arc. One tap FIRES a gravity-arced shell down the
/// barrel.
///
/// Depth (still one-touch):
///  * Each tank has 3 HP with on-tank health pips, a white hit-flash and a
///    brief invulnerability window after taking a hit.
///  * Firing kicks the turret back (recoil) and spews a muzzle flash; the shell
///    leaves a smoke/spark trail and detonates on impact (particle burst +
///    screen shake + hit-stop + a lasting scorch decal).
///  * Destructible cover crates sit in the mid-field; shells chip and eventually
///    shatter them, so players must vary their aim to reach a guarded foe.
///  * First tank to land 3 hits wins; otherwise the most hits at the 40s time
///    limit. The time limit always resolves the round.
///
/// Bots LEAD the arc: they solve (by a cheap arc search) the launch angle that
/// drops a shell onto the nearest reachable opponent, apply a [BotProfile]
/// accuracy error, and fire on their [ReactionClock] cadence.
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

  // ── Round / scoring tuning ──────────────────────────────────────────────────
  static const double _timeLimit = 40;
  static const int _hitsToWin = 3;
  static const int _maxHp = 3;

  // ── Ballistics tuning ───────────────────────────────────────────────────────
  static const double _gravity = 360; // px/s^2 on shells
  static const double _shellSpeed = 720; // launch px/s
  static const double _shellLife = 4.5; // seconds before a shell fizzles
  static const double _shellRadius = 7;
  static const int _trailSamples = 12; // trail points kept per shell
  static const double _outOfBoundsPad = 120;

  // ── Tank geometry tuning (mirrors TankRenderer so sim + visuals agree) ──────
  static const double _baseR = 26; // base tank radius (scaled to fit arena)
  static const double _turretPivotOut = 0.62; // pivot offset along edge normal
  static const double _barrelLen = 1.9; // barrel length / radius
  static const double _hitRadius = 0.95; // body hit radius / radius
  static const double _edgeInsetFactor = 0.085; // edge inset / min(arena side)
  static const double _sweepHalfBand = 0.62; // half sweep arc (radians)
  static const double _sweepSpeed = 1.45; // sweep angular speed (rad/s)

  // ── Feel timers ─────────────────────────────────────────────────────────────
  static const double _flashSec = 0.2;
  static const double _recoilSec = 0.28;
  static const double _muzzleSec = 0.09;
  static const double _invulnSec = 0.7;
  static const double _invulnBlinkHz = 9; // blink phases per second
  static const double _scorchLife = 6;
  static const double _scorchRadius = 34;

  // ── Cover crate tuning ──────────────────────────────────────────────────────
  static const int _crateHp = 3;
  static const double _crateFlashSec = 0.14;
  static const double _crateSizeFactor = 0.05; // crate side / min(arena side)

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botBaseTolerance = 0.10; // good-aim cone at full accuracy
  static const int _botArcCandidates = 13; // angles probed across the band
  static const int _botArcSteps = 26; // integration steps per probed arc
  static const double _botArcDt = 0.05; // arc-probe timestep (seconds)
  static const double _botWildChance = 0.4; // share of errorRate → wild shots

  // ── Ambient ─────────────────────────────────────────────────────────────────
  static const int _emberCount = 26;
  static const double _horizonFactor = 0.34; // horizon Y / arena height

  late Juice _juice;
  final List<_Tank> _tanks = <_Tank>[];
  final List<_Shell> _shells = <_Shell>[];
  final List<_Crate> _crates = <_Crate>[];
  final List<_Scorch> _scorches = <_Scorch>[];
  final List<Offset> _embers = <Offset>[];

  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for ambient/flash
  late Size _size;
  late double _scale;
  late double _horizonY;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    final minSide = math.min(_size.width, _size.height);
    // Scale tanks down on small arenas, up modestly on big ones.
    _scale = (minSide / 520).clamp(0.7, 1.6);
    _horizonY = _size.height * _horizonFactor;
    _buildTanks();
    _buildCrates();
    _seedEmbers();
    begin();
  }

  // ── World construction ──────────────────────────────────────────────────────

  void _buildTanks() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final edge = _edgeFor(i, count);
      final base = _basePos(edge);
      // Sweep band is centered on the inward normal so the barrel always aims
      // into the playfield, regardless of which edge the tank sits on.
      final inward = -edge.outward;
      final center = math.atan2(inward.dy, inward.dx);
      final barrel = AimSweep(
        minAngle: center - _sweepHalfBand,
        maxAngle: center + _sweepHalfBand,
        speed: _sweepSpeed,
        angle: center + ctx.rng.jitter(_sweepHalfBand * 0.6),
      );
      _tanks.add(_Tank(
        playerId: p.id,
        color: Color(p.colorArgb),
        base: base,
        edge: edge,
        barrel: barrel,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Assign each seat to a screen edge: bottom, then top, then the sides.
  TankEdge _edgeFor(int index, int count) {
    switch (count) {
      case 1:
        return TankEdge.bottom;
      case 2:
        return index == 0 ? TankEdge.bottom : TankEdge.top;
      case 3:
        return [TankEdge.bottom, TankEdge.left, TankEdge.right][index];
      default:
        return [
          TankEdge.bottom,
          TankEdge.top,
          TankEdge.left,
          TankEdge.right,
        ][index];
    }
  }

  /// Turret-base anchor: inset from the assigned edge, centered along it.
  Offset _basePos(TankEdge edge) {
    final w = _size.width, h = _size.height;
    final inset = math.min(w, h) * _edgeInsetFactor + _baseR * _scale;
    return switch (edge) {
      TankEdge.bottom => Offset(w * 0.5, h - inset),
      TankEdge.top => Offset(w * 0.5, inset),
      TankEdge.left => Offset(inset, h * 0.58),
      TankEdge.right => Offset(w - inset, h * 0.58),
    };
  }

  /// A short row of destructible crates across the mid-field, biased toward the
  /// vertical center so they actually intercept fire between opposing tanks.
  void _buildCrates() {
    final w = _size.width, h = _size.height;
    final side = math.min(w, h) * _crateSizeFactor;
    final midY = h * 0.5;
    // Three clustered columns with slight vertical stagger for cover variety.
    const count = 3;
    for (var i = 0; i < count; i++) {
      final fx = (i + 1) / (count + 1);
      final cx = w * fx;
      final cy = midY + (i.isEven ? -1 : 1) * side * 0.7;
      final rect =
          Rect.fromCenter(center: Offset(cx, cy), width: side, height: side);
      _crates.add(_Crate(rect: rect));
    }
  }

  void _seedEmbers() {
    for (var i = 0; i < _emberCount; i++) {
      _embers.add(Offset(
        ctx.rng.range(0, _size.width),
        ctx.rng.range(0, _size.height),
      ));
    }
  }

  // ── Input ───────────────────────────────────────────────────────────────────

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
    final muzzle = _muzzleOf(tank);
    _shells.add(_Shell(
      pos: muzzle,
      vel: dir * _shellSpeed,
      ownerId: id,
      color: tank.color,
    ));
    tank.recoil = _recoilSec;
    tank.muzzle = _muzzleSec;
    // Muzzle smoke puff + sparks in the firing direction.
    final baseAngle = math.atan2(dir.dy, dir.dx);
    _juice.particles.burst(
      at: muzzle,
      count: 6,
      color: const Color(0xFFFFD27A),
      speed: 210,
      baseAngle: baseAngle,
      spread: math.pi * 0.5,
      size: 5,
      gravity: 120,
      life: 0.3,
    );
    _juice.shake.light();
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

    for (final t in _tanks) {
      t.barrel.update(sdt);
      t.tickTimers(dt, _flashSec, _recoilSec, _muzzleSec, _invulnSec);
    }
    for (final c in _crates) {
      c.tickFlash(dt, _crateFlashSec);
    }
    _ageScorches(dt);
    _driveBots(dt);
    _stepShells(sdt);
    _checkEnd();
  }

  void _ageScorches(double dt) {
    for (final s in _scorches) {
      s.life -= dt;
    }
    _scorches.removeWhere((s) => s.life <= 0);
  }

  // ── Bots: lead the arc, then fire on cadence ────────────────────────────────

  void _driveBots(double dt) {
    for (final t in _tanks) {
      final clock = t.clock;
      if (clock == null) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldFire(t)) _fire(t.playerId);
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  /// A bot fires when its live sweep angle is within an accuracy-scaled cone of
  /// the launch angle that would land a shell on the nearest reachable target.
  /// Low-accuracy bots also take occasional wild shots so they are never idle.
  bool _botShouldFire(_Tank shooter) {
    final accuracy = ctx.botProfile.accuracy.clamp(0.2, 1.0);
    final tol = _botBaseTolerance / accuracy;
    final best = _bestLaunchAngle(shooter);
    if (best != null) {
      // Accuracy error nudges the "wanted" angle so even good lineups miss a
      // little at lower difficulties.
      final err = ctx.rng.jitter((1 - accuracy) * _sweepHalfBand * 0.5);
      if (wrapAngle(shooter.barrel.angle - (best + err)).abs() <= tol) {
        return true;
      }
    }
    return ctx.rng.chance(ctx.botProfile.errorRate * _botWildChance);
  }

  /// Probe a set of launch angles across the tank's sweep band; return the one
  /// whose simulated arc passes closest to any opponent within the band, or null
  /// when nothing is reasonably reachable. Cheap and bounded — never throws.
  double? _bestLaunchAngle(_Tank shooter) {
    final lo = shooter.barrel.minAngle;
    final hi = shooter.barrel.maxAngle;
    final muzzle = _muzzleOf(shooter);
    double? bestAngle;
    var bestMiss = double.infinity;
    for (var i = 0; i < _botArcCandidates; i++) {
      final f = _botArcCandidates == 1 ? 0.5 : i / (_botArcCandidates - 1);
      final angle = lo + (hi - lo) * f;
      final miss = _arcClosestMiss(muzzle, angle, shooter.playerId);
      if (miss < bestMiss) {
        bestMiss = miss;
        bestAngle = angle;
      }
    }
    // Only commit if the best arc actually grazes a target.
    final reach = _baseR * _scale * 2.2;
    return (bestAngle != null && bestMiss <= reach) ? bestAngle : null;
  }

  /// Closest distance a shell launched at [angle] from [muzzle] gets to any
  /// opponent of [ownerId], integrating the same gravity arc as live shells.
  double _arcClosestMiss(Offset muzzle, double angle, int ownerId) {
    var pos = muzzle;
    var vel = Offset(math.cos(angle), math.sin(angle)) * _shellSpeed;
    var best = double.infinity;
    for (var step = 0; step < _botArcSteps; step++) {
      vel = vel + Offset(0, _gravity * _botArcDt);
      pos = pos + vel * _botArcDt;
      if (_outOfBounds(pos)) break;
      for (final t in _tanks) {
        if (t.playerId == ownerId) continue;
        final d = (_turretPivotOf(t) - pos).distance;
        if (d < best) best = d;
      }
    }
    return best;
  }

  // ── Shells ──────────────────────────────────────────────────────────────────

  void _stepShells(double dt) {
    final survivors = <_Shell>[];
    for (final s in _shells) {
      final vel = s.vel + Offset(0, _gravity * dt);
      final pos = s.pos + vel * dt;
      final life = s.life - dt;

      final victimId = _hitTank(pos, s.ownerId);
      if (victimId != null) {
        _registerHit(victimId, s.ownerId, pos);
        continue; // shell consumed
      }
      final crate = _hitCrate(pos);
      if (crate != null) {
        _chipCrate(crate, s, pos);
        continue; // shell consumed
      }
      if (life <= 0 || _outOfBounds(pos)) {
        if (life <= 0) _fizzle(pos, s.color);
        continue;
      }

      s.advance(pos, vel, life, _trailSamples);
      survivors.add(s);
    }
    _shells
      ..clear()
      ..addAll(survivors);
  }

  int? _hitTank(Offset pos, int ownerId) {
    for (final t in _tanks) {
      if (t.playerId == ownerId) continue;
      if (t.invuln > 0) continue;
      final reach = _baseR * _scale * _hitRadius + _shellRadius;
      if ((_turretPivotOf(t) - pos).distance <= reach) return t.playerId;
    }
    return null;
  }

  _Crate? _hitCrate(Offset pos) {
    for (final c in _crates) {
      if (c.hp <= 0) continue;
      if (c.rect.inflate(_shellRadius).contains(pos)) return c;
    }
    return null;
  }

  void _registerHit(int victimId, int shooterId, Offset at) {
    final victim = _tankOf(victimId);
    final shooter = _tankOf(shooterId);
    if (victim == null || shooter == null) return;
    victim.hp = (victim.hp - 1).clamp(0, _maxHp);
    victim.flash = _flashSec;
    victim.invuln = _invulnSec;
    addScore(shooterId, 1);
    _explode(at, shooter.color, heavy: true);
    _scorches.add(_Scorch(at: at));
    _juice.popup(at.translate(0, -_baseR * _scale), 'HIT!', shooter.color,
        size: 26);
  }

  void _chipCrate(_Crate crate, _Shell shell, Offset at) {
    crate.hp = (crate.hp - 1).clamp(0, _crateHp);
    crate.flash = _crateFlashSec;
    // Wood splinters + a small puff, lighter than a tank hit.
    _juice.particles.burst(
      at: at,
      count: 9,
      color: const Color(0xFFC79A5C),
      speed: 230,
      size: 5,
      gravity: 500,
      life: 0.45,
      shape: ParticleShape.square,
    );
    _juice.shake.light();
    _juice.hitStop.trigger(0.03);
    if (crate.hp <= 0) {
      // Shatter: bigger burst + a scorch where the crate stood.
      _explode(crate.rect.center, shell.color, heavy: false);
      _scorches.add(_Scorch(at: crate.rect.center));
    }
  }

  /// Impact explosion: a hot two-tone particle burst + shake + hit-stop.
  void _explode(Offset at, Color color, {required bool heavy}) {
    _juice.particles.burst(
      at: at,
      count: heavy ? 20 : 12,
      color: color,
      speed: heavy ? 360 : 260,
      spread: math.pi * 2,
      size: heavy ? 8 : 6,
      gravity: 520,
      life: heavy ? 0.7 : 0.5,
    );
    _juice.particles.burst(
      at: at,
      count: heavy ? 12 : 7,
      color: const Color(0xFFFFE6A0),
      speed: heavy ? 300 : 220,
      spread: math.pi * 2,
      size: heavy ? 6 : 4,
      gravity: 400,
      life: 0.4,
    );
    if (heavy) {
      _juice.shake.heavy();
      _juice.hitStop.trigger(0.1, scale: 0.1);
    } else {
      _juice.shake.medium();
      _juice.hitStop.trigger(0.05);
    }
  }

  void _fizzle(Offset at, Color color) {
    _juice.particles.burst(
      at: at,
      count: 5,
      color: color.withValues(alpha: 0.7),
      speed: 120,
      size: 4,
      gravity: 200,
      life: 0.4,
    );
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
    final reachedTarget = _tanks.any((t) => scoreOf(t.playerId) >= _hitsToWin);
    if (reachedTarget || _elapsed >= _timeLimit) {
      _juice.confetti(_size);
      finishByScore();
    }
  }

  // ── Geometry helpers (mirror TankRenderer) ──────────────────────────────────

  Offset _turretPivotOf(_Tank t) =>
      t.base + t.edge.outward * (_baseR * _scale * _turretPivotOut);

  Offset _muzzleOf(_Tank t) {
    final dir = t.barrel.direction;
    return _turretPivotOf(t) + dir * (_baseR * _scale * _barrelLen);
  }

  _Tank? _tankOf(int id) {
    for (final t in _tanks) {
      if (t.playerId == id) return t;
    }
    return null;
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    TankRenderer.drawBattlefield(
      canvas,
      size,
      horizonY: _horizonY,
      embers: _embers,
      t: _animClock,
    );

    // Scorch decals sit under everything else for grounded impact marks.
    for (final s in _scorches) {
      final fade = (s.life / _scorchLife).clamp(0.0, 1.0);
      TankRenderer.drawScorch(canvas, s.at, _scorchRadius * (0.6 + 0.4 * fade));
    }

    for (final c in _crates) {
      if (c.hp <= 0) continue;
      TankRenderer.drawCrate(canvas, c.view(_crateHp));
    }

    // Aim guides first (under the tanks), then the tanks themselves.
    for (final t in _tanks) {
      if (t.hp <= 0) continue;
      TankRenderer.drawAimGuide(canvas, _viewOf(t));
    }
    for (final t in _tanks) {
      TankRenderer.drawTank(canvas, _viewOf(t));
    }

    for (final s in _shells) {
      TankRenderer.drawShell(canvas, s.view());
    }

    _juice.render(canvas);
    canvas.restore();
  }

  TankView _viewOf(_Tank t) {
    // Invuln phase counts blink cycles; pass the phase index so the renderer can
    // strobe the body without us mutating anything during render.
    final blinkPhase =
        t.invuln > 0 ? (_animClock * _invulnBlinkHz) % 2 + 1 : 0.0;
    return TankView(
      base: t.base,
      color: t.color,
      edge: t.edge,
      aimAngle: t.barrel.angle,
      hp: t.hp,
      maxHp: _maxHp,
      flash: (t.flash / _flashSec).clamp(0.0, 1.0),
      recoil: easeOut((t.recoil / _recoilSec).clamp(0.0, 1.0)),
      muzzle: (t.muzzle / _muzzleSec).clamp(0.0, 1.0),
      invuln: blinkPhase,
      scale: _scale,
    );
  }
}

/// One tank. Mutable round-scoped state (allowed for the duration of one round).
class _Tank {
  final int playerId;
  final Color color;
  final Offset base; // turret-base anchor in arena px
  final TankEdge edge;
  final AimSweep barrel;
  final ReactionClock? clock; // null for human seats
  int hp = TankDuel._maxHp;
  double flash = 0; // hit-flash timer
  double recoil = 0; // recoil timer
  double muzzle = 0; // muzzle-flash timer
  double invuln = 0; // invulnerability timer

  _Tank({
    required this.playerId,
    required this.color,
    required this.base,
    required this.edge,
    required this.barrel,
    this.clock,
  });

  void tickTimers(double dt, double flashSec, double recoilSec,
      double muzzleSec, double invulnSec) {
    if (flash > 0) flash = (flash - dt).clamp(0, flashSec);
    if (recoil > 0) recoil = (recoil - dt).clamp(0, recoilSec);
    if (muzzle > 0) muzzle = (muzzle - dt).clamp(0, muzzleSec);
    if (invuln > 0) invuln = (invuln - dt).clamp(0, invulnSec);
  }
}

/// One in-flight shell. Mutates in place along its arc and keeps a short trail.
class _Shell {
  Offset pos;
  Offset vel;
  final int ownerId;
  final Color color;
  double life = TankDuel._shellLife;
  final List<Offset> _trail = <Offset>[];

  _Shell({
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

  ShellView view() => ShellView(
        pos: pos,
        vel: vel,
        color: color,
        trail: List<Offset>.unmodifiable(_trail),
      );
}

/// One destructible cover crate. Mutable round-scoped state.
class _Crate {
  final Rect rect;
  int hp = TankDuel._crateHp;
  double flash = 0;

  _Crate({required this.rect});

  void tickFlash(double dt, double flashSec) {
    if (flash > 0) flash = (flash - dt).clamp(0, flashSec);
  }

  CrateView view(int maxHp) => CrateView(
        rect: rect,
        hp: hp,
        maxHp: maxHp,
        flash: (flash / TankDuel._crateFlashSec).clamp(0.0, 1.0),
      );
}

/// A fading scorch decal left by an explosion. Mutable round-scoped state.
class _Scorch {
  final Offset at;
  double life = TankDuel._scorchLife;
  _Scorch({required this.at});
}
