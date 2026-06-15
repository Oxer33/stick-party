import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';
import '../../core/math2.dart';
import '../../engine/helpers/tap_mash_meter.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'tug_render.dart';

/// Side of the rope. Top pulls the marker toward -1, bottom toward +1. The rope
/// runs vertically (north/south) down the tall portrait screen.
enum _Side { top, bottom }

/// Tug of War — a TOP team and a BOTTOM team HEAVE on the BEAT to drag a
/// VERTICAL rope marker past their goal line (top/bottom edge of the tall
/// screen); the first side to do so wins and the losers ragdoll-fly into a
/// central mud/lava pit. At the time limit the side nearer its goal wins, so the
/// round ALWAYS resolves. Sides split by [Team] (Team.a = top, Team.b = bottom)
/// or, with no teams, even/odd player id (even = top).
///
/// OBJECTIVE (obvious from the scene): drag the rope's flag MARKER past YOUR
/// goal line. The flag rides the rope between the two goal lines and the live
/// score is how far your side has dragged it home ([_publishScores]).
///
/// CORE — read the TENSION, time the POWER HEAVE, NOT a mash:
///  * A shared metronome sweeps a marker through a centered SWEET-SPOT on the
///    beat track. **One TAP landed in the sweet-spot = one HEAVE** that hauls the
///    rope toward your goal, armed once per window pass.
///  * Every clean heave winds your side's **ROPE TENSION** up; it bleeds away
///    fast, so it only stays high while you keep landing heaves. The big, prominent
///    TENSION meter is the skill made VISIBLE — and the per-beat decision:
///      - Heave while the rope is **TAUT** (high tension) → a **POWER HEAVE**:
///        2–3× the pull, the rope thickens / shakes / glows and a big pop fires.
///        This is the play that wins, and you can SEE it coming as the bar fills.
///      - Heave while **SLACK** (low tension) → a weak dud that barely nudges the
///        rope. So a centered tap that builds tension, then a TAUT power heave,
///        out-hauls someone who grabs every weak heave the instant it arms.
///    Precision still matters: a dead-center tap winds MORE tension than an edge
///    tap, so aiming for center is how you reach TAUT fastest.
///
/// WHY BLIND SPAM LOSES (the anti-mash teeth):
///  * Any tap that is NOT a fresh on-beat heave is a **MISS** — an off-beat tap,
///    OR a second/third tap inside a window you already heaved. A MISS makes the
///    rope SLIP toward your OWN goal-loss (a small recoil to the opponent) and
///    DUMPS your tension + effort. So a blind masher tapping every frame lands
///    one SLACK dud per window and then SLIPS on every other tap, its tension
///    pinned near zero — it drives the marker the WRONG way and loses the rope to
///    a player who reads the bar and power-heaves on each beat. (Proven by a
///    deterministic test.)
///
/// CLIMAX: late-round HEAVEs pull harder ("FINAL HEAVE!"). COMEBACK: the trailing
/// side gets a small HEAVE bonus so it stays in the fight (never enough to beat a
/// steady taut lead). Bots time POWER HEAVES on a [BotProfile] cadence and never
/// double-tap, so they never self-slip; easy bots heave slack / mistime the window
/// (beatable) and hard bots wind tension and POWER HEAVE often.
///
/// Kid read: watch your TENSION bar fill, wait till the rope is TAUT, then TAP on
/// the slider's middle for a giant heave. Mashing keeps you SLACK and slips you.
class TugOfWar extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tug_of_war',
        name: 'Tug of War',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'TAP',
      );

  // ── Round / marker tuning (no magic numbers inline) ─────────────────────────
  // ~20s cap; back-and-forth play means an all-bot round still runs several
  // seconds before one side edges past its goal, so it never resolves instantly.
  static const double _timeLimit = 20;
  static const double _winThreshold = 1.0; // |marker| to win
  static const double _markerCenterPullPerSec = 0.03; // idle bleed toward 0
  // ON-BEAT HEAVE: the rope moves only on a HEAVE — a TAP (down) landed inside
  // the sweet-spot when a fresh heave is armed (one per window pass). Pull scales
  // with PRECISION: an edge-of-window tap barely moves the rope, a dead-center
  // tap pulls hardest. So aiming for the center — rhythm + nerve — beats slapping
  // the instant the window opens. Off-beat taps and extra in-window taps MISS
  // (see _missSlip), so blind mashing backfires instead of pulling.
  static const double _heavePullMin = 0.012; // pull for an edge-of-window heave
  static const double _heavePullMax = 0.060; // pull for a dead-center heave

  // ── Rope TENSION → POWER HEAVE (the visible skill) ───────────────────────────
  // Every clean heave winds the side's ROPE TENSION up (more for a centered tap),
  // and it bleeds fast — so it only stays high while you keep landing heaves. The
  // big TENSION meter is the readable, learnable cue. Heave while TAUT (tension at
  // or above [_tautThreshold]) and the heave is a POWER HEAVE: the base pull is
  // multiplied from [_powerHeaveMulMin] (just taut) up to [_powerHeaveMulMax]
  // (fully wound). Heave while SLACK and the heave is a weak dud ([_slackHeaveMul]
  // of base) that barely nudges the rope. So the per-beat decision is VISIBLE and
  // ACTIVE: wind the bar to TAUT for a giant haul, vs grab a weak heave sooner.
  // Tuned so a STEADY on-beat chain of centered heaves climbs into the TAUT band
  // in ~3–4 beats and then sustains POWER (read value after the fast inter-beat
  // decay stays above [_tautThreshold]), while a masher — which dumps 80% of its
  // tension on every off-beat miss — is pinned SLACK and only ever lands duds.
  static const double _tensionGainEdge = 0.18; // tension wound by an edge heave
  static const double _tensionGainCenter = 0.60; // tension wound by a center heave
  static const double _tensionDecayPerSec = 0.70; // fast bleed — must keep heaving
  static const double _tautThreshold = 0.5; // tension ≥ this ⇒ POWER HEAVE
  static const double _powerHeaveMulMin = 2.0; // pull × this at the taut threshold
  static const double _powerHeaveMulMax = 3.0; // pull × this at full tension
  static const double _slackHeaveMul = 0.5; // a slack (low-tension) heave is a dud
  // A miss dumps this fraction of the side's tension (on top of the effort dump),
  // so a masher can never stay taut — its dud heaves never build into a POWER one.
  static const double _slipTensionDump = 0.8;

  // ── Effort meter (per side) tuning ──────────────────────────────────────────
  static const double _effortPerTap = 0.12; // meter bump per tap
  static const double _effortDecayPerSec = 0.55; // bleeds so you must keep going

  // ── Visible HEAVE beat (a sweeping sweet-spot you tap ON) ────────────────────
  // A HEAVE is armed once per window pass (one heave per beat — a human can't
  // double-dip a single beat for free; a second tap MISSES and slips), so total
  // pull tracks *timing*, not raw tap rate. Blind spam off the beat slips.
  static const double _beatPeriodSec = 1.05; // one full left→right→left sweep
  static const double _beatWindowHalf = 0.13; // sweet-spot half-width (0..1 pos)
  static const double _heaveSurgeSec = 0.34; // pull-surge window (body twitch)
  static const double _heaveCueSec = 0.45; // shockwave cue life

  // ── Miss-slip (the anti-mash teeth) ─────────────────────────────────────────
  // ANY tap that is not a fresh on-beat heave is a MISS: an off-beat tap, or a
  // repeat tap inside a window already heaved. A miss SLIPS the rope toward the
  // misser's own goal-loss (a small recoil to the opponent) and DUMPS a chunk of
  // their effort. So a frame-by-frame masher heaves once per window then slips on
  // every other tap, netting BACKWARD — blind spam loses the rope. [_slipRecoil]
  // is kept well under a clean centered heave so a single mistimed tap is a
  // readable nick, not a death sentence; it only piles up under real mashing.
  static const double _slipRecoil = 0.013; // marker recoil toward the opponent per miss
  static const double _slipEffortDump = 0.5; // fraction of effort lost on a miss
  // The marker recoil + effort dump apply on EVERY miss (that's the anti-spam
  // teeth), but the SLIP cosmetic (popup + body buckle) is rate-limited to once
  // per this cooldown so a frame-by-frame masher can't flood thousands of popups.
  static const double _slipCueCooldownSec = 0.22;
  // Bots heave ONCE per armed window (no repeat taps), so they never self-slip.
  // Their heave precision is set by accuracy — strong bots land near center, weak
  // bots near the edge. Centered enough that even weak bots still pull a little.
  static const double _botHeavePrecBase = 0.35; // weakest-bot heave precision
  static const double _botHeavePrecGain = 0.6; // extra precision at full accuracy
  static const double _botHeavePrecJitter = 0.45; // ×(1-acc) heave-precision spread
  // Window-hit chance = accuracy / this. Set just ABOVE 1 so even a hard bot
  // (accuracy 0.93 ⇒ ~0.89 hit) catches MOST windows and HOLDS the rope TAUT, but
  // skips a few — that small dropout + the heave-precision jitter give a hard duel
  // genuine seed-to-seed variance (a coin-flippy wall, not an all-or-nothing wipe).
  // Weaker bots skip far more, bleed out of TAUT, and land SLACK duds (beatable).
  static const double _botFlawlessAccuracy = 1.05;

  // ── Final-HEAVE climax ───────────────────────────────────────────────────────
  // In the last stretch every landed HEAVE pulls harder (a frantic finale) and a
  // one-shot "FINAL HEAVE!" banner + shake fire so the ending is unmistakable.
  static const double _climaxFrac = 0.72; // fraction of timeLimit → climax begins
  static const double _climaxHeaveMul = 1.6; // HEAVE pull × this during climax

  // ── Comeback (kid-assist) ────────────────────────────────────────────────────
  // The side currently LOSING the marker battle gets a small bonus on its HEAVE
  // pull, scaled by how far behind it is — keeps a trailing team in the fight
  // without ever out-pulling a steady on-beat lead on its own.
  static const double _comebackMaxBonus = 0.4; // up to +40% HEAVE pull when far behind

  // ── Uneven-teams fairness (a lone puller vs two) ─────────────────────────────
  // With an odd seat count one side has FEWER pullers (3p ⇒ 1-vs-2). That side's
  // every HEAVE is multiplied so the rope contest stays fair regardless of side
  // sizes: each missing body is worth [_underdogPullPerDeficit] extra pull, so a
  // 1-vs-2 lone puller heaves ~1.9x (≈ matching two opponents). The multiplier is
  // exactly 1.0 when the sides are even (1v1 / 2v2), so balanced modes are
  // untouched. This stacks on top of the marker-based comeback bonus.
  static const double _underdogPullPerDeficit = 0.9; // +90% HEAVE per missing teammate
  static const double _underdogMaxDeficit = 2.0; // cap the deficit it scales with

  // ── Bot heave cadence (sec/attempt); harder bots attempt faster + steadier ──
  static const double _botWarmupSec = 0.45; // short grace: human gets the 1st beat
  static const double _botBaseInterval = 0.22;
  static const double _botAccuracyBonus = 0.07; // faster at high accuracy
  static const double _botJitterBase = 0.06; // sloppier at low accuracy
  // Per-heave bot pull factor scaled by accuracy: a SLOPPY bot grips weak (well
  // under a clean human heave), a TOP bot grips a touch SUPERHUMAN — so a perfect
  // human sweeps easy/medium but a hard bot can out-haul them on some seeds, a
  // genuine-but-beatable wall. Lerps [_botPullFactorMin]→[_botPullFactorMax].
  static const double _botPullFactorMin = 0.5; // weakest-bot pull factor
  static const double _botPullFactorMax = 1.35; // strongest-bot pull factor
  static const double _botPullFactorExp = 2.6; // convex: edge concentrated at top

  // ── Layout tuning (fractions of arena) ──────────────────────────────────────
  static const double _ropeInsetFrac = 0.1; // team hands inset from edges (Y)
  static const double _midXFrac = 0.5; // rope / action column (X)
  static const double _ropeBowFrac = 0.04; // sideways rope wobble depth / width
  static const double _goalInsetFrac = 0.2; // goal line inset from edges (Y)
  static const double _runnerGapFrac = 0.16; // spacing per figure across a side
  static const double _runnerBackoffFrac = 0.025; // figures beyond the goal line
  static const double _pitWidthFrac = 0.42; // pit ellipse width / width
  static const double _pitHeightFrac = 0.14; // pit ellipse height / height
  static const double _crowdBandFrac = 0.14; // dark crowd band height / height
  static const double _effortBarFrac = 0.34; // effort bar width / width
  static const double _effortBarInsetFrac = 0.1; // bar Y inset from each edge
  static const double _beatTrackFrac = 0.62; // HEAVE beat track width / width
  static const double _beatTrackYFrac = 0.5; // beat track height (frac h)

  // ── Figure / feel tuning ────────────────────────────────────────────────────
  static const double _figureScale = 2.0; // bigger, readable pullers
  static const double _maxLeanRad = 0.3; // max strain tilt at full effort
  static const double _bodyWidthFactor = 3.2; // dust/shadow half-width / torsoW
  static const Color _splashMud = Color(0xFFB8500F);
  static const Color _splashLava = Color(0xFFFFC23A);
  static const Color _accent = Color(0xFFFFB54D);

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for shimmer/dust
  double _marker = 0; // [-1, 1]; -1 = top wins, +1 = bottom wins
  double _beatPos = 0.5; // 0..1 sweep position of the shared HEAVE beat
  double _beatClock = 0; // phase accumulator for the ping-pong sweep
  bool _beatWasInWindow = true; // edge-detect to re-arm HEAVE once per pass
  bool _resolved = false;
  bool _finalHeaveFired = false; // one-shot "FINAL HEAVE!" climax cue latch

  late double _midX;
  late double _topHandY;
  late double _bottomHandY;
  late double _topGoalY;
  late double _bottomGoalY;
  late double _centerY;
  late Offset _pitCenter;
  late double _pitRx;
  late double _pitRy;
  late double _footReach; // pelvis→foot length at rest (for grounding)
  late double _bodyW; // rough body half-width for dust/shadows

  final Map<int, _Puller> _pullers = <int, _Puller>{};
  final Map<_Side, TapMashMeter> _effort = <_Side, TapMashMeter>{};
  // Per-side ROPE TENSION (0..1): wound by clean heaves, bleeds fast, dumped on a
  // miss. At/above [_tautThreshold] a heave becomes a POWER HEAVE. This is the
  // headline, visible skill meter the player reads to time the big haul.
  final Map<_Side, double> _tension = <_Side, double>{
    _Side.top: 0.0,
    _Side.bottom: 0.0,
  };
  // Brief per-side glow timer lit when a POWER HEAVE just fired (drives the rope
  // thicken/shake/glow + the TAUT meter pop). Cosmetic only.
  final Map<_Side, double> _powerFlash = <_Side, double>{
    _Side.top: 0.0,
    _Side.bottom: 0.0,
  };

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _computeLayout();

    _effort[_Side.top] = _makeEffortMeter();
    _effort[_Side.bottom] = _makeEffortMeter();

    final proportions = StickProportions.hero.scaled(_figureScale);
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = proportions.thigh + proportions.shin;
    _bodyW = proportions.torsoWidth * _bodyWidthFactor;

    for (final p in ctx.players) {
      final side = _sideFor(p);
      // Facing is fixed up per-figure in [_fixFacings] once roots are known.
      _pullers[p.id] = _Puller(
        slot: p,
        side: side,
        figure: StickFigure(
          proportions: proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1.0,
        )..setLoco(LocoState.run),
        botInterval: _botInterval(),
        botJitter: _botJitter(),
      );
    }
    _fixFacings();
    begin();
  }

  void _computeLayout() {
    _midX = _size.width * _midXFrac;
    _topHandY = _size.height * _ropeInsetFrac;
    _bottomHandY = _size.height * (1 - _ropeInsetFrac);
    _topGoalY = _size.height * _goalInsetFrac;
    _bottomGoalY = _size.height * (1 - _goalInsetFrac);
    _centerY = _size.height / 2;
    _pitRx = _size.width * _pitWidthFrac * 0.5;
    _pitRy = _size.height * _pitHeightFrac * 0.5;
    // Pit sits dead center; the rope sags into its mouth from both ends.
    _pitCenter = Offset(_midX, _centerY);
  }

  /// Make each puller face the rope column: figures left of center face right,
  /// figures right of center face left, so a spread row grips inward.
  void _fixFacings() {
    for (final pl in _pullers.values) {
      final root = _runnerRoot(pl);
      pl.figure.facing = root.dx <= _midX ? 1.0 : -1.0;
    }
  }

  TapMashMeter _makeEffortMeter() => TapMashMeter(
        tapImpulse: _effortPerTap,
        decayPerSec: _effortDecayPerSec,
      );

  /// Bright puller style: player-color fill, brightened outline, strong glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0, // we draw our own contact shadow
        gradientBottom: 0.55,
        smearAlpha: 0.28,
      );

  /// Team-aware split: Team.a = top, Team.b = bottom honor explicit teams;
  /// otherwise even ids pull top, odd ids pull bottom. Guarantees a non-empty
  /// opposing side when there are 2+ players.
  _Side _sideFor(PlayerSlot p) {
    if (p.team == Team.a) return _Side.top;
    if (p.team == Team.b) return _Side.bottom;
    return p.id.isEven ? _Side.top : _Side.bottom;
  }

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.05, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  /// Sloppier (more jitter) at low accuracy, so weak bots miss the rhythm
  /// window more often and strong bots stay metronomic.
  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.25;
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    // One-touch: only the press matters. A tap is either a fresh on-beat HEAVE or
    // a MISS that slips. Release / holdTick carry no decision in this rework.
    if (input.phase == InputPhase.down) _tap(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _tickBeat(dt); // real-time so the sweet-spot reads the same regardless of hitstop
    _maybeFireFinalHeave();
    _driveBots(sdt);
    _tickHeave(sdt);
    _tickEffort(sdt);
    _tickTension(sdt);
    _applyMarkerCenterPull(sdt);

    for (final pl in _pullers.values) {
      pl.figure.update(sdt);
    }
    _publishScores();
    _resolveIfDecided();
  }

  // ── Beat: a shared metronome marker ping-ponging across the rhythm track ─────

  /// Advance the ping-pong sweep. [_beatPos] runs 0→1→0 over [_beatPeriodSec],
  /// so the marker visibly slides through the centered sweet-spot twice a cycle.
  /// Each time the marker leaves the window we re-arm every puller's HEAVE latch,
  /// so the next window pass grants exactly one fresh HEAVE per player.
  void _tickBeat(double dt) {
    _beatClock = (_beatClock + dt) % _beatPeriodSec;
    final tri = _beatClock / _beatPeriodSec; // 0..1
    _beatPos = tri < 0.5 ? tri * 2 : 2 - tri * 2; // triangle wave 0→1→0

    final inWindow = _beatInWindow;
    if (!inWindow && _beatWasInWindow) {
      for (final pl in _pullers.values) {
        pl.heaveArmed = true;
      }
    }
    _beatWasInWindow = inWindow;
  }

  /// True when the beat marker currently sits inside the centered sweet-spot.
  bool get _beatInWindow => (_beatPos - 0.5).abs() <= _beatWindowHalf;

  /// Test-only view of the sweet-spot window so deterministic tests can tap
  /// exactly on the beat. Not used by gameplay.
  @visibleForTesting
  bool get beatWindowOpenForTest => _beatInWindow;

  /// Test-only view of how centered the beat is right now (0 = window edge,
  /// 1 = dead center) so a test can model a SKILLED human that taps at the
  /// strongest moment, not just anywhere in the window. Not used by gameplay.
  @visibleForTesting
  double get beatPrecisionForTest => _beatInWindow ? _beatPrecision : 0.0;

  /// 0..1 precision of the current beat position: 1 = dead-center, 0 = window
  /// edge. Drives how strong an on-beat HEAVE is, so aiming for the center beats
  /// slapping the moment you enter the window.
  double get _beatPrecision =>
      1.0 - ((_beatPos - 0.5).abs() / _beatWindowHalf).clamp(0.0, 1.0);

  /// Test-only read of a player's side ROPE TENSION (0..1). Lets a test watch
  /// the visible skill meter build as clean heaves land. Not used by gameplay.
  @visibleForTesting
  double tensionForTest(int playerId) {
    final pl = _pullers[playerId];
    if (pl == null) return 0.0;
    return _tension[pl.side] ?? 0.0;
  }

  /// Test-only POWER-HEAVE threshold so a test can assert the TAUT boundary
  /// without hard-coding the tuning value. Not used by gameplay.
  @visibleForTesting
  static double get tautThresholdForTest => _tautThreshold;

  /// Test-only driver: force [playerId]'s side tension to [tension], then land a
  /// single dead-center HEAVE for that player (independent of the beat clock), and
  /// return how far that one heave dragged the marker toward the player's goal
  /// (its score delta). Lets a test prove a TAUT heave hauls multiples of a SLACK
  /// one with no reliance on beat timing. Only valid while running. Not gameplay.
  @visibleForTesting
  double driveHeaveAtTensionForTest(int playerId, double tension) {
    final pl = _pullers[playerId];
    if (pl == null || status != MiniGameStatus.running) return 0.0;
    _tension[pl.side] = tension.clamp(0.0, 1.0);
    final before = scoreOf(playerId).toDouble();
    _fireHeave(pl, 1.0); // a dead-center heave; tension decides power vs slack
    _publishScores();
    return scoreOf(playerId).toDouble() - before;
  }

  // ── Tap → on-beat HEAVE or MISS (slip) ──────────────────────────────────────

  /// A tap (down). Resolves to ONE of two outcomes:
  ///  * **HEAVE** — the beat is in the sweet-spot AND this player still has a
  ///    fresh heave armed this pass: consume the arm, feed effort, and haul the
  ///    rope toward the goal (pull scales with how centered the tap was).
  ///  * **MISS** — anything else (off-beat tap, or a repeat tap inside a window
  ///    already heaved): the rope SLIPS toward the misser's goal-loss and their
  ///    effort dumps. This is what makes blind mashing backfire.
  void _tap(int id) {
    final pl = _pullers[id];
    if (pl == null) return;
    if (_beatInWindow && pl.heaveArmed) {
      pl.heaveArmed = false; // consume this window pass: one heave per beat
      _fireHeave(pl, _beatPrecision.clamp(0.0, 1.0));
    } else if (_beatInWindow) {
      // Already heaved THIS window: an extra on-beat tap is simply ignored, not
      // punished — so a player who taps the still-lit "HEAVE!" again isn't hit
      // with a baffling SLIP. Spam still loses on the OFF-beat taps below (the
      // window is a small slice of the sweep, so a masher racks up misses).
      return;
    } else {
      _missSlip(pl);
    }
  }

  /// Land an on-beat HEAVE for [pl] at the given [precision] (0 = window edge,
  /// 1 = dead center).
  ///
  /// The skill lives in the ROPE TENSION read. The side's tension BEFORE this
  /// heave decides the payoff:
  ///  * **POWER HEAVE** — tension was TAUT (≥ [_tautThreshold]): the base pull is
  ///    multiplied 2–3× (scaled by how far past taut), the rope thickens / shakes
  ///    / glows and a big pop fires. This is the winning play and the bar tells
  ///    you when it is live.
  ///  * **SLACK HEAVE** — tension was low: a weak dud ([_slackHeaveMul] of base)
  ///    that barely nudges the rope.
  /// The heave THEN winds tension up (more for a centered tap), so chaining clean
  /// centered heaves is what climbs you into the TAUT band for the next pull.
  /// Base pull still lerps [_heavePullMin]→[_heavePullMax] by precision and is
  /// scaled by effort + climax / comeback / underdog, then drags the marker home.
  void _fireHeave(_Puller pl, double precision) {
    final prec = precision.clamp(0.0, 1.0);
    final tensionBefore = _tension[pl.side] ?? 0.0;
    final isPower = tensionBefore >= _tautThreshold;
    final powerMul = _heaveMultiplierFor(tensionBefore);

    _effort[pl.side]?.tap(); // a landed heave banks effort; misses dump it
    final effort = _effort[pl.side]?.progress ?? 0.0;
    _windTension(pl.side, prec); // this heave winds the rope for the NEXT pull
    _heaveJuice(pl, prec, isPower: isPower);
    if (isPower) {
      _powerFlash[pl.side] = _heaveCueSec;
      _powerHeaveJuice(pl, powerMul);
    }

    var pull = lerpD(_heavePullMin, _heavePullMax, prec) * (1.0 + 0.25 * effort);
    pull *= powerMul; // POWER HEAVE (taut) hauls 2–3×; SLACK heave is a dud
    if (pl.slot.isBot) pull *= _botPullFactor(); // grip scales with bot accuracy
    if (_inClimax) pull *= _climaxHeaveMul; // CLIMAX: finale pulls harder
    pull *= 1.0 + _comebackBonusFor(pl.side); // COMEBACK: help the trailing side
    pull *= _underdogPullMul(pl.side); // FAIRNESS: a short-handed side pulls harder
    _marker += pl.side == _Side.top ? -pull : pull;
    _marker = clampD(_marker, -_winThreshold, _winThreshold);
  }

  /// Pull multiplier from the side's tension AT the moment of the heave:
  /// SLACK (below taut) → [_slackHeaveMul] (a dud), TAUT → [_powerHeaveMulMin]
  /// ramping to [_powerHeaveMulMax] as tension fills toward 1. This is the whole
  /// risk/reward curve: a visible bar that, once TAUT, doubles-to-triples a heave.
  double _heaveMultiplierFor(double tension) {
    final tn = tension.clamp(0.0, 1.0);
    if (tn < _tautThreshold) return _slackHeaveMul;
    final over = ((tn - _tautThreshold) / (1.0 - _tautThreshold)).clamp(0.0, 1.0);
    return lerpD(_powerHeaveMulMin, _powerHeaveMulMax, over);
  }

  /// Wind a side's ROPE TENSION up by a landed heave: a centered tap winds far
  /// more ([_tensionGainCenter]) than an edge tap ([_tensionGainEdge]), so aiming
  /// for center is how you reach TAUT fastest. Clamped to 1.
  void _windTension(_Side side, double precision) {
    final gain = lerpD(_tensionGainEdge, _tensionGainCenter, precision.clamp(0.0, 1.0));
    _tension[side] = ((_tension[side] ?? 0.0) + gain).clamp(0.0, 1.0);
  }

  /// A MISS: a mistimed / spammed tap. The rope SLIPS toward the misser's own
  /// goal-loss (giving the opponent ground) and the side's effort dumps. Small
  /// per miss, but a frame-by-frame masher racks these up far faster than its one
  /// armed heave can pull — so spam nets BACKWARD. A clear, readable nick.
  void _missSlip(_Puller pl) {
    // ── Mechanic (every miss): recoil + effort dump — the anti-spam teeth. ──
    final recoil = _slipRecoil * (1.0 + _comebackBonusFor(_other(pl.side)));
    // The marker moves toward the OPPONENT's goal (top miss → drifts down/+;
    // bottom miss → drifts up/-), i.e. the misser loses ground.
    _marker += pl.side == _Side.top ? recoil : -recoil;
    _marker = clampD(_marker, -_winThreshold, _winThreshold);
    // Effort + TENSION bleed on a miss: a masher can never stay TAUT, so its dud
    // heaves never compound into a POWER one. This is the core anti-spam lever.
    _drainEffort(pl.side, _slipEffortDump);
    _tension[pl.side] =
        ((_tension[pl.side] ?? 0.0) * (1.0 - _slipTensionDump)).clamp(0.0, 1.0);
    pl.surge = 0;

    // ── Cosmetic (rate-limited): a masher misses every frame, so only fire the
    // SLIP popup + body buckle once per cooldown to avoid flooding popups. ──
    if (pl.slipCueCd > 0) return;
    pl.slipCueCd = _slipCueCooldownSec;
    pl.cue = _heaveCueSec; // reuse the cue ring as a "slip!" tell
    pl.figure.hurt(); // a buckle on the body so the mistimed tap reads as a slip
    final at = _runnerRoot(pl).translate(0, -_footReach * 0.9);
    _juice.popup(at, 'SLIP!', _splashLava, size: 22);
  }

  /// Bleed [frac] (0..1) of a side's effort meter — re-tapping the meter back up
  /// from a fraction of its current value. Used on a miss so a single mistimed
  /// tap dents the side's effort without the helper mutating engine internals.
  void _drainEffort(_Side side, double frac) {
    final m = _effort[side];
    if (m == null) return;
    final keep = (m.progress * (1.0 - frac.clamp(0.0, 1.0))) * m.maxValue;
    m.reset();
    // Re-bank the kept portion in whole tap impulses (cheap, allocation-free).
    var banked = 0.0;
    while (banked + _effortPerTap <= keep) {
      m.tap();
      banked += _effortPerTap;
    }
  }

  _Side _other(_Side side) => side == _Side.top ? _Side.bottom : _Side.top;

  /// True once the round passes the climax fraction of its life — HEAVEs surge.
  bool get _inClimax => _elapsed >= _timeLimit * _climaxFrac;

  /// 0.._comebackMaxBonus extra HEAVE-pull fraction for [side], scaled by how
  /// far it is losing the marker battle. Zero for the side currently ahead, so
  /// only the trailing team is ever helped and a steady lead still wins.
  double _comebackBonusFor(_Side side) {
    // Marker < 0 favors top, > 0 favors bottom; a side is "behind" when the
    // marker sits on the opponent's half.
    final behind = side == _Side.top ? math.max(0.0, _marker) : math.max(0.0, -_marker);
    final t = (behind / _winThreshold).clamp(0.0, 1.0);
    return _comebackMaxBonus * t;
  }

  /// HEAVE-pull MULTIPLIER (>= 1) for the short-handed [side], so a lone puller
  /// matches a bigger opposing team. Scales with the seat DEFICIT (opponent count
  /// minus own count, capped): 1-vs-2 ⇒ ~1.9x, even sides ⇒ exactly 1.0. Unlike
  /// the marker-based comeback bonus this depends only on roster sizes, so it is
  /// steady all round and keeps even-team modes untouched.
  double _underdogPullMul(_Side side) {
    final deficit = _countOnSide(_other(side)) - _countOnSide(side);
    if (deficit <= 0) return 1.0;
    final scaled = deficit.toDouble().clamp(0.0, _underdogMaxDeficit);
    return 1.0 + _underdogPullPerDeficit * scaled;
  }

  /// Fire the one-shot "FINAL HEAVE!" climax cue when the finale begins.
  void _maybeFireFinalHeave() {
    if (_finalHeaveFired || !_inClimax) return;
    _finalHeaveFired = true;
    _juice.popup(
      Offset(_midX, _centerY - _pitRy * 2.4),
      'FINAL HEAVE!',
      _accent,
      size: 34,
    );
    _juice.shake.medium();
    // A soft gold screen wash marks the start of the frantic finale.
    _juice.flashScreen(_accent, strength: 0.3);
  }

  /// Cosmetic burst for a landed HEAVE. A SLACK heave is a small dud ("slack")
  /// with a thin spark; a POWER HEAVE is loud and is handled by [_powerHeaveJuice]
  /// on top of this. Precision still scales the base burst (a center tap reads
  /// stronger than an edge one).
  void _heaveJuice(_Puller pl, double precision, {required bool isPower}) {
    pl.surge = _heaveSurgeSec;
    pl.cue = _heaveCueSec;
    final prec = precision.clamp(0.0, 1.0);
    final at = _runnerRoot(pl).translate(0, -_footReach * 0.9);
    if (!isPower) {
      // A weak, low-tension heave: a quiet "slack" tell so the player FEELS that
      // it barely moved the rope and learns to wind tension first.
      _juice.popup(at, 'slack', _splashLava.withValues(alpha: 0.85), size: 18);
      _juice.particles.burst(
        at: at,
        count: 3,
        color: _colorOf(pl.slot.id),
        speed: 90,
        size: 4,
        life: 0.3,
      );
      return;
    }
    // POWER HEAVE base burst (the headline pop is added in _powerHeaveJuice).
    _juice.particles.burst(
      at: at,
      count: (6 + 6 * prec).round(),
      color: _colorOf(pl.slot.id),
      speed: 180 + 110 * prec,
      size: 5,
      life: 0.4,
    );
  }

  /// The unmistakable POWER HEAVE pop: a big "POWER HEAVE!" banner-popup, a
  /// camera-shake scaled by the multiplier, a hot shockwave cue and a bright
  /// burst — so a taut heave is felt instantly, distinct from a slack dud.
  /// [mul] is the live pull multiplier (2..3) so a fully-wound heave shouts
  /// louder than a just-taut one.
  void _powerHeaveJuice(_Puller pl, double mul) {
    final at = _runnerRoot(pl).translate(0, -_footReach * 0.9);
    final hot = (mul - _powerHeaveMulMin) /
        (_powerHeaveMulMax - _powerHeaveMulMin); // 0..1 across the taut band
    final h = hot.clamp(0.0, 1.0);
    _juice.popup(at, 'POWER HEAVE!', _accent, size: 28 + 10 * h);
    _juice.shake.shake(0.18 + 0.12 * h, 4.0 + 3.0 * h);
    _juice.particles.burst(
      at: at,
      count: (14 + 12 * h).round(),
      color: _brighten(_colorOf(pl.slot.id), 0.3),
      speed: 280 + 160 * h,
      size: 7,
      life: 0.55,
    );
    // A short, sharp hit-stop sells the yank without stalling the round.
    _juice.hitStop.trigger(Feel.hitStopDefaultSec);
  }

  /// Decay every side's ROPE TENSION toward zero. Fast bleed means a side stays
  /// TAUT only while it keeps landing clean heaves — the meter is alive and
  /// readable, and idle/slipping sides fall back to SLACK quickly.
  void _tickTension(double dt) {
    final drop = _tensionDecayPerSec * dt;
    for (final side in _Side.values) {
      final v = _tension[side] ?? 0.0;
      if (v > 0) _tension[side] = math.max(0.0, v - drop);
      final pf = _powerFlash[side] ?? 0.0;
      if (pf > 0) _powerFlash[side] = math.max(0.0, pf - dt);
    }
  }

  /// Decay the per-puller surge / cue / slip-cue timers (body twitch + cue ring
  /// life + the SLIP-cosmetic cooldown).
  void _tickHeave(double dt) {
    for (final pl in _pullers.values) {
      if (pl.surge > 0) pl.surge = math.max(0, pl.surge - dt);
      if (pl.cue > 0) pl.cue = math.max(0, pl.cue - dt);
      if (pl.slipCueCd > 0) pl.slipCueCd = math.max(0, pl.slipCueCd - dt);
    }
  }

  void _tickEffort(double dt) {
    for (final m in _effort.values) {
      m.update(dt);
    }
  }

  void _applyMarkerCenterPull(double dt) {
    if (_marker == 0) return;
    final pull = _markerCenterPullPerSec * dt;
    if (_marker > 0) {
      _marker = math.max(0, _marker - pull);
    } else {
      _marker = math.min(0, _marker + pull);
    }
  }

  /// Drive bots — WINDOW-driven, so timing is reliable (not phase-locked to a
  /// drifting cadence). Once per armed window pass a bot makes a SINGLE heave
  /// decision: a [_botHitsBeat] roll (which saturates to flawless at top accuracy)
  /// decides whether it commits a clean heave this window. Committing or skipping
  /// both consume the arm, so a bot acts exactly once per window — never off-beat,
  /// never twice (it can't self-slip). Because each clean heave winds ROPE TENSION
  /// and the bleed between windows is fixed, this tiers the POWER HEAVE naturally:
  /// a HARD bot catches EVERY window at near-center precision, so it HOLDS the rope
  /// TAUT and sustains POWER HEAVES (a genuine wall a perfect human only mostly
  /// beats). A WEAK bot skips windows, so its tension bleeds out and it mostly
  /// lands SLACK duds — beatable. A separate cadence clock only feeds a little
  /// between-heave side effort so the pace stays lively. A short warmup hands the
  /// human the first beat.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return;
    for (final pl in _pullers.values) {
      if (!pl.slot.isBot) continue;

      // One heave decision per armed window pass (window-locked, like a human).
      if (_beatInWindow && pl.heaveArmed) {
        pl.heaveArmed = false; // consume this window pass either way
        if (_botHitsBeat()) {
          _fireHeave(pl, _botHeavePrecision());
        }
      }

      // Between-heave effort feed on a light cadence (lively pace + body lean).
      pl.botClock += dt;
      var guard = 0;
      while (pl.botClock >= pl.nextTapAt && guard++ < 8) {
        pl.botClock -= pl.nextTapAt;
        _effort[pl.side]?.tap();
        pl.nextTapAt = _nextBotInterval(pl);
      }
    }
  }

  /// A bot's chance of committing a heave this window (accuracy / a near-1 divisor,
  /// clamped). A HARD bot catches MOST windows and HOLDS the rope TAUT — sustaining
  /// POWER HEAVES (a genuine wall) — while still skipping a few for variance. A
  /// weaker bot skips enough windows that its tension bleeds out between hits, so
  /// it mostly lands SLACK duds and stays beatable. Timing reliability is the tier
  /// separator here; precision + pull factor scale the payoff.
  bool _botHitsBeat() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final chance = (acc / _botFlawlessAccuracy).clamp(0.0, 1.0);
    return ctx.rng.chance(chance);
  }

  /// The precision a bot heaves at (0 = edge, 1 = center). The mean scales with
  /// accuracy (strong bots near center, weak near the floor) and gets a symmetric
  /// jitter whose width SHRINKS with accuracy — a top bot is steady, a weak bot
  /// scatters. The per-heave jitter is the honest source of seed-to-seed variance,
  /// so a hard duel is a real coin-flippy wall (the human edges it on some seeds,
  /// the bot on others) rather than an all-or-nothing wipe. Never slips (floored).
  double _botHeavePrecision() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final mean = _botHeavePrecBase + _botHeavePrecGain * acc;
    final spread = _botHeavePrecJitter * (1.0 - acc);
    return (mean + ctx.rng.jitter(spread)).clamp(0.0, 1.0);
  }

  /// Per-heave pull factor for a bot, scaled by accuracy: a sloppy bot grips well
  /// under a clean human heave; a top bot grips a touch superhuman so it can
  /// out-haul even a perfect human on some seeds (a real wall), while easy/medium
  /// stay sweepable.
  double _botPullFactor() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final t = math.pow(acc, _botPullFactorExp).toDouble();
    return lerpD(_botPullFactorMin, _botPullFactorMax, t);
  }

  double _nextBotInterval(_Puller pl) =>
      math.max(0.04, pl.botInterval + ctx.rng.jitter(pl.botJitter));

  /// Score = how far this player's side has dragged the marker (0..1), so the
  /// on-field HUD shows the leading side. Teammates share their side value.
  void _publishScores() {
    for (final pl in _pullers.values) {
      final advantage = pl.side == _Side.top
          ? math.max(0.0, -_marker)
          : math.max(0.0, _marker);
      setScore(pl.slot.id, advantage);
    }
  }

  // ── Resolution ──────────────────────────────────────────────────────────────

  void _resolveIfDecided() {
    if (_marker <= -_winThreshold) {
      _resolve(_Side.top);
    } else if (_marker >= _winThreshold) {
      _resolve(_Side.bottom);
    } else if (_elapsed >= _timeLimit) {
      // Nearer goal wins; dead-even falls to top for determinism.
      _resolve(_marker <= 0 ? _Side.top : _Side.bottom);
    }
  }

  void _resolve(_Side winner) {
    if (_resolved) return;
    _resolved = true;

    // Comedy: losers get yanked off their feet and ragdoll-fly toward the
    // winner's edge (up if top wins, down if bottom wins) and off-screen.
    final winnerIsTop = winner == _Side.top;
    // Floor placed past the far edge so the loser sails off rather than landing.
    final groundY = winnerIsTop ? -_size.height : _size.height * 2;
    for (final pl in _pullers.values) {
      if (pl.side == winner) continue;
      final root = _runnerRoot(pl);
      // Fling toward the winner's edge: dominant vertical lift in that direction
      // plus a small inward nudge so the arc carries over the pit.
      final vy = winnerIsTop ? -_size.height * 0.55 : _size.height * 0.55;
      final vx = (_midX - root.dx).sign * _size.width * 0.12;
      pl.figure.enterRagdoll(root, groundY, Offset(vx, vy));
    }

    // Winning side throws an arms-up cheer (firing once, here, as the round
    // resolves) so the victors react on the body BEFORE the confetti — the
    // losing side is already ragdoll-flying into the pit above.
    for (final pl in _pullers.values) {
      if (pl.side != winner) continue;
      pl.figure
        ..setLoco(LocoState.idle)
        ..victory();
    }

    _splashAndPopups(winner);
    // Signature WIN! cinematic: burst + shake + slow-mo + zoom toward the rope
    // knot (the marker that just crossed) + flash + banner + haptic.
    _juice.bigMoment(_knotPos(), _colorOf(_anyWinnerId(winner)), banner: 'WIN!');
    _juice.hitStop.trigger(Feel.hitStopHeavySec, scale: 0.1);
    _juice.confetti(_size, colors: [_colorOf(_anyWinnerId(winner))]);
    _publishScores();

    final winners = <int>[];
    final losers = <int>[];
    for (final pl in _pullers.values) {
      (pl.side == winner ? winners : losers).add(pl.slot.id);
    }
    finishByOrder([...winners, ...losers]);
  }

  void _splashAndPopups(_Side winner) {
    // Big mud + lava splash erupting upward from the pit.
    _juice.particles.burst(
      at: _pitCenter,
      count: 26,
      color: _splashMud,
      speed: 420,
      spread: math.pi * 1.1,
      baseAngle: -math.pi / 2,
      size: 9,
      gravity: 900,
      life: 0.8,
    );
    _juice.particles.burst(
      at: _pitCenter,
      count: 16,
      color: _splashLava,
      speed: 360,
      spread: math.pi * 0.9,
      baseAngle: -math.pi / 2,
      size: 7,
      gravity: 800,
      life: 0.7,
    );
    _juice.popup(_pitCenter.translate(0, -_pitRy * 2.2), 'SPLASH!', _splashLava,
        size: 40);

    // "WIN!" over the winning side's goal line.
    final winY = winner == _Side.top ? _topGoalY : _bottomGoalY;
    _juice.popup(Offset(_midX, winY), 'WIN!', _colorOf(_anyWinnerId(winner)),
        size: 36);
  }

  int _anyWinnerId(_Side winner) {
    for (final pl in _pullers.values) {
      if (pl.side == winner) return pl.slot.id;
    }
    return ctx.players.isEmpty ? 0 : ctx.players.first.id;
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    TugRenderer.drawBackground(canvas, size);
    TugRenderer.drawCrowdBands(canvas, size, _crowdBandFrac,
        lead: _marker, t: _animClock);
    TugRenderer.drawPit(canvas, _pitCenter, _pitRx, _pitRy, _animClock);
    TugRenderer.drawFieldLines(
        canvas, size, _midX, _centerY, _topGoalY, _bottomGoalY,
        lead: _marker, t: _animClock);

    _drawTeamsAndRope(canvas);
    _drawTensionBars(canvas);
    _drawBeatTrack(canvas);

    // Vignette over the field, intensifying as the marker nears an edge.
    TugRenderer.drawVignette(canvas, size, _markerEdgeProximity(), t: _animClock);

    _juice.render(canvas);
    canvas.restore();

    // Screen-space cinematic overlays (flash + WIN! banner) after the world
    // transform is restored, so they are not shaken or zoomed.
    _juice.renderOverlay(canvas, size);
  }

  /// 0 at center, →1 as the marker approaches either goal (drives tension cues).
  double _markerEdgeProximity() =>
      (_marker.abs() / _winThreshold).clamp(0.0, 1.0);

  void _drawTeamsAndRope(Canvas canvas) {
    final topLead = _colorOf(_frontPullerId(_Side.top));
    final bottomLead = _colorOf(_frontPullerId(_Side.bottom));

    // Rope first (behind the pullers' hands), running vertically to the knot.
    final knot = _knotPos();
    final bow = _size.width * _ropeBowFrac;
    // The rope reads TAUT from two sources: how near the marker is to a goal AND a
    // live POWER HEAVE (a fresh power flash on either side thickens / shakes /
    // glows the whole rope for that beat). max() so a power heave pops it even at
    // mid-field, making the big haul unmistakable on the rope itself.
    final powerTaut = math.max(_powerFlashOf(_Side.top), _powerFlashOf(_Side.bottom));
    final ropeTaut = math.max(_markerEdgeProximity(), powerTaut);
    TugRenderer.drawRope(
      canvas,
      Offset(_midX, _topHandY),
      Offset(_midX, _bottomHandY),
      knot,
      bow,
      topLead,
      bottomLead,
      t: _animClock,
      taut: ropeTaut,
    );

    // Pullers: shadow + dust under each, then the leaning/straining figure.
    for (final pl in _pullers.values) {
      final root = _runnerRoot(pl);
      final feet = Offset(root.dx, root.dy + _footReach);
      final color = _colorOf(pl.slot.id);

      if (!pl.figure.isRagdoll) {
        TugRenderer.drawContactShadow(canvas, feet, _bodyW);
        final effort = _effort[pl.side]?.progress ?? 0.0;
        final dustDir = root.dx <= _midX ? -1.0 : 1.0;
        TugRenderer.drawFootDust(canvas, feet, _bodyW, effort, _animClock,
            dir: dustDir);
      }

      _drawLeaningPuller(canvas, pl, root);

      if (pl.cue > 0) {
        final strength = (pl.cue / _heaveCueSec).clamp(0.0, 1.0);
        TugRenderer.drawHeaveCue(
            canvas, root.translate(0, -_footReach * 0.9), strength, color);
      }
    }

    // Flag marker rides the rope knot last so it sits on top of the rope.
    TugRenderer.drawMarkerFlag(
        canvas, knot, _marker, topLead, bottomLead, _animClock);
  }

  /// Draw a puller straining against the rope by an amount that grows with their
  /// side's effort (premium body language). Ragdolls render upright (their own
  /// frame already encodes the tumble). The strain is a tilt that ROTATES the
  /// figure around its planted feet — the figure never translates off-frame, so
  /// the top team stays on the tall screen. Top and bottom teams tilt in
  /// opposite screen directions so the two rows visibly lean against each other.
  void _drawLeaningPuller(Canvas canvas, _Puller pl, Offset root) {
    if (pl.figure.isRagdoll) {
      TugRenderer.drawPuller(canvas, pl.figure, root);
      return;
    }
    final effort = _effort[pl.side]?.progress ?? 0.0;
    final surgeKick = pl.surge > 0 ? 0.06 : 0.0;
    // Tilt away from the pull, around the feet pivot. Top team leans one way,
    // bottom team the other, so the rows read as hauling against each other.
    final dirTilt = pl.side == _Side.top ? -1.0 : 1.0;
    final tilt = (_maxLeanRad * effort + surgeKick) * dirTilt;
    final pivot = Offset(root.dx, root.dy + _footReach);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(tilt);
    canvas.translate(-pivot.dx, -pivot.dy);
    TugRenderer.drawPuller(canvas, pl.figure, root);
    canvas.restore();
  }

  /// The headline ROPE TENSION meters — one per side, near each team's edge. The
  /// fill is the side's live tension; the TAUT zone (≥ [_tautThreshold]) is marked
  /// so the player can SEE exactly when a heave becomes a POWER HEAVE, and the bar
  /// flares on a fresh power flash. This is the visible, learnable skill cue the
  /// whole rework hangs on (it replaces the old raw effort bar).
  void _drawTensionBars(Canvas canvas) {
    final barW = _size.width * _effortBarFrac;
    final topBarY = _size.height * _effortBarInsetFrac;
    final bottomBarY = _size.height * (1 - _effortBarInsetFrac);
    final topColor = _colorOf(_frontPullerId(_Side.top));
    final bottomColor = _colorOf(_frontPullerId(_Side.bottom));
    TugRenderer.drawTensionBar(
      canvas,
      Offset(_midX, topBarY),
      barW,
      _tension[_Side.top] ?? 0.0,
      _tautThreshold,
      _powerFlashOf(_Side.top),
      topColor,
      _accent,
      dir: -1,
      t: _animClock,
    );
    TugRenderer.drawTensionBar(
      canvas,
      Offset(_midX, bottomBarY),
      barW,
      _tension[_Side.bottom] ?? 0.0,
      _tautThreshold,
      _powerFlashOf(_Side.bottom),
      bottomColor,
      _accent,
      dir: 1,
      t: _animClock,
    );
  }

  /// Normalized (0..1) freshness of a side's last POWER HEAVE flash, for the rope
  /// + bar pop. 1 right when it fires, decaying to 0 over [_heaveCueSec].
  double _powerFlashOf(_Side side) =>
      ((_powerFlash[side] ?? 0.0) / _heaveCueSec).clamp(0.0, 1.0);

  /// The shared HEAVE beat: a centered rhythm track with a sweet-spot window and
  /// a sweeping marker. Tapping while the marker is inside the window lands a
  /// HEAVE — this is the visible rhythm cue the whole skill layer hangs on. Sits
  /// on the center row, on top of the pit, so both teams read the same beat.
  void _drawBeatTrack(Canvas canvas) {
    final width = _size.width * _beatTrackFrac;
    final center = Offset(_midX, _size.height * _beatTrackYFrac);
    TugRenderer.drawBeatTrack(
      canvas,
      center,
      width,
      _beatPos,
      _beatWindowHalf,
      inWindow: _beatInWindow,
      accent: _accent,
      t: _animClock,
    );
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  /// Rope knot world position: rides between the goal lines vertically, mapped
  /// from the marker. Sits on the rope column (center x).
  Offset _knotPos() {
    final t = (_marker + 1) / 2; // 0..1 over [-1,1]
    final y = lerpDouble(_topGoalY, _bottomGoalY, t)!;
    return Offset(_midX, y);
  }

  /// Stick root for a puller: stacked just beyond their goal line (top team
  /// above the top line, bottom team below the bottom line), spread across the
  /// width by their index within the side so multiple figures don't overlap.
  /// Pelvis is lifted by [_footReach] so the feet plant on the team's foot line.
  Offset _runnerRoot(_Puller pl) {
    final gap = _size.width * _runnerGapFrac;
    final backoff = _size.height * _runnerBackoffFrac;
    final index = _indexOnSide(pl);
    final count = _countOnSide(pl.side);
    // Spread the side's figures symmetrically across the center column.
    final spreadX = _midX + (index - (count - 1) / 2.0) * gap;
    if (pl.side == _Side.top) {
      final y = _topGoalY - backoff - _footReach;
      return Offset(spreadX, y);
    }
    final y = _bottomGoalY + backoff - _footReach;
    return Offset(spreadX, y);
  }

  int _indexOnSide(_Puller pl) {
    var i = 0;
    for (final other in _pullers.values) {
      if (other.side != pl.side) continue;
      if (other.slot.id == pl.slot.id) return i;
      i++;
    }
    return i;
  }

  int _countOnSide(_Side side) {
    var n = 0;
    for (final pl in _pullers.values) {
      if (pl.side == side) n++;
    }
    return n;
  }

  /// The front (index 0) puller id on a side, used for the team's accent tint.
  int _frontPullerId(_Side side) {
    for (final pl in _pullers.values) {
      if (pl.side == side && _indexOnSide(pl) == 0) return pl.slot.id;
    }
    // Fallback to any player on that side, else player 0.
    for (final pl in _pullers.values) {
      if (pl.side == side) return pl.slot.id;
    }
    return ctx.players.isEmpty ? 0 : ctx.players.first.id;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}

/// Per-player tug state for one round. Mutable round-scoped state (allowed for
/// the duration of a single round).
class _Puller {
  final PlayerSlot slot;
  final _Side side;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;

  // Bot cadence clock.
  double botClock = 0;
  double nextTapAt;

  // On-beat HEAVE bookkeeping.
  bool heaveArmed = true; // true = a fresh heave is available this window pass
  double surge = 0; // seconds of active pull surge remaining (body twitch)
  double cue = 0; // seconds of HEAVE / SLIP shockwave cue remaining
  double slipCueCd = 0; // cooldown gating the SLIP cosmetic (anti popup-flood)

  _Puller({
    required this.slot,
    required this.side,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
  }) : nextTapAt = botInterval;
}
