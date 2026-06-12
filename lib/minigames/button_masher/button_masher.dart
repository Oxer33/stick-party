import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'masher_render.dart';

/// Tower Climb — a race UP a tall tower to the FLAG at the top, past sweeping
/// hazard bars. (Keeps the legacy `button_masher` id; the old spam-a-button
/// "high striker" is gone.)
///
/// OBJECTIVE (obvious from the scene): be FIRST to climb your stickman to the
/// FLAG atop the tower. If nobody summits before the buzzer, the climber who
/// reached the HIGHEST rung wins. The flag sits at the top of every lane and the
/// score is the best rung ever reached ([_Climber.peakRung]).
///
/// CORE — one-touch, NOT a mash:
///  * **One TAP = climb ONE rung.** No tap = hold your rung. That is the whole
///    control: when to step, when to wait.
///
/// INTERPOSING DIFFICULTY — sweeping HAZARD BARS:
///  * Horizontal bars sweep left↔right across the tower at fixed HEIGHTS (bands).
///    Each bar is **telegraphed**: it spends a beat in a flashing WARN state
///    (harmless) before it goes LIVE and lethal, so a reading player always gets
///    a tell. If your climber sits in a bar's band while the LIVE bar sweeps
///    across your lane, you are KNOCKED DOWN several rungs and briefly STUNNED.
///  * So you climb through the GAP — step up when no live bar is at your level,
///    and WAIT a beat when one is sweeping through. Bars sweep FASTER and the
///    bands pack CLOSER together higher up (a calibrated ramp), so the top is a
///    real gauntlet.
///  * A blind masher taps every frame, climbs straight into the next bar, gets
///    knocked down, climbs into it again → it loses height to a measured climber
///    who steps only in the safe windows. (Proven by a deterministic test.)
///
/// BOTS: climb on a [BotProfile] cadence but PAUSE when a live/telegraphing bar
/// threatens the rung just above them — strong bots read the tell and thread the
/// gap, weak bots ([errorRate]) sometimes step anyway and eat a bar. A real,
/// beatable 1+CPU contest.
///
/// Kid read: tap to climb, stop when a bar swings past your guy, go for the flag.
class ButtonMasher extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'button_masher',
        name: 'Tower Climb',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  // ── Round tuning (no magic numbers inline) ──────────────────────────────────
  // Nobody-summits ceiling. A measured solo climber summits in ~25s (well
  // inside this), so a clean run ends on the flag; the timer only bites when
  // the gauntlet keeps everyone short (the ~25-40s target band).
  static const double _timeLimit = 34;
  // A tall tower: a measured climb takes ~25s, but a blind masher gets knocked
  // out of the upper bands so hard it plateaus around rung ~22 and never tops
  // out before the buzzer (the whole anti-spam point — verified across seeds).
  static const int _rungs = 40; // rungs from ground (0) to the flag (_rungs)
  // peakRung is 0.._rungs; the HUD shows the rung count directly as the score.

  // ── Climb ─────────────────────────────────────────────────────────────────
  static const double _climbPerTap = 1.0; // rungs gained per tap
  // The climber visually eases toward its target rung so a step reads as a
  // spring up rather than a teleport.
  static const double _climbSpringPerSec = 16.0;

  // ── Knockback on a bar hit ──────────────────────────────────────────────────
  // A hit is HEAVY: it must cost a continuous masher MORE height than it can
  // regain before the next sweep catches it, so a blind climb nets negative in
  // the upper tower and stalls. A careful climber takes the hit ~never.
  static const double _knockbackRungs = 8.0; // rungs lost when a bar hits you
  static const double _stunSec = 1.5; // taps ignored while stunned
  // A climber is only re-hittable after a short grace so one sweep = one hit
  // (not a per-frame grind while the bar overlaps).
  static const double _hitGraceSec = 0.7;

  // ── Hazard bands + sweeping bars (the interposing difficulty) ───────────────
  // Bands are evenly spaced up the climb. The bottom of the tower has a safe
  // run-up with no band; bands then pack the rest up to just below the flag.
  static const int _bandCount = 10;
  static const double _firstBandRung = 5.0; // safe run-up below this
  static const double _lastBandRung = 37.0; // top band sits just under the flag
  // A bar's lethal half-height in rungs: you are "in the band" within this many
  // rungs of the band center.
  static const double _bandHalfRungs = 1.25;

  // Sweep speed (phase units/sec, phase 0..1 = one lane crossing). Higher bands
  // sweep faster — the top is busier. Speed lerps from lo (bottom band) to hi
  // (top band) by band height.
  static const double _sweepSpeedLo = 0.45;
  static const double _sweepSpeedHi = 0.95;
  // Telegraph: each LIVE pass is preceded by a WARN beat where the bar parks at
  // the lane edge and flashes (harmless). warnSec shrinks higher up so top bars
  // give less lead time (still always a tell).
  static const double _warnSecLo = 0.95;
  static const double _warnSecHi = 0.5;
  // The lethal core only covers the MIDDLE of the lane sweep; a margin at each
  // edge is the safe pocket where a climber can pass while the bar is parked.
  static const double _barCoverFrac = 0.72; // fraction of lane width the bar spans
  // Idle dwell at the far edge between passes (a breath where the band is open).
  static const double _dwellSec = 0.4;

  // ── Summit / flag ───────────────────────────────────────────────────────────
  // Reaching the flag (the top rung) ends the climb for that player (they plant
  // the flag) and, if they're first, ends the round immediately.
  static const double _summitRung = _rungs * 1.0; // _rungs as a double

  // ── Tap feedback ────────────────────────────────────────────────────────────
  static const double _flashLifeSec = 0.22;
  static const int _maxFlashes = 5;
  static const double _stepLungeSec = 0.16; // a quick reach-up clip per step

  // ── Bot climb cadence (sec/step); harder bots read bars + step crisper ──────
  static const double _botBaseInterval = 0.34;
  static const double _botAccuracyBonus = 0.16; // faster steps at high accuracy
  static const double _botJitterBase = 0.12; // sloppier cadence at low accuracy
  // How far ahead (seconds of sweep) a bot looks for a threatening bar before it
  // commits a step. Strong bots scan a wide window (wait early, thread cleanly);
  // weak bots scan a narrow one so they step late and eat sweeps.
  static const double _botLookaheadLo = 0.18; // low accuracy
  static const double _botLookaheadHi = 0.6; // high accuracy
  // Bots wait a beat at the gun so a human gets a fair head start.
  static const double _botWarmupSec = 1.2;

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for bg shimmer
  bool _resultReacted = false; // one-shot end-of-round body reactions latch
  int? _summitWinner; // first climber to plant the flag (ends the round)

  final Map<int, _Climber> _climbers = <int, _Climber>{};
  // The shared ladder of sweeping hazard bands. One set of bars for the whole
  // tower; each lane reads the same band phases so the contest is identical for
  // everyone (fair race). Built once at init.
  late final List<_Band> _bands;
  // Lane layout depends only on the (fixed) arena + roster, so build it once.
  late final Map<int, _Lane> _laneByPlayer;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _laneByPlayer = _lanes(_size);
    _bands = _buildBands();

    final proportions = _climberProportions();

    for (final p in ctx.players) {
      _climbers[p.id] = _Climber(
        slot: p,
        figure: StickFigure(
          proportions: proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.idle),
        botInterval: _botInterval(),
        botJitter: _botJitter(),
        botLookahead: _botLookahead(),
      );
    }
    begin();
  }

  /// Lithe climber build — a touch lighter than the carnival striker so it reads
  /// clinging to the tower rail.
  StickProportions _climberProportions() => StickProportions.hero.scaled(1.7);

  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.28,
      );

  /// Evenly spaced hazard bands, the lowest at [_firstBandRung] and the highest
  /// at [_lastBandRung]. Higher bands sweep faster, warn for less time and start
  /// out of phase with one another (staggered so they don't all open at once).
  List<_Band> _buildBands() {
    final bands = <_Band>[];
    final span = _lastBandRung - _firstBandRung;
    for (var i = 0; i < _bandCount; i++) {
      final t = _bandCount <= 1 ? 0.0 : i / (_bandCount - 1); // 0 (low)..1 (high)
      final rung = _firstBandRung + span * t;
      bands.add(_Band(
        rung: rung,
        sweepSpeed: lerpD(_sweepSpeedLo, _sweepSpeedHi, t),
        warnSec: lerpD(_warnSecLo, _warnSecHi, t),
        // Stagger start: alternate edges + a phase offset so the gauntlet is a
        // shifting pattern, not a synced wall.
        dir: i.isEven ? 1 : -1,
        phase: (i * 0.37) % 1.0,
        state: _BandState.sweeping,
        // Deterministic per-band warm-in so the bottom band isn't lethal on the
        // very first frame (the run-up stays open a moment).
        timer: ctx.rng.range(0, _dwellSec),
      ));
    }
    return bands;
  }

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.12, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.25;
  }

  /// Seconds of sweep a bot looks ahead before stepping — wide for strong bots
  /// (they wait early and thread the gap) and narrow for weak ones (they step
  /// late and clip bars).
  double _botLookahead() {
    final prof = ctx.botProfile;
    return lerpD(_botLookaheadLo, _botLookaheadHi, prof.accuracy.clamp(0.0, 1.0));
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

    _tickBands(sdt);
    _driveBots(sdt);

    for (final c in _climbers.values) {
      _tickClimber(c, sdt);
      // Score = best rung reached. A climber knocked down keeps its peak, so
      // ranking rewards how HIGH you got, not how many times you tapped.
      setScore(c.slot.id, c.peakRung.round());
    }

    if (_summitWinner != null || _elapsed >= _timeLimit) {
      _reactToResult();
      finishByScore(); // highest rung wins (summit already pins the max)
    }
  }

  /// Advance every band's sweep + telegraph clock. Pure phase bookkeeping; the
  /// hit test reads the resulting [_Band.coversLaneCenter].
  void _tickBands(double dt) {
    for (final b in _bands) {
      switch (b.state) {
        case _BandState.dwell:
          b.timer -= dt;
          if (b.timer <= 0) {
            b.dir = -b.dir; // turn around for the next pass
            b.state = _BandState.warn;
            b.timer = b.warnSec;
          }
          break;
        case _BandState.warn:
          // Parked at the start edge, flashing — harmless lead time.
          b.timer -= dt;
          if (b.timer <= 0) {
            b.state = _BandState.sweeping;
            b.phase = b.dir > 0 ? 0.0 : 1.0;
          }
          break;
        case _BandState.sweeping:
          b.phase += b.dir * b.sweepSpeed * dt;
          if (b.phase >= 1.0 || b.phase <= 0.0) {
            b.phase = b.phase.clamp(0.0, 1.0);
            b.state = _BandState.dwell;
            b.timer = _dwellSec;
          }
          break;
      }
    }
  }

  void _tickClimber(_Climber c, double dt) {
    // Stun + hit-grace clocks.
    if (c.stun > 0) c.stun = math.max(0.0, c.stun - dt);
    if (c.hitGrace > 0) c.hitGrace = math.max(0.0, c.hitGrace - dt);

    // Ease the rendered rung toward the target rung (a step springs up).
    final follow = (1.0 - math.exp(-_climbSpringPerSec * dt)).clamp(0.0, 1.0);
    c.rung += (c.targetRung - c.rung) * follow;
    if (c.rung < 0) c.rung = 0;
    c.peakRung = math.max(c.peakRung, c.rung);

    // Hazard hit test: a LIVE bar whose band straddles this climber's rung and
    // whose lethal core currently covers the lane (center) knocks the climber
    // down. Off-grace only, and never after planting the flag.
    if (!c.planted && c.stun <= 0 && c.hitGrace <= 0) {
      final band = _bandHitting(c);
      if (band != null) _knockDown(c, band);
    }

    // Plant the flag the first time a climber tops out.
    if (!c.planted && c.targetRung >= _summitRung) _plantFlag(c);

    // Step lunge + tap-flash clocks.
    if (c.lunge > 0) c.lunge = math.max(0.0, c.lunge - dt);
    for (final f in c.flashes) {
      f.life -= dt;
    }
    c.flashes.removeWhere((f) => f.life <= 0);

    c.figure.update(dt);
  }

  /// The band currently hitting [c] (LIVE bar, band straddles the climber's
  /// rung, lethal core over the lane center) — or null when the climber is in a
  /// safe pocket. The lane center is at sweep-fraction 0.5, so the core covers
  /// it only while the bar sweeps through the middle [_barCoverFrac] of its run.
  _Band? _bandHitting(_Climber c) {
    for (final b in _bands) {
      if (b.state != _BandState.sweeping) continue; // warn/dwell are harmless
      if ((c.rung - b.rung).abs() > _bandHalfRungs) continue; // not in the band
      if (b.coversLaneCenter(_barCoverFrac)) return b;
    }
    return null;
  }

  /// Knock [c] down several rungs + stun it, with a hurt flinch and a puff. The
  /// peak rung is untouched, so a hit costs progress on THIS attempt but never
  /// erases how high the climber has been (fair, readable scoring).
  void _knockDown(_Climber c, _Band band) {
    c.targetRung = math.max(0.0, c.targetRung - _knockbackRungs);
    c.stun = _stunSec;
    c.hitGrace = _hitGraceSec;
    c.figure.hurt();

    final at = _rungAnchor(c, c.rung);
    _juice.particles.burst(
      at: at,
      count: 8,
      color: MasherRenderer.hazardRed,
      speed: 220,
      spread: math.pi * 1.6,
      size: 5,
      gravity: 600,
      life: 0.4,
    );
    _juice.popup(at.translate(0, -_size.height * 0.02), 'BONK!',
        MasherRenderer.hazardRed,
        size: 26);
    _juice.shake.light();
  }

  /// First climber to reach the flag plants it: a full cinematic SUMMIT! beat
  /// (golden burst + popup + signature [Juice.bigMoment]) and the round ends.
  /// Later summiteers still plant their own flag (cheer) but don't re-trigger
  /// the win.
  void _plantFlag(_Climber c) {
    c.planted = true;
    c.targetRung = _summitRung;
    c.figure
      ..setLoco(LocoState.idle)
      ..special(); // triumphant fist-pump as the flag goes in

    final flag = _flagAnchor(c);
    final color = _colorOf(c.slot.id);
    final firstToTop = _summitWinner == null;
    if (firstToTop) _summitWinner = c.slot.id;

    _juice.particles.burst(
      at: flag,
      count: firstToTop ? 22 : 12,
      color: MasherRenderer.flagGold,
      speed: 360,
      spread: math.pi * 2,
      size: 7,
      gravity: 500,
      life: 0.7,
    );
    _juice.particles.burst(
      at: flag,
      count: 12,
      color: color,
      speed: 260,
      size: 5,
      life: 0.6,
    );
    if (firstToTop) {
      _juice.popup(
        flag.translate(0, -_size.height * 0.04),
        'SUMMIT!',
        MasherRenderer.flagGold,
        size: 38,
      );
      _juice.bigMoment(flag, color, banner: 'SUMMIT!');
    }
  }

  /// One-shot end-of-round body reactions: the highest climber (the scored
  /// quantity / summit winner) throws a VICTORY cheer, the rest slump. Fires once
  /// at the buzzer (or the instant someone summits).
  void _reactToResult() {
    if (_resultReacted || _climbers.isEmpty) return;
    _resultReacted = true;
    var winnerId = _summitWinner ?? _climbers.values.first.slot.id;
    if (_summitWinner == null) {
      var best = -1.0;
      for (final c in _climbers.values) {
        if (c.peakRung > best) {
          best = c.peakRung;
          winnerId = c.slot.id;
        }
      }
    }
    for (final c in _climbers.values) {
      if (c.slot.id == winnerId) {
        c.figure
          ..setLoco(LocoState.idle)
          ..victory();
      } else {
        c.figure.hurt();
      }
    }
  }

  // ── Tap → climb one rung + lunge + feedback ─────────────────────────────────

  void _tap(int id) {
    final c = _climbers[id];
    if (c == null) return;
    // A stunned or summited climber ignores taps (the knockdown is the cost of
    // mashing into a bar; once you've planted the flag you're done).
    if (c.stun > 0 || c.planted) return;

    c.targetRung = math.min(_summitRung, c.targetRung + _climbPerTap);

    // Reach-up lunge clip + a little hop-loco for life.
    c.lunge = _stepLungeSec;
    c.figure.attack(1);

    _spawnStepFeedback(c);
    if (c.targetRung >= _summitRung) _plantFlag(c);
  }

  /// Each step = a flash ring + a small dust kick off the rung the climber
  /// reaches, so a step reads as a grab even amid a frantic climb.
  void _spawnStepFeedback(_Climber c) {
    final at = _rungAnchor(c, c.targetRung);
    final color = _colorOf(c.slot.id);
    c.flashes.add(_Flash(at: at, life: _flashLifeSec));
    if (c.flashes.length > _maxFlashes) c.flashes.removeAt(0);
    _juice.particles.burst(
      at: at,
      count: 4,
      color: color,
      speed: 130,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.8,
      size: 3.5,
      gravity: 500,
      life: 0.3,
    );
  }

  /// Bots step on a [BotProfile] cadence, but only AFTER checking the rung just
  /// above them is clear within their lookahead window. A strong bot scans far
  /// ahead (waits for the gap, threads it); a weak bot scans little and, on an
  /// [errorRate] slip, steps into a closing bar anyway. The guard caps catch-up
  /// steps for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // human head start
    for (final c in _climbers.values) {
      if (!c.slot.isBot) continue;
      if (c.planted) continue;
      if (c.stun > 0) {
        c.botClock = 0; // re-time after the stun clears
        continue;
      }
      c.botClock += dt;
      var guard = 0;
      while (c.botClock >= c.nextStepAt && guard++ < 6) {
        c.botClock -= c.nextStepAt;
        if (_botShouldStep(c)) {
          _tap(c.slot.id);
        }
        c.nextStepAt = _nextBotInterval(c);
        if (c.planted) break;
      }
    }
  }

  /// A bot steps unless stepping would carry it into a bar. It reads the band it
  /// would enter (the rung just above) and waits while that band's bar is LIVE
  /// over the lane OR is about to be (telegraphing / arriving within the bot's
  /// lookahead). On an [errorRate] slip it ignores the tell and steps anyway —
  /// mistiming into the bar exactly like a careless human.
  bool _botShouldStep(_Climber c) {
    final nextRung = c.targetRung + _climbPerTap;
    final threat = _threatForRung(c, nextRung);
    if (threat == null) return true; // clear above → climb
    // Careless slip: step into the closing bar and (likely) eat it.
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return true;
    return false; // read the bar, hold this beat
  }

  /// The band threatening a climb to [rung] for [c] within its bot lookahead —
  /// LIVE-and-over-lane now, or warning / sweeping toward the lane soon — or null
  /// if that rung is safe to step into.
  _Band? _threatForRung(_Climber c, double rung) {
    final look = c.botLookahead;
    for (final b in _bands) {
      if ((rung - b.rung).abs() > _bandHalfRungs) continue; // not this band
      if (b.threatensLaneSoon(_barCoverFrac, look)) return b;
    }
    return null;
  }

  double _nextBotInterval(_Climber c) =>
      math.max(0.1, c.botInterval + ctx.rng.jitter(c.botJitter));

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    MasherRenderer.drawBackground(canvas, size, _animClock);

    for (final p in ctx.players) {
      final c = _climbers[p.id];
      final lane = _laneByPlayer[p.id];
      if (c == null || lane == null) continue;
      _drawClimber(canvas, c, lane);
    }

    _juice.render(canvas);
    canvas.restore();

    // Screen-space cinematic overlays (flash + banner) after the world
    // transform is restored, so they are not shaken or zoomed.
    _juice.renderOverlay(canvas, size);
  }

  void _drawClimber(Canvas canvas, _Climber c, _Lane lane) {
    final color = _colorOf(c.slot.id);
    final tower = _Tower.of(lane, _rungs);

    MasherRenderer.drawTower(
      canvas,
      tower.spec,
      color: color,
      rungs: _rungs,
      reachedFraction: c.peakRung / _summitRung,
      number: c.slot.id + 1,
      glowPulse: 0.5 + 0.5 * math.sin(_animClock * 3.0 + c.slot.id),
    );

    // Sweeping hazard bars across this lane. Each band reads its phase/state so
    // a LIVE bar is a solid danger slab and a WARN bar is a flashing ghost — the
    // telegraph the player reads to time a step.
    for (final b in _bands) {
      MasherRenderer.drawHazardBar(
        canvas,
        tower.spec,
        bandRung: b.rung,
        rungs: _rungs,
        laneFrac: b.laneFrac,
        coverFrac: _barCoverFrac,
        live: b.state == _BandState.sweeping,
        warn: b.state == _BandState.warn,
        warnPulse: 0.5 + 0.5 * math.sin(_animClock * 14.0 + b.rung),
      );
    }

    MasherRenderer.drawFlag(
      canvas,
      tower.spec,
      color: color,
      planted: c.planted,
      wave: _animClock * 4.0 + c.slot.id,
    );

    // Step flash rings on the rungs the climber grabs.
    for (final f in c.flashes) {
      final t = (f.life / _flashLifeSec).clamp(0.0, 1.0);
      MasherRenderer.drawTapFlash(canvas, f.at, t, color, tower.width);
    }

    // The climber stickman clinging to the rail at its current rung, reaching up
    // on a step. A stunned climber is drawn knocked-loose (lean + dim).
    final root = tower.spec.rungAt(c.rung / _summitRung);
    MasherRenderer.drawClimber(
      canvas,
      c.figure,
      root,
      reach: _lungePhase(c),
      stunned: c.stun > 0,
      color: color,
      scale: tower.width,
    );
  }

  /// 0 (clinging) → 1 (arm fully reached up) → 0 over a step, eased so the grab
  /// snaps up and settles.
  double _lungePhase(_Climber c) {
    if (c.lunge <= 0) return 0;
    final p = 1.0 - (c.lunge / _stepLungeSec).clamp(0.0, 1.0); // 0..1 through step
    return p < 0.4 ? easeOut(p / 0.4) : easeOut((1 - p) / 0.6);
  }

  // ── Layout ──────────────────────────────────────────────────────────────────

  /// One vertical tower lane per player, split evenly across the width.
  Map<int, _Lane> _lanes(Size size) {
    final players = ctx.players;
    final n = players.length;
    final result = <int, _Lane>{};
    final groundY = size.height * 0.9; // foot of the tower
    for (var i = 0; i < n; i++) {
      final center = size.width * (i + 0.5) / n;
      // Narrower per-lane towers when the field fills so 4 towers don't collide.
      final width = (size.width / n) * (n >= 3 ? 0.42 : 0.5);
      result[players[i].id] = _Lane(
        center: center,
        width: width,
        topY: size.height * 0.08,
        feet: Offset(center, groundY),
      );
    }
    return result;
  }

  /// World position of [rung] on player [c]'s tower.
  Offset _rungAnchor(_Climber c, double rung) {
    final lane = _laneByPlayer[c.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height / 2);
    return _Tower.of(lane, _rungs).spec.rungAt(rung / _summitRung);
  }

  Offset _flagAnchor(_Climber c) {
    final lane = _laneByPlayer[c.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height * 0.1);
    return _Tower.of(lane, _rungs).spec.flag;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  // ── Test seams (read-only) ──────────────────────────────────────────────────

  /// The rung [id]'s climber is stepping toward (0 = ground), or -1 if there is
  /// no such climber. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  double rungOf(int id) => _climbers[id]?.targetRung ?? -1;

  /// The best rung [id]'s climber ever reached (the scored quantity), or -1 if
  /// there is no such climber. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  double peakRungOf(int id) => _climbers[id]?.peakRung ?? -1;

  /// Whether [id]'s climber can safely step up ONE rung right now — i.e. the
  /// rung just above it is not threatened by any LIVE-or-imminent hazard bar.
  /// This is exactly the read a careful player (or a hint cue) makes before
  /// stepping. Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  bool isStepSafe(int id) {
    final c = _climbers[id];
    if (c == null) return false;
    return _threatForRung(c, c.targetRung + _climbPerTap) == null;
  }
}

/// A player's vertical column of the arena. Pure layout value.
class _Lane {
  final double center; // x of the lane center
  final double width; // tower base width
  final double topY; // top of the playable column (flag sits near here)
  final Offset feet; // ground line under the tower

  const _Lane({
    required this.center,
    required this.width,
    required this.topY,
    required this.feet,
  });
}

/// Derived geometry of one climbing tower. Wraps a [TowerSpec] (the value the
/// renderer consumes) so render and sim agree on rung + flag positions.
class _Tower {
  final TowerSpec spec;

  const _Tower(this.spec);

  factory _Tower.of(_Lane lane, int rungs) {
    final railBottom = lane.feet.dy - lane.width * 0.2; // ground rung
    final railTop = lane.topY + lane.width * 0.9; // leave room for the flag
    return _Tower(TowerSpec(
      center: lane.center,
      width: lane.width,
      railTop: railTop,
      railBottom: railBottom,
      rungs: rungs,
    ));
  }

  double get width => spec.width;
}

/// A short-lived step flash ring on a rung. Mutable round-scoped state.
class _Flash {
  final Offset at;
  double life;
  _Flash({required this.at, required this.life});
}

/// Telegraph state of a sweeping hazard band.
enum _BandState { sweeping, dwell, warn }

/// One horizontal hazard band on the shared ladder: a bar that sweeps across the
/// lane at a fixed rung [rung], with a WARN tell before each LIVE pass and a
/// DWELL breath at the far edge. Mutable round-scoped state.
class _Band {
  final double rung; // band center height (in rungs)
  final double sweepSpeed; // phase units/sec while sweeping
  final double warnSec; // telegraph lead time before a live pass

  int dir; // +1 sweeping right, -1 sweeping left
  double phase; // 0..1 sweep fraction across the lane (0 = left edge)
  _BandState state;
  double timer; // counts down in warn/dwell

  _Band({
    required this.rung,
    required this.sweepSpeed,
    required this.warnSec,
    required this.dir,
    required this.phase,
    required this.state,
    required this.timer,
  });

  /// Sweep fraction for rendering: the parked WARN bar sits at its start edge.
  double get laneFrac {
    if (state == _BandState.warn) return dir > 0 ? 0.0 : 1.0;
    return phase.clamp(0.0, 1.0);
  }

  /// True while the LIVE lethal core (the middle [coverFrac] of the sweep)
  /// covers the lane center (sweep-fraction 0.5).
  bool coversLaneCenter(double coverFrac) {
    if (state != _BandState.sweeping) return false;
    final half = coverFrac.clamp(0.0, 1.0) / 2;
    return (phase - 0.5).abs() <= half;
  }

  /// True if this band threatens the lane center NOW or within [lookSec] of
  /// sweep — i.e. it is warning (a live pass is imminent), or it is sweeping and
  /// its core is over / arriving at the center within the lookahead. Used by
  /// bots to wait for a safe pocket.
  bool threatensLaneSoon(double coverFrac, double lookSec) {
    switch (state) {
      case _BandState.warn:
        // A live pass is coming the instant warn ends; treat as a threat if the
        // warn ends within the lookahead.
        return timer <= lookSec;
      case _BandState.dwell:
        return false; // breathing at the edge — safe for now
      case _BandState.sweeping:
        final half = coverFrac.clamp(0.0, 1.0) / 2;
        // Distance (in phase) from the core's leading edge to the center.
        final aheadOfCenter = (dir > 0 && phase < 0.5) || (dir < 0 && phase > 0.5);
        final distToCore = (phase - 0.5).abs() - half;
        if (distToCore <= 0) return true; // already over the center
        if (!aheadOfCenter) return false; // core already passed the center
        final secsToCore = distToCore / sweepSpeed;
        return secsToCore <= lookSec;
    }
  }
}

/// Per-player climb state for one round. Mutable round-scoped state (allowed for
/// the duration of a single round).
class _Climber {
  final PlayerSlot slot;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;
  final double botLookahead; // seconds of sweep this bot reads ahead

  double rung = 0; // current rendered rung (eased)
  double targetRung = 0; // rung the climber is stepping toward
  double peakRung = 0; // best rung reached — THIS is the score source
  double stun = 0; // seconds of stun remaining (taps ignored)
  double hitGrace = 0; // seconds before this climber can be hit again
  double lunge = 0; // seconds of reach-up clip remaining
  bool planted = false; // reached the flag and planted it

  // Bot cadence clock.
  double botClock = 0;
  double nextStepAt;

  final List<_Flash> flashes = <_Flash>[];

  _Climber({
    required this.slot,
    required this.figure,
    required this.botInterval,
    required this.botJitter,
    required this.botLookahead,
  }) : nextStepAt = botInterval;
}
