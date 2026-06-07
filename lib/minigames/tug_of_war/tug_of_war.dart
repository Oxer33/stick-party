import 'dart:math' as math;
import 'dart:ui';

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

/// Side of the rope. Left pulls the marker toward -1, right toward +1.
enum _Side { left, right }

/// Tug of War — two teams MASH to drag a rope marker across their goal line and
/// yank the losers into a central mud/lava pit.
///
/// Sides split by [Team] when set (duel / 2v2), else by even/odd player id.
///
/// Skill layer (still one-touch) — rhythm beats blind spam:
///  * Each side has a decaying [TapMashMeter]: a tap adds effort, idle bleeds it
///    away — so you must keep mashing to hold a lead. Effort scales both the
///    pull strength and how far back the team leans (premium body language).
///  * **Visible HEAVE beat**: a shared metronome marker sweeps back and forth
///    across a rhythm track with a highlighted SWEET-SPOT window. Tapping while
///    the marker is inside the window lands a HEAVE — a big bonus pull with a
///    "HEAVE!" popup + shockwave; mistimed taps give a weak pull. So timing the
///    beat (not mashing fastest) wins the rope.
///  * The net of both sides' effort drives the marker; first side past
///    ±threshold wins, and at the time limit the side nearer its goal wins, so
///    the round ALWAYS resolves.
///  * **Loser comedy**: the losing team is yanked off its feet and RAGDOLL-flies
///    into the pit with a big SPLASH (mud + lava particles), "SPLASH!" / "WIN!"
///    popups, slow-mo and a heavy shake.
///
/// Bots warm up (~1s grace) then tap on a [BotProfile] cadence; their timing
/// scatters around the beat by accuracy, so easy bots hit the sweet spot rarely
/// (beatable) while hard bots land it often.
class TugOfWar extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tug_of_war',
        name: 'Tug of War',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'MASH',
      );

  // ── Round / marker tuning (no magic numbers inline) ─────────────────────────
  // ~20s cap; back-and-forth play means an all-bot round still runs several
  // seconds before one side edges past its goal, so it never resolves instantly.
  static const double _timeLimit = 20;
  static const double _winThreshold = 1.0; // |marker| to win
  static const double _markerCenterPullPerSec = 0.03; // idle bleed toward 0
  // The rope moves ONLY on a HEAVE; off-beat taps do nothing to the marker (they
  // just feed the effort meter / body language). A HEAVE's pull scales with
  // timing precision, so a steady on-the-center rhythm out-pulls frantic spam
  // that catches windows at random points — rhythm beats button-mashing.
  static const double _heavePullMin = 0.014; // pull for a sloppy edge HEAVE
  static const double _heavePullMax = 0.060; // pull for a dead-center HEAVE

  // ── Effort meter (per side) tuning ──────────────────────────────────────────
  static const double _effortPerTap = 0.12; // meter bump per tap
  static const double _effortDecayPerSec = 0.55; // bleeds so you must keep going

  // ── Visible HEAVE beat (a sweeping sweet-spot you tap ON) ────────────────────
  // A HEAVE is rate-limited to one per window pass (a human can't double-dip a
  // single beat), so total pull tracks *timing*, not raw tap rate — blind spam
  // off the beat goes almost nowhere.
  static const double _beatPeriodSec = 1.05; // one full left→right→left sweep
  static const double _beatWindowHalf = 0.13; // sweet-spot half-width (0..1 pos)
  static const double _heaveGainInWindow = 0.5; // heave charge per good hit
  static const double _heaveDecayPerSec = 0.7; // charge bleed when missing
  static const double _heaveFireThreshold = 1.0; // charge full = bar tip glows
  static const double _heaveSurgeSec = 0.34; // pull-surge window (body twitch)
  static const double _heaveCueSec = 0.45; // shockwave cue life

  // ── Bot mash cadence (sec/tap); harder bots mash faster + steadier ──────────
  static const double _botWarmupSec = 1.0; // grace before bots engage
  static const double _botBaseInterval = 0.22;
  static const double _botAccuracyBonus = 0.07; // faster at high accuracy
  static const double _botJitterBase = 0.06; // sloppier at low accuracy

  // ── Layout tuning (fractions of arena) ──────────────────────────────────────
  static const double _ropeInsetFrac = 0.1; // team hands inset from edges
  static const double _midYFrac = 0.52; // foot / action line height
  static const double _ropeSagFrac = 0.055; // catenary sag depth / height
  static const double _goalInsetFrac = 0.17; // goal line inset from edges
  static const double _runnerGapFrac = 0.075; // spacing per figure within a side
  static const double _runnerBackoffFrac = 0.04; // figures behind the goal line
  static const double _pitWidthFrac = 0.36; // pit ellipse width / width
  static const double _pitHeightFrac = 0.11; // pit ellipse height / height
  static const double _groundTopFrac = 0.4; // ground slab starts here (frac h)
  static const double _effortBarFrac = 0.22; // effort bar width / width
  static const double _beatTrackFrac = 0.6; // HEAVE beat track width / width
  static const double _beatTrackYFrac = 0.2; // beat track height (frac h)

  // ── Figure / feel tuning ────────────────────────────────────────────────────
  static const double _figureScale = 2.0; // bigger, readable pullers
  static const double _maxLeanRad = 0.42; // max backward lean at full effort
  static const double _bodyWidthFactor = 3.2; // dust/shadow half-width / torsoW
  static const Color _splashMud = Color(0xFFB8500F);
  static const Color _splashLava = Color(0xFFFFC23A);
  static const Color _accent = Color(0xFFFFB54D);

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for shimmer/dust
  double _marker = 0; // [-1, 1]; -1 = left wins, +1 = right wins
  double _beatPos = 0.5; // 0..1 sweep position of the shared HEAVE beat
  double _beatClock = 0; // phase accumulator for the ping-pong sweep
  bool _beatWasInWindow = true; // edge-detect to re-arm HEAVE once per pass
  bool _resolved = false;

  late double _midY;
  late double _leftHandX;
  late double _rightHandX;
  late double _leftGoalX;
  late double _rightGoalX;
  late double _centerX;
  late Offset _pitCenter;
  late double _pitRx;
  late double _pitRy;
  late double _footReach; // pelvis→foot length at rest (for grounding)
  late double _bodyW; // rough body half-width for dust/shadows

  final Map<int, _Puller> _pullers = <int, _Puller>{};
  final Map<_Side, TapMashMeter> _effort = <_Side, TapMashMeter>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _computeLayout();

    _effort[_Side.left] = _makeEffortMeter();
    _effort[_Side.right] = _makeEffortMeter();

    final proportions = StickProportions.hero.scaled(_figureScale);
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = proportions.thigh + proportions.shin;
    _bodyW = proportions.torsoWidth * _bodyWidthFactor;

    for (final p in ctx.players) {
      final side = _sideFor(p);
      final facing = side == _Side.left ? 1.0 : -1.0; // face the rope/center
      _pullers[p.id] = _Puller(
        slot: p,
        side: side,
        figure: StickFigure(
          proportions: proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: facing,
        )..setLoco(LocoState.run),
        botInterval: _botInterval(),
        botJitter: _botJitter(),
      );
    }
    begin();
  }

  void _computeLayout() {
    _midY = _size.height * _midYFrac;
    _leftHandX = _size.width * _ropeInsetFrac;
    _rightHandX = _size.width * (1 - _ropeInsetFrac);
    _leftGoalX = _size.width * _goalInsetFrac;
    _rightGoalX = _size.width * (1 - _goalInsetFrac);
    _centerX = _size.width / 2;
    _pitRx = _size.width * _pitWidthFrac * 0.5;
    _pitRy = _size.height * _pitHeightFrac * 0.5;
    // Pit straddles the foot line so the two teams flank it and the rope sags
    // into its mouth; its lower half opens beneath the ground line.
    _pitCenter = Offset(_centerX, _midY + _pitRy * 0.15);
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

  /// Team-aware split: Team.a/Team.b honor explicit teams; otherwise even ids
  /// pull left, odd ids pull right. Guarantees a non-empty opposing side when
  /// there are 2+ players.
  _Side _sideFor(PlayerSlot p) {
    if (p.team == Team.a) return _Side.left;
    if (p.team == Team.b) return _Side.right;
    return p.id.isEven ? _Side.left : _Side.right;
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
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _tap(input.playerId);
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
    _driveBots(sdt);
    _tickHeave(sdt);
    _tickEffort(sdt);
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

  /// 0..1 precision of the current beat position: 1 = dead-center, 0 = window
  /// edge. Drives how strong an on-beat HEAVE is, so aiming for the center beats
  /// slapping the moment you enter the window.
  double get _beatPrecision =>
      1.0 - ((_beatPos - 0.5).abs() / _beatWindowHalf).clamp(0.0, 1.0);

  // ── Tap → effort + on-beat HEAVE + marker pull ──────────────────────────────

  void _tap(int id) => _doTap(id, onBeat: _beatInWindow, precision: _beatPrecision);

  /// Shared tap path. The rope moves ONLY on a HEAVE — the first in-window tap of
  /// each window pass (the [heaveArmed] latch re-arms when the beat leaves the
  /// window) — with pull scaled by timing [precision] (center > edge). Off-beat
  /// taps just feed the effort meter, so a tidy on-the-center rhythm out-pulls
  /// random spam. Bots run the same path gated by accuracy → identical rhythm.
  void _doTap(int id, {required bool onBeat, required double precision}) {
    final pl = _pullers[id];
    if (pl == null) return;

    // Effort meter for this side (decays, so mashing reads as continuous effort).
    _effort[pl.side]?.tap();

    if (!(onBeat && pl.heaveArmed)) return; // off-beat / already-spent: no pull
    pl.heaveArmed = false; // consume this window pass

    final prec = precision.clamp(0.0, 1.0);
    final effort = _effort[pl.side]?.progress ?? 0.0;
    pl.heaveCharge =
        (pl.heaveCharge + _heaveGainInWindow).clamp(0.0, _heaveFireThreshold);
    _fireHeave(pl, prec);

    // Stronger side-effort gives a small bonus, so holding a fast rhythm helps.
    final pull = lerpD(_heavePullMin, _heavePullMax, prec) * (1.0 + 0.25 * effort);
    _marker += pl.side == _Side.left ? -pull : pull;
    _marker = clampD(_marker, -_winThreshold, _winThreshold);
  }

  void _fireHeave(_Puller pl, double precision) {
    pl.surge = _heaveSurgeSec;
    pl.cue = _heaveCueSec;
    final prec = precision.clamp(0.0, 1.0);
    final at = _runnerRoot(pl).translate(0, -_footReach * 0.9);
    // A dead-center HEAVE shouts louder than a sloppy edge one.
    _juice.popup(at, prec > 0.66 ? 'HEAVE!' : 'heave', _accent,
        size: 22 + 10 * prec);
    if (prec > 0.66) _juice.shake.light();
    _juice.particles.burst(
      at: at,
      count: (4 + 6 * prec).round(),
      color: _colorOf(pl.slot.id),
      speed: 150 + 90 * prec,
      size: 5,
      life: 0.4,
    );
  }

  void _tickHeave(double dt) {
    for (final pl in _pullers.values) {
      if (pl.surge > 0) pl.surge = math.max(0, pl.surge - dt);
      // Charge always bleeds toward 0 between on-beat hits (drives bar glow).
      if (pl.heaveCharge > 0) {
        pl.heaveCharge = math.max(0, pl.heaveCharge - _heaveDecayPerSec * dt);
      }
      if (pl.cue > 0) pl.cue = math.max(0, pl.cue - dt);
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

  /// Bots mash on a cadence clock with [BotProfile]-driven interval + jitter, so
  /// they read as steady (hard) or sloppy (easy) without ever branching beyond
  /// "is this slot a bot?". A short warmup gives the human the first beat. Each
  /// bot tap rolls its own on-beat chance from accuracy, so weak bots rarely
  /// HEAVE (beatable) and strong bots land it often. The guard caps catch-up
  /// taps for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return;
    for (final pl in _pullers.values) {
      if (!pl.slot.isBot) continue;
      pl.botClock += dt;
      var guard = 0;
      while (pl.botClock >= pl.nextTapAt && guard++ < 8) {
        pl.botClock -= pl.nextTapAt;
        // Bots are bound by the *real* beat just like a human: they can only
        // HEAVE while the marker is in the window, and even then only if their
        // accuracy roll lands — so weak bots fluff the timing and are beatable.
        final onBeat = _beatInWindow && _botHitsBeat();
        // A landing bot uses real precision scaled down by sloppiness; a missing
        // bot taps off-beat (weak nudge + burns its own upcoming heave).
        final prec = onBeat
            ? _beatPrecision * ctx.botProfile.accuracy.clamp(0.0, 1.0)
            : 0.0;
        _doTap(pl.slot.id, onBeat: onBeat, precision: prec);
        pl.nextTapAt = _nextBotInterval(pl);
      }
    }
  }

  /// A bot's chance of nailing the sweet spot scales with accuracy, so HEAVE
  /// timing is what separates tiers — easy bots mostly mistime it.
  bool _botHitsBeat() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    return ctx.rng.chance(0.25 + 0.7 * acc);
  }

  double _nextBotInterval(_Puller pl) =>
      math.max(0.04, pl.botInterval + ctx.rng.jitter(pl.botJitter));

  /// Score = how far this player's side has dragged the marker (0..1), so the
  /// on-field HUD shows the leading side. Teammates share their side value.
  void _publishScores() {
    for (final pl in _pullers.values) {
      final advantage = pl.side == _Side.left
          ? math.max(0.0, -_marker)
          : math.max(0.0, _marker);
      setScore(pl.slot.id, advantage);
    }
  }

  // ── Resolution ──────────────────────────────────────────────────────────────

  void _resolveIfDecided() {
    if (_marker <= -_winThreshold) {
      _resolve(_Side.left);
    } else if (_marker >= _winThreshold) {
      _resolve(_Side.right);
    } else if (_elapsed >= _timeLimit) {
      // Nearer goal wins; dead-even falls to left for determinism.
      _resolve(_marker <= 0 ? _Side.left : _Side.right);
    }
  }

  void _resolve(_Side winner) {
    if (_resolved) return;
    _resolved = true;

    // Comedy: losers get yanked off their feet and ragdoll-fly into the pit.
    final groundY = _pitCenter.dy + _pitRy;
    for (final pl in _pullers.values) {
      if (pl.side == winner) continue;
      final root = _runnerRoot(pl);
      final toPit = _pitCenter - root;
      final dir =
          toPit.distance < 1e-3 ? const Offset(0, -1) : toPit / toPit.distance;
      // Fling up-and-inward toward the pit so the arc lands in the mud.
      final fling = Offset(dir.dx * _size.width * 0.5, -_size.height * 0.42);
      pl.figure.enterRagdoll(root, groundY, fling);
    }

    _splashAndPopups(winner);
    _juice.shake.heavy();
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

    // "WIN!" over the winning side.
    final winX = winner == _Side.left ? _leftGoalX : _rightGoalX;
    _juice.popup(Offset(winX, _midY - _footReach * 1.4), 'WIN!',
        _colorOf(_anyWinnerId(winner)),
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
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    TugRenderer.drawBackground(canvas, size);
    TugRenderer.drawGround(canvas, size, size.height * _groundTopFrac);
    TugRenderer.drawPit(canvas, _pitCenter, _pitRx, _pitRy, _animClock);
    TugRenderer.drawFieldLines(
        canvas, size, _midY, _centerX, _leftGoalX, _rightGoalX);

    _drawTeamsAndRope(canvas);
    _drawEffortBars(canvas);
    _drawBeatTrack(canvas);

    // Vignette over the field, intensifying as the marker nears an edge.
    TugRenderer.drawVignette(canvas, size, _markerEdgeProximity());

    _juice.render(canvas);
    canvas.restore();
  }

  /// 0 at center, →1 as the marker approaches either goal (drives tension cues).
  double _markerEdgeProximity() =>
      (_marker.abs() / _winThreshold).clamp(0.0, 1.0);

  void _drawTeamsAndRope(Canvas canvas) {
    final leftLead = _colorOf(_frontPullerId(_Side.left));
    final rightLead = _colorOf(_frontPullerId(_Side.right));

    // Rope first (behind the pullers' hands), sagging to the knot.
    final knot = _knotPos();
    final sag = _size.height * _ropeSagFrac;
    TugRenderer.drawRope(
      canvas,
      Offset(_leftHandX, _midY),
      Offset(_rightHandX, _midY),
      knot,
      sag,
      leftLead,
      rightLead,
    );

    // Pullers: shadow + dust under each, then the leaning/straining figure.
    for (final pl in _pullers.values) {
      final root = _runnerRoot(pl);
      final feet = Offset(root.dx, root.dy + _footReach);
      final color = _colorOf(pl.slot.id);

      if (!pl.figure.isRagdoll) {
        TugRenderer.drawContactShadow(canvas, feet, _bodyW);
        final effort = _effort[pl.side]?.progress ?? 0.0;
        final dustDir = pl.side == _Side.left ? -1.0 : 1.0;
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
        canvas, knot, _marker, leftLead, rightLead, _animClock);
  }

  /// Draw a puller leaning back from the rope by an amount that grows with their
  /// side's effort (premium body language). Ragdolls render upright (their own
  /// frame already encodes the tumble). The lean rotates around the feet.
  void _drawLeaningPuller(Canvas canvas, _Puller pl, Offset root) {
    if (pl.figure.isRagdoll) {
      TugRenderer.drawPuller(canvas, pl.figure, root);
      return;
    }
    final effort = _effort[pl.side]?.progress ?? 0.0;
    // Lean away from the rope: left team leans left, right leans right. Add a
    // tiny surge twitch for the player who just heaved.
    final surgeKick = pl.surge > 0 ? 0.06 : 0.0;
    final lean = (_maxLeanRad * effort + surgeKick) *
        (pl.side == _Side.left ? 1.0 : -1.0);
    final pivot = Offset(root.dx, root.dy + _footReach);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(lean);
    canvas.translate(-pivot.dx, -pivot.dy);
    TugRenderer.drawPuller(canvas, pl.figure, root);
    canvas.restore();
  }

  void _drawEffortBars(Canvas canvas) {
    final barW = _size.width * _effortBarFrac;
    final barY = _midY - _size.height * 0.16;
    final leftColor = _colorOf(_frontPullerId(_Side.left));
    final rightColor = _colorOf(_frontPullerId(_Side.right));
    TugRenderer.drawEffortBar(
      canvas,
      Offset(_size.width * 0.26, barY),
      barW,
      _effort[_Side.left]?.progress ?? 0.0,
      _heaveOfSide(_Side.left),
      leftColor,
      dir: -1,
    );
    TugRenderer.drawEffortBar(
      canvas,
      Offset(_size.width * 0.74, barY),
      barW,
      _effort[_Side.right]?.progress ?? 0.0,
      _heaveOfSide(_Side.right),
      rightColor,
      dir: 1,
    );
  }

  /// The shared HEAVE beat: a centered rhythm track with a sweet-spot window and
  /// a sweeping marker. Tapping while the marker is inside the window lands a
  /// HEAVE — this is the visible rhythm cue the whole skill layer hangs on.
  void _drawBeatTrack(Canvas canvas) {
    final width = _size.width * _beatTrackFrac;
    final center = Offset(_centerX, _size.height * _beatTrackYFrac);
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

  /// Peak active surge/charge strength on a side (0..1) for the effort-bar glow.
  double _heaveOfSide(_Side side) {
    var best = 0.0;
    for (final pl in _pullers.values) {
      if (pl.side != side) continue;
      final v = pl.surge > 0
          ? (pl.surge / _heaveSurgeSec)
          : (pl.heaveCharge / _heaveFireThreshold);
      if (v > best) best = v;
    }
    return best.clamp(0.0, 1.0);
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  /// Rope knot world position: rides between the goal lines, mapped from the
  /// marker. Sits slightly below the rope baseline (the sag apex).
  Offset _knotPos() {
    final t = (_marker + 1) / 2; // 0..1 over [-1,1]
    final x = lerpDouble(_leftGoalX, _rightGoalX, t)!;
    // Knot dips toward the pit mouth so the rope visibly sags into the lava.
    return Offset(x, _pitCenter.dy - _pitRy * 0.35);
  }

  /// Stick root for a puller: stacked just behind their goal line, offset by
  /// their index within the side so multiple figures don't overlap. Pelvis is
  /// lifted by [_footReach] so the feet plant on the ground line.
  Offset _runnerRoot(_Puller pl) {
    final gap = _size.width * _runnerGapFrac;
    final backoff = _size.width * _runnerBackoffFrac;
    final index = _indexOnSide(pl);
    final y = _midY - _footReach;
    if (pl.side == _Side.left) {
      return Offset(_leftGoalX - backoff - index * gap, y);
    }
    return Offset(_rightGoalX + backoff + index * gap, y);
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
  bool heaveArmed = true; // true = a HEAVE is available this window pass
  double heaveCharge = 0; // 0.._heaveFireThreshold (drives effort-bar tip glow)
  double surge = 0; // seconds of active pull surge remaining
  double cue = 0; // seconds of HEAVE shockwave cue remaining

  _Puller({
    required this.slot,
    required this.side,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
  }) : nextTapAt = botInterval;
}
