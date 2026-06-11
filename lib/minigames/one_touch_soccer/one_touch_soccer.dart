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
import 'soccer_fx.dart';
import 'soccer_render.dart';
import 'striker.dart';

/// One-Touch Soccer — a NORTH/SOUTH pitch (goals at the TOP and BOTTOM of the
/// tall portrait screen) with a neutral ball (id -1) and one stick striker per
/// seat.
///
/// CONTROL (the heart of it — full player agency, still one touch):
///  * MOVEMENT is a VIRTUAL JOYSTICK. Touch down anywhere in your zone to anchor
///    a joystick; drag from there — the vector from the anchor to your finger is
///    the direction you run and its length is your speed. Release to stop. You
///    steer freely in 2-D.
///  * TRAP vs KICK is the per-touch DECISION. Reaching the ball WITHOUT a fresh
///    tap TRAPS it: most of its speed is killed and it sticks to your feet so you
///    carry / dribble it where you steer. Each TAP (the joystick press) arms a
///    KICK for your next contact, which SHOOTS the ball goalward — and the longer
///    the ball has been settled at your feet, the harder that shot flies. So a
///    kid runs with the ball at their feet and taps to shoot.
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

  // ── Touch tuning: TRAP (default) vs KICK (tap-armed) ─────────────────────────
  // Contact is a real decision. Untapped contact TRAPS the ball (kills most of
  // its speed, keeps it at the feet to dribble); a tapped/armed contact SHOOTS.
  static const double _kickContactFactor = 1.18; // overlap = within this*radii
  static const double _tapHoldSec = 0.22; // press held longer ⇒ dribble not shot
  static const double _touchCooldownSec = 0.18; // anti-jitter recovery / touch
  static const double _trapVelRetain = 0.12; // ball speed kept on a trap (0..1)
  static const double _trapCarrySpeed = 0.34; // post-trap nudge = striker speed*
  static const double _kickPerSecond = 3.6; // full-charge kick = pitch.h * this
  static const double _kickMinPowerFrac = 0.5; // floor power on a 0-charge shot
  static const double _kickChargeFullSec = 0.9; // time-since-touch → full power
  static const double _kickMoveBlend = 0.62; // weight of run dir vs goal dir
  static const double _spinPerSpeed = 0.012; // ball spin gain / speed
  static const double _spinDecayPerSec = 1.6;
  static const double _squashDecayPerSec = 4.5;
  static const double _hardKickSpeed = 360.0; // ball speed above → thwack juice
  static const double _trailLifeSec = 0.20;
  static const int _trailLen = 12;

  // ── Goal / celebration tuning ───────────────────────────────────────────────
  static const double _kickoffPauseSec = 1.25; // sim frozen after a goal
  static const double _bulgeDurationSec = 0.9; // net ripple length
  // The goal slow-mo is now supplied by Juice.bigMoment (the signature beat).

  // ── Climax (double goals) tuning ────────────────────────────────────────────
  // The final ~30% of the clock: every goal is worth 2 and a DOUBLE GOALS banner
  // pulses, so a late comeback is always on the table and the finish ramps.
  static const double _doubleGoalsFrac = 0.7; // enters at this share of time
  static const int _doubleGoalsValue = 2; // points per goal in the window

  // ── Speed pad (chaos) tuning ────────────────────────────────────────────────
  // A midfield pad the ball can roll over for a one-shot speed kick toward
  // whatever way it is already travelling — a sudden swing the table reacts to.
  static const double _padRadiusFactor = 1.7; // pad R / ball R
  static const double _padFirstSpawnSec = 5.0;
  static const double _padRespawnSec = 6.0;
  static const double _padLifeSec = 7.0;
  static const double _padAppearPerSec = 3.5;
  static const double _padPhasePerSec = 3.0;
  static const double _padBoostPerSecond = 2.6; // boost speed = pitch.h * this
  static const double _padMinBallSpeed = 30.0; // below this, kick toward a goal

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
  late SpeedPadController _pads;
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
    _pads = SpeedPadController(
      radius: _ballRadius * _padRadiusFactor,
      firstSpawnSec: _padFirstSpawnSec,
      respawnSec: _padRespawnSec,
      lifeSec: _padLifeSec,
      appearPerSec: _padAppearPerSec,
      phasePerSec: _padPhasePerSec,
    );
    begin();
  }

  /// True once the match has entered its climax (double-goals) window.
  bool get _isDoubleGoals => _elapsed >= _timeLimit * _doubleGoalsFrac;

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
    // A release must always be honored — even during the kickoff pause — so a
    // finger lifted mid-pause can never leave the joystick stuck active (which
    // would keep the striker running once the pause ends). Down/drag DO steer a
    // frozen ball, so those are ignored while the pause runs.
    if (_kickoffPause > 0 && input.phase != InputPhase.up) return;

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
      joy.tick(dt, tapHoldSec: _tapHoldSec);
    }

    // During the kickoff pause the world is frozen (only juice + timers run).
    // Figures still ANIMATE on real dt though, so the just-fired goal reactions
    // (scorers' arms-up cheer / keeper slump) actually play out in the dead beat
    // instead of freezing on frame 0. Loco is pinned to idle so a striker that
    // was sprinting when the goal landed doesn't run-in-place over its frozen
    // body. This advances only visual animation clocks — no sim/score/pacing.
    if (_kickoffPause > 0) {
      _pads.tick(sdt, ctx.rng, _pitch); // pad keeps drifting/aging visually
      _syncFigures(dt, freezeLocoIdle: true);
      _resolveOutcome();
      return;
    }

    _driveBots(dt);
    _steerStrikers(sdt);
    _arena.update(sdt);
    _resolveBallTouch();

    _pads.tick(sdt, ctx.rng, _pitch);
    _triggerSpeedPad();
    _updateBall(sdt);
    _syncFigures(sdt);
    _checkGoals();
    _resolveOutcome();
  }

  /// When the ball rolls over a ready speed pad, kick it (direction from the
  /// controller) and fire the SPEED! burst — a sudden swing the table reacts to.
  void _triggerSpeedPad() {
    final pad = _pads.pad;
    final dir = _pads.tryTrigger(
      ballPos: _ball.pos,
      ballVel: _ball.vel,
      ballRadius: _ballRadius,
      minBallSpeed: _padMinBallSpeed,
      topLine: _topLine,
      bottomLine: _bottomLine,
    );
    if (dir == null || pad == null) return;
    _arena.impulse(_ballId, dir * (_pitch.height * _padBoostPerSecond));
    _ballSquash = 1.0;
    SoccerFx.fireSpeedBurst(_juice, pad, dir, _ballRadius);
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

  // ── Ball contact: TRAP (default) or KICK (tap-armed) ─────────────────────────

  /// After the physics step, resolve every striker that overlaps the ball (and
  /// is off its short touch cooldown). The contact is a real DECISION:
  ///  * if the striker has a KICK armed (the player tapped, or a bot was armed),
  ///    SHOOT — direction blends the run with the goal heading, power scales with
  ///    time-since-last-touch so a settled ball blasts and a fresh poke nudges;
  ///  * otherwise TRAP — kill most of the ball's speed and leave it at the feet
  ///    moving with the striker, so the ball stays close to carry / dribble.
  /// A short cooldown stops one contact re-firing every frame.
  void _resolveBallTouch() {
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

      if (joy.kickArmed) {
        _kickBall(id, joy, self, toBall, kickBase);
      } else {
        _trapBall(joy, self);
      }
    }
  }

  /// SHOOT: launch the ball goalward at a power set by the shot charge (time
  /// since this striker last touched the ball), then consume the armed kick.
  void _kickBall(int id, Joystick joy, Body self, Offset toBall, double kickBase) {
    final dir = _kickDirection(id, self, toBall);
    if (dir == Offset.zero) return;

    // Power = floor + charge ramp, so a settled ball blasts and a fresh poke
    // only nudges — rewarding a clean trap-then-shoot.
    final charge = joy.touchChargeFrac(_kickChargeFullSec);
    final powerFrac = _kickMinPowerFrac + (1 - _kickMinPowerFrac) * charge;
    // Replace the ball's drift with a clean shot so the kick reads crisply.
    _ball.vel = dir * (kickBase * powerFrac);

    joy.consumeKick();
    joy.armKick(_touchCooldownSec);
    joy.trail = DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);
    final fig = _figures[id];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }
    _ballSquash = SoccerFx.fireKickFeedback(
      _juice,
      ballPos: _ball.pos,
      ballSpeed: _ball.vel.distance,
      ballRadius: _ballRadius,
      feet: self.pos.translate(0, _playerRadius),
      hardKickSpeed: _hardKickSpeed,
    );
  }

  /// TRAP: kill most of the ball's speed and set it moving with the striker so
  /// it settles at the feet to be carried. No goal bias — the player steers the
  /// dribble themselves. Starts the touch cooldown (and charge reset) so the
  /// next tapped contact builds power from this moment.
  void _trapBall(Joystick joy, Body self) {
    final carry = self.vel * _trapCarrySpeed;
    _ball.vel = _ball.vel * _trapVelRetain + carry;
    joy.armKick(_touchCooldownSec);
    SoccerFx.fireTrapFeedback(
      _juice,
      feet: self.pos.translate(0, _playerRadius),
    );
  }

  /// Kick direction = blend of the striker's run direction and the direction
  /// toward the goal it attacks (so a shot biases the ball goalward). Falls back
  /// to the contact normal when the striker is standing still.
  Offset _kickDirection(int id, Body self, Offset toBall) {
    var run = _moveDir[id] ?? Offset.zero;
    if (run == Offset.zero) run = _normalize(toBall); // contact push-off
    final toGoal = _normalize(_opponentGoalTarget(id) - self.pos);
    final blended = run * _kickMoveBlend + toGoal * (1 - _kickMoveBlend);
    return _normalize(blended);
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

  /// Pick a fresh heading for a bot (applied smoothly by [_steerStrikers]) and
  /// decide whether it should SHOOT or DRIBBLE on its next ball contact:
  ///  * the rear player on a 2-player side guards its goal (tracks the ball's
  ///    horizontal position in front of its own net) and never arms a kick;
  ///  * otherwise it heads for the ball; once inside the push range it aims at
  ///    the opponent goal AND arms a KICK so contact shoots goalward, while a
  ///    far approach leaves the kick disarmed so first contact TRAPS the ball
  ///    and it carries it up-field before lining up the shot.
  /// Bots never tap, so this is the only place their kick gets armed — which is
  /// what keeps them scoring. [BotProfile] adds hesitation (errorRate) and
  /// heading jitter (accuracy) so it reads as deliberate and is beatable.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return;
    final joy = _joysticks[playerId];
    if (ctx.rng.chance(ctx.botProfile.errorRate)) {
      _botHeading[playerId] = Offset.zero; // deliberate hesitation: coast
      joy?.consumeKick(); // hold the dribble during the hesitation
      return;
    }

    if (_isKeeper(playerId)) {
      _botHeading[playerId] = SoccerFx.guardHeading(
        attacksTop: _attacksTop[playerId] ?? true,
        selfPos: self.pos,
        ballPos: _ball.pos,
        pitch: _pitch,
        playerRadius: _playerRadius,
        depthFactor: _botGuardDepthFactor,
        laneGain: _botGuardLaneGain,
      );
      joy?.consumeKick(); // a keeper clears by trapping, never a wild shot
      return;
    }

    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botSteerErrorRad;

    // Inside the push range: aim through the ball at the opponent goal and arm
    // a shot. Farther out: head for the ball and trap-dribble it on arrival.
    final inAttackRange = dist <= _playerRadius * _botGoalPushRangeFactor;
    Offset aim;
    if (inAttackRange) {
      aim = _normalize(_opponentGoalTarget(playerId) - self.pos);
      joy?.armNextKick();
    } else {
      aim = _normalize(toBall);
      joy?.consumeKick();
    }
    if (aim == Offset.zero) aim = const Offset(0, -1);

    // A throttle just under full so bots are firm but not perfectly fast.
    final throttle = (0.7 + ctx.botProfile.accuracy * 0.3).clamp(0.0, 1.0);
    _botHeading[playerId] = _rotate(aim, ctx.rng.jitter(err)) * throttle;
  }

  /// Whether [playerId] keeps net (rear-most on a 2-player side).
  bool _isKeeper(int playerId) {
    final attacksTop = _attacksTop[playerId] ?? true;
    final mates = _attacksTop.entries
        .where((e) => e.value == attacksTop)
        .map((e) => e.key);
    return SoccerFx.isKeeper(playerId, mates, (id) {
      final b = _bodyOf(id);
      if (b == null) return double.negativeInfinity;
      // Depth toward own goal (own goal is BOTTOM when attacking top).
      return attacksTop ? (b.pos.dy - _pitch.top) : (_pitch.bottom - b.pos.dy);
    });
  }

  /// Center of the goal this player is attacking (where contact should drive).
  Offset _opponentGoalTarget(int playerId) => SoccerFx.opponentGoalTarget(
      _attacksTop[playerId] ?? true, _goalMouth.center, _topLine, _bottomLine);

  /// Advance every striker figure. [freezeLocoIdle] pins locomotion to idle
  /// (used during the kickoff pause so reaction actions play over a still base
  /// instead of a stale run cycle); it never affects the sim, only what plays.
  void _syncFigures(double dt, {bool freezeLocoIdle = false}) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null) {
        fig.setLoco(!freezeLocoIdle && body.vel.distance > _runSpeed
            ? LocoState.run
            : LocoState.idle);
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
    // In the double-goals climax each goal is worth 2 — late comebacks stay live.
    final value = _isDoubleGoals ? _doubleGoalsValue : 1;
    for (final p in ctx.players) {
      if (_attacksTop[p.id] == attacksTop) addScore(p.id, value);
    }
    final color = _sideColor(attacksTop);

    // Net bulge on the goal that was scored ON (opposite the scorer's side).
    if (attacksTop) {
      _bottomBulge = _bulgeDurationSec; // ball went into the BOTTOM goal
    } else {
      _topBulge = _bulgeDurationSec;
    }

    // Celebration: the GOAL is the signature beat — a single big-moment (burst +
    // heavy shake + slow-mo + zoom toward the ball + flash + 'GOAL!' banner +
    // haptic). The crowd-roar popup + confetti pile on the flavor; the cinematic
    // banner now carries the 'GOAL!' callout (no duplicate world popup).
    _juice.bigMoment(_ball.pos, color, banner: 'GOAL!');
    _juice.popup(_pitch.center.translate(0, _pitch.shortestSide * 0.12),
        'CROWD ROARS!', const Color(0xFFFFE08A),
        size: _pitch.shortestSide * 0.04);
    _juice.confetti(_size, colors: [color, _confettiA, _confettiB]);

    // CHARM: react to the goal during the dead pause that follows — the scoring
    // side throws its arms up, the side that conceded slumps at the keeper. Fired
    // exactly once here (a goal sets the kickoff pause + resets the ball, so
    // _checkGoals can't re-enter), so no extra guard flag is needed.
    _reactToGoal(scoringAttacksTop: attacksTop);

    _kickoffPause = _kickoffPauseSec;
    _resetBall();
  }

  /// Goal reaction (pure feel, fired once from [_scoreFor]): every striker on the
  /// scoring side cheers ([StickFigure.victory] — full-body arms-up) while the
  /// conceding side's KEEPER (its rear-most defender) slumps ([StickFigure.hurt]).
  /// Plays out in the existing kickoff pause; touches no scoring/pacing state.
  void _reactToGoal({required bool scoringAttacksTop}) {
    for (final entry in _figures.entries) {
      final id = entry.key;
      final fig = entry.value;
      final onScoringSide = _attacksTop[id] == scoringAttacksTop;
      if (onScoringSide) {
        fig.victory();
      } else if (_isKeeper(id)) {
        fig.hurt();
      }
    }
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
    _juice.applyWorldTransform(canvas);

    SoccerRenderer.drawBackground(canvas, size);
    SoccerRenderer.drawPitch(canvas, _pitch);
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onBottom: false, color: _topAccent, bulge: _bulgeFill(_topBulge));
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onBottom: true, color: _bottomAccent, bulge: _bulgeFill(_bottomBulge));

    final pad = _pads.pad;
    if (pad != null) SoccerFx.drawSpeedPad(canvas, pad);

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

    _juice.render(canvas);
    canvas.restore();

    // Screen-space HUD + cinematic overlays — drawn AFTER the world transform is
    // restored so the goal camera-punch never warps fixed UI. Joysticks map
    // normalized touch points through _toPixels (full-screen px), independent of
    // the world transform, so they land correctly here too.
    SoccerRenderer.drawVignette(canvas, size);
    _drawJoysticks(canvas);
    _drawScoreboard(canvas);
    SoccerRenderer.drawKickoffBanner(
        canvas, _pitch, 'KICK OFF', _kickoffBannerAlpha());
    // DOUBLE GOALS climax banner — hidden during the kickoff pause so it never
    // overlaps the centered KICK OFF banner.
    if (_isDoubleGoals && _kickoffPause <= 0) {
      SoccerFx.drawDoubleGoalsBanner(canvas, size, 1.0, _elapsed);
    }
    _juice.renderOverlay(canvas, size);
  }

  void _drawPlayers(Canvas canvas) {
    for (final entry in _figures.entries) {
      final id = entry.key;
      final body = _bodyOf(id);
      if (body == null) continue;
      final joy = _joysticks[id];
      final actor = SoccerActor.fromParts(
        playerId: id,
        feet: Offset(body.pos.dx, body.pos.dy + body.radius),
        radius: body.radius,
        figure: entry.value,
        color: Color(_colorOf(id)),
        trail: joy?.trail,
      );
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
        armed: joy.kickArmed,
      );
    }
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
