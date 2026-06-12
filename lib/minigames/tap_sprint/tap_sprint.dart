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
/// INTERPOSING DIFFICULTY — HURDLES:
///  * Hurdles sit at fixed distances down the track and scroll toward the runner.
///    Each is **telegraphed**: as it enters the runner's approach zone a "JUMP!"
///    cue + a flashing arc appear. A VAULT input — a tap landed inside the jump
///    window, OR a HOLD — clears the hurdle cleanly. An early / late / missing
///    vault = a TRIP: the runner stumbles (a hard speed loss + a brief dead
///    stop), then recovers.
///  * Hurdles get DENSER and the jump window TIGHTER the further you run (a
///    calibrated ramp), so the back half is a real gauntlet.
///  * A blind masher never *times* a vault — its taps are strides, not vaults,
///    so it trips on essentially every hurdle and stalls. A runner who reads the
///    telegraph and vaults on cue clears them and pulls away. (Proven by a
///    deterministic test.)
///
/// One-touch read, two clearly-different beats: TAP a steady beat to run; when a
/// hurdle lights up "JUMP!", press inside the window (or hold) to vault it.
///
/// BOTS: stride on a [BotProfile] cadence AND time a vault as each hurdle enters
/// the window — strong bots clear nearly every hurdle, weak bots ([errorRate])
/// mistime and trip often. A real, beatable 1+CPU contest.
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
  static const double _strideLo = 0.085; // good-cadence window (sec) lo
  static const double _strideHi = 0.26; // good-cadence window (sec) hi
  static const double _rhythmGainPerStride = 0.16; // rhythm per clean stride
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

  // The jump window: a runner may vault while a hurdle is within this many
  // meters AHEAD. The window NARROWS down the track (tighter timing late). Vault
  // outside it (too early) OR fail to vault before contact (too late/missed) =
  // a trip.
  static const double _windowStartM = 3.2; // window depth at the first hurdle
  static const double _windowEndM = 1.7; // window depth at the last hurdle
  // Airborne time per vault: a hurdle is CLEARED only if the runner is still in
  // this arc when its body reaches the hurdle, so a vault must be timed to the
  // approach (launch too early and the arc ends short → trip).
  static const double _vaultAirSec = 0.42; // airborne arc length (sec)

  // TRIP: a mistimed / missed hurdle. The runner loses most of its rhythm, dead
  // stops for a beat, then recovers. A trip is HEAVY on purpose — it must cost a
  // masher more than it can claw back before the next (denser) hurdle, so blind
  // play nets near-zero up the track. A reading runner trips ~never.
  static const double _tripRhythmKeep = 0.15; // rhythm retained after a trip
  static const double _tripStopSec = 0.6; // dead-stop (no advance) after a trip
  // A hurdle can only trip a runner once (a one-shot as it passes the body), so
  // a single hurdle is one trip, never a per-frame grind.

  // ── Vault input (tap-in-window OR hold) ─────────────────────────────────────
  // A HOLD of at least this long also triggers a vault (the second, clearly
  // readable one-touch mapping: press-and-hold to leap). A held press auto-vaults
  // the next hurdle that enters the window.
  static const double _holdVaultSec = 0.16;

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
  static const double _botBaseInterval = 0.16;
  static const double _botAccuracyBonus = 0.06; // faster (better rhythm) when good
  static const double _botJitterBase = 0.06; // sloppier cadence when weak
  // When a bot commits its vault, as a fraction of one vault arc-reach of ground
  // ahead (the distance the runner covers while airborne). A SMALL fraction =
  // launch LATE/close = reliably still airborne at contact → CLEAR; a LARGE
  // fraction (≳1) = launch EARLY = the arc ends before the hurdle = land short →
  // TRIP. So strong bots use a small fraction (crisp clears) and weak bots a
  // large one (mistimed, trip-prone) — a real skill gradient.
  static const double _botVaultFracStrong = 0.55; // high accuracy → late, clears
  static const double _botVaultFracWeak = 1.05; // low accuracy → early, lands short
  // Bots hold at the blocks for a beat so a human can get off the line first.
  static const double _botWarmupSec = 1.4;

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
        botVaultFrac: _botVaultFrac(),
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

  /// When a bot commits a vault (fraction of one arc-reach of ground ahead).
  /// High accuracy → the small [_botVaultFracStrong] (launch late → clears); low
  /// accuracy → the large [_botVaultFracWeak] (launch early → lands short → trip).
  double _botVaultFrac() {
    final prof = ctx.botProfile;
    return lerpD(_botVaultFracWeak, _botVaultFracStrong, prof.accuracy.clamp(0.0, 1.0));
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

  /// A press (tap-down). A press is a VAULT when (a) a hurdle is in the jump
  /// window AND (b) it is a CONTROLLED press — at least a stride-gap since the
  /// last press, i.e. NOT part of a mash. Otherwise it is a STRIDE on the run
  /// cadence.
  ///
  /// This is the anti-spam crux: a vault must be a *deliberate, timed* press. A
  /// blind masher hammering every frame has near-zero gap between presses, so
  /// none of its presses qualify as a vault — it never leaves the ground and
  /// clips every hurdle. A measured runner presses the "JUMP!" cue cleanly
  /// (a real gap), so its vault registers and it sails over.
  void _press(int id) {
    final r = _runners[id];
    if (r == null || r.finished) return;

    // Energy always bumps so the figure reads as "trying" regardless of timing.
    r.energy = (r.energy + _energyPerTap).clamp(0.0, 1.0);

    // A TAP is ALWAYS a stride — it never clears a hurdle. Vaulting requires a
    // deliberate HOLD (press-and-hold auto-leaps at the clear moment, see
    // [_canClearVaultNow]). So a runner who only taps trips on EVERY hurdle: the
    // obstacle genuinely interposes, and blind tapping loses to a player who
    // reads each hurdle and holds to leap it.
    _stride(r);
  }

  /// Hold-to-vault: a press held past [_holdVaultSec] arms auto-vaulting, and the
  /// runner then leaps automatically at the right moment for each hurdle (see the
  /// [_canClearVaultNow] gate in [_tickRunners]). A quick tap stays a stride and a
  /// deliberate press-and-hold is a leap — two clearly-readable one-touch inputs.
  void _holdTick(int id, double dt) {
    final r = _runners[id];
    if (r == null || r.finished) return;
    r.holdSec += dt;
    if (r.holdSec >= _holdVaultSec) r.holding = true;
  }

  void _release(int id) {
    final r = _runners[id];
    if (r == null) return;
    r.holding = false;
    r.holdSec = 0;
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

  /// A vault attempt: launch a fixed-length airborne ARC ([_vaultAirSec]). A
  /// hurdle is cleared only if the runner is still airborne WHEN ITS BODY REACHES
  /// the hurdle (see [_resolveHurdleContact]) — so a vault must be TIMED to the
  /// hurdle's approach, not just fired whenever it appears on screen:
  ///  * Vault TOO EARLY (hurdle far away) → the arc ends before contact → land →
  ///    TRIP. (A blind masher fires the instant the hurdle pops in, far out, and
  ///    crashes back down well short of it.)
  ///  * Vault on cue (hurdle close, inside the reach window) → still airborne at
  ///    contact → CLEAR.
  /// Re-launching while already airborne just refreshes the arc (a double-hop).
  void _vault(_Runner r) {
    final hadHurdle = _hurdleInWindow(r) != null;
    r.airborne = true;
    r.airTimer = _vaultAirSec;
    r.figure.setLoco(LocoState.jump);
    if (hadHurdle) {
      _juice.hit(
        _runnerRoot(r).translate(0, -_footReach * 1.1),
        _colorOf(r.slot.id),
        sparks: 6,
      );
    }
  }

  /// Index of the next un-passed hurdle inside the runner's jump window — the
  /// band where a vault is OFFERED (the "JUMP!" telegraph shows). The window is
  /// only the cue range; whether a vault actually CLEARS still depends on being
  /// airborne at contact, so firing at the far edge (too early) still trips.
  int? _hurdleInWindow(_Runner r) {
    final idx = r.nextHurdle;
    if (idx >= _hurdleMeters.length) return null;
    final ahead = _hurdleMeters[idx] - r.meters;
    final window = _jumpWindowAt(_hurdleMeters[idx]);
    if (ahead <= window && ahead > 0) return idx;
    return null;
  }

  /// The jump-window depth (meters of telegraph lead) for a hurdle at distance
  /// [hurdleM] — NARROWS toward the finish so late hurdles give less lead time
  /// and demand tighter timing (the calibrated ramp).
  double _jumpWindowAt(double hurdleM) {
    final t = (hurdleM / _raceMeters).clamp(0.0, 1.0);
    return lerpD(_windowStartM, _windowEndM, t);
  }

  /// True when a vault launched THIS instant would clear the next hurdle — i.e.
  /// the hurdle is close enough that the runner is still inside the [_vaultAirSec]
  /// arc when its body reaches it. This is the skilled read: vault now and sail
  /// over. A vault launched outside this band (hurdle too far) lands short → trip.
  /// Used by the hold-to-vault auto-trigger and the [shouldVaultNow] test seam.
  bool _canClearVaultNow(_Runner r) {
    if (r.airborne) return false;
    final idx = _hurdleInWindow(r); // a vault only fires when one is in the window
    if (idx == null) return false;
    final ahead = _hurdleMeters[idx] - r.meters;
    if (ahead <= 0) return false;
    final speed = lerpD(_jogSpeed, _sprintSpeed, r.rhythm);
    final arcReach = speed * _vaultAirSec; // ground covered while airborne
    // Clears across most of the arc; a small inset off the far edge keeps the
    // "lands exactly on the bar" knife-edge out of the safe read.
    return ahead <= arcReach * 0.9;
  }

  void _tickRunners(double dt) {
    for (final r in _runners.values) {
      r.sinceTap += dt;
      r.tripStop = math.max(0, r.tripStop - dt);

      // Auto-vault while holding: the held press leaps automatically at the
      // right moment (when a vault now would clear), so HOLD is a valid, forgiving
      // way to clear a hurdle — the second readable one-touch mapping.
      if (r.holding && _canClearVaultNow(r)) {
        _vault(r);
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

  /// Resolve the body passing a hurdle. Clearance is decided purely by whether
  /// the runner is AIRBORNE at the instant its body reaches the hurdle: airborne
  /// → vaulted clean; grounded → clipped it → TRIP. One-shot per hurdle (it is
  /// consumed as the body passes), so one hurdle is one trip, never a grind.
  void _resolveHurdleContact(_Runner r) {
    final idx = r.nextHurdle;
    if (idx >= _hurdleMeters.length) return;
    final hurdleM = _hurdleMeters[idx];
    if (r.meters < hurdleM) return; // not reached yet

    r.nextHurdle++; // consume this hurdle
    if (!r.airborne) _trip(r, hurdleM);
  }

  /// A TRIP: the runner clipped a hurdle (no vault in the window). Lose most of
  /// the gait rhythm, dead-stop for a beat, and play a full-body stumble. Heavy
  /// on purpose — a masher that trips every hurdle stalls; a reader trips ~never.
  void _trip(_Runner r, double hurdleM) {
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

  /// Bots stride on a cadence clock AND vault each hurdle as it enters their
  /// window. Strong bots stride faster (higher rhythm) and vault crisply; weak
  /// bots stride sloppier and, on an [errorRate] slip, fail to vault → trip. The
  /// guard caps catch-up strides for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // hold bots at the blocks for a beat
    for (final r in _runners.values) {
      if (!r.slot.isBot || r.finished) continue;
      _botMaybeVault(r);
      r.botClock += dt;
      var guard = 0;
      while (r.botClock >= r.nextTapAt && guard++ < 8) {
        r.botClock -= r.nextTapAt;
        _stride(r); // bots stride on-cadence (clamped in-window → grows rhythm)
        r.nextTapAt = _nextBotInterval(r);
      }
    }
  }

  /// A bot vaults the next hurdle once its body closes to [_Runner.botVaultFrac]
  /// of one vault arc-reach away. A SMALL fraction (strong bot) launches LATE/
  /// close so the runner is still airborne at contact → CLEAR; a LARGE fraction
  /// (weak bot, ≳1) launches EARLY so the arc ends before the hurdle → land short
  /// → TRIP. On an [errorRate] slip the bot skips the vault entirely and clips the
  /// hurdle — a careless miss, exactly like a human who didn't react in time.
  void _botMaybeVault(_Runner r) {
    if (r.airborne) return;
    final idx = r.nextHurdle;
    if (idx >= _hurdleMeters.length) return;
    if (r.botVaultedFor == idx) return; // already attempted this hurdle
    final hurdleM = _hurdleMeters[idx];
    final ahead = hurdleM - r.meters;
    if (ahead <= 0) return;
    final speed = lerpD(_jogSpeed, _sprintSpeed, r.rhythm);
    final arcReach = speed * _vaultAirSec; // ground covered while airborne
    final commitAt = arcReach * r.botVaultFrac;
    if (ahead > commitAt) return; // hurdle still too far to commit a vault
    r.botVaultedFor = idx;
    // Careless slip: skip the vault on this hurdle and eat the trip.
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return;
    _vault(r);
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
  /// it enters a runner's jump window it lights up (a "JUMP!" cue + arc) so a
  /// reading player always gets the tell; a cleared/passed hurdle fades.
  void _drawHurdles(Canvas canvas) {
    for (var lane = 0; lane < _laneOrder.length; lane++) {
      final r = _runners[_laneOrder[lane]];
      if (r == null) continue;
      final y = _laneYs[lane];
      for (var idx = 0; idx < _hurdleMeters.length; idx++) {
        final hurdleM = _hurdleMeters[idx];
        final ahead = hurdleM - r.meters;
        // Cull hurdles well behind or far ahead of this runner (keeps the lane
        // legible — only the nearby gauntlet is drawn).
        if (ahead < -2 || ahead > 26) continue;
        final x = lerpDouble(_startX, _finishX, hurdleM / _raceMeters)!;
        final passed = idx < r.nextHurdle;
        final live =
            !passed && idx == r.nextHurdle && _hurdleInWindow(r) != null;
        SprintRenderer.drawHurdle(
          canvas,
          Offset(x, y),
          _laneHeight(lane),
          live: live,
          passed: passed,
          warnPulse: 0.5 + 0.5 * math.sin(_animClock * 12.0 + idx),
        );
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
      final speed01 = r.energy;

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

  /// Whether a hurdle is inside [id]'s jump window — the "JUMP!" telegraph is
  /// showing (a hurdle is approaching and a vault is offered). The earliest tell.
  /// Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  bool hasHurdleInWindow(int id) {
    final r = _runners[id];
    if (r == null) return false;
    return _hurdleInWindow(r) != null;
  }

  /// Whether a vault launched THIS instant would CLEAR [id]'s next hurdle — the
  /// precise skilled read (the hurdle is close enough that the runner is still
  /// airborne when its body reaches it). A measured player vaults exactly here;
  /// vaulting earlier (merely on the telegraph) lands short → trip. Read-only;
  /// for deterministic gameplay tests + smart play.
  @visibleForTesting
  bool shouldVaultNow(int id) {
    final r = _runners[id];
    if (r == null) return false;
    return _canClearVaultNow(r);
  }
}

/// Per-player race state. Mutable round-scoped state (allowed for the duration
/// of a single round).
class _Runner {
  final PlayerSlot slot;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;
  final double botVaultFrac; // where in the window this bot commits its vault

  bool finished = false;

  // Distance + rhythm bookkeeping.
  double meters = 0; // distance covered down the track — THIS is the score
  double sinceTap = 1e9; // seconds since this runner's last stride tap
  double rhythm = 0; // 0..1 gait rhythm; sets run speed
  double energy = 0; // 0..1 smoothed recent tap rate (animation only)
  double stridePhase = 0; // gait phase for dust sync

  // Hurdle bookkeeping.
  int nextHurdle = 0; // index of the next hurdle the body will reach
  double tripStop = 0; // seconds of dead-stop remaining after a trip
  bool airborne = false; // mid-vault arc
  double airTimer = 0; // seconds of airborne arc remaining

  // Hold-to-vault.
  bool holding = false; // a press is held long enough to arm auto-vault
  double holdSec = 0; // seconds the current press has been held

  // Bot cadence clock.
  double botClock = 0;
  double nextTapAt;
  int botVaultedFor = -1; // hurdle index this bot has already attempted to vault

  _Runner({
    required this.slot,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
    required this.botVaultFrac,
  }) : nextTapAt = botInterval;
}
