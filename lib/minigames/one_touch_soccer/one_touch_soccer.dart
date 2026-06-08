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

/// One-Touch Soccer — a NORTH/SOUTH pitch (goals at the TOP and BOTTOM of the
/// tall portrait screen) with a neutral ball (id -1) and one stick striker per
/// seat.
///
/// CONTROL (the heart of it — full player agency):
///  * MOVEMENT is a VIRTUAL JOYSTICK. Touch down anywhere in your zone to anchor
///    a joystick; drag from there — the vector from the anchor to your finger is
///    the direction you run and its length is your speed. Release to stop. You
///    steer freely in 2-D: that is the whole game.
///  * KICKS are AUTOMATIC. Run your striker into the ball and it is kicked for
///    you — in your current run direction, biased toward the goal you attack —
///    with a small cooldown so contact does not jitter. No aiming, no charging.
///
/// PACING: a real back-and-forth match — first to [_goalsToWin] goals or until
/// the [_timeLimit] expires. The ball starts dead at center, there is a brief
/// kickoff pause after every goal, and bots warm up before engaging, so the ball
/// is never instantly scored and the midfield is genuinely contested.
///
/// Feel: the ball is light so kicks fly, carries spin, leaves a motion trail and
/// bounces off the SIDE walls. Goals trigger a net-bulge flash + big "GOAL!"
/// popup + confetti + slow-mo + crowd roar.
///
/// Teams / goals: even ids / [Team.a] attack the TOP goal (defend bottom); odd
/// ids / [Team.b] attack the BOTTOM goal (defend top). A goal awards a point to
/// every player on the scoring side (aggregated for 2v2). Bots steer toward the
/// ball with the SAME joystick model, pushing it toward the opponent goal, and
/// the rear player on a 2-player side drops back to guard its own net.
class OneTouchSoccer extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'one_touch_soccer',
        name: 'One-Touch Soccer',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'MOVE',
      );

  // ── Match / arena / sim tuning (no magic numbers inline) ────────────────────
  static const double _timeLimit = 40;
  static const int _goalsToWin = 3; // first side to this many goals wins early
  static const int _ballId = -1;
  static const double _pitchInsetFactor = 0.055;
  static const double _ballRadiusFactor = 0.030;
  static const double _playerRadiusFactor = 0.052;
  static const double _ballMass = 0.5; // lighter than strikers so kicks fly
  static const double _pitchFriction = 0.985; // grass: ball coasts then settles
  static const double _ballRestitution = 0.78; // wall bounce damping
  static const double _goalMouthFraction = 0.46; // of pitch width, centered
  static const double _figureScale = 0.95;

  // ── Joystick movement tuning ────────────────────────────────────────────────
  static const double _joyMaxRadius = 0.16; // full-tilt deflection (norm screen)
  static const double _joyDeadZone = 0.012; // ignore tiny jitters
  static const double _maxSpeedFactor = 0.62; // top speed = pitch.h * this /s
  static const double _accelPerSec = 9.0; // velocity lerp toward target /s
  static const double _releaseDragPerSec = 7.0; // decel rate after release /s

  // ── Auto-kick tuning ────────────────────────────────────────────────────────
  static const double _kickContactFactor = 1.18; // overlap = within this*radii
  static const double _kickCooldownSec = 0.22; // anti-jitter recovery
  static const double _kickPerSecond = 3.6; // base kick impulse = pitch.h * this
  static const double _kickMoveBlend = 0.62; // weight of run dir vs goal dir
  static const double _kickMinSpeedFactor = 0.45; // floor on a near-still tap-in
  static const double _spinPerSpeed = 0.012; // ball spin gain / speed
  static const double _spinDecayPerSec = 1.6;
  static const double _squashDecayPerSec = 4.5;
  static const double _hardKickSpeed = 360.0; // ball speed above → thwack juice
  static const double _trailLifeSec = 0.20;
  static const int _trailLen = 12;

  // ── Goal / celebration tuning ───────────────────────────────────────────────
  static const double _kickoffPauseSec = 1.25; // sim frozen after a goal
  static const double _bulgeDurationSec = 0.9; // net ripple length
  static const double _goalHitStopSec = 0.5; // slow-mo on a goal
  static const double _goalHitStopScale = 0.18;

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 1.5; // grace before bots engage
  static const double _botGuardDepthFactor = 0.20; // keeper y offset from wall
  static const double _botGuardLaneGain = 0.7; // how hard keeper tracks ball x
  static const double _botSteerErrorRad = 0.4; // heading jitter at accuracy 0
  static const double _botGoalPushRangeFactor = 5.0; // push toward goal within

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _topAccent = Color(0xFFFF5A5A); // top goal / side A
  static const Color _bottomAccent = Color(0xFF4D9BFF); // bottom goal / side B
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
  double _kickoffPause = 0; // > 0 while the post-goal pause runs
  double _topBulge = 0; // net ripple timers
  double _bottomBulge = 0;
  double _ballSpin = 0; // radians, for the seam hint
  double _ballSquash = 0; // 0..1, flatten on hard hits
  Offset _ballLastDir = Offset.zero;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, Joystick> _joysticks = <int, Joystick>{};

  /// Last move direction (unit) of each striker, for the auto-kick bias.
  final Map<int, Offset> _moveDir = <int, Offset>{};

  /// Per-bot desired heading (unit vector) refreshed on its reaction clock and
  /// applied smoothly every frame, mirroring how a human holds a joystick.
  final Map<int, Offset> _botHeading = <int, Offset>{};

  /// True if this player attacks the TOP goal (else the BOTTOM goal).
  final Map<int, bool> _attacksTop = <int, bool>{};

  /// Recent ball centers (newest last) for the motion trail.
  final List<Offset> _ballTrail = <Offset>[];

  late Body _ball;
  late double _ballRadius;
  late double _playerRadius;
  Rect _goalMouth = Rect.zero; // horizontal span both goals share
  double _topLine = 0;
  double _bottomLine = 0;
  bool _hasTopSide = false; // someone defends/attacks each goal
  bool _hasBottomSide = false;

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
    final mouthWidth = _pitch.width * _goalMouthFraction;
    final left = _pitch.center.dx - mouthWidth / 2;
    _goalMouth =
        Rect.fromLTRB(left, _pitch.top, left + mouthWidth, _pitch.bottom);
    // A goal counts once the ball center reaches the wall contact line.
    _topLine = _pitch.top + _ballRadius;
    _bottomLine = _pitch.bottom - _ballRadius;
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
      final attacksTop = _resolveSide(p);
      _attacksTop[p.id] = attacksTop;
      if (attacksTop) {
        _hasTopSide = true;
      } else {
        _hasBottomSide = true;
      }

      // Spawn each player on its own defending half, stacked horizontally.
      final defendBottom = attacksTop; // attack top ⇒ defend/start at bottom
      final sameSide =
          players.where((q) => _resolveSide(q) == attacksTop).toList();
      final indexOnSide = sameSide.indexWhere((q) => q.id == p.id);
      final lane = (indexOnSide + 1) / (sameSide.length + 1);
      final y = defendBottom
          ? _pitch.bottom - _pitch.height * 0.27
          : _pitch.top + _pitch.height * 0.27;
      final x = _pitch.left + _pitch.width * lane;
      final pos = Offset(x, y);
      _arena.add(Body(id: p.id, pos: pos, radius: _playerRadius));

      _figures[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_figureScale),
        style: _styleFor(Color(p.colorArgb)),
        facing: 1.0,
      )..setLoco(LocoState.idle);

      _joysticks[p.id] = Joystick();
      _moveDir[p.id] = Offset.zero;
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
        _botHeading[p.id] = Offset.zero;
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

  /// Even ids / Team.a attack TOP; odd ids / Team.b attack BOTTOM.
  bool _resolveSide(PlayerSlot p) {
    if (p.team == Team.a) return true;
    if (p.team == Team.b) return false;
    return p.id.isEven;
  }

  // ── Input: virtual joystick (press / drag / release) ─────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final joy = _joysticks[input.playerId];
    if (joy == null) return;
    // Inputs during the kickoff pause would steer on a frozen ball; ignore.
    if (_kickoffPause > 0) return;

    switch (input.phase) {
      case InputPhase.down:
        joy.press(input.normPos);
      case InputPhase.holdTick:
        // A move sample carries a position; a pure per-frame held tick carries
        // only dt (normPos == Offset.zero) and just keeps the last vector.
        if (input.normPos != Offset.zero) joy.drag(input.normPos);
      case InputPhase.up:
        joy.release();
    }
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;

    // Juice always runs on real dt; the sim runs on hit-stop-scaled dt.
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _tickTimers(dt);
    for (final joy in _joysticks.values) {
      joy.tick(dt);
    }

    // During the kickoff pause the world is frozen (only juice + timers run).
    if (_kickoffPause > 0) {
      _syncFigures(0);
      _resolveOutcome();
      return;
    }

    _driveBots(dt);
    _steerStrikers(sdt);
    _arena.update(sdt);
    _autoKick();

    _updateBall(sdt);
    _syncFigures(sdt);
    _checkGoals();
    _resolveOutcome();
  }

  void _tickTimers(double dt) {
    if (_kickoffPause > 0) _kickoffPause = math.max(0, _kickoffPause - dt);
    if (_topBulge > 0) _topBulge = math.max(0, _topBulge - dt);
    if (_bottomBulge > 0) _bottomBulge = math.max(0, _bottomBulge - dt);
  }

  /// Drive every striker's velocity from its joystick (or bot heading): steer
  /// toward the desired velocity with an acceleration cap, decelerate on
  /// release. This is the full-2-D agency — nothing homes onto the ball.
  void _steerStrikers(double dt) {
    if (dt <= 0) return;
    final maxSpeed = _pitch.height * _maxSpeedFactor;
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      final body = _bodyOf(id);
      if (body == null) continue;
      final desired = _desiredVelocity(id, entry.value, maxSpeed);

      // Frame-rate-independent exponential approach toward the target velocity.
      final rate = desired == Offset.zero ? _releaseDragPerSec : _accelPerSec;
      final t = (1 - math.exp(-rate * dt)).clamp(0.0, 1.0);
      body.vel = Offset.lerp(body.vel, desired, t) ?? body.vel;

      final sp = body.vel.distance;
      if (sp > 1) _moveDir[id] = body.vel / sp;
    }
  }

  /// Target velocity for striker [id]: bots use their smoothed heading, humans
  /// use the live joystick deflection. Returns [Offset.zero] when idle.
  Offset _desiredVelocity(int id, Joystick joy, double maxSpeed) {
    if (_botClocks.containsKey(id)) {
      final heading = _botHeading[id] ?? Offset.zero;
      return heading * maxSpeed; // heading magnitude already encodes throttle
    }
    final steer = joy.steer(maxRadius: _joyMaxRadius, deadZone: _joyDeadZone);
    return steer * maxSpeed;
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

  // ── Auto-kick: contact with the ball launches it (no aim, no charge) ──────────

  /// After the physics step, any striker overlapping the ball (and off its kick
  /// cooldown) automatically kicks it: direction blends the striker's current
  /// run with the heading toward the opponent goal, so contact drives the ball
  /// up-field. A short cooldown stops a single touch re-firing every frame.
  void _autoKick() {
    final kickBase = _pitch.height * _kickPerSecond;
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      final joy = entry.value;
      if (!joy.canKick) continue;
      final self = _bodyOf(id);
      if (self == null) continue;

      final toBall = _ball.pos - self.pos;
      final dist = toBall.distance;
      final contact = (_playerRadius + _ballRadius) * _kickContactFactor;
      if (dist > contact) continue;

      final dir = _kickDirection(id, self, toBall);
      if (dir == Offset.zero) continue;

      // Strength scales with the striker's speed but never drops below a floor,
      // so even a near-stationary touch nudges the ball off the spot.
      final speedFrac = (self.vel.distance / (_pitch.height * _maxSpeedFactor))
          .clamp(_kickMinSpeedFactor, 1.0);
      final kickMag = kickBase * speedFrac;
      _arena.impulse(_ballId, dir * kickMag);

      joy.armKick(_kickCooldownSec);
      joy.trail = DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);
      final fig = _figures[id];
      if (fig != null) {
        fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
        fig.dash();
      }
      _onBallKicked(self.pos);
    }
  }

  /// Kick direction = blend of the striker's run direction and the direction
  /// toward the goal it attacks (so contact biases the ball goalward). Falls
  /// back to the contact normal when the striker is standing still.
  Offset _kickDirection(int id, Body self, Offset toBall) {
    var run = _moveDir[id] ?? Offset.zero;
    if (run == Offset.zero) run = _normalize(toBall); // contact push-off
    final toGoal = _normalize(_opponentGoalTarget(id) - self.pos);
    final blended = run * _kickMoveBlend + toGoal * (1 - _kickMoveBlend);
    return _normalize(blended);
  }

  /// React to a ball strike: squash + spark + hit-stop + a "THWACK!" pop on the
  /// hardest strikes.
  void _onBallKicked(Offset at) {
    final speed = _ball.vel.distance;
    _ballSquash = (0.6 + (speed / _hardKickSpeed) * 0.4).clamp(0.0, 1.0);
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
    // Light dust at the striker's feet on contact.
    _juice.particles.burst(
      at: at.translate(0, _playerRadius),
      count: 5,
      color: _dust,
      speed: 120,
      size: 4,
      gravity: 220,
      life: 0.3,
    );
  }

  // ── Bots: steer via the SAME joystick movement model ─────────────────────────

  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a beat first
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Pick a fresh heading for a bot (applied smoothly by [_steerStrikers]):
  ///  * the rear player on a 2-player side guards its goal (tracks the ball's
  ///    horizontal position in front of its own net);
  ///  * otherwise it heads for the ball, and once close it aims its run at the
  ///    opponent goal so the auto-kick drives the ball up-field.
  /// [BotProfile] adds hesitation (errorRate) and heading jitter (accuracy) so
  /// it reads as deliberate and is beatable on easy.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) {
      _botHeading[playerId] = Offset.zero; // deliberate hesitation: coast
      return;
    }

    if (_isKeeper(playerId)) {
      _botHeading[playerId] = _botGuardHeading(playerId, self);
      return;
    }

    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botSteerErrorRad;

    // Close to the ball: steer through it toward the opponent goal.
    Offset aim;
    if (dist <= _playerRadius * _botGoalPushRangeFactor) {
      aim = _normalize(_opponentGoalTarget(playerId) - self.pos);
    } else {
      aim = _normalize(toBall);
    }
    if (aim == Offset.zero) aim = const Offset(0, -1);

    // A throttle just under full so bots are firm but not perfectly fast.
    final throttle = (0.7 + ctx.botProfile.accuracy * 0.3).clamp(0.0, 1.0);
    _botHeading[playerId] = _rotate(aim, ctx.rng.jitter(err)) * throttle;
  }

  /// Keeper heading: ease toward a guard slot in front of its own goal,
  /// tracking the ball's horizontal position so it covers shots on goal.
  Offset _botGuardHeading(int playerId, Body self) {
    final attacksTop = _attacksTop[playerId] ?? true;
    // Own goal is the BOTTOM when attacking top.
    final guardY = attacksTop
        ? _pitch.bottom - _pitch.height * _botGuardDepthFactor
        : _pitch.top + _pitch.height * _botGuardDepthFactor;
    final targetX = _pitch.center.dx +
        (_ball.pos.dx - _pitch.center.dx) * _botGuardLaneGain;
    final target = Offset(targetX, guardY);
    if ((target - self.pos).distance < _playerRadius * 0.8) {
      return Offset.zero; // in position: hold (avoids jitter)
    }
    return _normalize(target - self.pos) * 0.85;
  }

  /// The rear-most player on a side (closest to its own goal) keeps net. A lone
  /// player on a side never keeps net (they must attack to ever score).
  bool _isKeeper(int playerId) {
    final attacksTop = _attacksTop[playerId] ?? true;
    final mates = _attacksTop.entries
        .where((e) => e.value == attacksTop)
        .map((e) => e.key)
        .toList();
    if (mates.length < 2) return false;
    // "Rear" = deepest in own half. Own goal is BOTTOM when attacking top.
    var rear = mates.first;
    var rearDepth = double.negativeInfinity;
    for (final id in mates) {
      final b = _bodyOf(id);
      if (b == null) continue;
      // Depth from the opponent goal (bigger = deeper toward own goal).
      final depth =
          attacksTop ? (b.pos.dy - _pitch.top) : (_pitch.bottom - b.pos.dy);
      if (depth > rearDepth) {
        rearDepth = depth;
        rear = id;
      }
    }
    return rear == playerId;
  }

  /// Center of the goal this player is attacking (where contact should drive).
  Offset _opponentGoalTarget(int playerId) {
    final attacksTop = _attacksTop[playerId] ?? true;
    final y = attacksTop ? _topLine : _bottomLine;
    return Offset(_goalMouth.center.dx, y);
  }

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null) {
        fig.setLoco(
            body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle);
        final dir = _moveDir[entry.key] ?? Offset.zero;
        if (dir.dx.abs() > 0.05) fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      }
      fig.update(dt);
    }
  }

  // ── Goals + outcome ─────────────────────────────────────────────────────────

  /// Award a goal when the ball reaches a goal line within the goal mouth.
  void _checkGoals() {
    final withinMouth =
        _ball.pos.dx >= _goalMouth.left && _ball.pos.dx <= _goalMouth.right;
    if (!withinMouth) return;

    if (_ball.pos.dy <= _topLine && _hasTopSide) {
      // Scored on the TOP goal ⇒ the BOTTOM-attacking side scores.
      _scoreFor(attacksTop: false);
    } else if (_ball.pos.dy >= _bottomLine && _hasBottomSide) {
      // Scored on the BOTTOM goal ⇒ the TOP-attacking side scores.
      _scoreFor(attacksTop: true);
    }
  }

  void _scoreFor({required bool attacksTop}) {
    for (final p in ctx.players) {
      if (_attacksTop[p.id] == attacksTop) addScore(p.id, 1);
    }
    final color = _sideColor(attacksTop);

    // Net bulge on the goal that was scored ON (opposite the scorer's side).
    if (attacksTop) {
      _bottomBulge = _bulgeDurationSec; // ball went into the BOTTOM goal
    } else {
      _topBulge = _bulgeDurationSec;
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
    final topScore = _sideScore(attacksTop: true);
    final bottomScore = _sideScore(attacksTop: false);
    final reached = topScore >= _goalsToWin || bottomScore >= _goalsToWin;
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
        onBottom: false, color: _topAccent, bulge: _bulgeFill(_topBulge));
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onBottom: true, color: _bottomAccent, bulge: _bulgeFill(_bottomBulge));

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
    _drawJoysticks(canvas);
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
      final joy = _joysticks[id];
      final color = Color(_colorOf(id));
      final actor = _actorFor(id, body, entry.value, color, joy);
      SoccerRenderer.drawDashTrail(canvas, actor);
      SoccerRenderer.drawActorGround(canvas, actor);
      SoccerRenderer.drawActor(canvas, actor);
    }
  }

  /// Draw each active human joystick (base ring + thumb) in the player's color,
  /// anchored at the touch origin so the player sees their control.
  void _drawJoysticks(Canvas canvas) {
    if (_kickoffPause > 0) return;
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      if (_botClocks.containsKey(id)) continue; // bots have no on-screen stick
      final joy = entry.value;
      if (!joy.active) continue;
      SoccerRenderer.drawJoystick(
        canvas,
        origin: _toPixels(joy.origin),
        thumb: _toPixels(joy.current),
        maxRadius: _joyMaxRadius * _size.height,
        color: Color(_colorOf(id)),
      );
    }
  }

  SoccerActor _actorFor(
      int id, Body body, StickFigure fig, Color color, Joystick? joy) {
    final feet = Offset(body.pos.dx, body.pos.dy + body.radius);
    final trail = joy?.trail;
    return SoccerActor(
      figure: fig,
      // Figure pelvis anchors at feet so the stick stands on its disc.
      root: feet,
      feet: feet,
      radius: body.radius,
      color: color,
      number: id + 1,
      kickFlash: (trail?.strength ?? 0),
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
        color: _topAccent,
        score: _sideScore(attacksTop: true),
        label: 'TOP',
      ),
      SoccerSide(
        color: _bottomAccent,
        score: _sideScore(attacksTop: false),
        label: 'BOT',
      ),
      math.max(0.0, _timeLimit - _elapsed),
    );
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// Convert a normalized full-screen point to pixels.
  Offset _toPixels(Offset norm) =>
      Offset(norm.dx * _size.width, norm.dy * _size.height);

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
  int _sideScore({required bool attacksTop}) {
    for (final p in ctx.players) {
      if (_attacksTop[p.id] == attacksTop) return scoreOf(p.id).round();
    }
    return 0;
  }

  Color _sideColor(bool attacksTop) => attacksTop ? _topAccent : _bottomAccent;

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

  /// Rotate a vector by [radians] (used to add bot heading jitter).
  static Offset _rotate(Offset v, double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }
}
