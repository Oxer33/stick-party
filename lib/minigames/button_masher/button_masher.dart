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

/// Tower Climb (legacy id `button_masher`) — a race UP a tall tower to the FLAG
/// at the top, threading a clear, learnable RHYTHM of full-width hazard bars.
///
/// OBJECTIVE (obvious from the scene): be FIRST to climb your stickman to the
/// FLAG. If nobody summits before the buzzer, the climber who reached the
/// HIGHEST rung wins. Score is the best rung ever reached ([_Climber.peakRung]).
///
/// CORE — climb on the BEAT (a one-touch rhythm, NOT a mash):
///  * **One TAP = climb ONE rung.** No tap = hold your rung. That is the whole
///    control: when to step, when to wait.
///  * The whole tower pulses on a single METRONOME beat. One (low) or two
///    FULL-WIDTH hazard bars share that beat: they spend most of it parked and
///    dim (the SAFE gap), then a WARN telegraph flashes, then they go LIVE — a
///    solid full-width slab sweeping across — for a short danger window, then
///    back to safe. Climb… climb… HOLD on the danger beat… climb. One bar = one
///    rhythm the player can actually feel and ride.
///  * A bar is lethal only while LIVE, and only to a climber whose rung sits in
///    that bar's band. Step into a LIVE bar and you are KNOCKED DOWN several
///    rungs and briefly STUNNED. There is no horizontal pocket to thread — the
///    live slab covers the whole lane, so the only skill is TIMING: ride the gap
///    between beats. The beat just SPEEDS UP higher (shorter safe windows) and a
///    second bar joins in the upper tower, so the top is a real gauntlet.
///  * A blind masher taps every frame, climbs straight into the live beat, gets
///    knocked down, climbs into it again → it loses height to a measured climber
///    who only steps in the safe gap. (Proven by a deterministic test.)
///
/// BOTS: climb on a [BotProfile] cadence but read the beat — they HOLD when the
/// rung just above is live or telegraphing (only stepping into a band when the
/// gap can carry them clear through it) and step in the safe gap. Strong bots
/// step FASTER (more clean attempts per beat → climb higher); weak bots
/// ([errorRate]) sometimes mistime a step into the live bar and eat it. A real,
/// beatable 1+CPU contest.
///
/// Kid read: tap to climb, freeze when the tower flashes red, go for the flag.
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
  // Nobody-summits ceiling. A measured solo climber summits in ~22s (well inside
  // this), so a clean run ends on the flag; the timer only bites when the beat
  // keeps everyone short.
  static const double _timeLimit = 34;
  // A tall tower: a measured beat-climb tops out in ~22s, but a blind masher
  // climbs into the live beat over and over, so it plateaus well below the flag
  // and never tops out before the buzzer (the anti-spam point — verified across
  // seeds).
  static const int _rungs = 40; // rungs from ground (0) to the flag (_rungs)
  // peakRung is 0.._rungs; the HUD shows the rung count directly as the score.

  // ── Climb ─────────────────────────────────────────────────────────────────
  static const double _climbPerTap = 1.0; // rungs gained per tap
  // The climber visually eases toward its target rung so a step reads as a
  // spring up rather than a teleport.
  static const double _climbSpringPerSec = 16.0;
  // A step has a real cadence: a tap only counts once per this interval, so the
  // control is "one deliberate STEP per beat-slot", NOT a frame-rate mash. This
  // is the spam lever — a blind every-frame tapper climbs at a fixed moderate
  // rate (~7 rungs/s), so it can't rocket through a hazard band between beats;
  // it sits in the band as the slab goes live and eats the knockback. A measured
  // climber spends the same taps in the SAFE gap and holds on the danger beat.
  // (Taps inside the window are dropped, not queued, so mashing buys nothing.)
  static const double _tapCooldownSec = 0.14;
  // A CAREFUL climber's reaction margin on top of the time it needs to climb
  // clear of a band (see [_threatForRung]): it only steps into a band when the
  // safe gap covers the whole crossing PLUS this slack, so it never gets caught
  // mid-band. Small, so a threadable gap still exists every beat.
  static const double _safeStepLeadSec = 0.10;

  // ── Knockback on a live-beat hit ────────────────────────────────────────────
  // A hit is HEAVY: it must cost a continuous masher MORE height than it can
  // regain in one safe gap, so a blind climb nets negative in the upper tower
  // and stalls. A careful climber takes the hit ~never.
  static const double _knockbackRungs = 6.0; // rungs lost when a live bar hits you
  static const double _stunSec = 1.2; // taps ignored while stunned
  // A climber is only re-hittable after a short grace so one beat = one hit (not
  // a per-frame grind while the live window overlaps).
  static const double _hitGraceSec = 0.5;

  // ── The metronome beat (the whole readable difficulty) ──────────────────────
  // One shared beat drives every bar, so the tower pulses on a single rhythm the
  // player can feel. A beat is split into three readable phases:
  //   SAFE  — bars parked & dim at the lane edge, the climb window.
  //   WARN  — bars flash a telegraph in place (harmless lead-in).
  //   LIVE  — bars are a solid full-width slab sweeping across (lethal).
  // The danger window (warn+live) is a fixed FRACTION of the beat, so a faster
  // beat = the same readable shape, just quicker. The beat PERIOD shrinks as the
  // leading climber rises, so the rhythm tightens toward the summit.
  static const double _beatSecLo = 1.55; // beat period near the ground (relaxed)
  static const double _beatSecHi = 0.82; // beat period near the flag (tight)
  static const double _warnFrac = 0.20; // fraction of the beat spent telegraphing
  static const double _liveFrac = 0.34; // fraction of the beat the slab is lethal
  // → DANGER fraction (warn+live) = 0.54, SAFE = 0.46 of every beat. The danger
  //   beat occupies a bit MORE than half: a careful climber, stepping only on a
  //   clear beat, crosses a band cleanly; a continuous tapper is stepping >half
  //   the time INTO a warn/live band and eats the slab over and over. The hit is
  //   decided AT STEP TIME (see [_tap]) so it's a deterministic rhythm read, not
  //   a fragile dwell race that a metronomic mash can phase-thread.
  // The lower bar sits here; the upper (second) bar engages higher up. The
  // bottom run-up (everything below this bar's band) is open so the start always
  // reads, and the top above the upper band's reach is a clean dash to the flag.
  static const double _lowerBarRung = 14.0;
  static const double _upperBarRung = 28.0;
  // A bar's lethal half-height in rungs: a climber is "in the band" within this
  // many rungs of the bar center. A THIN band (height ~2 rungs) so the band is a
  // single readable rung-row to step across — the danger is the TIMING of the
  // step, not a tall wall.
  static const double _barHalfRungs = 1.0;
  // The upper bar runs half a beat out of phase, so the two bars are a clear
  // call-and-response (lower beats, then upper) rather than one synced wall —
  // still one felt rhythm.
  static const double _upperBeatOffset = 0.5;

  // ── Summit / flag ───────────────────────────────────────────────────────────
  // Reaching the flag (the top rung) ends the climb for that player (they plant
  // the flag) and, if they're first, ends the round immediately.
  static const double _summitRung = _rungs * 1.0; // _rungs as a double

  // ── Tap feedback ────────────────────────────────────────────────────────────
  static const double _flashLifeSec = 0.22;
  static const int _maxFlashes = 5;
  static const double _stepLungeSec = 0.16; // a quick reach-up clip per step

  // ── Bot climb cadence (sec/step); harder bots ride the beat crisper ─────────
  // A bot reads the beat with the same careful margin as a sharp human, so a bot
  // that commits a step always threads a genuinely clear gap. Its difficulty is
  // expressed through [BotProfile.errorRate] (a weak bot slips a step into the
  // closing slab and eats the knockback) and through cadence below (strong bots
  // step faster → more clean attempts per beat → climb higher).
  static const double _botBaseInterval = 0.34;
  static const double _botAccuracyBonus = 0.16; // faster steps at high accuracy
  static const double _botJitterBase = 0.12; // sloppier cadence at low accuracy
  // Bots wait a beat at the gun so a human gets a fair head start — but a SHARP
  // bot is quicker off the line. The warmup is scaled down by accuracy so a hard
  // bot (accuracy ~0.93) is almost ready at the gun and races the human's
  // first-to-summit line, while a weak bot keeps most of the handicap. This is
  // the difficulty lever that makes the hard bot a beatable-but-real threat
  // without touching the rhythm itself (it can summit just under a frame-perfect
  // human on a clean seed, and slips on others).
  static const double _botWarmupSec = 1.2; // full handicap (weak bots)
  static const double _botWarmupAccuracyCut = 1.15; // sec removed per unit accy

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for bg shimmer
  bool _resultReacted = false; // one-shot end-of-round body reactions latch
  int? _summitWinner; // first climber to plant the flag (ends the round)

  final Map<int, _Climber> _climbers = <int, _Climber>{};
  // The shared rhythm of full-width hazard bars. One beat for the whole tower so
  // every lane reads the same pulse (a fair race). Built once at init.
  late final _Beat _beat;
  late final List<_Bar> _bars;
  // Lane layout depends only on the (fixed) arena + roster, so build it once.
  late final Map<int, _Lane> _laneByPlayer;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _laneByPlayer = _lanes(_size);
    _beat = _Beat();
    _bars = _buildBars();

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
        botWarmup: _botWarmup(),
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

  /// The two full-width hazard bars on the shared beat: a lower one (engages
  /// just past the run-up) and an upper one (the second half of the climb). The
  /// upper bar runs half a beat out of phase so the pair is a readable
  /// call-and-response, not one wall.
  List<_Bar> _buildBars() => <_Bar>[
        _Bar(rung: _lowerBarRung, beatOffset: 0.0, sweepDir: 1),
        _Bar(rung: _upperBarRung, beatOffset: _upperBeatOffset, sweepDir: -1),
      ];

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.12, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.25;
  }

  /// Per-bot start handicap: the full warmup minus an accuracy-scaled cut. A
  /// hard bot (accuracy ~0.93) is off the line almost at the gun (~0.13s) so it
  /// genuinely races a frame-perfect human's first-to-summit line; a weak bot
  /// keeps most of the head-start it gives the human. Clamped so even the
  /// sharpest bot waits a beat (no instantaneous gun-jump) and the weakest still
  /// has a finite handicap.
  double _botWarmup() {
    final accuracy = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    return (_botWarmupSec - _botWarmupAccuracyCut * accuracy).clamp(0.1, 1.2);
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

    // The beat tightens as the LEADING climber rises, so the rhythm speeds up
    // toward the summit (a calibrated ramp) for everyone at once.
    _beat.tick(sdt, _beatPeriodFor(_leadFraction()));
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

  /// 0..1 height of the highest climber right now — drives the shared beat
  /// tempo so the rhythm tightens as the race climbs.
  double _leadFraction() {
    var best = 0.0;
    for (final c in _climbers.values) {
      if (c.peakRung > best) best = c.peakRung;
    }
    return (best / _summitRung).clamp(0.0, 1.0);
  }

  /// Beat period at climb height [frac] (0 ground .. 1 flag): relaxed low, tight
  /// high.
  double _beatPeriodFor(double frac) =>
      lerpD(_beatSecLo, _beatSecHi, frac.clamp(0.0, 1.0));

  void _tickClimber(_Climber c, double dt) {
    // Stun + hit-grace + step-cadence clocks.
    if (c.stun > 0) c.stun = math.max(0.0, c.stun - dt);
    if (c.hitGrace > 0) c.hitGrace = math.max(0.0, c.hitGrace - dt);
    if (c.tapCooldown > 0) c.tapCooldown = math.max(0.0, c.tapCooldown - dt);

    // Ease the rendered rung toward the target rung (a step springs up).
    final follow = (1.0 - math.exp(-_climbSpringPerSec * dt)).clamp(0.0, 1.0);
    c.rung += (c.targetRung - c.rung) * follow;
    if (c.rung < 0) c.rung = 0;
    c.peakRung = math.max(c.peakRung, c.rung);

    // Hazard hit test: a LIVE bar whose band straddles this climber's rung
    // knocks it down. Off-grace only, and never after planting the flag.
    if (!c.planted && c.stun <= 0 && c.hitGrace <= 0) {
      final bar = _barHitting(c);
      if (bar != null) _knockDown(c, bar);
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

  /// The bar currently hitting [c] (LIVE on the beat AND its band straddles the
  /// climber's rung) — or null when the climber is in the safe gap or away from
  /// every band. Full-width: there is no horizontal pocket; being in the band
  /// during the LIVE window is the whole test.
  _Bar? _barHitting(_Climber c) {
    for (final b in _bars) {
      // In the band if EITHER the rendered rung or the rung the climber just
      // stepped to sits within it — so a step UP into a live slab lands even
      // before the spring eases there (a tap into the live beat always bites).
      final inBand = (c.rung - b.rung).abs() <= _barHalfRungs ||
          (c.targetRung - b.rung).abs() <= _barHalfRungs;
      if (!inBand) continue;
      if (_beat.isLive(b.beatOffset)) return b;
    }
    return null;
  }

  /// Knock [c] down several rungs + stun it, with a hurt flinch and a puff. The
  /// peak rung is untouched, so a hit costs progress on THIS attempt but never
  /// erases how high the climber has been (fair, readable scoring).
  void _knockDown(_Climber c, _Bar bar) {
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
    // mashing into the live beat; once you've planted the flag you're done).
    if (c.stun > 0 || c.planted) return;
    // Step cadence: a tap inside the cooldown is DROPPED (not queued), so a
    // frame-rate mash climbs no faster than a deliberate tap and can't out-run
    // the beat read.
    if (c.tapCooldown > 0) return;
    c.tapCooldown = _tapCooldownSec;

    // RHYTHM READ (the whole skill): a step whose destination row lands in a bar
    // that is telegraphing (WARN) or LIVE is MISTIMED — the climber reaches into
    // the closing/live slab and is KNOCKED DOWN instead of climbing. A careful
    // player steps only on a clear beat and never eats this; a continuous tapper
    // hits it on >half its steps (danger fills >half the beat) and stalls. The
    // hit is decided here, at the instant of the step, so it is fully
    // deterministic — a metronomic mash cannot phase-thread it.
    final dest = math.min(_summitRung, c.targetRung + _climbPerTap);
    if (c.hitGrace <= 0) {
      final danger = _barInDangerAt(dest);
      if (danger != null) {
        _knockDown(c, danger);
        return; // mistimed step: bonk, no climb
      }
    }

    c.targetRung = dest;

    // Reach-up lunge clip + a little hop-loco for life.
    c.lunge = _stepLungeSec;
    c.figure.attack(1);

    _spawnStepFeedback(c);
    if (c.targetRung >= _summitRung) _plantFlag(c);
  }

  /// The bar whose band contains [rung] AND is in its danger window (WARN or
  /// LIVE) right now — i.e. stepping onto [rung] this instant is mistimed into a
  /// closing/live slab — or null if [rung] is clear to step onto. This is the
  /// step-time rhythm gate; full-width, so being in the band during danger is
  /// the whole test (no horizontal dodge).
  _Bar? _barInDangerAt(double rung) {
    for (final b in _bars) {
      if ((rung - b.rung).abs() > _barHalfRungs) continue; // not this band
      if (_beat.isWarn(b.beatOffset) || _beat.isLive(b.beatOffset)) return b;
    }
    return null;
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
  /// above them is safe on the beat within their lookahead window. A strong bot
  /// scans far ahead (waits for the gap, threads it); a weak bot scans little
  /// and, on an [errorRate] slip, steps into the live beat anyway. The guard
  /// caps catch-up steps for huge frame steps.
  void _driveBots(double dt) {
    for (final c in _climbers.values) {
      if (!c.slot.isBot) continue;
      if (_elapsed < c.botWarmup) continue; // per-bot head start (sharp = quick)
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

  /// A bot steps unless stepping would carry it into the live beat. It reads the
  /// bar it would enter (the rung just above) and waits while that bar is LIVE
  /// over its band OR is about to be (telegraphing / going live within the bot's
  /// lookahead). On an [errorRate] slip it ignores the tell and steps anyway —
  /// mistiming into the slab exactly like a careless human.
  bool _botShouldStep(_Climber c) {
    final nextRung = c.targetRung + _climbPerTap;
    // Bots read the beat with the same careful margin as a sharp human, so they
    // thread a band whenever the gap is genuinely clear. Their SKILL shows in
    // [errorRate] (a weak bot slips a step into the closing slab and eats it)
    // and in cadence (strong bots step faster → more clean attempts per beat),
    // NOT in a bigger safety buffer — a fatter buffer would paradoxically make
    // weak bots climb cleaner.
    final threat = _threatForRung(c, nextRung, _safeStepLeadSec);
    if (threat == null) return true; // safe gap above → climb
    // Careless slip: step into the closing beat and (likely) eat it.
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return true;
    return false; // read the beat, hold this step
  }

  /// The bar that makes stepping onto [rung] unsafe — its band contains [rung]
  /// and its danger (WARN/LIVE) is here now or arrives before the climber could
  /// climb clear of the band's TOP edge — or null if [rung] is safe to step
  /// onto. This is what stops a careful climber from ever PARKING inside a band:
  /// it only steps in when the gap is long enough to climb all the way through.
  /// [extraLookSec] is added to the band-exit time as the reader's reaction
  /// margin (both bots and the [isStepSafe] seam use the same careful margin —
  /// see [_botShouldStep]). Uses the live beat period so the estimate is honest.
  _Bar? _threatForRung(_Climber c, double rung, double extraLookSec) {
    final period = _beatPeriodFor(_leadFraction());
    for (final b in _bars) {
      final topEdge = b.rung + _barHalfRungs; // last rung still inside the band
      if (rung < b.rung - _barHalfRungs || rung > topEdge) continue; // clear
      // Beat-seconds to climb from this rung out past the band's top edge.
      final rungsToExit = (topEdge - rung) + _climbPerTap;
      final exitSec = rungsToExit * _tapCooldownSec;
      if (_beat.threatensSoon(b.beatOffset, exitSec + extraLookSec,
          period: period)) {
        return b;
      }
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

    // The shared beat pulse (0 deep in the safe gap .. 1 on the live strike)
    // drives a tower-wide flash so the rhythm is unmistakable.
    final beatFlash = _beat.dangerGlow();
    MasherRenderer.drawBackground(canvas, size, _animClock, beatPulse: beatFlash);

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

    // The full-width hazard bars across this lane, each reading the shared beat:
    // a parked dim slab in the SAFE gap, a flashing telegraph in WARN, a solid
    // sweeping slab in LIVE. One beat = one readable rhythm across every lane.
    for (final b in _bars) {
      MasherRenderer.drawHazardBar(
        canvas,
        tower.spec,
        bandRung: b.rung,
        halfRungs: _barHalfRungs,
        rungs: _rungs,
        live: _beat.isLive(b.beatOffset),
        warn: _beat.isWarn(b.beatOffset),
        sweep: _beat.liveSweep(b.beatOffset), // 0..1 across the lane while live
        sweepDir: b.sweepDir,
        beatPhase: _beat.phase(b.beatOffset),
        warnPulse: 0.5 + 0.5 * math.sin(_animClock * 16.0 + b.rung),
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
  /// rung just above it is not threatened by any LIVE-or-imminent hazard bar on
  /// the beat. This is exactly the read a careful player (or a hint cue) makes
  /// before stepping. Read-only; for deterministic gameplay tests + smart play.
  @visibleForTesting
  bool isStepSafe(int id) {
    final c = _climbers[id];
    if (c == null) return false;
    return _threatForRung(c, c.targetRung + _climbPerTap, _safeStepLeadSec) ==
        null;
  }

  /// The shared beat phase (0..1) for the bar at [barIndex] (0 = lower, 1 =
  /// upper), or -1 if out of range. Read-only; lets a deterministic test assert
  /// the rhythm/telegraph timing the player rides. For tests + tuning only.
  @visibleForTesting
  double beatPhaseOf(int barIndex) {
    if (barIndex < 0 || barIndex >= _bars.length) return -1;
    return _beat.phase(_bars[barIndex].beatOffset);
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

/// The shared metronome. A single phase clock in [0,1) loops every beat; bars
/// read it (with their own offset) to derive WARN / LIVE / SAFE. Keeping ONE
/// clock for the whole tower is what makes the danger a single felt rhythm
/// instead of a wall of independent timers. Mutable round-scoped state.
class _Beat {
  // The phase fraction at which a beat goes LIVE: WARN occupies the slice just
  // before it, SAFE is everything after the live window. So one beat reads:
  //   [ SAFE … | WARN | LIVE | SAFE … ]
  static const double _warnFrac = ButtonMasher._warnFrac;
  static const double _liveFrac = ButtonMasher._liveFrac;
  static const double _liveStart = 1.0 - _liveFrac; // live runs to the beat end
  static const double _warnStart = _liveStart - _warnFrac;

  double phaseRaw = 0; // 0..1, advances at 1/period per second

  /// Advance the metronome by [dt] at the current [period] (seconds/beat).
  void tick(double dt, double period) {
    if (period <= 0) return;
    phaseRaw = (phaseRaw + dt / period) % 1.0;
  }

  /// Phase 0..1 through THIS bar's beat (its [offset] shifts the shared clock).
  double phase(double offset) => (phaseRaw + offset) % 1.0;

  bool isWarn(double offset) {
    final p = phase(offset);
    return p >= _warnStart && p < _liveStart;
  }

  bool isLive(double offset) => phase(offset) >= _liveStart;

  /// 0..1 sweep position of the live slab across the lane (only meaningful while
  /// live); a smooth wipe so the live window reads as a fast pass.
  double liveSweep(double offset) {
    final p = phase(offset);
    if (p < _liveStart) return 0;
    return ((p - _liveStart) / _liveFrac).clamp(0.0, 1.0);
  }

  /// True if a bar at [offset] is LIVE now, or will go live within [lookSec] of
  /// beat (i.e. it is in WARN whose end is within the lookahead, or already
  /// live). Used to wait for the safe gap; [period] is the live seconds/beat so
  /// the lookahead is measured in real time.
  bool threatensSoon(double offset, double lookSec, {required double period}) {
    if (isLive(offset)) return true;
    final p = phase(offset);
    if (p >= _warnStart && p < _liveStart) {
      // Telegraphing — live the instant warn ends; threat if that is soon.
      final secsToLive = (_liveStart - p) * period;
      return secsToLive <= lookSec;
    }
    // In the safe gap: live is a full lap minus the distance already travelled.
    final secsToLive = ((_liveStart - p) % 1.0) * period;
    return secsToLive <= lookSec;
  }

  /// 0 deep in the safe gap → 1 on the live strike. Drives the tower-wide danger
  /// glow so the LIVE beat flashes the whole scene. Uses the hottest of the two
  /// bar offsets in play for a single unified pulse.
  double dangerGlow() =>
      math.max(_glowAt(0.0), _glowAt(ButtonMasher._upperBeatOffset));

  double _glowAt(double offset) {
    final p = phase(offset);
    if (p >= _liveStart) return 1.0; // live → full flash
    if (p >= _warnStart) {
      return 0.4 + 0.6 * ((p - _warnStart) / _warnFrac).clamp(0.0, 1.0);
    }
    // Safe gap: glow fades as we move away from the last live strike and rises
    // again as the next warn approaches (a breathing pulse, brightest at warn).
    final toWarn = _warnStart <= 0 ? 0.0 : (_warnStart - p) / _warnStart;
    return (1.0 - toWarn.clamp(0.0, 1.0)) * 0.3;
  }
}

/// One full-width hazard bar on the shared beat. It is lethal only while LIVE
/// and only to a climber whose rung is within the band; there is no horizontal
/// pocket — timing on the beat is the whole game. Pure value (its danger state
/// is read from the shared [_Beat]).
class _Bar {
  final double rung; // band center height (in rungs)
  final double beatOffset; // phase shift on the shared beat (0..1)
  final int sweepDir; // +1 live slab wipes right, -1 wipes left (visual only)

  const _Bar({
    required this.rung,
    required this.beatOffset,
    required this.sweepDir,
  });
}

/// Per-player climb state for one round. Mutable round-scoped state (allowed for
/// the duration of a single round).
class _Climber {
  final PlayerSlot slot;
  final StickFigure figure;
  final double botInterval;
  final double botJitter;
  final double botWarmup; // seconds this bot waits at the gun (accuracy-scaled)

  double rung = 0; // current rendered rung (eased)
  double targetRung = 0; // rung the climber is stepping toward
  double peakRung = 0; // best rung reached — THIS is the score source
  double stun = 0; // seconds of stun remaining (taps ignored)
  double hitGrace = 0; // seconds before this climber can be hit again
  double tapCooldown = 0; // seconds before the next tap counts (step cadence)
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
    required this.botWarmup,
  }) : nextStepAt = botInterval;
}
