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
import 'soccer_render.dart';
import 'striker.dart';

/// One-Touch Soccer — a rect-bounded pitch with a neutral ball (id -1) and one
/// stick striker per seat, scored into a goal at each end.
///
/// CONTROL (the heart of it — full player agency, never auto-aimed):
///  * Each striker has an AIM ARROW (in the player's color) that constantly
///    SWEEPS around it. The player decides WHERE to go by timing that sweep.
///  * Quick TAP  → a snappy DASH in the arrow's current direction (reposition,
///    intercept, chase a loose ball — your call, not the game's).
///  * HOLD then release → the aim LOCKS and a charge meter fills; releasing
///    fires a powerful POWER-KICK LUNGE in the locked direction (power ∝ charge).
///    Drive into the ball mid-lunge to launch it — a charged strike near the
///    ball is a satisfying "thwack" toward the goal you aimed at.
///  So the player chooses the run AND the shot: nothing homes onto the ball.
///
/// PACING: a real back-and-forth match — first to [_goalsToWin] goals or the
/// [_timeLimit] expires. The ball starts dead at center, there is a brief
/// kickoff pause after every goal, and bots warm up before engaging, so the
/// ball is never instantly scored and the midfield is genuinely contested.
///
/// Feel: the ball is light so kicks fly, carries spin, leaves a motion trail and
/// bounces off the walls. Goals trigger a net-bulge flash + big "GOAL!" popup +
/// confetti + slow-mo + crowd roar.
///
/// Teams / goals: even ids / [Team.a] attack the RIGHT goal, odd ids / [Team.b]
/// attack the LEFT goal. A goal awards a point to every player on the scoring
/// side (aggregated for 2v2). Bots warm up, then position toward the ball and
/// aim a charged strike at the opponent goal with [BotProfile]-scaled error;
/// the rear player on a 2-player side drops back to guard its own net.
class OneTouchSoccer extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'one_touch_soccer',
        name: 'One-Touch Soccer',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'TAP / HOLD',
      );

  // ── Match / arena / sim tuning (no magic numbers inline) ────────────────────
  static const double _timeLimit = 40;
  static const int _goalsToWin = 3; // first side to this many goals wins early
  static const int _ballId = -1;
  static const double _pitchInsetFactor = 0.055;
  static const double _ballRadiusFactor = 0.028;
  static const double _playerRadiusFactor = 0.05;
  static const double _ballMass = 0.5; // lighter than strikers so kicks fly
  static const double _pitchFriction = 0.985; // grass: ball coasts then settles
  static const double _ballRestitution = 0.78; // wall bounce damping
  static const double _goalMouthFraction = 0.42; // of pitch height, centered
  static const double _figureScale = 0.95;

  // ── Aim + charge control tuning (mirrors Sumo's striker feel) ───────────────
  static const double _aimSweepSpeed = 2.0; // rad/s, ~3.1s per revolution
  static const double _chargeTimeSec = 0.55; // hold time to full charge
  static const double _cooldownSec = 0.2; // snappy recovery between actions
  static const double _dashPerSecond = 2.2; // quick tap ≈ pitch.w*2.2 /s impulse
  static const double _kickPerSecond = 4.8; // full charge lunge impulse
  static const double _selfPushback = 0.05; // tiny recoil opposite a kick
  static const double _trailLifeSec = 0.22;

  // ── Ball-strike tuning (driving the ball with a lunge) ──────────────────────
  static const double _strikeRangeFactor = 2.6; // “near ball” = within this*radii
  static const double _strikeBaseScale = 1.3; // dash contact kick strength
  static const double _strikeChargeScale = 3.4; // + this*charge at point-blank
  static const double _spinPerSpeed = 0.012; // ball spin gain / speed
  static const double _spinDecayPerSec = 1.6;
  static const double _squashDecayPerSec = 4.5;
  static const double _hardKickSpeed = 360.0; // ball speed above → thwack juice
  static const int _trailLen = 12;

  // ── Goal / celebration tuning ───────────────────────────────────────────────
  static const double _kickoffPauseSec = 1.25; // sim frozen after a goal
  static const double _bulgeDurationSec = 0.9; // net ripple length
  static const double _goalHitStopSec = 0.5; // slow-mo on a goal
  static const double _goalHitStopScale = 0.18;

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 1.5; // grace before bots engage
  static const double _botGuardDepthFactor = 0.22; // keeper x offset from wall
  static const double _botGuardLaneGain = 0.7; // how hard keeper tracks ball y
  static const double _botStrikeRangeFactor = 3.2; // charge a kick within this
  static const double _botChaseRangeFactor = 9.0; // dash to close within this
  static const double _botAimErrorRad = 0.5; // aim jitter at accuracy 0
  static const double _botCarrySpeed = 150.0; // skip action while already fast

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _leftAccent = Color(0xFF4D9BFF); // left goal / side B
  static const Color _rightAccent = Color(0xFFFF5A5A); // right goal / side A
  static const Color _confettiA = Color(0xFFFFC93C);
  static const Color _confettiB = Color(0xFF54E08A);
  static const Color _dust = Color(0xFFDFF3E4);
  static const Color _spark = Color(0xFFFFFFFF);
  static const double _runSpeed = 55.0;

  late Juice _juice;
  late PushArena _arena;
  late Rect _pitch;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0;
  double _kickoffPause = 0; // > 0 while the post-goal pause runs
  double _leftBulge = 0; // net ripple timers
  double _rightBulge = 0;
  double _ballSpin = 0; // radians, for the seam hint
  double _ballSquash = 0; // 0..1, flatten on hard hits
  Offset _ballLastDir = Offset.zero;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, Striker> _strikers = <int, Striker>{};

  /// True if this player attacks the RIGHT goal (else the LEFT goal).
  final Map<int, bool> _attacksRight = <int, bool>{};

  /// Recent ball centers (newest last) for the motion trail.
  final List<Offset> _ballTrail = <Offset>[];

  late Body _ball;
  late double _ballRadius;
  late double _playerRadius;
  Rect _goalMouth = Rect.zero; // vertical span both goals share
  double _leftLine = 0;
  double _rightLine = 0;
  bool _hasLeftSide = false; // someone defends/attacks each goal
  bool _hasRightSide = false;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    final inset = math.min(_size.width, _size.height) * _pitchInsetFactor;
    _pitch = Rect.fromLTRB(
      inset,
      inset,
      _size.width - inset,
      _size.height - inset,
    );
    final minSide = math.min(_pitch.width, _pitch.height);
    _ballRadius = minSide * _ballRadiusFactor;
    _playerRadius = minSide * _playerRadiusFactor;

    _arena = PushArena(
      center: _pitch.center,
      ringRadius: _pitch.shortestSide / 2, // unused in rect mode but required
      friction: _pitchFriction,
      restitution: _ballRestitution,
      bounds: _pitch,
    );

    _computeGoals();
    _buildBall();
    _buildPlayers();
    begin();
  }

  void _computeGoals() {
    final mouthHeight = _pitch.height * _goalMouthFraction;
    final top = _pitch.center.dy - mouthHeight / 2;
    _goalMouth =
        Rect.fromLTRB(_pitch.left, top, _pitch.right, top + mouthHeight);
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
      mass: _ballMass,
    );
    _arena.add(_ball);
    _ballTrail.add(_ball.pos);
  }

  void _buildPlayers() {
    final players = ctx.players;
    for (final p in players) {
      final attacksRight = _resolveSide(p);
      _attacksRight[p.id] = attacksRight;
      if (attacksRight) {
        _hasRightSide = true;
      } else {
        _hasLeftSide = true;
      }

      // Spawn each player on its own defending half, stacked vertically.
      final defendLeft = attacksRight; // attack right ⇒ defend/start on left
      final sameSide =
          players.where((q) => _resolveSide(q) == attacksRight).toList();
      final indexOnSide = sameSide.indexWhere((q) => q.id == p.id);
      final lane = (indexOnSide + 1) / (sameSide.length + 1);
      final x = defendLeft
          ? _pitch.left + _pitch.width * 0.27
          : _pitch.right - _pitch.width * 0.27;
      final y = _pitch.top + _pitch.height * lane;
      final pos = Offset(x, y);
      _arena.add(Body(id: p.id, pos: pos, radius: _playerRadius));

      _figures[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_figureScale),
        style: _styleFor(Color(p.colorArgb)),
        facing: attacksRight ? 1.0 : -1.0,
      )..setLoco(LocoState.idle);

      // Aim starts pointing up-field (toward the opponent goal) so the first
      // tap is sensible before the player takes over the sweep.
      final towardGoal = attacksRight ? 0.0 : math.pi;
      _strikers[p.id] = Striker(aim: towardGoal);
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Bright kit style: player-color fill with a brightened outline + glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 4,
        lineWidth: 1.0,
        rimAlpha: 0.26,
        shadowAlpha: 0.0, // renderer draws its own contact shadow
        gradientBottom: 0.5,
        smearAlpha: 0.26,
      );

  /// Even ids / Team.a attack right; odd ids / Team.b attack left.
  bool _resolveSide(PlayerSlot p) {
    if (p.team == Team.a) return true;
    if (p.team == Team.b) return false;
    return p.id.isEven;
  }

  // ── Input: hold to charge + aim, release to dash / power-kick ────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final s = _strikers[input.playerId];
    final body = _bodyOf(input.playerId);
    if (s == null || body == null) return;
    // Inputs queued during the kickoff pause would fire on a frozen ball; ignore.
    if (_kickoffPause > 0) return;

    switch (input.phase) {
      case InputPhase.down:
        if (s.ready) s.charging = true; // lock aim, begin charging
      case InputPhase.up:
        if (s.charging) {
          s.charging = false;
          _commitAction(input.playerId, body, s.aim, s.charge);
          s.charge = 0;
        }
      case InputPhase.holdTick:
        break; // charge accrues in update() for frame-rate independence
    }
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    // Juice always runs on real dt; the sim runs on hit-stop-scaled dt.
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _tickTimers(dt);
    _tickStrikers(dt);

    // During the kickoff pause the world is frozen (only juice + timers run).
    if (_kickoffPause > 0) {
      _syncFigures(0);
      _resolveOutcome();
      return;
    }

    _driveBots(dt);
    _arena.update(sdt);

    _updateBall(sdt);
    _syncFigures(sdt);
    _checkGoals();
    _resolveOutcome();
  }

  void _tickTimers(double dt) {
    if (_kickoffPause > 0) _kickoffPause = math.max(0, _kickoffPause - dt);
    if (_leftBulge > 0) _leftBulge = math.max(0, _leftBulge - dt);
    if (_rightBulge > 0) _rightBulge = math.max(0, _rightBulge - dt);
  }

  /// Sweep the aim when idle, fill charge while held, recover cooldown + trail.
  void _tickStrikers(double dt) {
    final frozen = _kickoffPause > 0;
    for (final s in _strikers.values) {
      if (s.charging && !frozen) {
        s.charge = math.min(1.0, s.charge + dt / _chargeTimeSec);
      } else if (!frozen) {
        s.aim = _wrap(s.aim + _aimSweepSpeed * dt);
      }
      s.tick(dt);
    }
  }

  /// Advance ball-only visual state (trail, spin, squash) on the sim clock.
  void _updateBall(double dt) {
    final speed = _ball.vel.distance;
    if (speed > 1) _ballLastDir = _ball.vel / speed;

    _ballTrail.add(_ball.pos);
    while (_ballTrail.length > _trailLen) {
      _ballTrail.removeAt(0);
    }

    // Spin accumulates with travel, decays at rest.
    _ballSpin += speed * _spinPerSpeed * dt;
    if (speed < 1) {
      _ballSpin *= math.max(0.0, 1 - _spinDecayPerSec * dt);
    }
    _ballSquash = (_ballSquash - _squashDecayPerSec * dt).clamp(0.0, 1.0);
  }

  // ── Bots ────────────────────────────────────────────────────────────────────

  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a beat first
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bot decision (no hold simulation — it picks an aim + charge and commits):
  ///  * the rear player on a 2-player side guards its goal (eases back into the
  ///    keeper slot, tracking the ball's vertical position);
  ///  * otherwise it AIMS at the opponent goal when near the ball and fires a
  ///    charged power-kick, or dashes toward the ball to close the gap.
  /// [BotProfile] adds hesitation (errorRate) and aim jitter (accuracy) so it
  /// reads as deliberate and is beatable on easy.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final s = _strikers[playerId];
    if (self == null || s == null || !s.ready) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // deliberate hesitate

    if (_isKeeper(playerId)) {
      _botGuard(playerId, self, s);
      return;
    }

    if (self.vel.distance > _botCarrySpeed) return; // ride out current motion

    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final err = (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;

    // Near the ball: aim a charged strike at the opponent goal mouth.
    if (dist <= _playerRadius * _botStrikeRangeFactor) {
      final target = _opponentGoalTarget(playerId);
      final toGoal = target - _ball.pos;
      final aim = math.atan2(toGoal.dy, toGoal.dx) + ctx.rng.jitter(err);
      final charge =
          (ctx.botProfile.accuracy * ctx.rng.range(0.55, 1.0)).clamp(0.0, 1.0);
      s.aim = aim;
      _commitAction(playerId, self, aim, charge);
      return;
    }

    // Far but worth chasing: dash toward the ball (a quick, low-charge move).
    if (dist <= _playerRadius * _botChaseRangeFactor) {
      var dir = _normalize(toBall);
      if (dir == Offset.zero) dir = const Offset(0, -1);
      final aim = math.atan2(dir.dy, dir.dx) + ctx.rng.jitter(err * 0.5);
      s.aim = aim;
      _commitAction(playerId, self, aim, 0.0); // 0 charge ⇒ a dash
    }
  }

  /// Keeper behaviour: ease toward a guard slot in front of its own goal,
  /// tracking the ball's vertical position so it covers shots on goal. Uses a
  /// quiet dash (no power-kick) so it repositions without launching the ball.
  void _botGuard(int playerId, Body self, Striker s) {
    final attacksRight = _attacksRight[playerId] ?? true;
    final guardX = attacksRight
        ? _pitch.left + _pitch.width * _botGuardDepthFactor
        : _pitch.right - _pitch.width * _botGuardDepthFactor;
    final targetY = _pitch.center.dy +
        (_ball.pos.dy - _pitch.center.dy) * _botGuardLaneGain;
    final target = Offset(guardX, targetY);
    // Only nudge if meaningfully out of position (keeps it from jittering).
    if ((target - self.pos).distance < _playerRadius * 0.8) return;
    final dir = _normalize(target - self.pos);
    if (dir == Offset.zero) return;
    final aim = math.atan2(dir.dy, dir.dx);
    s.aim = aim;
    _commitAction(playerId, self, aim, 0.0); // dash-only reposition
  }

  /// The rear-most player on a side (closest to its own goal) keeps net. A lone
  /// player on a side never keeps net (they must attack to ever score).
  bool _isKeeper(int playerId) {
    final attacksRight = _attacksRight[playerId] ?? true;
    final mates = _attacksRight.entries
        .where((e) => e.value == attacksRight)
        .map((e) => e.key)
        .toList();
    if (mates.length < 2) return false;
    // "Rear" = deepest in own half. Own goal is LEFT when attacking right.
    var rear = mates.first;
    var rearDepth = double.negativeInfinity;
    for (final id in mates) {
      final b = _bodyOf(id);
      if (b == null) continue;
      // Depth from the opponent goal (bigger = deeper toward own goal).
      final depth =
          attacksRight ? (_pitch.right - b.pos.dx) : (b.pos.dx - _pitch.left);
      if (depth > rearDepth) {
        rearDepth = depth;
        rear = id;
      }
    }
    return rear == playerId;
  }

  /// Center of the goal this player is attacking (where a strike should aim).
  Offset _opponentGoalTarget(int playerId) {
    final attacksRight = _attacksRight[playerId] ?? true;
    final x = attacksRight ? _rightLine : _leftLine;
    return Offset(x, _goalMouth.center.dy);
  }

  // ── Action: dash (tap) or power-kick lunge (charged release) ─────────────────

  /// Apply an aimed move of the given [charge] (0..1) in [aimAngle].
  /// Charge 0 = a quick dash; higher charge = a stronger power-kick lunge. When
  /// the move starts near the ball, an explicit directional kick drives the ball
  /// in the aim direction (scaled by charge) for a crisp "thwack".
  void _commitAction(int playerId, Body self, double aimAngle, double charge) {
    final s = _strikers[playerId];
    if (s == null || !s.ready) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    final perSecond = _dashPerSecond + (_kickPerSecond - _dashPerSecond) * charge;
    final magnitude = _pitch.width * perSecond;
    _arena.impulse(playerId, dir * magnitude);
    if (charge > 0) {
      _arena.impulse(playerId, -dir * magnitude * _selfPushback);
    }

    s.fire(_cooldownSec, charge: charge);
    s.trail = DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }

    _tryStrikeBall(self, dir, charge);

    // Dust kick behind the move + a light spark telegraph.
    _juice.particles.burst(
      at: self.pos - dir * _playerRadius,
      count: (5 + 5 * charge).round(),
      color: _dust,
      speed: 150,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 220,
      life: 0.32,
    );
    if (charge > 0.6) _juice.shake.light();
  }

  /// If [self] is near the ball, drive it in the move's [dir] (NOT toward the
  /// ball — the player aimed this). Strength scales with charge + proximity.
  void _tryStrikeBall(Body self, Offset dir, double charge) {
    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final closeRange = (_playerRadius + _ballRadius) * _strikeRangeFactor;
    if (dist > closeRange) return;
    final proximity = (1.0 - (dist / closeRange)).clamp(0.0, 1.0);

    final scale = _strikeBaseScale + _strikeChargeScale * charge;
    final kickMag = _pitch.width * _dashPerSecond * scale * proximity;
    _arena.impulse(_ballId, dir * kickMag);
    _onBallKicked(proximity);
  }

  /// React to a ball strike: squash the ball + spark + hit-stop + a "THWACK!"
  /// pop on the hardest strikes.
  void _onBallKicked(double proximity) {
    final speed = _ball.vel.distance;
    _ballSquash =
        (proximity * 0.8 + (speed / _hardKickSpeed) * 0.4).clamp(0.0, 1.0);
    if (speed >= _hardKickSpeed) {
      _juice.hit(_ball.pos, _spark, sparks: 10);
      _juice.shake.light();
      _juice.popup(_ball.pos.translate(0, -_ballRadius * 2.4), 'THWACK!',
          const Color(0xFFFFE08A), size: _ballRadius * 1.8);
    } else {
      _juice.particles.burst(
        at: _ball.pos,
        count: 5,
        color: _spark,
        speed: 180,
        size: 4,
        life: 0.28,
      );
    }
  }

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null) {
        fig.setLoco(
            body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle);
      }
      fig.update(dt);
    }
  }

  // ── Goals + outcome ─────────────────────────────────────────────────────────

  /// Award a goal when the ball reaches a goal line within the goal mouth.
  void _checkGoals() {
    final withinMouth =
        _ball.pos.dy >= _goalMouth.top && _ball.pos.dy <= _goalMouth.bottom;
    if (!withinMouth) return;

    if (_ball.pos.dx <= _leftLine && _hasLeftSide) {
      // Scored on the LEFT goal ⇒ the RIGHT-attacking side scores.
      _scoreFor(attacksRight: true);
    } else if (_ball.pos.dx >= _rightLine && _hasRightSide) {
      // Scored on the RIGHT goal ⇒ the LEFT-attacking side scores.
      _scoreFor(attacksRight: false);
    }
  }

  void _scoreFor({required bool attacksRight}) {
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) addScore(p.id, 1);
    }
    final color = _sideColor(attacksRight);

    // Net bulge on the goal that was scored ON (opposite the scorer's side).
    if (attacksRight) {
      _leftBulge = _bulgeDurationSec; // ball went into the LEFT goal
    } else {
      _rightBulge = _bulgeDurationSec;
    }

    // Celebration: explosion + GOAL popup + crowd roar + confetti + slow-mo.
    _juice.ko(_ball.pos, color);
    _juice.popup(
        _pitch.center, 'GOAL!', color, size: _pitch.shortestSide * 0.12);
    _juice.popup(_pitch.center.translate(0, _pitch.shortestSide * 0.12),
        'CROWD ROARS!', const Color(0xFFFFE08A),
        size: _pitch.shortestSide * 0.04);
    _juice.confetti(_size, colors: [color, _confettiA, _confettiB]);
    _juice.hitStop.trigger(_goalHitStopSec, scale: _goalHitStopScale);
    _juice.shake.heavy();

    _kickoffPause = _kickoffPauseSec;
    _resetBall();
  }

  void _resetBall() {
    _ball.pos = _pitch.center;
    _ball.vel = Offset.zero;
    _ballSpin = 0;
    _ballSquash = 0;
    _ballLastDir = Offset.zero;
    _ballTrail
      ..clear()
      ..add(_ball.pos);
  }

  /// Finish early when a side reaches [_goalsToWin], or when time expires.
  void _resolveOutcome() {
    final leftScore = _sideScore(attacksRight: false);
    final rightScore = _sideScore(attacksRight: true);
    final reached = leftScore >= _goalsToWin || rightScore >= _goalsToWin;
    if (reached || _elapsed >= _timeLimit) {
      finishByScore();
    }
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SoccerRenderer.drawBackground(canvas, size);
    SoccerRenderer.drawPitch(canvas, _pitch);
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onRight: false, color: _leftAccent, bulge: _bulgeFill(_leftBulge));
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onRight: true, color: _rightAccent, bulge: _bulgeFill(_rightBulge));

    _drawPlayers(canvas);

    SoccerRenderer.drawBall(
      canvas,
      _ball.pos,
      _ballRadius,
      trail: List<Offset>.unmodifiable(_ballTrail),
      velDir: _ballLastDir,
      spin: _ballSpin,
      squash: _ballSquash,
    );

    SoccerRenderer.drawVignette(canvas, size);
    _drawScoreboard(canvas);
    SoccerRenderer.drawKickoffBanner(
        canvas, _pitch, 'KICK OFF', _kickoffBannerAlpha());

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawPlayers(Canvas canvas) {
    for (final entry in _figures.entries) {
      final id = entry.key;
      final body = _bodyOf(id);
      if (body == null) continue;
      final s = _strikers[id];
      final color = Color(_colorOf(id));
      final actor = _actorFor(id, body, entry.value, color, s);
      SoccerRenderer.drawDashTrail(canvas, actor);
      SoccerRenderer.drawActorGround(canvas, actor);
      SoccerRenderer.drawActor(canvas, actor);
      // The aim arrow + charge — the player's control, drawn on top of the body.
      if (s != null && _kickoffPause <= 0) {
        SoccerRenderer.drawAim(
          canvas,
          body.pos,
          _playerRadius,
          color,
          aim: s.aim,
          charge: s.charge,
          charging: s.charging,
          ready: s.ready,
          clock: _animClock,
        );
      }
    }
  }

  SoccerActor _actorFor(
      int id, Body body, StickFigure fig, Color color, Striker? s) {
    final feet = Offset(body.pos.dx, body.pos.dy + body.radius);
    final trail = s?.trail;
    return SoccerActor(
      figure: fig,
      // Figure pelvis anchors at feet so the stick stands on its disc.
      root: feet,
      feet: feet,
      radius: body.radius,
      color: color,
      number: id + 1,
      kickFlash: s?.flash ?? 0,
      trailFrom: trail?.from,
      trailDir: trail?.dir ?? Offset.zero,
      trailStrength: trail?.strength ?? 0,
    );
  }

  void _drawScoreboard(Canvas canvas) {
    SoccerRenderer.drawScoreboard(
      canvas,
      _pitch,
      SoccerSide(
        color: _leftAccent,
        score: _sideScore(attacksRight: false),
        label: 'L',
      ),
      SoccerSide(
        color: _rightAccent,
        score: _sideScore(attacksRight: true),
        label: 'R',
      ),
      math.max(0.0, _timeLimit - _elapsed),
    );
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// 0..1 net-ripple strength with an ease-out fade.
  double _bulgeFill(double remaining) {
    if (remaining <= 0) return 0;
    return (remaining / _bulgeDurationSec).clamp(0.0, 1.0);
  }

  /// 0..1 fade for the kickoff banner (fades out as the pause ends).
  double _kickoffBannerAlpha() {
    if (_kickoffPause <= 0) return 0;
    return (_kickoffPause / _kickoffPauseSec).clamp(0.0, 1.0);
  }

  /// Score for one side (any one member's score; all members share it).
  int _sideScore({required bool attacksRight}) {
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) return scoreOf(p.id).round();
    }
    return 0;
  }

  Color _sideColor(bool attacksRight) =>
      attacksRight ? _rightAccent : _leftAccent;

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

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }

  static double _wrap(double a) {
    const twoPi = math.pi * 2;
    var r = a % twoPi;
    if (r > math.pi) r -= twoPi;
    if (r < -math.pi) r += twoPi;
    return r;
  }
}
