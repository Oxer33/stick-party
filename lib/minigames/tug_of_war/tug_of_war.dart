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

/// Tug of War — a TOP team and a BOTTOM team MASH to drag a VERTICAL rope marker
/// past their goal line (top/bottom edge of the tall screen); the first side to
/// do so wins and the losers ragdoll-fly into a central mud/lava pit. At the
/// time limit the side nearer its goal wins, so the round ALWAYS resolves. Sides
/// split by [Team] (Team.a = top, Team.b = bottom) or, with no teams, even/odd
/// player id (even = top).
///
/// Skill layer (one-touch) — rhythm beats blind spam: the rope moves ONLY on a
/// HEAVE, the first in-window tap of a shared metronome's sweep through a
/// centered SWEET-SPOT; pull scales with timing precision, and a decaying
/// per-side effort meter (mash to hold it) gives a small bonus. Off-beat taps
/// just feed effort. CLIMAX: late-round HEAVEs pull harder ("FINAL HEAVE!").
/// COMEBACK: the trailing side gets a small HEAVE bonus so it stays in the
/// fight. Bots tap on a [BotProfile] cadence and scatter around the beat by
/// accuracy, so easy bots mistime it (beatable) and hard bots land it often.
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
  // HOLD-AND-RELEASE DIG-IN: the rope moves only when a player DIGS IN — press
  // (down) while the beat is in the sweet-spot to start charging a heave, then
  // RELEASE (up) to fire. A longer hold pulls harder (charge lerps the pull),
  // but holding PAST the window close SLIPS: the marker recoils toward you and
  // the dig-in is wasted. So timing the press AND the release both matter —
  // rhythm + nerve beat blind spam.
  static const double _heavePullMin = 0.014; // pull for an instant (zero-hold) dig
  static const double _heavePullMax = 0.060; // pull for a full-charge dig

  // ── Effort meter (per side) tuning ──────────────────────────────────────────
  static const double _effortPerTap = 0.12; // meter bump per tap
  static const double _effortDecayPerSec = 0.55; // bleeds so you must keep going

  // ── Visible HEAVE beat (a sweeping sweet-spot you tap ON) ────────────────────
  // A HEAVE is rate-limited to one per window pass (a human can't double-dip a
  // single beat), so total pull tracks *timing*, not raw tap rate — blind spam
  // off the beat goes almost nowhere.
  static const double _beatPeriodSec = 1.05; // one full left→right→left sweep
  static const double _beatWindowHalf = 0.13; // sweet-spot half-width (0..1 pos)
  static const double _heaveDecayPerSec = 0.7; // charge bleed when missing
  static const double _heaveFireThreshold = 1.0; // charge full = bar tip glows
  static const double _heaveSurgeSec = 0.34; // pull-surge window (body twitch)
  static const double _heaveCueSec = 0.45; // shockwave cue life

  // ── Hold-and-release dig-in tuning ──────────────────────────────────────────
  // A held dig charges from 0→1 over [_holdToFullSec]; the charge lerps the pull
  // between [_heavePullMin] and [_heavePullMax]. Releasing after the beat has
  // left the window (plus a short grace) SLIPS: the marker recoils by
  // [_slipRecoil] toward the opponent and the slipping side's effort meter dumps.
  static const double _holdToFullSec = 0.42; // hold time for a full-charge dig
  static const double _slipGraceSec = 0.12; // grace past window close before a slip
  static const double _slipRecoil = 0.05; // marker recoil toward the opponent
  // Bots can't hold (they send down only), so they auto-release at a charge set
  // by accuracy — strong bots dig in deeper. Centered so even weak bots pull.
  static const double _botHoldChargeBase = 0.45; // weakest-bot release charge
  static const double _botHoldChargeGain = 0.5; // extra release charge at full acc

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

  // ── Bot mash cadence (sec/tap); harder bots mash faster + steadier ──────────
  static const double _botWarmupSec = 1.0; // grace before bots engage
  static const double _botBaseInterval = 0.22;
  static const double _botAccuracyBonus = 0.07; // faster at high accuracy
  static const double _botJitterBase = 0.06; // sloppier at low accuracy

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
    switch (input.phase) {
      case InputPhase.down:
        _press(input.playerId);
      case InputPhase.up:
        _release(input.playerId);
      case InputPhase.holdTick:
        break; // charge advances in update(); holdTick carries no new decision
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

    _tickBeat(dt); // real-time so the sweet-spot reads the same regardless of hitstop
    _maybeFireFinalHeave();
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

  /// Test-only view of the dig-in window so deterministic tests can press
  /// exactly on the beat. Not used by gameplay.
  @visibleForTesting
  bool get beatWindowOpenForTest => _beatInWindow;

  /// 0..1 precision of the current beat position: 1 = dead-center, 0 = window
  /// edge. Drives how strong an on-beat HEAVE is, so aiming for the center beats
  /// slapping the moment you enter the window.
  double get _beatPrecision =>
      1.0 - ((_beatPos - 0.5).abs() / _beatWindowHalf).clamp(0.0, 1.0);

  // ── Press / hold / release → dig-in HEAVE or SLIP ───────────────────────────

  /// A press (down). Always feeds the side's effort meter. If the beat is in the
  /// sweet-spot and this player still has an un-spent dig this pass, begin a HOLD
  /// — `heaveCharge` then ramps in [_tickHeave] while held. An off-beat press
  /// just feeds effort (no dig), so blind spam goes nowhere.
  void _press(int id) {
    final pl = _pullers[id];
    if (pl == null) return;

    _effort[pl.side]?.tap();

    if (pl.holding) return; // already digging in
    if (!(_beatInWindow && pl.heaveArmed)) return; // off-beat / already spent
    pl.heaveArmed = false; // consume this window pass
    pl.holding = true;
    pl.heaveCharge = 0;
    pl.holdStartPrecision = _beatPrecision.clamp(0.0, 1.0);
  }

  /// A release (up). Fires the held dig: a longer hold pulls harder. But if the
  /// player held PAST the window close (beyond a short grace) it SLIPS instead —
  /// the marker recoils toward them and their effort dumps. Releasing without a
  /// live hold does nothing.
  void _release(int id) {
    final pl = _pullers[id];
    if (pl == null || !pl.holding) return;
    pl.holding = false;
    final charge = pl.heaveCharge.clamp(0.0, _heaveFireThreshold);
    if (pl.heldTooLong) {
      _slip(pl);
    } else {
      _fireDig(pl, charge);
    }
    pl.heldTooLong = false;
  }

  /// Fire a dig-in HEAVE for [pl] with the given hold [charge] (0..1). Pull lerps
  /// between [_heavePullMin] (instant) and [_heavePullMax] (full hold), boosted a
  /// touch by a clean (centered) press, by the side's effort, and by the climax /
  /// comeback multipliers — then drags the marker toward this side's goal.
  void _fireDig(_Puller pl, double charge) {
    final effort = _effort[pl.side]?.progress ?? 0.0;
    // A cleaner (more centered) press start adds a small bonus, so timing the
    // press still matters on top of the hold length.
    final precBonus = 0.15 * pl.holdStartPrecision;
    _fireHeave(pl, charge);

    var pull = lerpD(_heavePullMin, _heavePullMax, charge.clamp(0.0, 1.0)) *
        (1.0 + 0.25 * effort + precBonus);
    if (_inClimax) pull *= _climaxHeaveMul; // CLIMAX: finale pulls harder
    pull *= 1.0 + _comebackBonusFor(pl.side); // COMEBACK: help the trailing side
    _marker += pl.side == _Side.top ? -pull : pull;
    _marker = clampD(_marker, -_winThreshold, _winThreshold);
  }

  /// A SLIP: the player held their dig too long. The marker recoils toward their
  /// own side (giving the opponent ground) and their effort meter dumps. A clear,
  /// readable punishment for greedy over-holding.
  void _slip(_Puller pl) {
    final recoil = _slipRecoil * (1.0 + _comebackBonusFor(_other(pl.side)));
    // A slip gives the OPPONENT ground: the marker moves toward the opponent's
    // goal (top slips → marker drifts down/+; bottom slips → marker drifts up/-).
    _marker += pl.side == _Side.top ? recoil : -recoil;
    _marker = clampD(_marker, -_winThreshold, _winThreshold);
    // Effort dumps: a slip wastes the side's built-up effort (full reset).
    _effort[pl.side]?.reset();
    pl.heaveCharge = 0;
    pl.surge = 0;
    pl.cue = _heaveCueSec; // reuse the cue ring as a "slip!" tell
    pl.figure.hurt(); // a buckle on the body so the over-hold reads as a slip
    final at = _runnerRoot(pl).translate(0, -_footReach * 0.9);
    _juice.popup(at, 'SLIP!', _splashLava, size: 24);
    _juice.shake.light();
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
      if (pl.cue > 0) pl.cue = math.max(0, pl.cue - dt);

      if (pl.holding) {
        _tickHold(pl, dt);
      } else if (pl.heaveCharge > 0) {
        // Idle charge bleeds toward 0 (drives the effort-bar tip glow fade).
        pl.heaveCharge = math.max(0, pl.heaveCharge - _heaveDecayPerSec * dt);
      }
    }
  }

  /// Advance a live hold: ramp `heaveCharge` 0→1 over [_holdToFullSec] and, once
  /// the beat has left the window past [_slipGraceSec], latch [heldTooLong] so
  /// the eventual release SLIPS. A wildly over-long hold auto-releases (a slip)
  /// so a forgotten finger never freezes the dig.
  void _tickHold(_Puller pl, double dt) {
    pl.heaveCharge =
        (pl.heaveCharge + dt / _holdToFullSec).clamp(0.0, _heaveFireThreshold);
    pl.holdSinceWindow = _beatInWindow ? 0.0 : pl.holdSinceWindow + dt;
    if (pl.holdSinceWindow > _slipGraceSec) pl.heldTooLong = true;
    // Safety auto-release: a hold left way past the slip point resolves itself.
    if (pl.holdSinceWindow > _slipGraceSec + _holdToFullSec) {
      _release(pl.slot.id);
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

  /// Bots can only send down (no hold), so they're routed through an INSTANT
  /// dig-and-release: on a cadence tick that lands while the beat is in the
  /// window (and their accuracy roll hits), a bot presses + immediately releases
  /// at a charge chosen by accuracy — strong bots dig in deeper and clean, weak
  /// bots mistime the beat or release shallow, so they stay beatable. Off-beat
  /// ticks just feed effort. A short warmup gives the human the first beat; the
  /// guard caps catch-up taps for huge frame steps. Bots never over-hold, so
  /// they never self-slip.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return;
    for (final pl in _pullers.values) {
      if (!pl.slot.isBot) continue;
      pl.botClock += dt;
      var guard = 0;
      while (pl.botClock >= pl.nextTapAt && guard++ < 8) {
        pl.botClock -= pl.nextTapAt;
        // Feed effort every tick (the press path also does this for humans).
        _effort[pl.side]?.tap();
        final onBeat =
            _beatInWindow && pl.heaveArmed && _botHitsBeat();
        if (onBeat) {
          pl.heaveArmed = false; // consume this window pass like a human press
          pl.holdStartPrecision = _beatPrecision.clamp(0.0, 1.0);
          _fireDig(pl, _botHoldCharge()); // instant auto-release at chosen charge
        }
        pl.nextTapAt = _nextBotInterval(pl);
      }
    }
  }

  /// A bot's chance of nailing the sweet spot scales with accuracy, so dig-in
  /// timing is what separates tiers — easy bots mostly mistime it.
  bool _botHitsBeat() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    return ctx.rng.chance(0.25 + 0.7 * acc);
  }

  /// The hold charge a bot releases at (its auto-release point), scaled by
  /// accuracy so strong bots dig in deeper — never over-held, so never a slip.
  double _botHoldCharge() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    return (_botHoldChargeBase + _botHoldChargeGain * acc).clamp(0.0, 1.0);
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
    TugRenderer.drawCrowdBands(canvas, size, _crowdBandFrac);
    TugRenderer.drawPit(canvas, _pitCenter, _pitRx, _pitRy, _animClock);
    TugRenderer.drawFieldLines(
        canvas, size, _midX, _centerY, _topGoalY, _bottomGoalY);

    _drawTeamsAndRope(canvas);
    _drawEffortBars(canvas);
    _drawBeatTrack(canvas);

    // Vignette over the field, intensifying as the marker nears an edge.
    TugRenderer.drawVignette(canvas, size, _markerEdgeProximity());

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
    TugRenderer.drawRope(
      canvas,
      Offset(_midX, _topHandY),
      Offset(_midX, _bottomHandY),
      knot,
      bow,
      topLead,
      bottomLead,
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

  void _drawEffortBars(Canvas canvas) {
    final barW = _size.width * _effortBarFrac;
    final topBarY = _size.height * _effortBarInsetFrac;
    final bottomBarY = _size.height * (1 - _effortBarInsetFrac);
    final topColor = _colorOf(_frontPullerId(_Side.top));
    final bottomColor = _colorOf(_frontPullerId(_Side.bottom));
    TugRenderer.drawEffortBar(
      canvas,
      Offset(_midX, topBarY),
      barW,
      _effort[_Side.top]?.progress ?? 0.0,
      _heaveOfSide(_Side.top),
      topColor,
      dir: -1,
    );
    TugRenderer.drawEffortBar(
      canvas,
      Offset(_midX, bottomBarY),
      barW,
      _effort[_Side.bottom]?.progress ?? 0.0,
      _heaveOfSide(_Side.bottom),
      bottomColor,
      dir: 1,
    );
  }

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

  // On-beat dig-in (hold-and-release) bookkeeping.
  bool heaveArmed = true; // true = a dig is available this window pass
  bool holding = false; // true while a dig is charging (down held)
  double heaveCharge = 0; // 0.._heaveFireThreshold (hold charge / bar tip glow)
  double holdStartPrecision = 0; // beat precision when the hold began (0..1)
  double holdSinceWindow = 0; // seconds the hold has run since the beat left window
  bool heldTooLong = false; // latched once a hold passes the slip point
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
