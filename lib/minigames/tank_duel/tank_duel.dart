import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/fx/particles.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/aim_sweep.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'tank_fx.dart';
import 'tank_render.dart';

/// Tank Duel — every player owns a tank mounted on a screen edge with a turret
/// that auto-sweeps a firing arc. One tap FIRES a gravity-arced shell down the
/// barrel.
///
/// CONTROL (the heart of it — a real per-shot DECISION, still one touch):
///  * The turret AIM sweeps a firing arc continuously and at a learnable speed.
///  * Quick TAP → an instant, FLAT, fast SNAP shot at base speed — great for a
///    foe out in the open, but it sails straight so cover stops it.
///  * HOLD → CHARGE the shot: a power gauge fills (and the sweep eases off so
///    you can fine-tune), then the shell looses the instant you RELEASE. A LOW
///    charge lobs a slow, high ARC that drops over a near crate onto a guarded
///    foe; a FULL charge is a flat long-range SNIPE. So every shell is an
///    arc-vs-direct choice — and charging keeps your finger down while enemies
///    keep firing, so a big lob EXPOSES you. (A one-frame down→up still fires a
///    snap shot, so tap-to-fire is intact.)
///
/// Feel / depth:
///  * Each tank has 3 HP with on-tank health pips, a white hit-flash and a
///    brief invulnerability window after taking a hit.
///  * Firing kicks the turret back (recoil) and spews a muzzle flash; the shell
///    leaves a smoke/spark trail and detonates on impact (particle burst +
///    screen shake + hit-stop + a lasting scorch decal).
///  * Destructible cover crates sit in the mid-field; shells chip and eventually
///    shatter them, so players must vary their aim to reach a guarded foe.
///  * First tank to land 3 hits wins; otherwise the most hits at the 40s time
///    limit. A round never ends before a short floor so it always plays out, and
///    the time limit always resolves it.
///
/// FAIR BOTS: they LEAD the arc — solving (by a cheap arc search) the launch
/// angle that drops a shell onto the nearest reachable ENEMY (a teammate is
/// never a target) — but only after a warm-up grace, and with a [BotProfile]
/// accuracy error plus a per-shot flinch so easy bots genuinely MISS often and
/// are beatable, not snipers. Each shot a bot also picks a CHARGE: it usually
/// snap-fires flat at base speed, but a stronger (more accurate) bot will
/// sometimes wind up a charged shot — and it solves the arc at the SAME charged
/// speed it will fire at, so a charged bot shell still lands instead of
/// overshooting.
///
/// MODES — every shell carries its owner's TEAM, and damage/scoring resolve by
/// team so a 2v2 plays as two squads, not four loners:
///  * TEAM 2v2 ([GameMode.team2v2] with an even seat count): seats split into
///    [Team.a] (even ids) vs [Team.b] (odd ids). FRIENDLY FIRE IS OFF — a shell
///    that reaches a teammate does no damage and fizzles. A team WINS when all
///    of the other team's tanks are downed (or, at the time limit, the team with
///    the most aggregate hits). Each tank still keeps its own player color, but
///    its tracer is TEAM-tinted so the table reads "blue squad vs red squad".
///  * FREE-FOR-ALL (FFA / duel / 1+CPU / any ODD seat count): each tank is its
///    own team, every kill scores individually, and the last tank standing (or
///    most hits) wins. Running 3p as an FFA is the deliberate fix for the unfair
///    1-vs-2 a 3-seat "team" split would create — nobody is the lone, ganged
///    side; each of the three fights for itself.
class TankDuel extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tank_duel',
        name: 'Tank Duel',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'TAP',
      );

  // ── Round / scoring tuning ──────────────────────────────────────────────────
  static const double _timeLimit = 40;
  static const int _hitsToWin = 3;
  static const int _maxHp = 3;
  // A round never resolves on the hits-target before this floor, so even a fast
  // opening flurry still plays out for a few seconds (never ends < ~4s).
  static const double _minRoundSec = 4.5;

  // ── Ballistics tuning ───────────────────────────────────────────────────────
  static const double _gravity = 360; // px/s^2 on shells
  // A shot's launch speed scales with charge: a snap TAP fires at the base
  // (tap) speed for a flat fast shot; a FULL charge fires at the max speed for a
  // long flat snipe. A LOW charge sits near the base speed but, because the
  // shell is slow, gravity bends it into a high lob that clears near cover.
  static const double _shellSpeed = 720; // base (tap / zero-charge) launch px/s
  static const double _shellSpeedMin = 440; // slowest charged launch (high lob)
  static const double _shellSpeedMax = 1180; // full-charge launch (flat snipe)
  static const double _shellLife = 4.5; // seconds before a shell fizzles
  static const double _shellRadius = 7;
  static const int _trailSamples = 16; // trail points kept per shell (long streak)
  static const double _outOfBoundsPad = 120;

  // ── Tank geometry tuning (mirrors TankRenderer so sim + visuals agree) ──────
  static const double _baseR = 26; // base tank radius (scaled to fit arena)
  static const double _turretPivotOut = 0.62; // pivot offset along edge normal
  static const double _barrelLen = 1.9; // barrel length / radius
  static const double _hitRadius = 0.95; // body hit radius / radius
  static const double _edgeInsetFactor = 0.085; // edge inset / min(arena side)
  static const double _sweepHalfBand = 0.62; // half sweep arc (radians)
  static const double _sweepSpeed = 1.35; // sweep angular speed (rad/s) — learnable
  static const double _holdAimScale = 0.4; // sweep eases to this while charging

  // ── Charge tuning (the per-shot power/range decision) ───────────────────────
  // While the finger is down, holdPower ramps 0→1 over [_chargeFullSec]. A
  // release under [_tapMaxSec] is a pure TAP (flat snap at base speed); any
  // longer hold looses a CHARGED shell whose speed is lerp(min,max,holdPower) —
  // low = slow high lob over near cover, full = flat long snipe.
  static const double _tapMaxSec = 0.12; // down→up faster than this = a pure tap
  static const double _chargeFullSec = 0.9; // hold this long to reach full power

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
  static const double _botWarmupSec = 1.5; // grace before bots start firing
  static const double _botBaseTolerance = 0.085; // good-aim cone at full accuracy
  static const double _botAimErrorRad = 0.42; // max steady aim error at accuracy 0
  static const double _botFlinchRad = 0.22; // extra random yank added per shot
  static const int _botArcCandidates = 13; // angles probed across the band
  static const int _botArcSteps = 26; // integration steps per probed arc
  static const double _botArcDt = 0.05; // arc-probe timestep (seconds)
  static const double _botWildChance = 0.4; // share of errorRate → wild shots
  // A bot picks a charge per shot: mostly a flat snap (zero charge), but a more
  // accurate bot sometimes winds up. It then solves the arc at the SAME charged
  // speed it will fire at, so the charged shell still lands.
  static const double _botChargeChance = 0.55; // accuracy × this = P(charge)
  static const double _botChargeMin = 0.45; // floor of a chosen bot charge
  static const double _botChargeMax = 1.0; // ceiling of a chosen bot charge

  // ── Climax (frenzy) tuning ──────────────────────────────────────────────────
  // The final ~30% of the match: bots fire faster (shorter re-arm) and a FRENZY
  // banner throbs, so the round visibly ramps to a finish.
  static const double _frenzyFrac = 0.7; // enters at this share of the limit
  static const double _frenzyBotReloadMul = 0.55; // bot re-arm × this in frenzy

  // ── Airdrop pickup (chaos) tuning ───────────────────────────────────────────
  // A supply crate any tank can shoot; popping it grants the shooter a brief
  // OVERCHARGE (double-damage, heavier) shells — a swingy surprise.
  static const double _airHalfFactor = 0.7; // crate half-size / baseR (× scale)
  static const double _airFirstDropSec = 5.0;
  static const double _airRespawnSec = 7.0;
  static const double _airLifeSec = 8.0;
  static const double _airAppearPerSec = 3.0;
  static const double _airBobPerSec = 2.2;
  static const double _airFieldInset = 0.14; // field inset / min(arena side)
  static const double _overchargeSec = 5.0; // buff duration
  static const int _overchargeDamage = 2; // damage per shell while overcharged
  static const Color _airColor = Color(0xFFFFE45C);

  // ── Gunner mascot tuning ─────────────────────────────────────────────────────
  // A small player-colored stick gunner rides each turret: idle while aiming,
  // flinches [StickFigure.hurt] when its tank is hit, cheers [victory] on the
  // winner, and slumps (hurt) atop a wreck. Anim advances on frame dt.
  static const double _gunnerScale = 0.42; // hero proportions × this (rides small)
  static const double _gunnerSeatOut = 0.34; // seat offset along turret "up" / r
  static const double _gunnerWreckSeatOut = 0.16; // lower, slumped onto a wreck

  // ── Team palette (tracers/aura in team mode read squad-colored) ──────────────
  static const Color _teamAColor = Color(0xFF36B6FF); // squad A — cool blue
  static const Color _teamBColor = Color(0xFFFF5A52); // squad B — hot red

  // ── Ambient ─────────────────────────────────────────────────────────────────
  static const int _emberCount = 26;
  static const double _horizonFactor = 0.34; // horizon Y / arena height

  late Juice _juice;
  final List<_Tank> _tanks = <_Tank>[];
  final List<_Shell> _shells = <_Shell>[];
  final List<_Crate> _crates = <_Crate>[];
  final List<_Scorch> _scorches = <_Scorch>[];
  final List<Offset> _embers = <Offset>[];

  // One small stick gunner per tank, keyed by playerId; advances on frame dt.
  final Map<int, StickFigure> _gunners = <int, StickFigure>{};

  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for ambient/flash
  late Size _size;
  late double _scale;
  late double _horizonY;
  late AirdropController _airdrop;
  late Rect _airField; // where airdrops may land
  // Team mode is on only for an even seat count in [GameMode.team2v2]; an odd
  // count (or ffa/duel) stays FFA so a 3p never splits into an unfair 1-vs-2.
  bool _teamMode = false;
  bool _frenzyAnnounced = false;
  bool _winnerCelebrated = false; // one-shot winner victory pulse fired
  int? _winnerId; // resolved winner (drives the hull victory pulse), or null
  Team? _winnerTeam; // resolved winning team in team mode (drives squad pulse)

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    // Team 2v2 only with an even seat count: an odd roster (1 / 3) stays FFA so
    // it never becomes a lop-sided 1-vs-2. Duel / ffa are always FFA too.
    _teamMode = ctx.mode == GameMode.team2v2 && ctx.players.length.isEven;
    final minSide = math.min(_size.width, _size.height);
    // Scale tanks down on small arenas, up modestly on big ones.
    _scale = (minSide / 520).clamp(0.7, 1.6);
    _horizonY = _size.height * _horizonFactor;
    _buildTanks();
    _buildCrates();
    _seedEmbers();
    final inset = minSide * _airFieldInset;
    _airField = Rect.fromLTRB(
        inset, inset, _size.width - inset, _size.height - inset);
    _airdrop = AirdropController(
      half: _baseR * _scale * _airHalfFactor,
      firstDropSec: _airFirstDropSec,
      respawnSec: _airRespawnSec,
      lifeSec: _airLifeSec,
      appearPerSec: _airAppearPerSec,
      bobPerSec: _airBobPerSec,
    );
    begin();
  }

  /// True once the match has entered its climax (frenzy) window.
  bool get _isFrenzy => _elapsed >= _timeLimit * _frenzyFrac;

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
      final color = Color(p.colorArgb);
      final team = _teamMode ? _teamOf(p) : Team.none;
      _tanks.add(_Tank(
        playerId: p.id,
        color: color,
        team: team,
        // The tracer reads SQUAD-colored in team mode (so two tanks on one team
        // share a shell color) but stays the player's own color in FFA.
        tracer: _teamMode ? _teamTint(team) : color,
        base: base,
        edge: edge,
        barrel: barrel,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
      // A small player-colored stick gunner rides the turret; it faces inward so
      // it reads as crewing a barrel that points into the field.
      _gunners[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_gunnerScale),
        style: _gunnerStyle(color),
        facing: inward.dx >= 0 ? 1.0 : -1.0,
      )..setLoco(LocoState.idle);
    }
  }

  /// Squad for [p] in team mode: an explicit [PlayerSlot.team] wins, else even
  /// ids are [Team.a] and odd ids [Team.b] (matching the soccer split).
  Team _teamOf(PlayerSlot p) {
    if (p.team == Team.a || p.team == Team.b) return p.team;
    return p.id.isEven ? Team.a : Team.b;
  }

  /// Squad tracer/aura tint for a [team] (only used in team mode).
  Color _teamTint(Team team) => team == Team.b ? _teamBColor : _teamAColor;

  /// Bright stick-gunner style: player-color fill with a brightened neon outline
  /// + glow (same recipe sumo/soccer use for their figures).
  StickStyle _gunnerStyle(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 3,
        lineWidth: 1.0,
        rimAlpha: 0.26,
        shadowAlpha: 0.0, // tank already lays its own contact shadow
        gradientBottom: 0.5,
        smearAlpha: 0.2,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

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
    if (status != MiniGameStatus.running) return;
    final tank = _tankOf(input.playerId);
    if (tank == null) return;

    switch (input.phase) {
      case InputPhase.down:
        // Begin a hold: power starts charging and the sweep eases so the player
        // can fine-tune. A quick release snap-fires flat; a longer hold looses a
        // charged shell whose speed (and thus arc) scales with the charge.
        tank.holding = true;
        tank.holdSec = 0;
        tank.holdPower = 0;
      case InputPhase.up:
        if (tank.holding) {
          final power = tank.holdSec <= _tapMaxSec ? 0.0 : tank.holdPower;
          tank.holding = false;
          tank.holdSec = 0;
          tank.holdPower = 0;
          // Release always looses — a tap (power 0) still fires a flat snap.
          _fire(input.playerId, power);
        }
      case InputPhase.holdTick:
        break; // hold time accrues in update() for frame-rate independence
    }
  }

  /// Launch speed for a shot of the given [power] (0..1). A pure tap (power 0)
  /// fires flat at the base speed; any charge lerps from a slow high-lob speed
  /// up to a fast flat-snipe speed.
  double _launchSpeedFor(double power) {
    if (power <= 0) return _shellSpeed;
    return lerpD(_shellSpeedMin, _shellSpeedMax, power.clamp(0.0, 1.0));
  }

  void _fire(int id, [double power = 0]) {
    final tank = _tankOf(id);
    if (tank == null) return;
    final dir = tank.barrel.direction;
    final muzzle = _muzzleOf(tank);
    final speed = _launchSpeedFor(power);
    _shells.add(_Shell(
      pos: muzzle,
      vel: dir * speed,
      ownerId: id,
      // Squad-tinted tracer in team mode (two teammates fire the same color),
      // the player's own color in FFA — so 4 tanks' shells read at a glance.
      color: tank.tracer,
    ));
    tank.recoil = _recoilSec;
    tank.muzzle = _muzzleSec;
    // Muzzle blast: a hot forward cone of sparks + a backward smoke kick, so a
    // shot reads as powerful even when it sails into open field. A charged shot
    // throws a fatter, faster cone so its extra power reads at a glance.
    final p = power.clamp(0.0, 1.0);
    final baseAngle = math.atan2(dir.dy, dir.dx);
    _juice.particles.burst(
      at: muzzle,
      count: 10 + (8 * p).round(),
      color: const Color(0xFFFFE6A0),
      speed: 280 + 200 * p,
      baseAngle: baseAngle,
      spread: math.pi * 0.45,
      size: 6 + 2 * p,
      gravity: 120,
      life: 0.32,
    );
    _juice.particles.burst(
      at: muzzle,
      count: 5,
      color: const Color(0xFFB9C2CF).withValues(alpha: 0.7),
      speed: 120,
      baseAngle: baseAngle + math.pi, // smoke kicks back off the muzzle
      spread: math.pi * 0.6,
      size: 7,
      gravity: -40,
      life: 0.5,
    );
    _juice.shake.light();
    _juice.hitStop.trigger(0.025); // a tiny kick so the shot has weight
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
      // Holding eases the sweep for fine-tuning AND charges power; release fires.
      final aimDt = t.holding ? sdt * _holdAimScale : sdt;
      t.barrel.update(aimDt);
      if (t.holding) {
        t.holdSec += dt;
        t.holdPower = (t.holdPower + dt / _chargeFullSec).clamp(0.0, 1.0);
      }
      t.tickTimers(dt, _flashSec, _recoilSec, _muzzleSec, _invulnSec);
      t.tickOvercharge(dt);
    }
    for (final c in _crates) {
      c.tickFlash(dt, _crateFlashSec);
    }
    _syncGunners(dt);
    _ageScorches(dt);
    _airdrop.tick(dt, ctx.rng, _airField);
    _driveBots(dt);
    _stepShells(sdt);
    _announceFrenzy();
    _checkEnd();
  }

  /// Announce the climax once (shake + popup); banner + faster bots then carry.
  void _announceFrenzy() {
    if (_frenzyAnnounced || !_isFrenzy) return;
    _frenzyAnnounced = true;
    _juice.shake.medium();
    _juice.popup(Offset(_size.width / 2, _size.height * 0.22), 'FRENZY!',
        const Color(0xFFFF7A2E),
        size: 38);
  }

  void _ageScorches(double dt) {
    for (final s in _scorches) {
      s.life -= dt;
    }
    _scorches.removeWhere((s) => s.life <= 0);
  }

  /// Advance every gunner's animation on frame dt (like the other figure games).
  /// A live gunner that isn't mid-action settles back to [LocoState.idle]; a
  /// downed gunner is left in whatever clip it holds (the wreck draws it slumped)
  /// and still ticks so its pose ages instead of freezing.
  void _syncGunners(double dt) {
    for (final t in _tanks) {
      final g = _gunners[t.playerId];
      if (g == null) continue;
      if (t.hp > 0 && !g.actionPlaying) g.setLoco(LocoState.idle);
      g.update(dt);
    }
  }

  // ── Bots: lead the arc, then fire on cadence ────────────────────────────────

  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // grace so the human gets first move
    // In the frenzy climax bots re-arm faster: their reaction clock runs at an
    // accelerated rate so shells come thicker as the round closes.
    final clockDt = _isFrenzy ? dt / _frenzyBotReloadMul : dt;
    for (final t in _tanks) {
      final clock = t.clock;
      if (clock == null) continue;
      if (!clock.tick(clockDt)) continue;
      // Pick this shot's charge: mostly a flat snap, but a more accurate bot
      // sometimes winds up a charged lob/snipe. The arc is then SOLVED at this
      // charge's speed so the shell lands rather than overshooting.
      final charge = _botChargeForShot();
      if (_botShouldFire(t, _launchSpeedFor(charge))) _fire(t.playerId, charge);
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  /// The charge a bot commits to this shot. Accuracy gates how often it bothers
  /// to wind up (weaker bots almost always snap-fire flat); when it does charge
  /// it picks a random power in the usable band. Deterministic via [ctx.rng].
  double _botChargeForShot() {
    final accuracy = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    if (!ctx.rng.chance(accuracy * _botChargeChance)) return 0;
    return ctx.rng.range(_botChargeMin, _botChargeMax);
  }

  /// A bot fires when its live sweep angle is within an accuracy-scaled cone of
  /// the launch angle that would land a shell — fired at [shellSpeed] — on the
  /// nearest reachable target.
  ///
  /// Fairness: the "wanted" angle is corrupted by a steady accuracy error PLUS a
  /// fresh per-shot flinch. At low accuracy these are large versus the firing
  /// cone, so an easy bot commits the trigger while badly off-aim — it fires
  /// and *misses* often rather than waiting for a perfect line-up. A small
  /// chance of an extra wild shot keeps it from ever stalling.
  bool _botShouldFire(_Tank shooter, double shellSpeed) {
    final accuracy = ctx.botProfile.accuracy.clamp(0.2, 1.0);
    final tol = _botBaseTolerance / accuracy;
    final best = _bestLaunchAngle(shooter, shellSpeed);
    if (best != null) {
      final miss = 1 - accuracy;
      // Steady bias + a fresh flinch each shot; both shrink as accuracy rises.
      final err = ctx.rng.jitter(miss * _botAimErrorRad) +
          ctx.rng.jitter(miss * _botFlinchRad);
      if (wrapAngle(shooter.barrel.angle - (best + err)).abs() <= tol) {
        return true;
      }
    }
    return ctx.rng.chance(ctx.botProfile.errorRate * _botWildChance);
  }

  /// Best lead angle for [shooter] firing at [shellSpeed] (see
  /// [TankFx.bestLaunchAngle]); builds the live opponent-pivot list and
  /// delegates the arc search. A faster (charged) shell flies flatter, so the
  /// solved angle differs — keeping a charged bot shot honest.
  double? _bestLaunchAngle(_Tank shooter, double shellSpeed) {
    // Bots aim at ENEMIES only: a teammate (team mode) is never targeted, and a
    // downed tank is skipped so the bot keeps hunting a live foe.
    final targets = <Offset>[
      for (final t in _tanks)
        if (t.playerId != shooter.playerId &&
            t.hp > 0 &&
            !_areAllies(shooter, t))
          _turretPivotOf(t),
    ];
    return TankFx.bestLaunchAngle(
      lo: shooter.barrel.minAngle,
      hi: shooter.barrel.maxAngle,
      muzzle: _muzzleOf(shooter),
      targets: targets,
      shellSpeed: shellSpeed,
      gravity: _gravity,
      candidates: _botArcCandidates,
      steps: _botArcSteps,
      arcDt: _botArcDt,
      reach: _baseR * _scale * 2.2,
      bounds: _size,
      outPad: _outOfBoundsPad,
    );
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
      if (_airdrop.contains(pos)) {
        _popAirdrop(s, pos);
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
    final owner = _tankOf(ownerId);
    for (final t in _tanks) {
      if (t.playerId == ownerId) continue;
      // FRIENDLY FIRE OFF: in team mode a shell passes harmlessly THROUGH a
      // teammate (never a valid hit), so it can sail on to an enemy beyond or
      // fizzle. In FFA every other tank is fair game.
      if (owner != null && _areAllies(owner, t)) continue;
      // A downed tank (hp 0) is no longer a target: it isn't removed from the
      // list and its post-down invuln expires, so without this it would keep
      // absorbing shells once a round runs on past a pre-[_minRoundSec] down —
      // re-firing the 'DIRECT HIT!' big-moment and re-scoring on a corpse.
      if (t.hp <= 0) continue;
      if (t.invuln > 0) continue;
      final reach = _baseR * _scale * _hitRadius + _shellRadius;
      if ((_turretPivotOf(t) - pos).distance <= reach) return t.playerId;
    }
    return null;
  }

  /// True when [a] and [b] are on the same squad (team mode only). In FFA every
  /// [Team.none] tank is its own side, so this is always false.
  bool _areAllies(_Tank a, _Tank b) =>
      _teamMode && a.team != Team.none && a.team == b.team;

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
    // An overcharged shooter deals double damage (and scores both pips), so a
    // popped airdrop is a real swing.
    final damage = shooter.overcharged ? _overchargeDamage : 1;
    victim.hp = (victim.hp - damage).clamp(0, _maxHp);
    victim.flash = _flashSec;
    victim.invuln = _invulnSec;
    addScore(shooterId, damage);
    _scorches.add(_Scorch(at: at));
    // The victim's gunner flinches; on the killing blow it slumps (the wreck
    // draw keeps it slumped). Guarded — a missing/already-playing figure no-ops.
    final gunner = _gunners[victimId];
    if (gunner != null && !gunner.actionPlaying) gunner.hurt();

    // The signature beat is a DIRECT HIT that DOWNS a tank (its last pip): a
    // single big-moment (burst + heavy shake + slow-mo + zoom toward the hit +
    // flash + 'DIRECT HIT!' banner + haptic). A non-downing clinch keeps the KO
    // flourish; ordinary chip-hits keep the snappy HIT! popup. The explosion
    // particles fire on every hit, but its screen-jolt is suppressed on the
    // down/KO branches because bigMoment/ko already own a heavier shake +
    // hit-stop — stacking explode's jolt too would double the screen-shake.
    final downed = victim.hp <= 0;
    final clinch = !downed && scoreOf(shooterId) >= _hitsToWin;
    TankFx.explode(_juice, at, shooter.color,
        heavy: true, jolt: !(downed || clinch));
    if (downed) {
      // Stamp the down time so the renderer can age its burning WRECK + smoke
      // column. Visual only — hp/score/removal already handled above.
      if (victim.downedAt < 0) victim.downedAt = _animClock;
      _juice.bigMoment(at, shooter.color, banner: 'DIRECT HIT!');
    } else if (clinch) {
      _juice.ko(at, shooter.color);
    } else {
      _juice.popup(at.translate(0, -_baseR * _scale), 'HIT!', shooter.color,
          size: 26);
    }
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
      TankFx.explode(_juice, crate.rect.center, shell.color, heavy: false);
      _scorches.add(_Scorch(at: crate.rect.center));
    }
  }

  /// A shell popped the airdrop: grant the shooter a brief OVERCHARGE (double
  /// damage, heavier shells) + a gold burst + popup, then re-arm the drop.
  void _popAirdrop(_Shell shell, Offset at) {
    final shooter = _tankOf(shell.ownerId);
    if (shooter != null) shooter.overcharge = _overchargeSec;
    _airdrop.consume();
    TankFx.explode(_juice, at, _airColor, heavy: false);
    _juice.particles.burst(
      at: at,
      count: 20,
      color: _airColor,
      speed: 320,
      size: 6,
      gravity: 200,
      life: 0.6,
    );
    _juice.popup(at.translate(0, -_baseR * _scale), 'OVERCHARGE!', _airColor,
        size: 28);
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
    // Past the floor (so an early flurry can't end it in under a few seconds) a
    // round resolves on the win condition; the time limit always ends it.
    //  * TEAM: a team wins the instant the OTHER team is fully downed.
    //  * FFA: any tank reaching the hits-target wins (and a wipe-out — only one
    //    tank left alive — also ends it so a sweep doesn't idle out the clock).
    final pastFloor = _elapsed >= _minRoundSec;
    final decided = pastFloor &&
        (_teamMode ? _aTeamIsWiped() : _ffaDecided());
    if (decided || _elapsed >= _timeLimit) {
      _celebrateWinner(); // mark the winner + pop its victory beat (visual only)
      _juice.confetti(_size);
      _finishMatch();
    }
  }

  /// FFA finish trigger: someone hit the target, or only one tank is still up.
  bool _ffaDecided() {
    if (_tanks.any((t) => scoreOf(t.playerId) >= _hitsToWin)) return true;
    return _aliveCount() <= 1 && _tanks.length > 1;
  }

  /// Team finish trigger: at least one squad has every tank downed (so the other
  /// squad has won). Guarded so a not-yet-engaged round doesn't false-trigger.
  bool _aTeamIsWiped() {
    final aAlive = _tanks.any((t) => t.team == Team.a && t.hp > 0);
    final bAlive = _tanks.any((t) => t.team == Team.b && t.hp > 0);
    return !aAlive || !bAlive;
  }

  int _aliveCount() => _tanks.where((t) => t.hp > 0).length;

  /// Aggregate hits scored by all tanks on [team].
  num _teamScore(Team team) {
    num sum = 0;
    for (final t in _tanks) {
      if (t.team == team) sum += scoreOf(t.playerId);
    }
    return sum;
  }

  /// Resolve the round. FFA ranks by each tank's own hits. TEAM ranks the whole
  /// winning squad above the losing one (by aggregate team hits, then a tank's
  /// own hits, then seat) so 2v2 finishes as "blue beat red", not four loners —
  /// while [finalScores] still reports each player's individual hits.
  void _finishMatch() {
    if (!_teamMode) {
      finishByScore();
      return;
    }
    // A strict, total team order so teammates are ALWAYS adjacent in the final
    // ranking (no interleaving even when aggregate hits tie): a living squad
    // beats a wiped one; then more aggregate team hits; then a stable squad
    // ordinal (Team.a first) as the final, deterministic tiebreak.
    final winning = _winnerTeam ?? Team.a;
    int teamKey(Team t) {
      final wiped = !_tanks.any((x) => x.team == t && x.hp > 0);
      final score = _teamScore(t).toInt();
      final ordinal = t == winning ? 0 : 1; // resolved winner always sorts first
      return (wiped ? 1 : 0) * 1000000 - score * 10 + ordinal;
    }
    final ids = ctx.players.map((p) => p.id).toList()
      ..sort((a, b) {
        final ta = _tankOf(a), tb = _tankOf(b);
        final ka = ta == null ? 0 : teamKey(ta.team);
        final kb = tb == null ? 0 : teamKey(tb.team);
        if (ka != kb) return ka.compareTo(kb);
        // Same squad: better individual shooter first, then id (stable).
        final cmp = scoreOf(b).compareTo(scoreOf(a));
        return cmp != 0 ? cmp : a.compareTo(b);
      });
    finishWith(
        WinResult(ranking: ids, finalScores: Map<int, num>.from(scores.byPlayer)));
  }

  /// One-shot winner celebration at finish. FFA: pick the top-scoring tank
  /// (ties → first seat, matching the scoreboard), cheer its gunner and pop a
  /// [Juice.bigMoment] at its hull; [_winnerId] then drives its victory pulse.
  /// TEAM: delegate to [_celebrateWinningTeam] (whole squad cheers + pulses).
  /// Reads only scores/hp; changes no scoring/ranking.
  void _celebrateWinner() {
    if (_winnerCelebrated) return;
    _winnerCelebrated = true;
    if (_teamMode) {
      _celebrateWinningTeam();
      return;
    }
    _Tank? best;
    var bestScore = -1.0;
    for (final t in _tanks) {
      final double s = scoreOf(t.playerId).toDouble();
      if (s > bestScore) {
        bestScore = s;
        best = t;
      }
    }
    if (best == null) return;
    _winnerId = best.playerId;
    _cheerGunner(best);
    _juice.bigMoment(_turretPivotOf(best), best.color, banner: 'WINNER!');
  }

  /// Team finish beat: pick the winning squad (a wiped enemy, else more aggregate
  /// hits; ties → Team.a) and pop a victory cheer + a [Juice.bigMoment] at each
  /// surviving member. [_winnerTeam] then drives the squad hull pulse.
  void _celebrateWinningTeam() {
    final aWiped = !_tanks.any((t) => t.team == Team.a && t.hp > 0);
    final bWiped = !_tanks.any((t) => t.team == Team.b && t.hp > 0);
    final Team winner;
    if (aWiped != bWiped) {
      winner = aWiped ? Team.b : Team.a;
    } else {
      winner = _teamScore(Team.b) > _teamScore(Team.a) ? Team.b : Team.a;
    }
    _winnerTeam = winner;
    var fired = false;
    for (final t in _tanks) {
      if (t.team != winner) continue;
      _winnerId ??= t.playerId; // first surviving member drives single-hull reads
      if (t.hp > 0) _cheerGunner(t);
      if (!fired) {
        fired = true;
        _juice.bigMoment(_turretPivotOf(t), _teamTint(winner),
            banner: 'TEAM WINS!');
      }
    }
  }

  /// Switch a tank's gunner into its arms-up [StickFigure.victory] cheer.
  void _cheerGunner(_Tank t) {
    final g = _gunners[t.playerId];
    if (g == null) return;
    g.setLoco(LocoState.idle);
    g.victory();
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
    _juice.applyWorldTransform(canvas);

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

    final drop = _airdrop.crate;
    if (drop != null) TankFx.drawAirdrop(canvas, drop);

    // Aim guides first (under the live tanks), then the tanks themselves. A
    // downed tank is drawn as a burning WRECK + smoke column instead of an intact
    // hull, so a KO leaves a smoldering hulk on the field.
    for (final t in _tanks) {
      if (t.hp <= 0) continue;
      TankRenderer.drawAimGuide(canvas, _viewOf(t));
    }
    // Team mode: a faint squad-colored ground ring under every live tank so the
    // table reads "blue squad vs red squad" at rest (matching the shell tracers),
    // drawn under the hulls so it never muddies them.
    if (_teamMode) {
      for (final t in _tanks) {
        if (t.hp > 0) _drawTeamRing(canvas, t);
      }
    }
    for (final t in _tanks) {
      if (t.hp <= 0) {
        TankRenderer.drawWreck(canvas, _wreckOf(t));
        _drawGunner(canvas, t, downed: true);
        continue;
      }
      if (t.overcharged) _drawOverchargeRing(canvas, t);
      TankRenderer.drawTank(canvas, _viewOf(t));
      _drawGunner(canvas, t, downed: false);
    }

    for (final s in _shells) {
      TankRenderer.drawShell(canvas, s.view());
    }

    _juice.render(canvas);
    canvas.restore();

    // Screen-space overlays (after the world transform is restored so they are
    // never shaken or zoomed by the camera punch): the FRENZY banner + the
    // cinematic flash/banner from bigMoment.
    if (_isFrenzy) {
      TankFx.drawFrenzyBanner(canvas, size, 1.0, _animClock);
    }
    _juice.renderOverlay(canvas, size);
  }

  /// A faint, steady squad-colored ground ring under a tank (team mode only) so
  /// the two teams read apart at a glance even when nobody is firing.
  void _drawTeamRing(Canvas canvas, _Tank t) {
    final r = _baseR * _scale;
    final tint = _teamTint(t.team);
    final at = t.base + t.edge.outward * (r * _shadowDrop);
    canvas.drawCircle(
      at,
      r * 1.7,
      Paint()..color = tint.withValues(alpha: 0.10),
    );
    canvas.drawCircle(
      at,
      r * 1.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.07)
        ..color = tint.withValues(alpha: 0.5),
    );
  }

  static const double _shadowDrop = 0.55; // mirrors TankRenderer shadow offset

  /// A pulsing gold ring under an overcharged tank so the table sees who is
  /// dangerous right now (double-damage shells).
  void _drawOverchargeRing(Canvas canvas, _Tank t) {
    final r = _baseR * _scale;
    final pulse = 0.5 + 0.5 * math.sin(_animClock * 6.0);
    canvas.drawCircle(
      _turretPivotOf(t),
      r * (1.2 + 0.15 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = _airColor
            .withValues(alpha: (0.5 + 0.3 * pulse).clamp(0.0, 1.0)),
    );
  }

  /// Draw a tank's stick gunner riding the turret. It's anchored a touch above
  /// the turret dome in SCREEN space (always upright, never rotated by the tank's
  /// edge) so a bottom/top/side tank all read "a little crew member on top". On a
  /// [downed] wreck it sits lower (slumped into the hulk). Guarded + wrapped so a
  /// missing figure or a paint hiccup never throws from render.
  void _drawGunner(Canvas canvas, _Tank t, {required bool downed}) {
    final g = _gunners[t.playerId];
    if (g == null) return;
    final r = _baseR * _scale;
    final pivot = _turretPivotOf(t);
    // Seat the pelvis above the dome; the legs (~0.6r at this scale) then rest
    // near the turret top. A wreck seat sits lower so the gunner slumps onto it.
    final seatOut = downed ? _gunnerWreckSeatOut : _gunnerSeatOut;
    final root = pivot + const Offset(0, -1) * (r * (_turretR + seatOut));
    g.render(canvas, root);
  }

  static const double _turretR = 0.78; // mirrors TankRenderer turret radius / r

  TankView _viewOf(_Tank t) {
    // Invuln phase counts blink cycles; pass the phase index so the renderer can
    // strobe the body without us mutating anything during render.
    final blinkPhase =
        t.invuln > 0 ? (_animClock * _invulnBlinkHz) % 2 + 1 : 0.0;
    // Precision/charge lights up only once a hold passes the tap threshold, so a
    // quick snap tap stays clean; [charge] then drives a power gauge + a reticle
    // that creeps out along the barrel toward the predicted range.
    final charging = t.holding && t.holdSec > _tapMaxSec;
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
      precision: charging,
      charge: charging ? t.holdPower : 0.0,
      victory: _isWinner(t) ? 1.0 : 0.0,
    );
  }

  /// True once the round is over and [t] is on the winning side — used to pulse
  /// the winning hull(s) bright. In FFA that's the single top tank; in team mode
  /// it's every tank on the winning squad. Reads only resolved ids, mutates none.
  bool _isWinner(_Tank t) {
    if (status != MiniGameStatus.finished) return false;
    if (_teamMode && _winnerTeam != null) return t.team == _winnerTeam;
    return t.playerId == _winnerId;
  }

  /// Snapshot a downed tank's wreck (burning hulk + smoke column). The wreck age
  /// drives ember flicker + smoke rise; the ambient clock drives flicker phase.
  WreckView _wreckOf(_Tank t) {
    final age = t.downedAt < 0 ? 0.0 : math.max(0.0, _animClock - t.downedAt);
    return WreckView(
      base: t.base,
      color: t.color,
      edge: t.edge,
      aimAngle: t.barrel.angle,
      scale: _scale,
      age: age,
      t: _animClock,
    );
  }
}

/// One tank. Mutable round-scoped state (allowed for the duration of one round).
class _Tank {
  final int playerId;
  final Color color; // the player's own color (hull/turret tint)
  final Team team; // squad in team mode; [Team.none] in FFA
  final Color tracer; // shell tracer color: squad-tinted in team mode, else own
  final Offset base; // turret-base anchor in arena px
  final TankEdge edge;
  final AimSweep barrel;
  final ReactionClock? clock; // null for human seats
  int hp = TankDuel._maxHp;
  double flash = 0; // hit-flash timer
  double recoil = 0; // recoil timer
  double muzzle = 0; // muzzle-flash timer
  double invuln = 0; // invulnerability timer
  bool holding = false; // finger down → charging power + sweep eased
  double holdSec = 0; // how long the current hold has lasted
  double holdPower = 0; // 0..1 charge accrued while holding (scales launch speed)
  double overcharge = 0; // seconds of airdrop double-damage buff remaining
  double downedAt = -1; // _animClock when destroyed (-1 = still alive); wreck age

  _Tank({
    required this.playerId,
    required this.color,
    required this.team,
    required this.tracer,
    required this.base,
    required this.edge,
    required this.barrel,
    this.clock,
  });

  bool get overcharged => overcharge > 0;

  void tickTimers(double dt, double flashSec, double recoilSec,
      double muzzleSec, double invulnSec) {
    if (flash > 0) flash = (flash - dt).clamp(0, flashSec);
    if (recoil > 0) recoil = (recoil - dt).clamp(0, recoilSec);
    if (muzzle > 0) muzzle = (muzzle - dt).clamp(0, muzzleSec);
    if (invuln > 0) invuln = (invuln - dt).clamp(0, invulnSec);
  }

  void tickOvercharge(double dt) {
    if (overcharge > 0) overcharge = math.max(0, overcharge - dt);
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
