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
/// CONTROL (the heart of it — every touch is an ACTIVE, readable decision):
///  * MOVEMENT is a VIRTUAL JOYSTICK. Touch down anywhere in your zone to anchor
///    a joystick; drag from there — the vector from the anchor to your finger is
///    the direction you run and its length is your speed. Release to stop. You
///    steer freely in 2-D.
///  * The TRAP is an ACTIVE CLAIM, not a passive stick. A loose ball is NOT
///    yours just because you ran into it — it rolls THROUGH / past your feet (to
///    a teammate, a rival, or away). You only OWN the ball when you actively TRAP
///    it: a TAP while the loose ball is in range KILLS its velocity and claims
///    it. A mistimed trap (the ball not yet in range, or already gone) whiffs and
///    the ball stays loose — a turnover a positioned opponent punishes. So
///    positioning + trap timing are the visible skill.
///  * SHOOTING is one-touch: while you POSSESS the ball, a TAP/flick SHOOTS it
///    goalward — a HYBRID aim (mostly at the goal, bent by the way you run) at a
///    power set by a quick charge that fills the instant you trap. So a player
///    traps, runs the ball up, then taps to fire. A blind tap while possessing
///    fires it straight away — an instant turnover — so spamming the button
///    throws the ball away instead of building a strike.
///
/// PACING: a real back-and-forth match — first to [_goalsToWin] goals or until
/// the [_timeLimit] expires. The ball starts dead at center, there is a brief
/// kickoff pause after every goal, and bots warm up before engaging, so the ball
/// is never instantly scored and the midfield is genuinely contested.
///
/// Feel: the ball is light so kicks fly, carries spin, leaves a motion trail and
/// bounces off the SIDE walls. A trap pops a ring + dust; a whiffed trap flashes
/// a TURNOVER. Goals trigger a net-bulge flash + big "GOAL!" popup + confetti +
/// slow-mo + crowd roar.
///
/// Teams / goals: even ids / [Team.a] attack the TOP goal (defend bottom); odd
/// ids / [Team.b] attack the BOTTOM goal (defend top). A goal awards a point to
/// every player on the scoring side (aggregated for 2v2). Bots steer toward the
/// ball with the SAME joystick model and TRAP it with the same active claim
/// (easy bots mistime the trap and turn it over; hard bots trap clean and aim),
/// and the rear player on a 2-player side drops back to guard its own net.
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

  // ── Ball control: ACTIVE TRAP to claim + TAP to shoot ────────────────────────
  // The ball is NOT yours by proximity. You must actively TRAP it: a TAP while
  // the loose ball is in range claims it (kills its velocity, sticks it ahead of
  // your feet). A tap whose window expires with no ball in range WHIFFS — the
  // ball stays loose (a turnover). Once owned, a TAP SHOOTS; shot power is a quick
  // charge that fills the moment you trap, so a held-then-aimed strike blasts and
  // a panic re-tap fires it weakly straight away (an instant turnover).
  static const double _kickContactFactor = 1.18; // overlap = within this*radii
  static const double _trapRangeFactor = 1.55; // a TAP traps a loose ball within this*contact
  // The trapped ball sits just BEYOND contact range (> 1.0) so it never overlaps
  // its owner — otherwise the arena would resolve the owner↔ball overlap every
  // frame and shove the (heavy) ball + the striker apart, knocking the dribbler
  // backwards off its own run.
  static const double _stickAheadFactor = 1.18; // ball sits this*(R+r) ahead of the feet
  static const double _possessReclaimSec = 0.32; // after YOU shoot you can't re-trap for this long
  // A press opens a TRAP/SHOOT window: a tap (released within [_tapHoldSec] and
  // dragged less than [_tapMaxDrag]) fires the intent; a longer hold or a real
  // drag is a steer-to-move and never traps or shoots. While the window is open
  // and you do NOT yet own the ball, a loose ball entering trap range is CLAIMED.
  static const double _tapHoldSec = 0.2;
  static const double _tapMaxDrag = 0.05;
  static const double _trapWindowSec = 0.26; // a press stays "trap-armed" this long
  static const double _kickPerSecond = 3.6; // full-power shot = pitch.h * this
  static const double _kickMinPowerFrac = 0.05; // a no-charge tap shoots this weak (goal-gate stops it)
  static const double _kickChargeFullSec = 0.5; // seconds of settled possession → full shot power
  // A trap kills the ball's incoming speed to this fraction (a clean catch), so a
  // claimed ball sits dead at the feet ready to be carried — never a deflection.
  static const double _trapSpeedKeep = 0.0;
  // Aim is a HYBRID: the shot flies mostly AT the goal you attack, bent toward
  // the way you are running — so it is readable (always goalward) yet you can
  // angle it into a corner past the keeper. 0 = straight at goal, 1 = where you run.
  static const double _shootBendToRun = 0.45;
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
  static const double _trapPopSec = 0.32; // trap-pop ring fade after a claim
  static const double _whiffFlashSec = 0.5; // 'MISS'/'TURNOVER' cue fade
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
  // of control) AND is in the attacking half — otherwise it keeps dribbling the
  // ball goalward. So the bot earns its shot power exactly like a skilled human,
  // and never floor-pokes the way a masher does.
  static const double _botShootPossession = 0.18;
  // A bot attempts an active TRAP when a loose ball is within this*trapRange and
  // slow enough to catch. Its trap SUCCEEDS scaled by accuracy: a hard bot snaps
  // the claim, an easy bot frequently mistimes it and turns the ball over — the
  // same active-trap skill a human reads, expressed through BotProfile.
  static const double _botTrapRangeFactor = 1.0; // of the human trap range
  static const double _botTrapMaxBallSpeed = 280.0; // won't lunge at a rocket
  // Floor on a bot's trap success so even an easy bot occasionally claims (keeps
  // an all-bot match flowing); ceiling keeps a hard bot just shy of automatic.
  static const double _botTrapSuccessFloor = 0.35;
  static const double _botTrapSuccessCeil = 0.97;

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
  double _trapPop = 0; // > 0 just after a claim (trap-pop ring)
  Offset _trapPopAt = Offset.zero; // where the last trap landed
  Color _trapPopColor = const Color(0xFFFFFFFF);
  double _ballSpin = 0; // radians, for the seam hint
  double _ballSquash = 0; // 0..1, flatten on hard hits
  Offset _ballLastDir = Offset.zero;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, Joystick> _joysticks = <int, Joystick>{};

  /// Last move direction (unit) of each striker, for the auto-kick bias.
  final Map<int, Offset> _moveDir = <int, Offset>{};

  /// Seconds each striker has held the ball in CONTROL since it TRAPPED it (a
  /// continuous claim at its feet). This — not raw proximity time — charges a
  /// shot, so the only way to a powerful, aimed strike is to TRAP and keep the
  /// ball. A masher that re-taps shoots the instant it traps (charge ~0) and so
  /// only ever floor-pokes; a turnover resets it to 0 for everyone.
  final Map<int, double> _possessionSec = <int, double>{};

  /// Side ([_attacksTop] value) of the striker who last touched the ball, or null
  /// at kickoff. A goal counts only if the scoring side made this last touch — so
  /// a defender's powerful clearance or deflection can never be an own-goal.
  bool? _lastTouchAttacksTop;

  /// Total seconds each striker has CONTROLLED the ball across the whole match.
  /// Used to break a tie on goals: the side that kept the ball wins. A masher
  /// never controls it (it kicks on every touch), so it banks ~0 here and loses
  /// every drawn match — spam cannot win even a 0–0.
  final Map<int, double> _cumPossession = <int, double>{};

  /// The striker who currently OWNS the ball (it is stuck to their feet), or null
  /// when the ball is loose (a live shot, or nobody close). Recomputed each frame.
  int? _possessor;

  /// Per-striker lockout after THEY shoot: they cannot re-own the ball until this
  /// elapses, so a shot actually travels instead of re-sticking to the shooter.
  final Map<int, double> _shootCd = <int, double>{};

  /// Touch bookkeeping to tell a TRAP/SHOOT tap from a run/move drag: where the
  /// finger pressed, how long it has been held, and whether it has dragged far.
  final Map<int, Offset> _pressNorm = <int, Offset>{};
  final Map<int, double> _pressSec = <int, double>{};
  final Map<int, bool> _draggedFar = <int, bool>{};

  /// Remaining seconds of each striker's open TRAP window (a press opens it; a
  /// long hold or a far drag closes it early). While > 0 and the striker does NOT
  /// own the ball, a loose ball entering trap range is actively CLAIMED. This is
  /// the active-claim core: no window open ⇒ the ball rolls through your feet.
  final Map<int, double> _trapArm = <int, double>{};

  /// Brief per-striker flash timer after a WHIFFED trap (a tap that found no ball
  /// in range, or a turnover), so the renderer can stamp a 'MISS'/'TURNOVER' cue.
  /// Pure feel; never gates the sim.
  final Map<int, double> _whiffFlash = <int, double>{};

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
      _possessionSec[p.id] = 0;
      _cumPossession[p.id] = 0;
      _shootCd[p.id] = 0;
      _trapArm[p.id] = 0;
      _whiffFlash[p.id] = 0;
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

  /// Test-only view of who currently OWNS the ball (the active-trap possessor),
  /// or null when the ball is loose. Lets a deterministic test assert that a
  /// well-timed tap CLAIMS a loose ball and a mistimed one does NOT, without
  /// reaching into private sim state. Not used by gameplay.
  @visibleForTesting
  int? possessorForTest() => _possessor;

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

    final id = input.playerId;
    switch (input.phase) {
      case InputPhase.down:
        joy.press(input.normPos);
        _pressNorm[id] = input.normPos;
        _pressSec[id] = 0;
        _draggedFar[id] = false;
        // A press is an ACTIVE intent. If you already OWN the ball it is a SHOOT
        // tap (fired on release once we know it stayed a tap). If the ball is
        // loose it OPENS a trap window: a loose ball that enters range while the
        // window is open is CLAIMED in [_resolveTraps]. Either way, intent first.
        if (_possessor != id) _trapArm[id] = _trapWindowSec;
      case InputPhase.holdTick:
        // A move sample carries a position; a pure per-frame held tick carries
        // only dt (normPos == Offset.zero) and just keeps the last vector.
        if (input.normPos != Offset.zero) {
          joy.drag(input.normPos);
          final dn = _pressNorm[id];
          if (dn != null && (input.normPos - dn).distance > _tapMaxDrag) {
            _draggedFar[id] = true;
            _trapArm[id] = 0; // a real drag is a MOVE, not a trap/shoot
          }
        }
      case InputPhase.up:
        joy.release();
        // A quick press that barely moved is a TAP. Possessing ⇒ SHOOT; loose ⇒
        // it was a trap attempt — if the window never caught a ball it WHIFFS
        // (a turnover cue). A press that dragged or was held is a MOVE, never a
        // stray shot or trap.
        final tap = !(_draggedFar[id] ?? false) &&
            (_pressSec[id] ?? 99) <= _tapHoldSec;
        if (tap) {
          if (_possessor == id) {
            _shoot(id);
          } else if ((_trapArm[id] ?? 0) <= 0) {
            // The window already expired with no claim → a whiffed trap tap.
            _flashWhiff(id);
          }
          // else: window still open — let _resolveTraps catch a just-arriving
          // ball this frame or the next few; if it never lands, it lapses quietly.
        } else {
          _trapArm[id] = 0;
        }
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
      joy.tick(dt); // just ages the kick trail now
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
    _resolveTraps(sdt); // active CLAIM: an open trap window catches a loose ball
    _holdPossession(sdt); // glue an owned ball to feet + bank settled possession

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
    if (_trapPop > 0) _trapPop = math.max(0, _trapPop - dt);
    // Age each held press (to tell a tap from a hold), each post-shot lockout and
    // each whiff cue. (The trap WINDOW is aged in _resolveTraps on the sim clock.)
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      if (entry.value.active) {
        _pressSec[id] = (_pressSec[id] ?? 0) + dt;
      }
      final cd = _shootCd[id] ?? 0;
      if (cd > 0) _shootCd[id] = math.max(0, cd - dt);
      final wf = _whiffFlash[id] ?? 0;
      if (wf > 0) _whiffFlash[id] = math.max(0, wf - dt);
    }
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

  // ── Ball control: ACTIVE TRAP to claim + glue while owned ────────────────────

  /// Range within which an open trap window can claim a loose ball.
  double get _trapRange =>
      (_playerRadius + _ballRadius) * _kickContactFactor * _trapRangeFactor;

  /// The ACTIVE claim. For each striker whose TRAP window is open (a fresh press,
  /// not yet a hold/drag) and that does NOT already own the ball: if the LOOSE
  /// ball is within [_trapRange] and the striker is off its post-shot lockout,
  /// CLAIM it — kill the ball's velocity, set [_possessor], pop a trap ring. The
  /// nearest armed striker wins a contested claim. A striker that did NOT tap (no
  /// open window) is ignored, so the ball rolls straight through its feet — the
  /// whole point: possession is taken, never gifted by proximity. Windows tick
  /// down here; a window that lapses with the striker still empty was a whiff.
  void _resolveTraps(double dt) {
    // Only contest if the ball is actually loose (no current owner). An owned
    // ball is glued; a rival takes it only after a shot/turnover frees it.
    if (_possessor == null) {
      int? claimer;
      var best = double.infinity;
      for (final id in _joysticks.keys) {
        if ((_trapArm[id] ?? 0) <= 0) continue; // no active trap intent
        if ((_shootCd[id] ?? 0) > 0) continue; // just shot — can't re-claim yet
        final b = _bodyOf(id);
        if (b == null) continue;
        final d = (b.pos - _ball.pos).distance;
        if (d <= _trapRange && d < best) {
          best = d;
          claimer = id;
        }
      }
      if (claimer != null) _claimBall(claimer);
    }

    // Age every open trap window. A human window that lapses unclaimed (the tap
    // landed but no ball ever arrived) shows a quiet MISS only if the player
    // already lifted — handled in onInput; here we just expire the window.
    for (final id in _joysticks.keys) {
      final w = _trapArm[id] ?? 0;
      if (w > 0) _trapArm[id] = math.max(0, w - dt);
    }
  }

  /// Claim the loose ball for [id]: kill its velocity (a clean catch), mark the
  /// possessor, reset its shot charge to 0 (you must settle to power up) and pop
  /// the trap feedback. Closes the trap window (one claim per tap).
  void _claimBall(int id) {
    final self = _bodyOf(id);
    if (self == null) return;
    _possessor = id;
    _possessionSec[id] = 0; // a fresh claim starts the charge from zero
    _trapArm[id] = 0;
    _ball.vel = _ball.vel * _trapSpeedKeep; // kill incoming speed
    _ballSquash = 1.0;
    _lastTouchAttacksTop = _attacksTop[id];
    _trapPop = _trapPopSec;
    _trapPopAt = _ball.pos;
    _trapPopColor = Color(_colorOf(id));
    SoccerFx.fireTrapFeedback(_juice,
        feet: self.pos.translate(0, _playerRadius), ballPos: _ball.pos,
        ballRadius: _ballRadius, color: _trapPopColor);
  }

  /// Stamp the whiff cue for [id] (a missed trap = a turnover) and pop its
  /// feedback. Humans only — bots turn the ball over silently (no popup clutter).
  void _flashWhiff(int id) {
    _whiffFlash[id] = _whiffFlashSec;
    if (_botClocks.containsKey(id)) return;
    final self = _bodyOf(id);
    if (self == null) return;
    SoccerFx.fireWhiffFeedback(_juice,
        feet: self.pos.translate(0, _playerRadius), radius: _playerRadius);
  }

  /// Glue an OWNED ball to its possessor's feet and bank settled possession (the
  /// live shot charge + the match-long tie-break total). No owner ⇒ the ball is
  /// loose and just obeys physics. There is NO proximity ownership: a ball only
  /// becomes owned via [_claimBall], and only leaves the feet when the owner taps
  /// to shoot (or a turnover frees it). So you move the ball by trapping then
  /// carrying it — never by running into it.
  void _holdPossession(double dt) {
    final owner = _possessor;
    for (final id in _joysticks.keys) {
      if (id != owner) _possessionSec[id] = 0;
    }
    if (owner == null) return;

    final self = _bodyOf(owner);
    if (self == null) {
      _possessor = null;
      return;
    }
    _possessionSec[owner] = (_possessionSec[owner] ?? 0) + dt;
    _cumPossession[owner] = (_cumPossession[owner] ?? 0) + dt; // match-long total

    // Glue the ball just ahead of the owner's feet in the carry direction (where
    // they run, or toward the goal when standing still), clamped inside the pitch
    // so a carry along a wall never rides the ball out of bounds.
    var dir = _moveDir[owner] ?? Offset.zero;
    if (dir == Offset.zero) dir = _normalize(_opponentGoalTarget(owner) - self.pos);
    final ahead = (_playerRadius + _ballRadius) * _stickAheadFactor;
    final raw = self.pos + dir * ahead;
    _ball.pos = Offset(
      raw.dx.clamp(_pitch.left + _ballRadius, _pitch.right - _ballRadius),
      raw.dy.clamp(_pitch.top + _ballRadius, _pitch.bottom - _ballRadius),
    );
    _ball.vel = self.vel;
    _lastTouchAttacksTop = _attacksTop[owner]; // for the no-own-goal rule
  }

  /// SHOOT the owned ball: a HYBRID aim — mostly AT the goal you attack, bent
  /// toward the way you are running ([_shootBendToRun]) so it is readable yet you
  /// can angle a corner — at a power set by the possession SETTLED since the trap
  /// (a carried, settled ball blasts; a tap fired the instant you trap nudges and
  /// dies on the goal-speed gate). Releases the ball and locks the shooter out of
  /// re-claiming it for a beat so the shot actually travels.
  void _shoot(int id) {
    final self = _bodyOf(id);
    if (self == null) return;
    final charge =
        ((_possessionSec[id] ?? 0) / _kickChargeFullSec).clamp(0.0, 1.0);
    final toGoal = _normalize(_opponentGoalTarget(id) - self.pos);
    var run = _moveDir[id] ?? Offset.zero;
    if (run == Offset.zero) run = toGoal;
    final dir = _normalize(toGoal * (1 - _shootBendToRun) + run * _shootBendToRun);
    if (dir == Offset.zero) return;

    final powerFrac = _kickMinPowerFrac + (1 - _kickMinPowerFrac) * charge;
    _ball.vel =
        dir * (_pitch.height * _kickPerSecond * powerFrac * _shotFactorOf(id));

    _possessionSec[id] = 0;
    _trapArm[id] = 0;
    _shootCd[id] = _possessReclaimSec;
    _lastTouchAttacksTop = _attacksTop[id]; // for the no-own-goal rule
    _possessor = null;

    _joysticks[id]?.trail = DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);
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

  /// Pick a fresh heading for a bot (applied smoothly by [_steerStrikers]) and,
  /// when it OWNS the ball in a shooting spot, fire a shot — bots play the exact
  /// same dribble/shoot model as a human, just without a thumb:
  ///  * the rear player on a 2-player side keeps net (tracks the ball in front of
  ///    its own goal) and never shoots;
  ///  * a LONE striker whose net is threatened (ball deep in its zone, out of
  ///    reach, and it isn't dribbling) drops back to a guard slot to intercept;
  ///  * otherwise it CHASES a loose ball to win it, DRIBBLES toward the goal once
  ///    it owns it, and SHOOTS only when it has banked possession AND reached the
  ///    attacking half — so it earns its shot power exactly like a skilled human.
  /// [BotProfile] adds hesitation (errorRate) + heading jitter (accuracy) so it
  /// reads as deliberate and stays beatable.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) {
      _botHeading[playerId] = Offset.zero; // deliberate hesitation: coast
      return;
    }

    final attacksTop = _attacksTop[playerId] ?? true;
    final toBall = _ball.pos - self.pos;
    final dist = toBall.distance;
    final inAttackRange = dist <= _playerRadius * _botGoalPushRangeFactor;
    final owns = _possessor == playerId;

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
      return;
    }

    // DEFEND: only a side WITHOUT a keeper (a lone striker) drops back to guard
    // its own net, and only when the ball is DEEP in its zone, out of reach, and
    // it isn't already dribbling it out. On a 2-player side the rear-most is the
    // keeper (above), so the outfielder presses — else both camp the net and a
    // 2v2 grinds goalless.
    if (_ownCountOf(attacksTop) <= 1 &&
        _ballDeepInOwnZone(attacksTop) &&
        !inAttackRange &&
        !owns) {
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
      return;
    }

    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botSteerErrorRad;

    // Own it → dribble toward the goal and SHOOT once charged + in the attacking
    // half (the bot earns power by dribbling, just like a human). Loose → chase
    // and, when the ball is close + slow enough, ACTIVELY TRAP it — a claim that
    // SUCCEEDS scaled by accuracy (a hard bot snaps it, an easy bot often mistimes
    // it and the ball rolls on = a turnover). Bots run the exact active-trap path.
    Offset aim;
    if (owns) {
      aim = _normalize(_opponentGoalTarget(playerId) - self.pos);
      final controlled = (_possessionSec[playerId] ?? 0) >= _botShootPossession;
      if (controlled && _selfInAttackingHalf(attacksTop, self.pos)) {
        _shoot(playerId);
      }
    } else {
      aim = _normalize(toBall); // chase a loose ball to win it
      _botTryTrap(playerId, dist);
    }
    if (aim == Offset.zero) aim = const Offset(0, -1);

    // A throttle just under full so bots are firm but not perfectly fast.
    final throttle = (0.7 + ctx.botProfile.accuracy * 0.3).clamp(0.0, 1.0);
    _botHeading[playerId] = _rotate(aim, ctx.rng.jitter(err)) * throttle;
  }

  /// A bot's ACTIVE TRAP attempt on a loose ball (the bot equivalent of a human
  /// tapping to claim). Only when the ball is loose, within the bot's trap reach
  /// and slow enough to catch: roll success scaled by accuracy (clamped to a
  /// floor so even an easy bot occasionally claims, and a ceiling so a hard bot is
  /// not automatic). On success it OPENS the same trap window a human press does,
  /// so [_resolveTraps] makes the claim through the one shared path; on failure
  /// it leaves the window shut and the ball rolls on — a turnover. [dist] is the
  /// bot→ball distance already computed by the caller.
  void _botTryTrap(int playerId, double dist) {
    if (_possessor != null) return; // ball already owned
    if ((_shootCd[playerId] ?? 0) > 0) return; // just shot — can't re-claim
    if ((_trapArm[playerId] ?? 0) > 0) return; // a window is already open
    final reach = _trapRange * _botTrapRangeFactor;
    if (dist > reach) return; // not close enough to claim yet
    if (_ball.vel.distance > _botTrapMaxBallSpeed) return; // too hot to catch
    final success = (ctx.botProfile.accuracy)
        .clamp(_botTrapSuccessFloor, _botTrapSuccessCeil);
    if (ctx.rng.chance(success)) {
      _trapArm[playerId] = _trapWindowSec; // _resolveTraps will make the claim
    }
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
    // A ball under control (stuck to a dribbler's feet) is never a goal — you
    // must SHOOT a loose ball to score, so no one can simply walk it into the net.
    if (_possessor != null) return;

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
    // No one owns the fresh ball: clear live possession, any shot lockout and any
    // open trap window so the kickoff is a clean scramble, and forget who last
    // touched it. Clear the trap-pop cue too so it never lingers across kickoff.
    for (final id in _joysticks.keys) {
      _possessionSec[id] = 0;
      _shootCd[id] = 0;
      _trapArm[id] = 0;
      _whiffFlash[id] = 0;
    }
    _possessor = null;
    _trapPop = 0;
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

    // Possession read UNDER the ball: a glow halo + a tether from the owner to
    // the ball, drawn ONLY while someone owns it (its absence = a loose ball that
    // must be TRAPPED). Makes the active-claim state instantly legible.
    _drawPossession(canvas);

    SoccerRenderer.drawBall(
      canvas,
      _ball.pos,
      _ballRadius,
      trail: List<Offset>.unmodifiable(_ballTrail),
      velDir: _ballLastDir,
      spin: _ballSpin,
      squash: _ballSquash,
    );

    // Trap-pop ring ON TOP of the ball the instant a claim lands (fades fast).
    if (_trapPop > 0) {
      SoccerFx.drawTrapPop(canvas,
          at: _trapPopAt,
          radius: _ballRadius,
          color: _trapPopColor,
          t: (_trapPop / _trapPopSec).clamp(0.0, 1.0));
    }

    _drawAimAndPower(canvas);

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

  /// The POSSESSION read, drawn ONLY while a striker (human OR bot) owns the
  /// ball: a glow halo + a tether from the owner's feet to the ball in the
  /// owner's color. Its presence/absence is the active-claim signal — a loose
  /// ball wears no tether, so a player reads at a glance that it is up for grabs
  /// and must be TRAPPED. Phase rides [_elapsed] (the existing sim clock — no new
  /// Ticker), so the halo breathes deterministically.
  void _drawPossession(Canvas canvas) {
    final id = _possessor;
    if (id == null) return;
    final self = _bodyOf(id);
    if (self == null) return;
    SoccerFx.drawPossessionTether(
      canvas,
      feet: self.pos.translate(0, _playerRadius),
      ballPos: _ball.pos,
      ballRadius: _ballRadius,
      color: Color(_colorOf(id)),
      phase: _elapsed,
    );
  }

  /// While a HUMAN owns the ball, draw the readable shot preview AT the ball: an
  /// arrow in the HYBRID aim (where a TAP would shoot — mostly at the goal, bent
  /// by the way you run) plus a power ring that fills with the possession SETTLED
  /// since the trap. So a player always sees HOW to shoot and HOW HARD before
  /// tapping (and a fresh claim shows an empty ring — settle to power up).
  void _drawAimAndPower(Canvas canvas) {
    final id = _possessor;
    if (id == null || _botClocks.containsKey(id)) return; // humans only
    final self = _bodyOf(id);
    if (self == null) return;
    final toGoal = _normalize(_opponentGoalTarget(id) - self.pos);
    var run = _moveDir[id] ?? Offset.zero;
    if (run == Offset.zero) run = toGoal;
    final dir = _normalize(toGoal * (1 - _shootBendToRun) + run * _shootBendToRun);
    if (dir == Offset.zero) return;
    final charge =
        ((_possessionSec[id] ?? 0) / _kickChargeFullSec).clamp(0.0, 1.0);
    final color = Color(_colorOf(id));

    final base = _ballRadius * 1.1;
    final len = _ballRadius * (2.2 + 3.0 * charge);
    final start = _ball.pos + dir * base;
    final end = _ball.pos + dir * (base + len);
    final w = _ballRadius * (0.34 + 0.3 * charge);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    final perp = Offset(-dir.dy, dir.dx);
    final head = _ballRadius * (0.7 + 0.3 * charge);
    final tip = end + dir * head;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((end + perp * head * 0.6).dx, (end + perp * head * 0.6).dy)
        ..lineTo((end - perp * head * 0.6).dx, (end - perp * head * 0.6).dy)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.85),
    );
    // Power ring around the ball — fills with the banked dribble possession.
    canvas.drawArc(
      Rect.fromCircle(center: _ball.pos, radius: _ballRadius * 1.7),
      -math.pi / 2,
      math.pi * 2 * charge,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ballRadius * 0.3
        ..strokeCap = StrokeCap.round
        ..color = (Color.lerp(color, const Color(0xFFFFFFFF), charge) ?? color)
            .withValues(alpha: 0.9),
    );
  }

  /// Draw each active human joystick (base ring + thumb) in the player's color,
  /// anchored at the touch origin so the player sees their control. The thumb
  /// wears the ARMED halo when a tap would ACT this instant — either you own the
  /// ball (a tap SHOOTS) or your trap window is open (a tap-in-range CLAIMS) — so
  /// the "this touch does something" cue tracks the real active-trap state.
  void _drawJoysticks(Canvas canvas) {
    if (_kickoffPause > 0) return;
    for (final entry in _joysticks.entries) {
      final id = entry.key;
      if (_botClocks.containsKey(id)) continue; // bots have no on-screen stick
      final joy = entry.value;
      if (!joy.active) continue;
      final armed = _possessor == id || (_trapArm[id] ?? 0) > 0;
      SoccerRenderer.drawJoystick(
        canvas,
        origin: _toPixels(joy.origin),
        thumb: _toPixels(joy.current),
        maxRadius: _joyMaxRadius * _size.height,
        color: Color(_colorOf(id)),
        armed: armed,
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
