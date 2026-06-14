import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

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
  // Heavy ball: a deliberate KICK / TRAP sets the ball's velocity directly so
  // those are unaffected, but a heavy ball barely moves on a body COLLISION — so
  // a masher can no longer shove it around by ramming it (the physics-collision
  // exploit that bypassed the kick economy). The ball is moved by SKILL, not by
  // running into it.
  static const double _ballMass = 8.0;
  static const double _pitchFriction = 0.985; // grass: ball coasts then settles
  static const double _ballRestitution = 0.78; // wall bounce damping
  static const double _goalMouthFraction = 0.42; // of pitch width, centered
  // A goal only counts if the ball crosses the line at least this fraction of a
  // full-power shot — a REAL strike. A slow ball (a masher's floor poke, or a
  // dribble nudged at the mouth) bounces off the end wall instead of scoring, so
  // the ONLY way to score is a possession-charged shot. This is the hard,
  // defense-independent guarantee that mashing cannot score. Floor poke power is
  // [_kickMinPowerFrac] (0.10), comfortably below this.
  static const double _goalMinSpeedFrac = 0.10;
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
  static const double _kickMinPowerFrac = 0.05; // floor power on a 0-charge poke
  static const double _kickChargeFullSec = 0.3; // possession secs → full power
  static const double _controlRangeFactor = 1.25; // ball within this*contact = control
  // Goalward aim is EARNED, not automatic: a shot flies along the striker's own
  // run line plus at most this much pull toward the goal, scaled by shot charge.
  // A settled, charged shot (skill) curves in; a fresh bundled poke (spam) gets
  // zero assist and flies exactly where the striker was already moving — so a
  // player must aim their own approach, the game never aims for them.
  static const double _kickGoalAssistMax = 0.34;
  // A goal struck above this fraction of a full-power shot reads as a SCREAMER —
  // a skill flourish that only a charged, committed strike can earn.
  static const double _screamerSpeedFrac = 0.6;
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
  // Pad boost is kept BELOW the goal-speed gate ([_goalMinSpeedFrac]) so a pad
  // can only reposition a loose ball, never gift a free scoring shot to whoever
  // herds the ball onto it — the pad is chaos flavor, not a spam scoring tool.
  static const double _padBoostPerSecond = 0.30; // boost speed = pitch.h * this
  static const double _padMinBallSpeed = 30.0; // below this, kick toward a goal

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 1.5; // grace before bots engage
  static const double _botGuardDepthFactor = 0.20; // keeper y offset from wall
  static const double _botGuardLaneGain = 0.5; // how hard keeper tracks ball x
  static const double _botSteerErrorRad = 0.4; // heading jitter at accuracy 0
  static const double _botGoalPushRangeFactor = 5.0; // push toward goal within
  // Outfield DEFENDER (any non-keeper dropping back to protect its net): it
  // steps out a little further than a stay-home keeper and tracks the ball's
  // lane harder, and it recovers at a FULL sprint — so a chase-and-poke masher
  // runs its weak shots straight into a body, while a placed shot can still
  // beat it. (Kept separate from the keeper consts so 2v2/fairness are intact.)
  static const double _botDefendDepthFactor = 0.26;
  static const double _botDefendLaneGain = 0.9;
  // A non-keeper only drops back to guard when the ball is within this fraction
  // of the pitch from its own goal; higher up it PRESSES the ball to win it.
  static const double _botDefendZoneFrac = 0.40;
  // A bot only SHOOTS once it has banked at least this much possession (seconds
  // of control) AND is in the attacking half — otherwise it keeps trapping and
  // dribbling the ball goalward. So the bot earns its shot power exactly like a
  // skilled human, and never floor-pokes the way a masher does.
  static const double _botShootPossession = 0.06;

  // ── Uneven-teams fairness (e.g. a lone human vs a 2-bot side) ────────────────
  // With an odd seat count one side is short-handed (3p ⇒ 1-vs-2). The short
  // side gets a per-extra-opponent handicap so a lone player is never hopelessly
  // outnumbered: its strikers run FASTER and its shots fly HARDER, while the
  // bigger side's keeper tracks the ball SOFTER (an easier net to beat). The
  // factor scales with the seat deficit and is exactly neutral (1.0) whenever the
  // two sides are even (1v1 / 2v2 / 1+CPU), so balanced modes are untouched.
  static const double _fairnessSpeedPerExtra = 0.22; // +22% striker speed / extra foe
  static const double _fairnessShotPerExtra = 0.30; // +30% shot power / extra foe
  static const double _fairnessKeeperPerExtra = 0.30; // big side keeper laneGain × (1-this)
  static const double _fairnessMaxExtra = 2.0; // cap the deficit the handicap scales with

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

  /// Seconds each striker has held the ball in CONTROL (continuous possession at
  /// its feet without booting it). This — not raw time — charges a shot, so the
  /// only way to a powerful, aimed strike is to TRAP and keep the ball. A masher
  /// that kicks on every contact never controls it, so its possession stays ~0
  /// and its pokes stay at the feeble floor with no goalward assist.
  final Map<int, double> _possessionSec = <int, double>{};

  /// True when a striker's most recent ball contact was a KICK (so possession is
  /// broken). A trap clears it; possession only grows while this is false.
  final Map<int, bool> _lastTouchWasKick = <int, bool>{};

  /// Side ([_attacksTop] value) of the striker who last touched the ball, or null
  /// at kickoff. A goal counts only if the scoring side made this last touch — so
  /// a defender's powerful clearance or deflection can never be an own-goal.
  bool? _lastTouchAttacksTop;

  /// Total seconds each striker has CONTROLLED the ball across the whole match.
  /// Used to break a tie on goals: the side that kept the ball wins. A masher
  /// never controls it (it kicks on every touch), so it banks ~0 here and loses
  /// every drawn match — spam cannot win even a 0–0.
  final Map<int, double> _cumPossession = <int, double>{};

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
  int _topCount = 0; // seats on each side (drives the uneven-teams handicap)
  int _bottomCount = 0;

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
        _topCount++;
      } else {
        _hasBottomSide = true;
        _bottomCount++;
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
      // Possession only banks AFTER a real trap (flag starts "kicked"), so a
      // masher that only ever kicks banks exactly zero and loses every tie.
      _possessionSec[p.id] = 0;
      _cumPossession[p.id] = 0;
      _lastTouchWasKick[p.id] = true;
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

  // ── Uneven-teams fairness factors ────────────────────────────────────────────

  /// Seat count on the side opposite [attacksTop].
  int _opponentCountOf(bool attacksTop) => attacksTop ? _bottomCount : _topCount;

  /// Seat count on the side [attacksTop].
  int _ownCountOf(bool attacksTop) => attacksTop ? _topCount : _bottomCount;

  /// How many EXTRA opponents the side [attacksTop] faces (0 when even or when it
  /// is the larger side), capped by [_fairnessMaxExtra]. This is the lever every
  /// fairness factor scales off, so a balanced split yields 0 (neutral handicap).
  double _extraFoesFor(bool attacksTop) {
    final deficit = _opponentCountOf(attacksTop) - _ownCountOf(attacksTop);
    if (deficit <= 0) return 0.0;
    return deficit.toDouble().clamp(0.0, _fairnessMaxExtra);
  }

  /// Striker speed multiplier for [id]: >1 on the short-handed side so a lone
  /// player covers the pitch faster, exactly 1 on even teams or the larger side.
  double _speedFactorOf(int id) =>
      1.0 + _fairnessSpeedPerExtra * _extraFoesFor(_attacksTop[id] ?? true);

  /// Shot-power multiplier for [id]: >1 on the short-handed side so its shots fly
  /// harder, exactly 1 on even teams or the larger side.
  double _shotFactorOf(int id) =>
      1.0 + _fairnessShotPerExtra * _extraFoesFor(_attacksTop[id] ?? true);

  /// Keeper lane-tracking gain for the side [attacksTop]: the LARGER side's keeper
  /// tracks the ball softer (an easier net for the short-handed side to beat),
  /// scaled by the deficit the OPPONENT faces; unchanged on even teams.
  double _keeperLaneGainOf(bool attacksTop) {
    final opponentExtra = _extraFoesFor(!attacksTop); // the short side's deficit
    final weaken = (_fairnessKeeperPerExtra * opponentExtra).clamp(0.0, 0.9);
    return _botGuardLaneGain * (1.0 - weaken);
  }

  /// Test-only views of the uneven-teams fairness handicap so deterministic tests
  /// can assert a short-handed side runs faster / shoots harder / faces a softer
  /// keeper without driving a whole noisy bot match. Not used by gameplay.
  @visibleForTesting
  double speedFactorForTest(int id) => _speedFactorOf(id);
  @visibleForTesting
  double shotFactorForTest(int id) => _shotFactorOf(id);
  @visibleForTesting
  double keeperLaneGainForTest(bool attacksTop) => _keeperLaneGainOf(attacksTop);

  /// Test-only views of the EARNED shot economy (the spam-proofing lever): the
  /// 0..1 power fraction and the 0..1 goalward-assist a shot gets for a given
  /// banked POSSESSION (seconds of ball control). Both sit at their floor
  /// (feeble power, zero aim) for a no-possession poke — what a masher always
  /// gets — and climb only as the ball is controlled, so a deterministic test
  /// can prove skill out-shoots spam without a noisy match.
  @visibleForTesting
  double shotPowerFracForTest(double possessionSec) {
    final charge = (possessionSec / _kickChargeFullSec).clamp(0.0, 1.0);
    return _kickMinPowerFrac + (1 - _kickMinPowerFrac) * charge;
  }

  @visibleForTesting
  double goalAssistForTest(double possessionSec) {
    final charge = (possessionSec / _kickChargeFullSec).clamp(0.0, 1.0);
    return _kickGoalAssistMax * charge;
  }

  /// Test-only normalized (0..1 full-screen) positions so a scripted "chase and
  /// mash" spam policy can steer a human seat toward the live ball through the
  /// real input path, without exposing mutable sim state to gameplay.
  @visibleForTesting
  Offset ballPosNormForTest() =>
      Offset(_ball.pos.dx / _size.width, _ball.pos.dy / _size.height);

  @visibleForTesting
  Offset strikerPosNormForTest(int id) {
    final b = _bodyOf(id);
    if (b == null) return const Offset(0.5, 0.5);
    return Offset(b.pos.dx / _size.width, b.pos.dy / _size.height);
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
    _trackPossession(sdt);
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
    // SET (not add) the ball's velocity so a pad can never STACK on top of an
    // existing shot to exceed the goal-speed gate — a pad redirects a loose ball
    // at a fixed, sub-gate pace; it can never gift a scoring shot.
    _ball.vel = dir * (_pitch.height * _padBoostPerSecond);
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
    final baseSpeed = _pitch.height * _maxSpeedFactor;
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      final body = _bodyOf(id);
      if (body == null) continue;
      // Short-handed strikers run faster (factor > 1); even teams are neutral.
      final maxSpeed = baseSpeed * _speedFactorOf(id);
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

  /// Grow the controlling striker's possession timer (and zero everyone else's)
  /// after the physics step. "Control" = the ball sits within
  /// [_controlRangeFactor] of contact range of the NEAREST striker AND that
  /// striker did not just boot it ([_lastTouchWasKick] false). A masher that
  /// kicks on every touch keeps that flag true, so it never banks possession and
  /// its shots stay at the feeble, unassisted floor — the spam-proofing core.
  void _trackPossession(double dt) {
    final ctrlRange = (_playerRadius + _ballRadius) *
        _kickContactFactor *
        _controlRangeFactor;
    int? controller;
    var best = double.infinity;
    for (final id in _joysticks.keys) {
      final b = _bodyOf(id);
      if (b == null) continue;
      final d = (b.pos - _ball.pos).distance;
      if (d <= ctrlRange && d < best) {
        best = d;
        controller = id;
      }
    }
    for (final id in _joysticks.keys) {
      if (id == controller && _lastTouchWasKick[id] != true) {
        _possessionSec[id] = (_possessionSec[id] ?? 0) + dt;
        _cumPossession[id] = (_cumPossession[id] ?? 0) + dt; // match-long total
      } else {
        _possessionSec[id] = 0;
      }
    }
  }

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

      // The contact is purely ARMED → KICK vs unarmed → TRAP. A masher holds the
      // kick armed every frame, so it ALWAYS kicks and therefore never controls
      // the ball — its shots stay at the powerless floor (below the goal-speed
      // gate, so they cannot score). Building a real shot needs the deliberate
      // disarm-to-trap (release / hold past the tap window) that a masher never
      // does. No movement "commit" check here: it only let erratic mashing trap
      // by accident and bank possession it never earned.
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
    // Charge = banked POSSESSION (time spent controlling the ball at the feet),
    // so it drives BOTH power and the earned goalward assist: a clean trap-and-
    // dribble shot is strong AND curves in, while a poke from a masher who never
    // controls the ball is feeble AND flies wherever it was already moving.
    final charge =
        ((_possessionSec[id] ?? 0) / _kickChargeFullSec).clamp(0.0, 1.0);
    final dir = _kickDirection(id, self, toBall, charge);
    if (dir == Offset.zero) return;

    // Power = floor + charge ramp, so a controlled ball blasts and a loose poke
    // only nudges — rewarding a clean trap-then-shoot. There is no position-based
    // power floor: a "defensive clearance" boost would hand a relentless chaser a
    // free long shot toward its own attacking goal whenever it reached its own
    // third, so power is ALWAYS earned by possession, never by location.
    final attacksTop = _attacksTop[id] ?? true;
    final powerFrac = _kickMinPowerFrac + (1 - _kickMinPowerFrac) * charge;
    // Replace the ball's drift with a clean shot so the kick reads crisply.
    // Short-handed strikers shoot harder (factor > 1); even teams are neutral.
    _ball.vel = dir * (kickBase * powerFrac * _shotFactorOf(id));

    // Booting the ball breaks possession: the next powerful shot must be earned
    // by trapping and controlling it again.
    _possessionSec[id] = 0;
    _lastTouchWasKick[id] = true;
    _lastTouchAttacksTop = attacksTop; // for the no-own-goal rule

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
    // A trap restores control: possession can now bank again (charging a shot).
    _lastTouchWasKick[self.id] = false;
    _lastTouchAttacksTop = _attacksTop[self.id]; // for the no-own-goal rule
    joy.armKick(_touchCooldownSec);
    SoccerFx.fireTrapFeedback(
      _juice,
      feet: self.pos.translate(0, _playerRadius),
    );
  }

  /// Kick direction = the striker's own RUN line, plus a goalward assist that is
  /// EARNED by shot [charge]: at zero charge (a fresh bundled poke / spam) the
  /// ball flies exactly where the striker was moving — no free aim — while a
  /// settled, charged shot (skill) curves up to [_kickGoalAssistMax] toward the
  /// goal. So aiming is the player's job; the game only rewards a clean
  /// trap-then-shoot with a little help. Falls back to the contact normal when
  /// the striker is standing still.
  Offset _kickDirection(int id, Body self, Offset toBall, double charge) {
    var run = _moveDir[id] ?? Offset.zero;
    if (run == Offset.zero) run = _normalize(toBall); // contact push-off
    final goalWeight = _kickGoalAssistMax * charge.clamp(0.0, 1.0);
    if (goalWeight <= 0) return _normalize(run);
    final toGoal = _normalize(_opponentGoalTarget(id) - self.pos);
    final blended = run * (1 - goalWeight) + toGoal * goalWeight;
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
  /// decide whether it should SHOOT, DRIBBLE or DEFEND on its next ball contact:
  ///  * the rear player on a 2-player side keeps net (tracks the ball's
  ///    horizontal position in front of its own goal) and never arms a kick;
  ///  * ANY non-keeper whose own net is threatened — the ball is loose in its
  ///    defensive half and it cannot yet contest it — drops back to a guard slot
  ///    between the ball and its goal to INTERCEPT (never arming, so it clears by
  ///    trapping). This is the positional skill a button-masher lacks: a pure
  ///    chaser leaves its net wide open, so its weak shots get blocked while this
  ///    bot wins the ball and counters;
  ///  * otherwise it heads for the ball; once inside the push range it aims at
  ///    the opponent goal AND arms a KICK so contact shoots goalward (a clearance
  ///    up-field doubles as the start of an attack), while a far approach leaves
  ///    the kick disarmed so first contact TRAPS the ball and carries it up-field.
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

    final attacksTop = _attacksTop[playerId] ?? true;
    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final inAttackRange = dist <= _playerRadius * _botGoalPushRangeFactor;

    if (_isKeeper(playerId)) {
      _botHeading[playerId] = SoccerFx.guardHeading(
        attacksTop: attacksTop,
        selfPos: self.pos,
        ballPos: _ball.pos,
        pitch: _pitch,
        playerRadius: _playerRadius,
        depthFactor: _botGuardDepthFactor,
        // The larger side's keeper tracks softer so the short side can score.
        laneGain: _keeperLaneGainOf(attacksTop),
      );
      joy?.consumeKick(); // a keeper clears by trapping, never a wild shot
      return;
    }

    // DEFEND: only a side WITHOUT a keeper (a lone striker) drops back to guard
    // its own net, and only when the ball is DEEP in its zone and out of reach.
    // On a 2-player side the rear-most is already the keeper (handled above), so
    // the outfielder must PRESS/attack — otherwise BOTH camp the net and a 2v2
    // grinds to a goalless stalemate. Everywhere else the bot chases to win the
    // ball and counter (the masher can't score through the goal-speed gate, so
    // there is no reason to over-defend).
    if (_ownCountOf(attacksTop) <= 1 &&
        _ballDeepInOwnZone(attacksTop) &&
        !inAttackRange) {
      final guard = SoccerFx.guardHeading(
        attacksTop: attacksTop,
        selfPos: self.pos,
        ballPos: _ball.pos,
        pitch: _pitch,
        playerRadius: _playerRadius,
        depthFactor: _botDefendDepthFactor,
        laneGain: _botDefendLaneGain,
      );
      final gd = guard.distance;
      _botHeading[playerId] = gd <= 1e-6 ? Offset.zero : guard / gd;
      joy?.consumeKick();
      return;
    }

    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botSteerErrorRad;

    // Attack flow that mirrors the skill the game demands: CHASE a loose ball,
    // then TRAP and DRIBBLE it goalward to bank possession, and SHOOT only once
    // it is controlled AND in the attacking half. Arming with no possession just
    // floor-pokes the ball (exactly what a masher does), so the bot earns its
    // power the same way a skilled human must.
    final controlled = (_possessionSec[playerId] ?? 0) >= _botShootPossession;
    final canShoot =
        inAttackRange && controlled && _selfInAttackingHalf(attacksTop, self.pos);
    Offset aim;
    if (canShoot) {
      aim = _normalize(_opponentGoalTarget(playerId) - self.pos); // take the shot
      joy?.armNextKick();
    } else if (inAttackRange) {
      aim = _normalize(_opponentGoalTarget(playerId) - self.pos); // dribble up
      joy?.consumeKick();
    } else {
      aim = _normalize(toBall); // chase a loose ball
      joy?.consumeKick();
    }
    if (aim == Offset.zero) aim = const Offset(0, -1);

    // A throttle just under full so bots are firm but not perfectly fast.
    final throttle = (0.7 + ctx.botProfile.accuracy * 0.3).clamp(0.0, 1.0);
    _botHeading[playerId] = _rotate(aim, ctx.rng.jitter(err)) * throttle;
  }

  /// True when [selfPos] is in [attacksTop]'s ATTACKING half (the half holding
  /// the goal it is trying to score on). Gates when a bot may take its shot.
  bool _selfInAttackingHalf(bool attacksTop, Offset selfPos) {
    final mid = _pitch.center.dy;
    return attacksTop ? selfPos.dy < mid : selfPos.dy > mid;
  }

  /// True when the ball sits DEEP in [attacksTop]'s own zone — within
  /// [_botDefendZoneFrac] of the goal it must protect (the BOTTOM when it attacks
  /// the top, the TOP when it attacks the bottom). Only then does a non-keeper
  /// drop back to guard; higher up it presses the ball instead.
  bool _ballDeepInOwnZone(bool attacksTop) {
    final band = _pitch.height * _botDefendZoneFrac;
    return attacksTop
        ? _ball.pos.dy > _pitch.bottom - band
        : _ball.pos.dy < _pitch.top + band;
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

    // Only a REAL strike scores: a slow ball (a masher's floor poke or a nudged
    // dribble) is not a goal — it just rebounds off the end wall. So scoring
    // demands a possession-charged shot, no matter how leaky the defense.
    final fastEnough =
        _ball.vel.distance >= _pitch.height * _kickPerSecond * _goalMinSpeedFrac;
    if (!fastEnough) return;

    // Which side a ball in this net is credited to. The whole rest of the game's
    // convention — opponentGoalTarget, spawn side, keeper guard, isKeeper depth —
    // treats attacksTop=true as "attacks the TOP goal", so a ball in the TOP net
    // is scored BY the attacksTop=true side (and the BOTTOM net by the other).
    final bool? scoringSide = (_ball.pos.dy <= _topLine && _hasTopSide)
        ? true
        : (_ball.pos.dy >= _bottomLine && _hasBottomSide)
            ? false
            : null;
    if (scoringSide == null) return;

    // NO OWN-GOALS: a goal counts only if the scoring side made the last touch.
    // A powerful defensive clearance or a deflection off the conceding side that
    // rolls in is waved off and the ball is re-kicked off — so the defender's
    // own power can never be turned into the masher's points.
    if (_lastTouchAttacksTop != scoringSide) {
      _resetBall();
      return;
    }

    _scoreFor(attacksTop: scoringSide);
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
    // A goal struck hard (a charged, committed strike) earns the SCREAMER call —
    // a visible reward for skill, never for a trickle-in poke.
    final screamer =
        _ball.vel.distance >= _pitch.height * _kickPerSecond * _screamerSpeedFrac;
    _juice.bigMoment(_ball.pos, color, banner: screamer ? 'SCREAMER!' : 'GOAL!');
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
    // No one owns the fresh ball: clear live possession and require a fresh TRAP
    // before anyone banks again (flag set as if kicked), so a masher banks none.
    for (final id in _joysticks.keys) {
      _possessionSec[id] = 0;
      _lastTouchWasKick[id] = true;
    }
    _lastTouchAttacksTop = null;
  }

  /// Finish early when a side reaches [_goalsToWin], or when time expires.
  void _resolveOutcome() {
    final topScore = _sideScore(attacksTop: true);
    final bottomScore = _sideScore(attacksTop: false);
    final reached = topScore >= _goalsToWin || bottomScore >= _goalsToWin;
    if (reached || _elapsed >= _timeLimit) {
      _finishByScoreThenPossession();
    }
  }

  /// Rank by goals, then by match-long POSSESSION as the tie-break. A drawn game
  /// is won by whoever controlled the ball more — so a masher (who never controls
  /// it) cannot win even a 0–0, while a side that trapped and dribbled is
  /// rewarded. This is what makes skilled play beat spam when the score is level.
  void _finishByScoreThenPossession() {
    final ids = ctx.players.map((p) => p.id).toList()
      ..sort((a, b) {
        final byScore = scoreOf(b).compareTo(scoreOf(a));
        if (byScore != 0) return byScore;
        return (_cumPossession[b] ?? 0).compareTo(_cumPossession[a] ?? 0);
      });
    finishWith(WinResult(
      ranking: ids,
      finalScores: {for (final id in ids) id: scoreOf(id)},
    ));
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
