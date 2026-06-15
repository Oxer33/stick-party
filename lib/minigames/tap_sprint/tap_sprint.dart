import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';
import '../../core/math2.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'sprint_render.dart';

/// Hurdle Dash — a [_raceMeters] m sprint over a track of HURDLES. (Keeps the
/// legacy `tap_sprint` id; the old "mash a button to run" sprint is gone.)
///
/// OBJECTIVE (obvious from the scene + HUD): be FIRST to cross the FINISH line.
/// If nobody finishes before the buzzer, the runner who covered the most
/// distance wins. The finish banner and a "Xm / 100m" readout sit over every
/// lane so the goal is unmistakable.
///
/// CORE — one-touch, a CADENCE not a mash:
///  * **Rhythmic TAPS = stride.** Speed is built and held by tapping ON the
///    stride cadence — a tap spaced inside [_strideLo].._strideHi banks a clean
///    stride and grows your gait rhythm; the rhythm (not the raw tap rate) sets
///    your run speed. Tapping FASTER than the cadence does nothing extra, and
///    OVER-MASHING (taps far below the window) breaks stride: it bleeds rhythm,
///    so a blind masher actually runs SLOWER than a metronomic runner.
///
/// INTERPOSING DIFFICULTY — HURDLES (the SKILL beat, a TIMED-RELEASE vault):
///  * Hurdles sit at fixed distances down the track and scroll toward the runner.
///    Each is **telegraphed**: as it enters the runner's approach window a
///    POWER/TIMING bar with a bright SWEET-SPOT zone rises above the runner.
///  * **PRESS = wind-up.** While the press is held the bar fills 0→1 at a fixed
///    rate (a readable, predictable sweep). **RELEASE decides everything:**
///      - release with the bar inside the sweet spot → a CLEAN VAULT (a big
///        satisfying pop + a rhythm/speed reward — you sail over and surge).
///      - release too EARLY (bar short of the zone) or too LATE (bar past it),
///        OR never wind up at all → a STUTTER-CLIP: the runner stumbles into the
///        bar (a hard speed loss + a brief dead stop), then recovers.
///    Re-pressing while winding RESETS the bar (a stutter), so hammering the
///    button never charges a vault — the bar just keeps snapping back to zero.
///  * Hurdles get DENSER and the sweet-spot zone TIGHTER the further you run (a
///    calibrated ramp), so the back half demands cleaner release timing.
///  * A blind tapper never HOLDS, so its bar never fills and it never releases in
///    the zone — it clips on essentially every hurdle and trips. A runner who
///    reads the bar and releases in the sweet spot clears cleanly and pulls away.
///    (Proven by a deterministic test.)
///
/// One-touch read, two clearly-different beats: TAP a steady beat to run; when a
/// hurdle lights up, PRESS to wind up the bar and RELEASE in the sweet spot to
/// vault. The skill is VISIBLE (the bar) and FELT (each clean release surges).
///
/// BOTS: stride on a [BotProfile] cadence AND wind up + release in the sweet spot
/// as each hurdle enters the window — strong bots release dead-center (clean),
/// weak bots release off-center or, on an [errorRate] slip, skip the wind-up and
/// clip. A real, beatable 1+CPU contest.
class TapSprint extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tap_sprint',
        name: 'Hurdle Dash',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  // ── Round / track tuning (no magic numbers inline) ──────────────────────────
  // Nobody-finishes ceiling. A measured solo runner finishes in ~22s (well
  // inside this); the timer only bites when the hurdle gauntlet keeps everyone
  // short (the ~25-40s target band). A blind masher trips so much it never
  // finishes in time — the whole anti-spam point.
  static const double _timeLimit = 38;
  static const double _raceMeters = 100; // finish distance; shown in the HUD

  // ── Stride cadence (the CADENCE, not a mash) ────────────────────────────────
  // A tap spaced inside [_strideLo, _strideHi] is a clean STRIDE: it grows gait
  // rhythm. A tap FASTER than _strideLo is an over-mash: it banks no rhythm and
  // bleeds a little (mashing breaks stride). Rhythm 0..1 drives run speed, so a
  // metronomic runner outruns a masher outright.
  static const double _strideLo = 0.10; // good-cadence window (sec) lo
  static const double _strideHi = 0.22; // good-cadence window (sec) hi — tighter
  static const double _rhythmGainPerStride = 0.17; // rhythm per clean stride
  static const double _rhythmDecayPerSec = 0.42; // idle / off-beat bleed toward 0
  static const double _overMashRhythmPenalty = 0.10; // rhythm lost per over-mash
  // The opening tap (or a tap after a long idle) is a free clean stride so a
  // runner is never punished merely getting off the blocks.
  static const double _kickoffGraceSec = 0.7;

  // Run speed (m/s) as a function of gait rhythm: a dead-rhythm jog floor up to
  // a full-rhythm sprint. Rhythm — not tap rate — is the throttle.
  static const double _jogSpeed = 1.8; // m/s at rhythm 0 (barely moving)
  static const double _sprintSpeed = 8.6; // m/s at rhythm 1 (full cadence)

  // ── Hurdles (the interposing difficulty) ────────────────────────────────────
  // Hurdles are seeded down the track from [_firstHurdleM] to near the finish.
  // Spacing SHRINKS toward the finish (denser late) and the jump window TIGHTENS
  // — a calibrated difficulty ramp. The first stretch is an open run-up so the
  // start is fair.
  static const double _firstHurdleM = 14; // open run-up before hurdle 1
  static const double _lastHurdleM = 94; // last hurdle sits just before the tape
  static const double _gapStartM = 13.0; // spacing between the first hurdles (m)
  static const double _gapEndM = 7.0; // spacing between the last hurdles (m)

  // The approach window: the band (meters AHEAD of the runner) in which the
  // POWER/TIMING bar is OFFERED for the next hurdle — pressing here begins a
  // wind-up. NARROWS down the track (less lead time late). Reaching the hurdle
  // without a clean release = a trip.
  static const double _windowStartM = 6.0; // approach depth at the first hurdle
  static const double _windowEndM = 3.6; // approach depth at the last hurdle
  // Airborne arc length once a CLEAN release launches the vault. Purely the
  // visual hop now — clearance is decided by the release timing, not the arc.
  static const double _vaultAirSec = 0.42; // airborne arc length (sec)

  // ── Timed-release vault (the SKILL) ─────────────────────────────────────────
  // PRESS with a hurdle in the approach window arms a wind-up; the power bar
  // fills 0→1 at this rate while HELD (a fixed, readable sweep). RELEASE judges
  // the bar against the sweet-spot zone: inside → CLEAN vault; outside (early or
  // late) → clip. The fill rate is constant (≈ [_windupFillSec] to top out) so
  // the read is a pure timing skill, not a rhythm-coupled one.
  static const double _windupFillSec = 0.62; // seconds for the bar to fill 0→1
  // Sweet-spot zone (a band on the 0..1 bar). Centered a little past the middle
  // so a player builds INTO it. Half-width NARROWS down the track (tighter late)
  // but stays kid-forgiving early.
  static const double _sweetCenter = 0.60; // zone centre on the 0..1 bar
  static const double _sweetHalfStart = 0.22; // zone half-width at hurdle 1 (wide)
  static const double _sweetHalfEnd = 0.13; // zone half-width at the last hurdle
  // A clean release rewards a rhythm bump + a brief speed surge (the felt pop).
  static const double _vaultRhythmReward = 0.14; // rhythm gained on a clean vault
  static const double _vaultSurgeSec = 0.5; // speed-line / surge tell duration

  // TRIP: a stutter-clip — a mistimed / missing release. The runner loses most
  // of its rhythm, dead stops for a beat, then recovers. Heavy on purpose — it
  // must cost a spammer more than it can claw back before the next (denser)
  // hurdle, so blind play nets near-zero up the track. A reader trips ~never.
  static const double _tripRhythmKeep = 0.15; // rhythm retained after a trip
  static const double _tripStopSec = 0.6; // dead-stop (no advance) after a trip
  // A hurdle can only trip a runner once (a one-shot as it passes the body), so
  // a single hurdle is one trip, never a per-frame grind.

  // ── Mash energy / animation tuning ──────────────────────────────────────────
  static const double _energyPerTap = 0.16; // smoothed-rate bump per tap
  static const double _energyDecayPerSec = 1.6; // bleed of the smoothed rate
  static const double _strideMaxBoost = 1.7; // extra leg-cycle speed at full E
  static const double _maxLeanRad = 0.32; // forward lean at full energy

  // ── Photo-finish tuning ─────────────────────────────────────────────────────
  static const double _photoFinishProgress = 0.93; // leader past this → arm it
  static const double _photoFinishSlowScale = 0.32; // slow-mo time scale
  static const double _photoFinishSec = 0.55; // slow-mo duration
  static const double _photoFinishGap = 0.06; // runner-up within this = "tight"

  // ── Final-stretch climax ─────────────────────────────────────────────────────
  static const double _finalStretchProgress = 0.78; // leader past this → cue

  // ── Bot stride cadence + vault timing ───────────────────────────────────────
  // Bots stride on a [BotProfile]-driven interval (harder = faster + steadier =
  // higher rhythm) and time a vault as each hurdle enters their window. Strong
  // bots vault crisply (clear); weak bots mistime on an [errorRate] slip (trip).
  static const double _botBaseInterval = 0.165;
  static const double _botAccuracyBonus = 0.05; // faster (better rhythm) when good
  static const double _botJitterBase = 0.05; // sloppier cadence when weak
  // A bot winds up as a hurdle enters its window and RELEASES at a target point
  // on the 0..1 bar: the sweet-spot centre plus an accuracy-scaled error. A
  // strong bot's error is tiny (releases dead-centre → clean); a weak bot's error
  // is large (releases off-centre → outside the zone → clip). On an [errorRate]
  // slip it skips the wind-up entirely and clips — a careless miss, like a human
  // who never reacted. A real skill gradient straight off [BotProfile].
  static const double _botReleaseErrStrong = 0.03; // release error at accuracy 1
  static const double _botReleaseErrWeak = 0.30; // release error at accuracy 0
  // Bots hold at the blocks for a beat so a human can get off the line first.
  // The hold SHRINKS with skill (accuracy): an easy bot dawdles at the blocks (a
  // big head-start for the human), a hard bot is off almost instantly. This is
  // the dominant difficulty lever — a near-perfect human runs ~13.6s, a hard bot
  // that runs the same pace can only be caught/beaten if it lets the human bank a
  // real head-start, so the easy→hard warm-up ramp turns the (already graded)
  // finish-time margin into a graded WIN-RATE: easy is a walkover, hard is a
  // genuine threat that trades the lead on its occasional [errorRate] trip.
  static const double _botWarmupWeakSec = 1.7; // hold at the blocks at accuracy 0
  static const double _botWarmupStrongSec = 0.1; // near-instant at accuracy 1

  // ── Figure / feel tuning ────────────────────────────────────────────────────
  static const double _figureScale = 1.9; // readable sprinters
  static const double _bodyWidthFactor = 2.6; // dust/shadow half-width / torsoW
  static const Color _accent = Color(0xFFFFD24A);
  // RENDER-only down-scale as the field fills so neighbouring lanes never
  // overlap. Scales ONLY the painted figure (about its feet) — lane positions,
  // foot line, distance and finish logic are untouched.
  static const double _renderScaleSolo = 1.0; // draw scale at 1 lane (full size)
  static const double _renderScaleFull = 0.6; // draw scale at 4 lanes (slimmer)

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for crowd/dust/tape
  bool _photoFinishFired = false;
  bool _finalStretchFired = false; // one-shot "FINAL STRETCH!" climax latch

  late double _startX;
  late double _finishX;
  late double _trackTop;
  late double _footReach; // pelvis→foot length at rest (for grounding)
  late double _bodyW;
  late StickProportions _proportions;

  // The shared course of hurdles (in meters down the track). One course for the
  // whole field so every lane runs the identical gauntlet — a fair race. Built
  // once at init.
  late final List<double> _hurdleMeters;

  final Map<int, _Runner> _runners = <int, _Runner>{};
  final List<double> _laneYs = <double>[]; // foot-line y per lane, top→bottom
  final List<int> _laneOrder = <int>[]; // player id per lane index
  final List<int> _finishOrder = <int>[]; // by crossing time, best first
  final Set<int> _confettiFor = <int>{}; // ids that already popped confetti

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _computeLayout();

    _proportions = StickProportions.hero.scaled(_figureScale);
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = _proportions.thigh + _proportions.shin;
    _bodyW = _proportions.torsoWidth * _bodyWidthFactor;

    _hurdleMeters = _buildCourse();
    _buildRunners();
    begin();
  }

  void _computeLayout() {
    _startX = _size.width * 0.085;
    _finishX = _size.width * (1 - 0.10);
    _trackTop = _size.height * 0.30;

    final top = _trackTop + (_size.height - _trackTop) * 0.10;
    final bot = _size.height - (_size.height - _trackTop) * 0.10;
    final n = ctx.players.length;
    _laneYs.clear();
    _laneOrder.clear();
    if (n == 1) {
      _laneYs.add((top + bot) / 2);
      _laneOrder.add(ctx.players.first.id);
      return;
    }
    for (var i = 0; i < n; i++) {
      _laneYs.add(lerpDouble(top, bot, i / (n - 1))!);
      _laneOrder.add(ctx.players[i].id);
    }
  }

  /// Hurdles down the track, packed CLOSER toward the finish (a calibrated
  /// density ramp): the gap between consecutive hurdles shrinks from [_gapStartM]
  /// to [_gapEndM] as we approach [_lastHurdleM]. The opening [_firstHurdleM] is
  /// an open run-up.
  List<double> _buildCourse() {
    final course = <double>[];
    var m = _firstHurdleM;
    while (m <= _lastHurdleM) {
      course.add(m);
      final t = (m / _raceMeters).clamp(0.0, 1.0); // 0 (start)..1 (finish)
      m += lerpD(_gapStartM, _gapEndM, t);
    }
    return course;
  }

  void _buildRunners() {
    for (final p in ctx.players) {
      _runners[p.id] = _Runner(
        slot: p,
        figure: StickFigure(
          proportions: _proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1, // sprinters face the finish line (to the right)
        )..setLoco(LocoState.idle),
        botInterval: _botInterval(),
        botJitter: _botJitter(),
        botReleaseErr: _botReleaseErr(),
      );
    }
  }

  /// Bright sprinter style: player-color fill, brightened outline, strong glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0, // we draw our own contact shadow
        gradientBottom: 0.55,
        smearAlpha: 0.3,
      );

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.06, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  /// Weaker bots jitter more so their stride rate wavers (worse rhythm); strong
  /// bots stay metronomic. Jitter never kicks a bot out of the stride window
  /// (see [_nextBotInterval]) so bots never break their own stride.
  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.2;
  }

  /// A bot's release-timing error magnitude on the 0..1 bar. High accuracy → the
  /// tiny [_botReleaseErrStrong] (releases dead-centre → clean vault); low
  /// accuracy → the large [_botReleaseErrWeak] (releases off-centre → outside the
  /// sweet spot → clip). The actual sign/offset is jittered per hurdle.
  double _botReleaseErr() {
    final prof = ctx.botProfile;
    return lerpD(_botReleaseErrWeak, _botReleaseErrStrong, prof.accuracy.clamp(0.0, 1.0));
  }

  /// How long bots hold at the blocks before they start striding — the dominant
  /// difficulty lever. SHRINKS with accuracy: a weak (easy) bot dawdles
  /// ([_botWarmupWeakSec]) and hands the human a big head-start; a strong (hard)
  /// bot is off almost instantly ([_botWarmupStrongSec]) and runs the human's
  /// pace, so the race is decided by who keeps cleaner rhythm down the gauntlet —
  /// a hard bot is a real threat, an easy one a walkover.
  double _botWarmup() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    return lerpD(_botWarmupWeakSec, _botWarmupStrongSec, acc);
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    switch (input.phase) {
      case InputPhase.down:
        _press(input.playerId);
        break;
      case InputPhase.holdTick:
        _holdTick(input.playerId, input.dt);
        break;
      case InputPhase.up:
        _release(input.playerId);
        break;
    }
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(sdt);
    _tickRunners(sdt);
    _maybeFinalStretch();
    _maybePhotoFinish();
    _resolve();
  }

  /// Fire the one-shot "FINAL STRETCH!" climax cue once the leader is deep into
  /// the track — a clear "the finish is close, push!" beat before the tape.
  void _maybeFinalStretch() {
    if (_finalStretchFired || _finishOrder.isNotEmpty) return;
    if (_leadProgress() < _finalStretchProgress) return;
    _finalStretchFired = true;
    _juice.popup(
      Offset(_size.width / 2, _size.height * 0.2),
      'FINAL STRETCH!',
      _accent,
      size: 34,
    );
    _juice.shake.medium();
  }

  // ── Press / hold → stride or vault ──────────────────────────────────────────

  /// A press (tap-down). Two clearly-different roles, decided by the scene:
  ///  * A hurdle is in the approach window → the press ARMS a WIND-UP: the
  ///    power/timing bar starts filling from zero and the player must RELEASE it
  ///    inside the sweet spot to vault. Pressing AGAIN while already winding
  ///    RESETS the bar to zero (a stutter) — so hammering never charges a vault.
  ///  * No hurdle in the window → the press is a STRIDE on the run cadence.
  ///
  /// This is the anti-spam crux moved to the RELEASE: a blind tapper hammering
  /// every frame keeps re-arming the bar at zero and never releases inside the
  /// zone, so it clips every hurdle. A measured runner presses once, watches the
  /// bar rise, and releases in the sweet spot — a clean, FELT vault.
  void _press(int id) {
    final r = _runners[id];
    if (r == null || r.finished) return;

    // Energy always bumps so the figure reads as "trying" regardless of timing.
    r.energy = (r.energy + _energyPerTap).clamp(0.0, 1.0);

    // A press lands as a wind-up only when a hurdle is actually offered (the bar
    // is on screen). Otherwise it is a plain stride. (Re)arming resets the bar
    // to zero, so a mid-wind re-press is a stutter, never extra charge.
    if (_hurdleInWindow(r) != null) {
      r.windingUp = true;
      r.windup = 0;
    } else {
      _stride(r);
    }
  }

  /// While a press is held, advance the wind-up bar (a fixed-rate sweep, so the
  /// read is pure timing). Only meaningful once a press armed a wind-up; a held
  /// press with no hurdle does nothing. The bar clamps at 1 (holding past the top
  /// just parks it in the over-charged "too late" region until release).
  void _holdTick(int id, double dt) {
    final r = _runners[id];
    if (r == null || r.finished || !r.windingUp) return;
    r.windup = math.min(1.0, r.windup + dt / _windupFillSec);
  }

  /// RELEASE — the decisive skill input. If a wind-up is armed and a hurdle is
  /// still launchable, judge the bar against the sweet-spot zone: inside → arm a
  /// CLEAN clearance for that hurdle + reward; outside (released too early or too
  /// late) → leave it un-armed so the body clips the bar → trip. A release with
  /// no armed wind-up is a no-op.
  void _release(int id) {
    final r = _runners[id];
    if (r == null) return;
    if (r.windingUp) _resolveRelease(r);
    r.windingUp = false;
    r.windup = 0;
  }

  /// Judge a release: the next hurdle is CLEARED iff the bar sat inside its
  /// sweet-spot zone at the instant of release. A clean release launches the
  /// visual vault arc and pays a rhythm bump + a brief speed surge (the felt
  /// pop). An off-zone release does nothing — the runner reaches the bar grounded
  /// and trips. (Releasing with no hurdle left in the window is harmless.)
  void _resolveRelease(_Runner r) {
    final idx = _hurdleInWindow(r);
    if (idx == null) return; // nothing to clear (cue already gone)
    if (_releaseInSweetSpot(r, idx)) {
      _cleanVault(r, idx);
    }
    // else: no clearance armed → the hurdle will trip the runner on contact.
  }

  /// Whether [r]'s current wind-up bar value lies inside the sweet-spot zone for
  /// hurdle [idx] (the zone narrows down the track). The core skill predicate.
  bool _releaseInSweetSpot(_Runner r, int idx) {
    final half = _sweetHalfAt(_hurdleMeters[idx]);
    return (r.windup - _sweetCenter).abs() <= half;
  }

  /// The sweet-spot half-width for a hurdle at [hurdleM] — NARROWS toward the
  /// finish (tighter release timing late), kid-forgiving early.
  double _sweetHalfAt(double hurdleM) {
    final t = (hurdleM / _raceMeters).clamp(0.0, 1.0);
    return lerpD(_sweetHalfStart, _sweetHalfEnd, t);
  }

  /// A clean, well-timed release: arm the clearance for [idx], launch the visual
  /// hop, and pay the reward (rhythm bump + speed surge + a bright pop). The
  /// felt, satisfying payoff for nailing the bar.
  void _cleanVault(_Runner r, int idx) {
    r.clearedHurdle = idx;
    r.airborne = true;
    r.airTimer = _vaultAirSec;
    r.surge = _vaultSurgeSec;
    r.rhythm = (r.rhythm + _vaultRhythmReward).clamp(0.0, 1.0);
    r.figure.setLoco(LocoState.jump);

    final at = _runnerRoot(r).translate(0, -_footReach * 1.1);
    _juice.hit(at, _colorOf(r.slot.id), sparks: 10);
    _juice.particles.burst(
      at: at,
      count: 8,
      color: SprintRenderer.cleanVault,
      speed: 300,
      size: 5,
      life: 0.5,
    );
    _juice.popup(at.translate(0, -_size.height * 0.015), '▲', _accent, size: 30);
  }

  /// A clean stride on the run cadence: a tap spaced inside the stride window
  /// grows rhythm (which drives run speed). An over-mash (tap far below the
  /// window) banks NO rhythm and bleeds a little — so mashing is strictly slower
  /// than a steady beat. The opening tap is a free stride.
  void _stride(_Runner r) {
    final gap = r.sinceTap;
    r.sinceTap = 0;

    final isKickoff = gap >= _kickoffGraceSec;
    final inWindow = gap >= _strideLo && gap <= _strideHi;

    if (inWindow || isKickoff) {
      r.rhythm = (r.rhythm + _rhythmGainPerStride).clamp(0.0, 1.0);
      r.figure.setLoco(LocoState.run);
    } else if (gap < _strideLo) {
      // Over-mash: pressing faster than the stride cadence breaks the gait.
      r.rhythm = math.max(0.0, r.rhythm - _overMashRhythmPenalty);
    }
    // (A tap slower than _strideHi just resets the beat; natural decay handles
    // the lost rhythm.)
  }

  /// Index of the next un-passed hurdle inside the runner's APPROACH window — the
  /// band where the power/timing bar is OFFERED (the telegraph shows). The window
  /// is only the cue range; whether the vault CLEARS depends on releasing the bar
  /// inside the sweet spot (see [_releaseInSweetSpot]).
  int? _hurdleInWindow(_Runner r) {
    final idx = r.nextHurdle;
    if (idx >= _hurdleMeters.length) return null;
    final ahead = _hurdleMeters[idx] - r.meters;
    final window = _jumpWindowAt(_hurdleMeters[idx]);
    if (ahead <= window && ahead > 0) return idx;
    return null;
  }

  /// The approach-window depth (meters of telegraph lead) for a hurdle at
  /// distance [hurdleM] — NARROWS toward the finish so late hurdles give less
  /// lead time before the runner reaches them (the calibrated ramp).
  double _jumpWindowAt(double hurdleM) {
    final t = (hurdleM / _raceMeters).clamp(0.0, 1.0);
    return lerpD(_windowStartM, _windowEndM, t);
  }

  void _tickRunners(double dt) {
    for (final r in _runners.values) {
      r.sinceTap += dt;
      r.tripStop = math.max(0, r.tripStop - dt);
      r.surge = math.max(0, r.surge - dt);

      // A wind-up that loses its hurdle (the runner reached/passed it, or the cue
      // expired) without a clean release goes stale — drop it so it can't carry
      // into the next hurdle's bar.
      if (r.windingUp && _hurdleInWindow(r) == null) {
        r.windingUp = false;
        r.windup = 0;
      }

      // Rhythm + energy bleed when not actively striding on-beat.
      r.rhythm = math.max(0, r.rhythm - _rhythmDecayPerSec * dt);
      r.energy = math.max(0, r.energy - _energyDecayPerSec * dt);

      // Move the body, THEN resolve any hurdle the body crossed this frame while
      // [r.airborne] still reflects the in-air state for that crossing — and only
      // THEN count the arc down. This keeps the airborne-at-contact test exact at
      // frame boundaries (no landing one tick early and clipping a cleared hurdle).
      _advance(r, dt);
      _resolveHurdleContact(r);

      if (r.airborne) {
        r.airTimer -= dt;
        if (r.airTimer <= 0) {
          r.airborne = false;
          r.figure.setLoco(r.energy > 0.02 ? LocoState.run : LocoState.idle);
        }
      }

      _advanceFigure(r, dt);
      setScore(r.slot.id, r.meters);

      if (!r.finished && r.meters >= _raceMeters) {
        _cross(r);
      }
    }
  }

  /// Advance the runner down the track. Speed is set by gait RHYTHM (a jog floor
  /// up to a full sprint), NOT the tap rate — so a metronomic runner outruns a
  /// masher. A fresh trip dead-stops the runner ([_Runner.tripStop]); otherwise
  /// it runs at its rhythm speed.
  void _advance(_Runner r, double dt) {
    if (r.finished || r.tripStop > 0) return;
    final speed = lerpD(_jogSpeed, _sprintSpeed, r.rhythm);
    r.meters = math.min(_raceMeters, r.meters + speed * dt);
  }

  /// Resolve the body passing a hurdle. Clearance is decided by the RELEASE: a
  /// clean, well-timed release armed [_Runner.clearedHurdle] for this index →
  /// vaulted clean (consume the arm); otherwise the runner clipped it → TRIP.
  /// One-shot per hurdle (consumed as the body passes), so one hurdle is one
  /// trip, never a per-frame grind.
  void _resolveHurdleContact(_Runner r) {
    final idx = r.nextHurdle;
    if (idx >= _hurdleMeters.length) return;
    final hurdleM = _hurdleMeters[idx];
    if (r.meters < hurdleM) return; // not reached yet

    r.nextHurdle++; // consume this hurdle
    if (r.clearedHurdle == idx) {
      r.clearedHurdle = -1; // clean vault — consume the armed clearance
    } else {
      _trip(r, hurdleM);
    }
  }

  /// A TRIP: a stutter-clip — the runner reached the hurdle without a clean
  /// release (released off-zone, never wound up, or still mid-wind). Lose most of
  /// the gait rhythm, dead-stop for a beat, and play a full-body stumble. Heavy
  /// on purpose — a spammer that trips every hurdle stalls; a reader trips ~never.
  void _trip(_Runner r, double hurdleM) {
    r.windingUp = false;
    r.windup = 0;
    r.clearedHurdle = -1;
    r.surge = 0;
    r.rhythm = math.min(r.rhythm, _tripRhythmKeep);
    r.tripStop = _tripStopSec;
    r.airborne = false;
    r.airTimer = 0;
    r.figure
      ..setLoco(LocoState.idle)
      ..hurt(); // a quick full-body trip so the clipped hurdle reads

    final at = _runnerRoot(r).translate(0, -_footReach * 0.5);
    _juice.particles.burst(
      at: at,
      count: 8,
      color: SprintRenderer.hurdleHit,
      speed: 200,
      spread: math.pi * 1.6,
      size: 5,
      gravity: 600,
      life: 0.4,
    );
    _juice.popup(at.translate(0, -_size.height * 0.02), 'TRIP!',
        SprintRenderer.hurdleHit,
        size: 26);
    _juice.shake.light();
  }

  /// Drive the figure with a stride speed scaled by mash energy: more energy →
  /// faster leg cycle. While dead-stopped from a trip the runner reads idle (a
  /// visible hitch); while airborne the jump clip plays at real time.
  void _advanceFigure(_Runner r, double dt) {
    if (r.airborne) {
      r.figure.update(dt);
      r.stridePhase += dt;
      return;
    }
    if (r.finished || r.energy <= 0.02 || r.tripStop > 0) {
      r.figure.update(dt);
      r.stridePhase += dt;
      return;
    }
    final stride = 1.0 + _strideMaxBoost * r.energy;
    final scaled = dt * stride;
    r.figure.update(scaled);
    r.stridePhase += scaled;
  }

  /// Record a crossing: lock the runner, append to the finish order, fire a
  /// per-runner confetti + place popup, and a celebratory beat on first place.
  void _cross(_Runner r) {
    r.finished = true;
    r.airborne = false;
    _finishOrder.add(r.slot.id);
    r.figure.setLoco(LocoState.idle);

    final place = _finishOrder.length;
    if (place == 1) r.figure.victory();
    final at = _runnerRoot(r).translate(0, -_footReach * 1.1);
    _juice.popup(at, _ordinal(place), _colorOf(r.slot.id), size: 34);
    if (!_confettiFor.contains(r.slot.id)) {
      _confettiFor.add(r.slot.id);
      _juice.confetti(_size, colors: [_colorOf(r.slot.id)]);
    }
    if (place == 1) {
      // A tight finish already played the PHOTO FINISH slow-mo as the tape
      // neared, so keep that crossing punchy but don't double up; a runaway
      // leader gets the full WINNER! beat here.
      if (_photoFinishFired) {
        _juice.shake.heavy();
        _juice.hitStop.trigger(Feel.hitStopHeavySec, scale: 0.12);
      } else {
        final winnerPos = _runnerRoot(r).translate(0, -_footReach * 0.62);
        _juice.bigMoment(winnerPos, _colorOf(r.slot.id), banner: 'WINNER!');
      }
    } else {
      _juice.shake.light();
    }
    _juice.hit(_tapeHitPoint(r), _colorOf(r.slot.id), sparks: 10);
  }

  /// Bots stride on a cadence clock AND run the SAME timed-release vault as a
  /// human: as a hurdle enters the window they wind the power bar up and release
  /// at a target point. Strong bots stride faster (higher rhythm) and release
  /// dead-centre (clean); weak bots stride sloppier and release off-centre, or on
  /// an [errorRate] slip skip the wind-up entirely → clip. The guard caps catch-up
  /// strides for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmup()) return; // hold bots at the blocks for a beat
    for (final r in _runners.values) {
      if (!r.slot.isBot || r.finished) continue;
      _botDriveVault(r, dt);
      // While winding up a vault the bot "holds" — it doesn't stride (its press
      // is committed to the bar), so the cadence clock only runs in the open.
      if (r.windingUp) continue;
      r.botClock += dt;
      var guard = 0;
      while (r.botClock >= r.nextTapAt && guard++ < 8) {
        r.botClock -= r.nextTapAt;
        _stride(r); // bots stride on-cadence (clamped in-window → grows rhythm)
        r.nextTapAt = _nextBotInterval(r);
      }
    }
  }

  /// Drive a bot's timed-release vault for the next hurdle. The first frame the
  /// hurdle is in the window the bot COMMITS: on an [errorRate] slip it skips the
  /// wind-up (→ clip, a careless miss); otherwise it arms the bar and picks a
  /// release target = the sweet-spot centre plus an accuracy-scaled error (tiny
  /// for strong bots → dead-centre clean; large for weak bots → off-zone clip).
  /// Each frame it then fills the bar and releases once it reaches that target.
  void _botDriveVault(_Runner r, double dt) {
    if (r.airborne) return;
    final idx = _hurdleInWindow(r);
    if (idx == null) return; // no hurdle offered yet

    if (r.botVaultedFor != idx) {
      r.botVaultedFor = idx;
      if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        r.windingUp = false; // careless slip → never winds → trips on contact
        r.botReleaseTarget = -1;
        return;
      }
      // Signed release error: strong bots land inside the (narrow) zone, weak
      // bots overshoot or undershoot it.
      final err = ctx.rng.jitter(r.botReleaseErr);
      r.botReleaseTarget = (_sweetCenter + err).clamp(0.06, 0.99);
      r.windingUp = true;
      r.windup = 0;
      return;
    }

    if (!r.windingUp) return; // committed to skip this hurdle
    r.windup = math.min(1.0, r.windup + dt / _windupFillSec);
    if (r.windup >= r.botReleaseTarget) {
      _resolveRelease(r); // release at the chosen point — clean iff in the zone
      r.windingUp = false;
    }
  }

  /// A bot's next stride interval, CLAMPED inside the stride window so a bot
  /// always banks a clean stride (never over-mashes itself slow). Tiers differ by
  /// interval length within the window — faster (harder) bots stride more often,
  /// holding higher rhythm — not by missing the window.
  double _nextBotInterval(_Runner r) {
    final raw = r.botInterval + ctx.rng.jitter(r.botJitter);
    return raw.clamp(_strideLo + 0.005, _strideHi - 0.005);
  }

  // ── Photo finish ─────────────────────────────────────────────────────────────

  void _maybePhotoFinish() {
    if (_photoFinishFired || _finishOrder.isNotEmpty) return;
    final lead = _leadProgress();
    if (lead < _photoFinishProgress || lead >= 1.0) return;
    final tight = (lead - _runnerUpProgress()) <= _photoFinishGap;
    if (!tight) return;
    _photoFinishFired = true;
    _juice.slowMo(dur: _photoFinishSec, scale: _photoFinishSlowScale);
    _juice.shake.medium();
    _juice.bigBanner('PHOTO FINISH!', color: _accent);
  }

  double _leadProgress() {
    var best = 0.0;
    for (final r in _runners.values) {
      final p = r.meters / _raceMeters;
      if (p > best) best = p;
    }
    return best;
  }

  /// Best progress among everyone except the single front-runner — used to judge
  /// how tight the finish is.
  double _runnerUpProgress() {
    var best = -1.0;
    var second = -1.0;
    for (final r in _runners.values) {
      final p = r.meters / _raceMeters;
      if (p > best) {
        second = best;
        best = p;
      } else if (p > second) {
        second = p;
      }
    }
    return second < 0 ? 0.0 : second;
  }

  // ── Resolution ──────────────────────────────────────────────────────────────

  void _resolve() {
    final allDone = _runners.values.every((r) => r.finished);
    if (!allDone && _elapsed < _timeLimit) return;

    // Finishers (by crossing time) first, then the rest by distance covered.
    final unfinished = _runners.values.where((r) => !r.finished).toList()
      ..sort((a, b) => b.meters.compareTo(a.meters));
    finishByOrder(<int>[
      ..._finishOrder,
      ...unfinished.map((r) => r.slot.id),
    ]);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    SprintRenderer.drawBackground(canvas, size, _trackTop, _animClock);
    SprintRenderer.drawTrack(canvas, size, _trackTop);
    SprintRenderer.drawDistanceMarkers(
        canvas, size, _startX, _finishX, _markerScroll());
    SprintRenderer.drawLanes(
        canvas, size, _startX, _finishX, _laneYs, _laneColors());
    SprintRenderer.drawStartLine(canvas, size, _startX);

    _drawHurdles(canvas);
    _drawRunners(canvas);

    // Finish furniture + the distance HUD on top so they read as "ahead".
    SprintRenderer.drawFinish(canvas, size, _finishX, _animClock);
    SprintRenderer.drawDistanceHud(
        canvas, size, _leaderMeters(), _raceMeters, _accent);

    _juice.render(canvas);
    canvas.restore();

    _juice.renderOverlay(canvas, size);
  }

  /// Distance markers drift with the leader for a sense of forward motion.
  double _markerScroll() => (_leadProgress() * _laneCount() * 1.7) % 1.0;

  int _laneCount() => math.max(1, _laneYs.length);

  List<Color> _laneColors() => [for (final id in _laneOrder) _colorOf(id)];

  double _leaderMeters() {
    var best = 0.0;
    for (final r in _runners.values) {
      if (r.meters > best) best = r.meters;
    }
    return best;
  }

  /// Draw the hurdles approaching in every lane. Each hurdle is telegraphed: as
  /// it enters a runner's approach window it lights up so a reading player always
  /// gets the tell; a cleared/passed hurdle fades. The active (live) hurdle also
  /// flies the POWER/TIMING bar (the wind-up + sweet-spot zone) above it.
  void _drawHurdles(Canvas canvas) {
    for (var lane = 0; lane < _laneOrder.length; lane++) {
      final r = _runners[_laneOrder[lane]];
      if (r == null) continue;
      final y = _laneYs[lane];
      final liveIdx = _hurdleInWindow(r);
      for (var idx = 0; idx < _hurdleMeters.length; idx++) {
        final hurdleM = _hurdleMeters[idx];
        final ahead = hurdleM - r.meters;
        // Cull hurdles well behind or far ahead of this runner (keeps the lane
        // legible — only the nearby gauntlet is drawn).
        if (ahead < -2 || ahead > 26) continue;
        final x = lerpDouble(_startX, _finishX, hurdleM / _raceMeters)!;
        final passed = idx < r.nextHurdle;
        final live = !passed && idx == liveIdx;
        SprintRenderer.drawHurdle(
          canvas,
          Offset(x, y),
          _laneHeight(lane),
          live: live,
          passed: passed,
          warnPulse: 0.5 + 0.5 * math.sin(_animClock * 12.0 + idx),
        );

        // The wind-up bar rides above the live hurdle: the sweet-spot zone is
        // always shown (the read), the fill + needle appear while winding.
        if (live) {
          final half = _sweetHalfAt(hurdleM);
          SprintRenderer.drawWindupBar(
            canvas,
            Offset(x, y),
            _laneHeight(lane),
            fill: r.windup,
            winding: r.windingUp,
            sweetLo: (_sweetCenter - half).clamp(0.0, 1.0),
            sweetHi: (_sweetCenter + half).clamp(0.0, 1.0),
            pulse: 0.5 + 0.5 * math.sin(_animClock * 9.0),
          );
        }
      }
    }
  }

  void _drawRunners(Canvas canvas) {
    final leaderId = _currentLeaderId();
    for (var lane = 0; lane < _laneOrder.length; lane++) {
      final r = _runners[_laneOrder[lane]];
      if (r == null) continue;
      final root = _runnerRoot(r);
      final feet = Offset(root.dx, root.dy + _footReach);
      final color = _colorOf(r.slot.id);
      // A fresh clean vault briefly drives the speed/effort tells to the top —
      // the felt "surge" payoff for nailing the release.
      final surge01 = (r.surge / _vaultSurgeSec).clamp(0.0, 1.0);
      final speed01 = math.max(r.energy, surge01);

      // Leader spotlight underfoot.
      if (r.slot.id == leaderId && !r.finished) {
        SprintRenderer.drawLeaderSpotlight(
            canvas, feet, _laneHeight(lane), color);
      }

      // Ground shadow squashes a touch with the gait for grounding.
      final squash = 1.0 - 0.12 * speed01;
      SprintRenderer.drawContactShadow(canvas, feet, _bodyW, squash);
      SprintRenderer.drawFootDust(canvas, feet, _bodyW, speed01, r.stridePhase);

      // Speed lines stream off the chest of a fast runner.
      final chest = root.translate(0, -_footReach * 0.62);
      SprintRenderer.drawSpeedLines(
          canvas, chest, _bodyW, speed01, _animClock, color);

      _drawLeaningRunner(canvas, r, root, speed01);

      // Lunge flash on the leader during the photo-finish beat.
      if (_juice.hitStop.isActive && r.slot.id == leaderId && !r.finished) {
        SprintRenderer.drawLungeFlash(canvas, chest, _bodyW, 0.8, _accent);
      }
    }
  }

  /// RENDER-only figure scale for the current field size: full at 1 lane,
  /// shrinking toward [_renderScaleFull] by 4 lanes so multi-lane sprinters stop
  /// overlapping. Applied about the feet in the draw path only.
  double _renderScale() {
    final n = _laneCount();
    final t = n <= 1 ? 0.0 : ((n - 1) / 3.0).clamp(0.0, 1.0);
    return lerpDouble(_renderScaleSolo, _renderScaleFull, t)!;
  }

  /// Draw a runner pitched forward by mash energy (premium body language) and
  /// lifted while airborne (the vault arc). The lean/scale pivot is the feet so
  /// the plant stays glued to the track.
  void _drawLeaningRunner(
      Canvas canvas, _Runner r, Offset root, double speed01) {
    final pivot = Offset(root.dx, root.dy + _footReach);
    final scale = _renderScale();
    final lean = r.finished ? 0.0 : _maxLeanRad * speed01;
    // Vault hop: lift the figure on a smooth arc while airborne.
    final hop = r.airborne
        ? math.sin((1 - (r.airTimer / _vaultAirSec).clamp(0.0, 1.0)) * math.pi)
        : 0.0;
    final lift = hop * _footReach * 1.2;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    if (lean != 0) canvas.rotate(lean);
    if (scale != 1.0) canvas.scale(scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    SprintRenderer.drawSprinter(canvas, r.figure, root.translate(0, -lift));
    canvas.restore();
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  /// Stick root for a runner: x mapped from distance along the track, y lifted
  /// by [_footReach] so the feet plant on the lane's foot line.
  Offset _runnerRoot(_Runner r) {
    final lane = _laneOrder.indexOf(r.slot.id);
    final y = (lane >= 0 ? _laneYs[lane] : _laneYs.first) - _footReach;
    final x = lerpDouble(_startX, _finishX, r.meters / _raceMeters)!;
    return Offset(x, y);
  }

  /// A point near the tape at the runner's lane height (for the cross spark).
  Offset _tapeHitPoint(_Runner r) {
    final lane = _laneOrder.indexOf(r.slot.id);
    final y = lane >= 0 ? _laneYs[lane] : _laneYs.first;
    return Offset(_finishX, y - _footReach * 0.5);
  }

  double _laneHeight(int lane) {
    if (_laneYs.length < 2) return (_size.height - _trackTop) * 0.6;
    if (lane <= 0) return _laneYs[1] - _laneYs[0];
    if (lane >= _laneYs.length - 1) return _laneYs[lane] - _laneYs[lane - 1];
    return (_laneYs[lane + 1] - _laneYs[lane - 1]) / 2;
  }

  /// The id of the runner currently furthest along (drives the spotlight).
  int _currentLeaderId() {
    var bestId = _laneOrder.isEmpty ? 0 : _laneOrder.first;
    var best = -1.0;
    for (final r in _runners.values) {
      if (r.meters > best) {
        best = r.meters;
        bestId = r.slot.id;
      }
    }
    return bestId;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static String _ordinal(int place) {
    switch (place) {
      case 1:
        return '1ST!';
      case 2:
        return '2ND';
      case 3:
        return '3RD';
      default:
        return '${place}TH';
    }
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  // ── Test seams (read-only / deterministic input) ────────────────────────────

  /// Meters [id]'s runner has covered (the scored quantity), or -1 if there is
  /// no such runner. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  double metersOf(int id) => _runners[id]?.meters ?? -1;

  /// Gait rhythm 0..1 of [id]'s runner (drives run speed), or -1 if none.
  /// Read-only; for deterministic gameplay tests.
  @visibleForTesting
  double rhythmOf(int id) => _runners[id]?.rhythm ?? -1;

  /// Whether a hurdle is inside [id]'s approach window — the power/timing bar is
  /// showing (a hurdle is approaching and a vault is offered). The earliest tell.
  /// Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  bool hasHurdleInWindow(int id) {
    final r = _runners[id];
    if (r == null) return false;
    return _hurdleInWindow(r) != null;
  }

  /// [id]'s current wind-up bar fill 0..1 (0 when not winding), or -1 if there is
  /// no such runner. Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  double windupOf(int id) => _runners[id]?.windup ?? -1;

  /// The sweet-spot zone [lo, hi] on the 0..1 bar for [id]'s next hurdle (the
  /// band a release must land in to vault cleanly). Empty when no hurdle is
  /// offered. Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  (double, double) sweetSpotOf(int id) {
    final r = _runners[id];
    if (r == null) return (0, 0);
    final idx = _hurdleInWindow(r);
    if (idx == null) return (0, 0);
    final half = _sweetHalfAt(_hurdleMeters[idx]);
    return ((_sweetCenter - half).clamp(0.0, 1.0),
        (_sweetCenter + half).clamp(0.0, 1.0));
  }

  /// Whether RELEASING [id]'s wind-up THIS instant would CLEAR the next hurdle —
  /// i.e. the bar is currently inside the sweet-spot zone. This is the precise
  /// skilled read: a measured player releases exactly here. Read-only; for
  /// deterministic gameplay tests + smart play.
  @visibleForTesting
  bool shouldVaultNow(int id) {
    final r = _runners[id];
    if (r == null || !r.windingUp) return false;
    final idx = _hurdleInWindow(r);
    if (idx == null) return false;
    return _releaseInSweetSpot(r, idx);
  }
}

/// Per-player race state. Mutable round-scoped state (allowed for the duration
/// of a single round).
class _Runner {
  final PlayerSlot slot;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;
  final double botReleaseErr; // this bot's release-timing error on the 0..1 bar

  bool finished = false;

  // Distance + rhythm bookkeeping.
  double meters = 0; // distance covered down the track — THIS is the score
  double sinceTap = 1e9; // seconds since this runner's last stride tap
  double rhythm = 0; // 0..1 gait rhythm; sets run speed
  double energy = 0; // 0..1 smoothed recent tap rate (animation only)
  double stridePhase = 0; // gait phase for dust sync

  // Hurdle bookkeeping.
  int nextHurdle = 0; // index of the next hurdle the body will reach
  int clearedHurdle = -1; // index a clean release has armed to clear cleanly
  double tripStop = 0; // seconds of dead-stop remaining after a trip
  bool airborne = false; // mid-vault visual arc (hop)
  double airTimer = 0; // seconds of airborne arc remaining
  double surge = 0; // seconds of post-clean-vault speed-surge tell remaining

  // Timed-release wind-up (the skill): a held press fills [windup] 0..1 while a
  // hurdle is in the window; RELEASE inside the sweet spot clears it.
  bool windingUp = false; // a press is held with a hurdle offered (bar charging)
  double windup = 0; // 0..1 power/timing bar fill

  // Bot cadence clock + release target.
  double botClock = 0;
  double nextTapAt;
  int botVaultedFor = -1; // hurdle index this bot has already committed to
  double botReleaseTarget = -1; // bar value this bot releases at for that hurdle

  _Runner({
    required this.slot,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
    required this.botReleaseErr,
  }) : nextTapAt = botInterval;
}
