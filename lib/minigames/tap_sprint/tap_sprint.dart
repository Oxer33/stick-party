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
import 'sprint_render.dart';

/// Tap Sprint — a 100 m dash. Each player is a stickman sprinter in a lane;
/// MASH (no-decay [TapMashMeter]) to run. The meter's fill is the runner's
/// position on the track; the first across the finish tape is 1st, then
/// 2nd/3rd/4th as they cross. On the time limit, unfinished runners are ranked
/// by distance covered, so the round always resolves.
///
/// Depth (still one-touch):
///  * **Stride rhythm**: tapping in a steady cadence window grows a per-runner
///    rhythm factor; erratic / spammed taps let it bleed off. A smooth gait
///    converts each tap into slightly more ground (a small rhythm bonus on top
///    of the no-decay meter), so rhythm — not just raw speed — wins the race.
///  * **Mash energy** drives the whole body language: a smoothed recent-tap
///    rate sets the run-cycle speed (we feed the animator a stretched dt), the
///    forward lean angle, plus footstep dust and back-streaking speed lines.
///  * **Photo finish**: when the leader is about to break the tape and nobody
///    has crossed yet, a brief slow-mo + spotlight sell the moment.
///
/// Bots mash on a [BotProfile]-driven cadence — harder bots are faster and
/// steadier, so they hold the rhythm window and pull ahead.
class TapSprint extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tap_sprint',
        name: 'Tap Sprint',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'MASH',
      );

  // ── Round / track tuning (no magic numbers inline) ──────────────────────────
  static const double _timeLimit = 30;
  static const double _tapImpulse = 0.016; // base no-decay meter gain per tap
  static const double _trackInsetXFrac = 0.085; // start margin / arena width
  static const double _finishInsetXFrac = 0.10; // finish margin / arena width
  static const double _trackTopFrac = 0.30; // stands above, track below
  static const double _laneTopPadFrac = 0.10; // first lane inset into track
  static const double _laneBotPadFrac = 0.10; // last lane inset into track

  // ── Stride rhythm tuning ────────────────────────────────────────────────────
  static const double _cadenceLo = 0.07; // good-cadence window (sec) lo
  static const double _cadenceHi = 0.22; // good-cadence window (sec) hi
  static const double _rhythmGainInWindow = 0.16; // rhythm added per good tap
  static const double _rhythmPenaltyOutWindow = 0.20; // rhythm lost per bad tap
  static const double _rhythmDecayPerSec = 0.35; // idle bleed toward 0
  static const double _rhythmBonusPerTap = 0.004; // extra fill / tap at rhythm 1

  // ── Mash energy / animation tuning ──────────────────────────────────────────
  static const double _energyPerTap = 0.16; // smoothed-rate bump per tap
  static const double _energyDecayPerSec = 1.5; // bleed of the smoothed rate
  static const double _strideMaxBoost = 1.7; // extra leg-cycle speed at full E
  static const double _maxLeanRad = 0.34; // forward lean at full energy

  // ── Photo-finish tuning ─────────────────────────────────────────────────────
  static const double _photoFinishProgress = 0.93; // leader past this → arm it
  static const double _photoFinishSlowScale = 0.32; // slow-mo time scale
  static const double _photoFinishSec = 0.55; // slow-mo duration

  // ── Final-stretch climax ─────────────────────────────────────────────────────
  // When the leader passes [_finalStretchProgress] a one-shot "FINAL STRETCH!"
  // banner + shake fire, so the finale is unmistakable well before the tape.
  static const double _finalStretchProgress = 0.74; // leader past this → cue

  // ── Comeback (rubber-band, kid-assist) ───────────────────────────────────────
  // Trailing runners convert each tap into a touch more ground, scaled by how
  // far behind the leader they are. Capped + small so it keeps a behind kid in
  // the race without ever letting them leapfrog a steady leader on its own.
  static const double _catchUpMaxBonusPerTap = 0.010; // extra fill / tap at full gap
  static const double _catchUpGapFull = 0.35; // gap (progress) for the full bonus

  // ── Bot mash cadence (sec/tap); harder bots mash faster + steadier ──────────
  static const double _botBaseInterval = 0.15;
  static const double _botAccuracyBonus = 0.07; // faster at high accuracy
  static const double _botJitterBase = 0.05; // sloppier (worse rhythm) when weak
  // Bots hold at the blocks for a beat so the start is fair and a human can get
  // off the line first — they never sprint away before the player reacts.
  static const double _botWarmupSec = 1.5;

  // ── Figure / feel tuning ────────────────────────────────────────────────────
  static const double _figureScale = 1.9; // readable sprinters
  static const double _bodyWidthFactor = 2.6; // dust/shadow half-width / torsoW
  static const Color _accent = Color(0xFFFFD24A);

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for crowd/dust/tape
  bool _photoFinishFired = false;
  bool _finalStretchFired = false; // one-shot "FINAL STRETCH!" climax cue latch

  late double _startX;
  late double _finishX;
  late double _trackTop;
  late double _footReach; // pelvis→foot length at rest (for grounding)
  late double _bodyW;
  late StickProportions _proportions;

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

    _buildRunners();
    begin();
  }

  void _computeLayout() {
    _startX = _size.width * _trackInsetXFrac;
    _finishX = _size.width * (1 - _finishInsetXFrac);
    _trackTop = _size.height * _trackTopFrac;

    final top = _trackTop + (_size.height - _trackTop) * _laneTopPadFrac;
    final bot = _size.height - (_size.height - _trackTop) * _laneBotPadFrac;
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

  void _buildRunners() {
    for (final p in ctx.players) {
      _runners[p.id] = _Runner(
        slot: p,
        meter: TapMashMeter(tapImpulse: _tapImpulse),
        figure: StickFigure(
          proportions: _proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1, // sprinters face the finish line (to the right)
        )..setLoco(LocoState.idle),
        botInterval: _botInterval(),
        botJitter: _botJitter(),
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
    return math.max(0.05, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  /// Weaker bots jitter more, so they fall out of the rhythm window and lose
  /// the per-tap bonus; strong bots stay metronomic and keep it.
  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.2;
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

  // ── Tap → rhythm + meter fill ───────────────────────────────────────────────

  void _tap(int id) {
    final r = _runners[id];
    if (r == null || r.finished) return;

    // Rhythm: a steady cadence grows it; spammed / erratic taps bleed it.
    final gap = r.sinceTap;
    r.sinceTap = 0;
    if (gap >= _cadenceLo && gap <= _cadenceHi) {
      r.rhythm = (r.rhythm + _rhythmGainInWindow).clamp(0.0, 1.0);
    } else {
      r.rhythm = (r.rhythm - _rhythmPenaltyOutWindow).clamp(0.0, 1.0);
    }

    // Mash energy bump (drives animation speed / lean / fx).
    r.energy = (r.energy + _energyPerTap).clamp(0.0, 1.0);

    // No-decay base fill from the shared meter, plus a small rhythm bonus so a
    // smooth gait covers slightly more ground per tap.
    r.meter.tap();
    r.rhythmBonus += _rhythmBonusPerTap * r.rhythm;

    // Comeback (rubber-band): a runner behind the leader earns a touch more
    // ground per tap, scaled by the gap — keeps a behind kid in the race.
    r.rhythmBonus += _catchUpBonus(r);

    r.figure.setLoco(LocoState.run);
  }

  /// Extra per-tap fill for a trailing runner, scaled 0..1 by how far behind the
  /// current leader it sits (capped at [_catchUpGapFull]). Zero for the leader.
  double _catchUpBonus(_Runner r) {
    final gap = _leadProgress() - r.progress;
    if (gap <= 0) return 0;
    final t = (gap / _catchUpGapFull).clamp(0.0, 1.0);
    return _catchUpMaxBonusPerTap * t;
  }

  void _tickRunners(double dt) {
    for (final r in _runners.values) {
      r.sinceTap += dt;
      // Rhythm + energy bleed when not feeding taps.
      r.rhythm = math.max(0, r.rhythm - _rhythmDecayPerSec * dt);
      r.energy = math.max(0, r.energy - _energyDecayPerSec * dt);

      _advanceFigure(r, dt);
      setScore(r.slot.id, r.progress);

      if (!r.finished && r.progress >= 1.0) {
        _cross(r);
      }
    }
  }

  /// Drive the figure with a stride speed scaled by mash energy: more energy →
  /// faster leg cycle (we feed the animator a stretched dt). The stride phase
  /// advances with the same scaled time so footstep dust pulses with the gait.
  void _advanceFigure(_Runner r, double dt) {
    if (r.finished || r.energy <= 0.02) {
      r.figure.setLoco(LocoState.idle);
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
  /// per-runner confetti + place popup, and a celebratory shake on first place.
  void _cross(_Runner r) {
    r.finished = true;
    _finishOrder.add(r.slot.id);
    r.figure.setLoco(LocoState.idle);

    final place = _finishOrder.length;
    final at = _runnerRoot(r).translate(0, -_footReach * 1.1);
    _juice.popup(at, _ordinal(place), _colorOf(r.slot.id), size: 34);
    if (!_confettiFor.contains(r.slot.id)) {
      _confettiFor.add(r.slot.id);
      _juice.confetti(_size, colors: [_colorOf(r.slot.id)]);
    }
    if (place == 1) {
      _juice.shake.heavy();
      _juice.hitStop.trigger(Feel.hitStopHeavySec, scale: 0.12);
    } else {
      _juice.shake.light();
    }
    _juice.hit(_tapeHitPoint(r), _colorOf(r.slot.id), sparks: 10);
  }

  /// Bots mash on a cadence clock with [BotProfile]-driven interval + jitter, so
  /// they read as steady (hard) or sloppy (easy) without ever branching beyond
  /// "is this slot a bot?". The guard caps catch-up taps for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // hold bots at the blocks for a beat
    for (final r in _runners.values) {
      if (!r.slot.isBot || r.finished) continue;
      r.botClock += dt;
      var guard = 0;
      while (r.botClock >= r.nextTapAt && guard++ < 8) {
        r.botClock -= r.nextTapAt;
        _tap(r.slot.id);
        r.nextTapAt = _nextBotInterval(r);
      }
    }
  }

  double _nextBotInterval(_Runner r) =>
      math.max(0.03, r.botInterval + ctx.rng.jitter(r.botJitter));

  // ── Photo finish ─────────────────────────────────────────────────────────────

  /// Arm a single slow-mo when the leader is about to break the tape and nobody
  /// has crossed yet — a brief, dramatic photo-finish beat.
  void _maybePhotoFinish() {
    if (_photoFinishFired || _finishOrder.isNotEmpty) return;
    final lead = _leadProgress();
    if (lead >= _photoFinishProgress && lead < 1.0) {
      _photoFinishFired = true;
      _juice.hitStop.trigger(_photoFinishSec, scale: _photoFinishSlowScale);
      _juice.shake.medium();
    }
  }

  double _leadProgress() {
    var best = 0.0;
    for (final r in _runners.values) {
      if (r.progress > best) best = r.progress;
    }
    return best;
  }

  // ── Resolution ──────────────────────────────────────────────────────────────

  void _resolve() {
    final allDone = _runners.values.every((r) => r.finished);
    if (!allDone && _elapsed < _timeLimit) return;

    // Finishers (by crossing time) first, then the rest by distance covered.
    final unfinished = _runners.values.where((r) => !r.finished).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    finishByOrder(<int>[
      ..._finishOrder,
      ...unfinished.map((r) => r.slot.id),
    ]);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SprintRenderer.drawBackground(canvas, size, _trackTop, _animClock);
    SprintRenderer.drawTrack(canvas, size, _trackTop);
    SprintRenderer.drawDistanceMarkers(
        canvas, size, _startX, _finishX, _markerScroll());
    SprintRenderer.drawLanes(
        canvas, size, _startX, _finishX, _laneYs, _laneColors());
    SprintRenderer.drawStartLine(canvas, size, _startX);

    _drawRunners(canvas);

    // Finish furniture on top of the runners so the tape reads as "ahead".
    SprintRenderer.drawFinish(canvas, size, _finishX, _animClock);

    _juice.render(canvas);
    canvas.restore();
  }

  /// Distance markers drift with the leader for a sense of forward motion.
  double _markerScroll() => (_leadProgress() * _laneCount() * 1.7) % 1.0;

  int _laneCount() => math.max(1, _laneYs.length);

  List<Color> _laneColors() => [for (final id in _laneOrder) _colorOf(id)];

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

  /// Draw a runner pitched forward by an amount that grows with mash energy
  /// (premium body language). Finished runners stand upright (decelerating).
  /// The lean rotates around the feet so the plant stays glued to the track.
  void _drawLeaningRunner(
      Canvas canvas, _Runner r, Offset root, double speed01) {
    if (r.finished) {
      SprintRenderer.drawSprinter(canvas, r.figure, root);
      return;
    }
    final lean = _maxLeanRad * speed01; // forward (into +x) = positive rotation
    final pivot = Offset(root.dx, root.dy + _footReach);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(lean);
    canvas.translate(-pivot.dx, -pivot.dy);
    SprintRenderer.drawSprinter(canvas, r.figure, root);
    canvas.restore();
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  /// Stick root for a runner: x mapped from progress along the track, y lifted
  /// by [_footReach] so the feet plant on the lane's foot line.
  Offset _runnerRoot(_Runner r) {
    final lane = _laneOrder.indexOf(r.slot.id);
    final y = (lane >= 0 ? _laneYs[lane] : _laneYs.first) - _footReach;
    final x = lerpDouble(_startX, _finishX, r.progress)!;
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
      if (r.progress > best) {
        best = r.progress;
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
}

/// Per-player race state. Mutable round-scoped state (allowed for the duration
/// of a single round).
class _Runner {
  final PlayerSlot slot;
  final TapMashMeter meter;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;

  bool finished = false;

  // Rhythm + energy bookkeeping.
  double sinceTap = 1e9; // seconds since this runner's last tap
  double rhythm = 0; // 0..1 stride-rhythm quality
  double energy = 0; // 0..1 smoothed recent mash rate
  double rhythmBonus = 0; // extra fill earned by a smooth gait (added to meter)
  double stridePhase = 0; // gait phase (advanced with scaled dt) for dust sync

  // Bot cadence clock.
  double botClock = 0;
  double nextTapAt;

  _Runner({
    required this.slot,
    required this.meter,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
  }) : nextTapAt = botInterval;

  /// Track position 0..1: the no-decay meter fill plus the rhythm bonus, capped.
  double get progress =>
      clampD(meter.progress + rhythmBonus, 0.0, 1.0);
}
