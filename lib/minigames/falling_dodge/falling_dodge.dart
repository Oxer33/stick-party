import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/lane_hopper.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'falling_fx.dart';
import 'falling_render.dart';

/// Numeric tuning — no magic numbers inline. All times in seconds, speeds px/s.
class _Tuning {
  // Round length. Well under the test's 80s safety cap; escalation guarantees
  // it converges far sooner. Tuned for a ~12-22s round in practice.
  static const double timeLimit = 26;

  static const int laneCount = 4; // horizontal lanes per player band
  static const double laneMargin = 0.14; // fraction inset of lanes in a band

  // Fall speed: starts at a fair, readable pace and ramps so the round always
  // resolves. Slower start than before so an undecided player still has time to
  // pick a side and commit; the ramp gets punishing late so even sharp bots get
  // caught and the round resolves by elimination, not just the time cap.
  static const double fallSpeedStart = 210; // px/s
  static const double fallAccel = 46; // px/s^2

  // Spawn cadence: shrinks over time (more hazards as it escalates). Late game
  // the floor is tight enough that two hazards can stack in a band, so there is
  // eventually no safe lane to hop into.
  static const double spawnEveryStart = 1.15; // s between hazards (per band)
  static const double spawnMin = 0.26; // floor on spawn interval
  static const double spawnRamp = 0.05; // interval shrink per second

  // Fairness windows (satisfy the "idle player survives ~8s" rule):
  //  * No hazard can land before [spawnWarmupSec] (first spawn is delayed), so
  //    the round can never end in the first ~2s.
  //  * For the first [idleGraceSec] the spawner never targets a runner's CURRENT
  //    lane, so simply standing still cannot get you crushed early — you still
  //    must choose a direction to bank near-miss style points and to survive the
  //    escalation once grace ends.
  static const double spawnWarmupSec = 1.6;
  static const double idleGraceSec = 8.0;

  // Sudden death: once the round is this far along, every spawn drops a SECOND
  // hazard in a different lane, so two of the four lanes are threatened at once
  // and even a perfectly-timed dodge can get pinched — this resolves the round
  // by elimination instead of leaning on the time cap. Well after the grace
  // window, so it never affects the idle-survival guarantee.
  static const double suddenDeathFrac = 0.62; // fraction of timeLimit

  // Hazard sizing relative to lane spacing (kept clear of neighbours).
  static const double hazardSizeBase = 0.62; // size / lane spacing
  static const double hazardSizeJitter = 0.16; // ± size variation

  // Per-kind speed multipliers (boulder mid, anvil fast/heavy, crate slow).
  static const double boulderSpeedMul = 1.0;
  static const double anvilSpeedMul = 1.35;
  static const double crateSpeedMul = 0.78;

  static const double hopAnimSpeed = 18; // lane ease rate (snappy)
  static const double runnerInsetFactor = 0.28; // runner row above band bottom
  // Figure scale tracks band height so the runner stays a clear, chunky
  // presence whether there are 1 or 4 stacked bands.
  static const double figureScaleMin = 0.9; // 4-up bands (~350px)
  static const double figureScaleMax = 2.4; // single full-height band
  static const double figureScaleLoBand = 300; // band px at min scale
  static const double figureScaleHiBand = 1300; // band px at max scale

  static const double hitPadFactor = 0.42; // collision slack / hazard size

  // ── GRAZE CHAIN (the heart of the rework) ──────────────────────────────────
  // A hazard that crosses the runner line ONE lane away is a GRAZE — the only
  // real way to score. Consecutive grazes stack a multiplier, so hugging danger
  // pays exponentially. Over-fleeing — being 2+ lanes from a passing hazard —
  // is cowardice: it banks nothing AND snaps the chain back to zero. So the
  // close dodge is the whole game; bolting to a far safe lane throws away points.
  static const double grazeBaseScore = 6; // points for the 1st graze in a chain
  static const double grazeStep = 0.85; // extra multiplier per chained graze
  static const int grazeMaxMult = 6; // multiplier cap (keeps scores sane)
  static const int grazeStreakMilestone = 4; // chain length that earns a banner

  // Survival is now only a gentle tiebreaker so a daredevil's banked grazes
  // dominate the ranking: a chicken who survives but never grazes still loses to
  // a bold runner who racked up a chain (even one who got crushed a bit early).
  static const double survivePerSec = 0.4; // small passive survival score / sec

  // Near-miss reward feel.
  static const double nearMissSlowMo = 0.22; // hitStop duration
  static const double nearMissTimeScale = 0.4; // sim time scale during slow-mo
  static const double nearMissFlashSec = 0.35;

  // Hop feel.
  static const double hopHoldSec = 0.16; // jump pose hold after a hop
  static const double dustSizeFactor = 4; // hop dust size / figure scale

  // Crush fling.
  static const double flingX = 150; // horizontal fling / figure scale
  static const double flingY = 120; // upward fling / figure scale

  // Bot reactivity. A bot commits a dodge when the nearest threat in its lane
  // is within this lead time (scaled by accuracy: better bots react earlier).
  static const double botLeadBase = 0.22; // base lead seconds
  static const double botLeadPerAccuracy = 0.55; // extra lead at accuracy 1
  // Grace before any bot reacts, mirroring the human's read time so bots never
  // dodge a hazard the player has not even seen yet (keeps them beatable).
  static const double botWarmupSec = 1.5;

  static const double scrollPerSec = 220; // band texture scroll rate (visual)
}

/// Falling Dodge: telegraphed hazards (boulders, anvils, spike-crates) rain
/// down each player's lane band.
///
/// CONTROL (the heart of it — full player agency, one touch):
///  * Tapping the LEFT of the runner hops it one lane LEFT; tapping the RIGHT
///    hops it RIGHT (read from the full-screen [PlayerInput.normPos] x against
///    the runner's screen-x). Small left/right chevrons flank the runner as the
///    affordance. The PLAYER decides which way to dodge each telegraphed hazard —
///    nothing auto-aims a "safe" lane for them.
///
/// A stylish near-miss rewards brief slow-mo + sparks + a "NICE!" popup; getting
/// crushed ragdolls + eliminates you. Fall speed and spawn rate escalate so the
/// round always converges — last runner standing wins, with a time-limit
/// fallback ranked by survival score.
///
/// Fairness: a warmup delays the first hazard, and for an early grace window the
/// spawner never targets a runner's current lane, so an idle player survives the
/// opening ~8s. Bots read the same ground telegraphs and make a REAL directional
/// choice on a reaction clock; [BotProfile] accuracy sets how early they react
/// and [errorRate] makes them sometimes commit the WRONG way and take a hit, so
/// they feel reactive and beatable, not scripted.
class FallingDodge extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'falling_dodge',
        name: 'Falling Dodge',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  final List<TrackFx> _tracks = <TrackFx>[];
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for spin/scroll (never scaled)
  double _fallSpeed = _Tuning.fallSpeedStart;
  bool _dangerFired = false; // one-shot sudden-death "DANGER!" climax cue latch
  bool _winnerFired = false; // one-shot final-survivor bigMoment latch

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildTracks();
    begin();
  }

  // ── World build ─────────────────────────────────────────────────────────────

  void _buildTracks() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    final bandH = arena.height / count;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final band = Rect.fromLTWH(0, bandH * i, arena.width, bandH);
      final lanes = _laneSet(band);
      final runnerY = band.bottom - bandH * _Tuning.runnerInsetFactor;
      final scale = _figureScaleFor(bandH);
      final lift = _footReach(scale);
      final track = TrackFx(
        playerId: p.id,
        color: Color(p.colorArgb),
        band: band,
        lanes: lanes,
        runnerY: runnerY,
        figureLift: lift,
        figureScale: scale,
        hopper:
            Hopper(lane: _Tuning.laneCount ~/ 2, laneCount: _Tuning.laneCount),
        figure: StickFigure(
          proportions: StickProportions.hero.scaled(scale),
          style: _runnerStyle(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.run),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      );
      // Stagger initial spawns so bands don't pulse in lockstep.
      track.spawnTimer = ctx.rng.range(0.1, _Tuning.spawnEveryStart);
      _tracks.add(track);
    }
  }

  LaneSet _laneSet(Rect band) {
    final inset = band.width * _Tuning.laneMargin;
    final usable = band.width - inset * 2;
    final spacing = usable / (_Tuning.laneCount - 1);
    return LaneSet(
      count: _Tuning.laneCount,
      start: band.left + inset,
      spacing: spacing,
    );
  }

  /// Scale the runner to the band height so 1..4 players all read clearly.
  double _figureScaleFor(double bandH) {
    final t = ((bandH - _Tuning.figureScaleLoBand) /
            (_Tuning.figureScaleHiBand - _Tuning.figureScaleLoBand))
        .clamp(0.0, 1.0);
    return lerpD(_Tuning.figureScaleMin, _Tuning.figureScaleMax, t);
  }

  /// Pelvis→foot reach at rest (legs near-vertical), used to plant feet.
  double _footReach(double scale) {
    final p = StickProportions.hero.scaled(scale);
    return p.thigh + p.shin;
  }

  StickStyle _runnerStyle(Color color) => StickStyle.hero.copyWith(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        rimAlpha: 0.26,
        shadowAlpha: 0.0, // we draw our own contact shadow
        smearAlpha: 0.26,
      );

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _hopDirected(input.playerId, input.normPos);
  }

  /// One touch with a DIRECTIONAL choice (the heart of the rework): the player
  /// taps the LEFT side of the runner to hop left, the RIGHT side to hop right.
  /// [normPos] is the full-screen 0..1 touch; bands span the full width, so its
  /// x maps straight across the runner's lanes. The player decides which way to
  /// dodge — nothing is auto-aimed.
  void _hopDirected(int id, Offset normPos) {
    final t = _trackOf(id);
    if (t == null || !t.alive) return;
    _commitHop(t, _dirFromTouch(t, normPos));
  }

  /// Resolve a touch to a hop direction. A tap to the left of the runner's
  /// current screen-x hops left (-1), to the right hops right (+1). A tap dead-on
  /// the runner keeps the last direction so it still does something sensible.
  int _dirFromTouch(TrackFx t, Offset normPos) {
    final touchX = normPos.dx * ctx.arena.width;
    final runnerX = t.lanes.coordOfVisual(t.hopper.visualLane);
    final delta = touchX - runnerX;
    const deadZonePx = 1.0;
    if (delta.abs() <= deadZonePx) return t.hopDir;
    return delta < 0 ? -1 : 1;
  }

  void _commitHop(TrackFx t, int dir) {
    final before = t.hopper.lane;
    t.hopper.hop(dir);
    t.hopDir = dir;
    if (t.hopper.lane == before) return;
    // Lean/hop pose + a take-off dust kick at the source lane.
    t.hopHold = _Tuning.hopHoldSec;
    t.figure.facing = dir >= 0 ? 1.0 : -1.0;
    if (!t.figure.isRagdoll) t.figure.setLoco(LocoState.jump);
    _juice.particles.burst(
      at: Offset(t.lanes.coordOf(before), t.runnerY),
      count: 5,
      color: const Color(0xFFE8EEF6),
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.7,
      size: _Tuning.dustSizeFactor * t.figureScale,
      gravity: 420,
      life: 0.3,
    );
  }

  /// A bot's dodge: step exactly ONE lane off the threatened (current) lane so
  /// it lands ADJACENT to the passing hazard — i.e. it goes for the GRAZE, not a
  /// far safe lane, which is how it banks (and spreads) points. It only hops a
  /// single lane, so it never over-flees itself out of the chain. [_driveBots]
  /// may flip this on a mistake so a fallible bot can step the wrong way.
  int _botDodgeDir(TrackFx t) {
    final lane = t.hopper.lane;
    // Prefer keeping its lean direction; bounce when it would hit a wall so the
    // single step always stays in-bounds (and thus adjacent, not off the edge).
    var dir = t.hopDir != 0 ? t.hopDir : 1;
    if (lane + dir < 0) dir = 1;
    if (lane + dir > _Tuning.laneCount - 1) dir = -1;
    return dir;
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _fallSpeed = _Tuning.fallSpeedStart + _Tuning.fallAccel * _elapsed;
    _maybeFireDanger();

    for (final t in _tracks) {
      if (t.alive) {
        _spawnTick(t, sdt);
        _stepHazards(t, sdt);
        _tickTokens(t, sdt);
      }
      _tickFigure(t, dt, sdt);
      _tickFlashes(t, dt);
    }
    _driveBots(dt);
    _checkEnd();
  }

  /// True once the round enters sudden death (two lanes threatened at once) —
  /// the finale visibly ramps. Mirrors the spawner's sudden-death gate.
  bool get _inSuddenDeath =>
      _elapsed >= _Tuning.timeLimit * _Tuning.suddenDeathFrac;

  /// Fire the one-shot "DANGER!" climax cue when sudden death begins, over every
  /// live runner, with a shake — an unmistakable "it just got harder" beat.
  void _maybeFireDanger() {
    if (_dangerFired || !_inSuddenDeath) return;
    _dangerFired = true;
    for (final t in _tracks) {
      if (!t.alive) continue;
      final x = t.lanes.coordOfVisual(t.hopper.visualLane);
      FallingFx.dangerPopup(_juice, Offset(x, t.runnerY - t.figureLift - 16));
    }
    _juice.shake.medium();
  }

  /// Advance this track's golden token: spawn on cadence, fall, and resolve a
  /// catch/miss at the runner line. A scoop banks bonus points + a golden burst.
  void _tickTokens(TrackFx t, double dt) {
    final caught = t.tokens.tick(
      dt: dt,
      elapsed: _elapsed,
      spawnLane: ctx.rng.intRange(0, _Tuning.laneCount),
      laneSpacing: t.lanes.spacing.abs(),
      bandTop: t.band.top,
      bandBottom: t.band.bottom,
      runnerY: t.runnerY,
      runnerLane: t.hopper.lane,
      rng: ctx.rng,
    );
    if (caught != null) _collectToken(t, caught);
  }

  void _collectToken(TrackFx t, TokenFx tok) {
    addScore(t.playerId, TokenTuning.bonusScore);
    FallingFx.collectToken(
      _juice,
      at: Offset(t.lanes.coordOf(tok.lane), t.runnerY),
      popupAt:
          Offset(t.lanes.coordOfVisual(t.hopper.visualLane), t.runnerY - 30),
      figureScale: t.figureScale,
    );
  }

  void _spawnTick(TrackFx t, double dt) {
    // Warmup: nothing falls until the player has had a beat to read the board,
    // so the round can never resolve in the first ~2s.
    if (_elapsed < _Tuning.spawnWarmupSec) return;
    t.spawnTimer -= dt;
    if (t.spawnTimer > 0) return;
    final interval = (_Tuning.spawnEveryStart - _Tuning.spawnRamp * _elapsed)
        .clamp(_Tuning.spawnMin, _Tuning.spawnEveryStart);
    t.spawnTimer = interval;
    _spawnHazard(t);
  }

  void _spawnHazard(TrackFx t) {
    final lane = _spawnLaneFor(t);
    _dropHazard(t, lane);
    // Sudden death: add a second hazard in a different lane so two lanes are
    // threatened at once and a perfect dodger can be pinched.
    if (_elapsed >= _Tuning.timeLimit * _Tuning.suddenDeathFrac) {
      final second = _otherLane(lane);
      _dropHazard(t, second);
    }
  }

  void _dropHazard(TrackFx t, int lane) {
    final kind = _pickKind();
    final spacing = t.lanes.spacing.abs();
    final sizeFrac = (_Tuning.hazardSizeBase +
            ctx.rng.jitter(_Tuning.hazardSizeJitter))
        .clamp(0.4, 0.95);
    final size = spacing * sizeFrac;
    t.hazards.add(HazardFx(
      lane: lane,
      kind: kind,
      size: size,
      speedMul: _speedMulFor(kind),
      spinPhase: ctx.rng.range(0, math.pi * 2),
      y: t.band.top - size,
    ));
  }

  /// A lane other than [lane] (uniform among the remaining lanes).
  int _otherLane(int lane) {
    final pick = ctx.rng.intRange(0, _Tuning.laneCount - 1);
    return pick < lane ? pick : pick + 1;
  }

  /// Choose the target lane for a new hazard. During the early grace window the
  /// runner's CURRENT lane is never targeted, so an idle player cannot be crushed
  /// in the first [idleGraceSec]; once grace ends every lane is fair game and the
  /// escalation forces a decision. After grace it's a flat random lane.
  int _spawnLaneFor(TrackFx t) {
    if (_elapsed >= _Tuning.idleGraceSec) {
      return ctx.rng.intRange(0, _Tuning.laneCount);
    }
    final avoid = t.hopper.lane;
    // Pick uniformly among the lanes that are not the runner's current lane.
    final pick = ctx.rng.intRange(0, _Tuning.laneCount - 1);
    return pick < avoid ? pick : pick + 1;
  }

  HazardKind _pickKind() {
    final r = ctx.rng.next();
    if (r < 0.5) return HazardKind.boulder; // common
    if (r < 0.8) return HazardKind.crate; // slow but wide spikes
    return HazardKind.anvil; // fast and punishing
  }

  double _speedMulFor(HazardKind k) => switch (k) {
        HazardKind.boulder => _Tuning.boulderSpeedMul,
        HazardKind.anvil => _Tuning.anvilSpeedMul,
        HazardKind.crate => _Tuning.crateSpeedMul,
      };

  void _stepHazards(TrackFx t, double dt) {
    final survivors = <HazardFx>[];
    for (final h in t.hazards) {
      final prevY = h.y;
      h.y += _fallSpeed * h.speedMul * dt;

      // Resolve a crossing of the runner line exactly once.
      if (!h.counted && prevY <= t.runnerY && h.y >= t.runnerY) {
        if (_isHit(t, h)) {
          _eliminate(t, h);
          return; // track is done; drop the rest of its hazards
        }
        h.counted = true;
        _registerNearMiss(t, h);
      }

      if (h.y > t.band.bottom + h.size) continue; // fell past the band
      survivors.add(h);
    }
    t.hazards
      ..clear()
      ..addAll(survivors);
  }

  /// A hit requires the same lane AND the runner's visual position close enough
  /// horizontally that it has not cleared the falling body yet.
  bool _isHit(TrackFx t, HazardFx h) {
    if (h.lane != t.hopper.lane) return false;
    final runnerX = t.lanes.coordOfVisual(t.hopper.visualLane);
    final hazardX = t.lanes.coordOf(h.lane);
    final pad = h.size * (_Tuning.hitPadFactor + 0.5);
    return (runnerX - hazardX).abs() <= pad;
  }

  /// Resolve a hazard that just crossed the runner line WITHOUT crushing the
  /// runner — the moment the graze chain lives or dies:
  ///  * EXACTLY one lane away → a clean GRAZE: bump the chain and bank
  ///    base × the (capped) chain multiplier, so each link is worth more than
  ///    the last. Slow-mo + spark + a "x2/x3…" popup sell the building streak.
  ///  * Two or more lanes away → the player bolted to safety: bank nothing and
  ///    RESET the chain to zero. Fleeing is the only thing that breaks a streak.
  ///  * Same lane but slipped through (a mid-hop horizontal miss) → neutral:
  ///    keep the chain, score nothing.
  void _registerNearMiss(TrackFx t, HazardFx h) {
    final laneGap = (h.lane - t.hopper.lane).abs();
    if (laneGap >= 2) {
      t.grazeChain = 0; // over-fled — cowardice snaps the streak
      t.grazeBannerAt = 0; // re-arm the streak banner for a fresh chain
      return;
    }
    if (laneGap != 1) return; // dead-on slip-through: neutral, keep the chain

    t.grazeChain += 1;
    final mult = t.grazeChain.clamp(1, _Tuning.grazeMaxMult);
    final award =
        _Tuning.grazeBaseScore * (1 + (mult - 1) * _Tuning.grazeStep);
    addScore(t.playerId, award);

    // Charm: lean AWAY from the hazard that just whistled past and throw a quick
    // [hurt] flinch — a readable "that was close!" beat. The hazard sits one lane
    // off; face opposite it. Upper-body flinch, so the run loco keeps going.
    if (!t.figure.isRagdoll) {
      t.figure.facing = h.lane > t.hopper.lane ? -1.0 : 1.0;
      t.figure.hurt();
    }

    _juice.hitStop
        .trigger(_Tuning.nearMissSlowMo, scale: _Tuning.nearMissTimeScale);
    _juice.particles.burst(
      at: Offset(t.lanes.coordOf(h.lane), t.runnerY),
      count: 8 + mult,
      color: const Color(0xFF35E0FF),
      speed: 260,
      size: 5 * t.figureScale,
      life: 0.4,
    );
    // Popup shows the live multiplier so the streak is unmistakable to kids.
    _juice.popup(
      Offset(t.lanes.coordOfVisual(t.hopper.visualLane), t.runnerY - 28),
      mult >= 2 ? 'x$mult!' : 'NICE!',
      const Color(0xFF8DEBFF),
      size: 22 + 8 * t.figureScale,
    );
    t.flashes.add(FlashFx(lane: h.lane, life: _Tuning.nearMissFlashSec));

    // Signature beat: crossing a big streak milestone earns a one-shot banner +
    // zoom-punch toward this runner. Latched per-track so it fires once per
    // milestone reached (and re-arms only after a fresh chain climbs back up).
    if (t.grazeChain >= _Tuning.grazeStreakMilestone &&
        t.grazeChain > t.grazeBannerAt) {
      t.grazeBannerAt = t.grazeChain;
      final runnerPos = Offset(
          t.lanes.coordOfVisual(t.hopper.visualLane), t.runnerY - t.figureLift);
      _juice.bigBanner('STREAK x${t.grazeChain}', color: t.color);
      _juice.cameraPunch(runnerPos);
    }
  }

  void _tickFigure(TrackFx t, double dt, double sdt) {
    t.hopper.update(sdt, speed: _Tuning.hopAnimSpeed);
    if (t.hopHold > 0) {
      t.hopHold -= dt;
      if (t.hopHold <= 0 && t.alive && !t.figure.isRagdoll) {
        t.figure.setLoco(LocoState.run);
      }
    }
    t.figure.update(dt);
  }

  void _tickFlashes(TrackFx t, double dt) {
    if (t.flashes.isEmpty) return;
    for (final f in t.flashes) {
      f.life -= dt;
    }
    t.flashes.removeWhere((f) => f.life <= 0);
  }

  // ── Bots ─────────────────────────────────────────────────────────────────────

  /// Bots read the same ground telegraph and make a REAL directional choice on
  /// their reaction clock — just like the player picks a side. Better accuracy →
  /// react with more lead time. On a mistake ([errorRate]) the bot commits the
  /// WRONG way instead of the safe way, so a weak bot can dodge straight into a
  /// hazard — they feel fallible, not scripted, and stay beatable on easy.
  void _driveBots(double dt) {
    if (_elapsed < _Tuning.botWarmupSec) return; // mirror the human's read time
    for (final t in _tracks) {
      final clock = t.clock;
      if (clock == null || !t.alive) continue;
      if (!clock.tick(dt)) continue;
      clock.arm(ctx.botProfile, ctx.rng);

      if (!_botThreatImminent(t)) continue;
      var dir = _botDodgeDir(t);
      // A fumbled reaction flips the choice → the bot dives the wrong way.
      if (ctx.rng.chance(ctx.botProfile.errorRate)) dir = -dir;
      _commitHop(t, dir);
    }
  }

  /// True when a hazard is bearing down on the bot's current lane within its
  /// (accuracy-scaled) lead window — i.e. the moment a real player would react.
  bool _botThreatImminent(TrackFx t) {
    final lane = t.hopper.lane;
    final lead = _Tuning.botLeadBase +
        _Tuning.botLeadPerAccuracy * ctx.botProfile.accuracy.clamp(0.0, 1.0);
    for (final h in t.hazards) {
      if (h.lane != lane || h.counted || h.y > t.runnerY) continue;
      final speed = _fallSpeed * h.speedMul;
      if (speed <= 0) continue;
      final eta = (t.runnerY - h.y) / speed;
      if (eta <= lead) return true;
    }
    return false;
  }

  // ── Elimination / outcome ────────────────────────────────────────────────────

  void _eliminate(TrackFx t, HazardFx h) {
    t.alive = false;
    t.eliminatedAt = _elapsed; // banked for the survival-time tiebreaker
    t.hazards.clear();
    t.grazeChain = 0; // a crush ends the streak (no posthumous links)
    t.grazeBannerAt = 0; // re-arm (moot post-crush, but keeps state consistent)
    final runnerX = t.lanes.coordOfVisual(t.hopper.visualLane);
    final at = Offset(runnerX, t.runnerY);
    // Crush: fling away from the impact lane, with an upward stomp component.
    final away = (runnerX - t.lanes.coordOf(h.lane)) >= 0 ? 1.0 : -1.0;
    t.figure.enterRagdoll(
      Offset(runnerX, t.runnerY - t.figureLift),
      t.runnerY,
      Offset(away * _Tuning.flingX * t.figureScale,
          -_Tuning.flingY * t.figureScale),
    );
    _juice.ko(at, t.color);
    _juice.popup(Offset(runnerX, t.runnerY - 34), 'OUT!', t.color, size: 30);
  }

  void _checkEnd() {
    final timeUp = _elapsed >= _Tuning.timeLimit;
    // Count survivors without allocating a list every frame; only materialize
    // the survivor list on the single frame the round actually resolves.
    var aliveCount = 0;
    for (final t in _tracks) {
      if (t.alive) aliveCount++;
    }
    if (aliveCount > 1 && !timeUp) return;
    _finish();
  }

  void _finish() {
    // Banked GRAZE points are the whole story; survival is only a gentle
    // tiebreaker (time alive × a small rate) added on top. A survivor banks the
    // full round's worth, an eliminated runner banks up to when they fell — but
    // either bonus is tiny next to a real graze chain, so a bold daredevil who
    // racked up a streak outranks a timid runner who only ran away.
    for (final t in _tracks) {
      final timeAlive = t.alive ? _elapsed : t.eliminatedAt;
      addScore(t.playerId, timeAlive * _Tuning.survivePerSec);
    }
    // Rank everyone by total score (graze-dominated), highest first; ties break
    // by player id so the order is always stable and the full set is preserved.
    final ranked = _tracks.map((t) => t.playerId).toList()
      ..sort((a, b) {
        final byScore = scoreOf(b).compareTo(scoreOf(a));
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    // Signature climax: crown the winner with a single big cinematic beat,
    // aimed at their runner. Latched so it never re-fires if _finish is reached
    // again on a later frame.
    if (!_winnerFired && ranked.isNotEmpty) {
      _winnerFired = true;
      final winnerId = ranked.first;
      final w = _tracks.firstWhere((t) => t.playerId == winnerId,
          orElse: () => _tracks.first);
      final winnerPos = Offset(
          w.lanes.coordOfVisual(w.hopper.visualLane), w.runnerY - w.figureLift);
      _juice.bigMoment(winnerPos, w.color, banner: 'SURVIVOR!');
      // Charm: a surviving winner reacts under the banner instead of freezing —
      // settle out of the run into a full-body cheer. An eliminated top-ranker
      // is already a ragdoll, so only a live survivor celebrates.
      if (w.alive && !w.figure.isRagdoll) {
        w.figure.setLoco(LocoState.idle);
        w.figure.victory();
      }
    }
    _juice.confetti(ctx.arena);
    finishByOrder(_dedupe(ranked));
  }

  /// Ensure every player id appears exactly once, preserving [order] first.
  List<int> _dedupe(List<int> order) {
    final seen = <int>{};
    final result = <int>[];
    for (final id in order) {
      if (seen.add(id)) result.add(id);
    }
    for (final p in ctx.players) {
      if (seen.add(p.id)) result.add(p.id);
    }
    return result;
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    FallingRenderer.drawBackground(canvas, size, _escalation());

    final scroll = _animClock * _Tuning.scrollPerSec;
    for (final t in _tracks) {
      FallingTrackPainter.draw(
        canvas,
        t,
        scroll: scroll,
        animClock: _animClock,
        laneCount: _Tuning.laneCount,
      );
    }

    _juice.render(canvas);
    canvas.restore();

    _juice.renderOverlay(canvas, size);
  }

  /// 0..1 escalation, used for ambient heat — ramps with fall speed and pins to
  /// full once sudden death begins so the finale background glows hottest.
  double _escalation() {
    if (_inSuddenDeath) return 1;
    final span = _Tuning.fallAccel * _Tuning.timeLimit;
    if (span <= 0) return 0;
    return ((_fallSpeed - _Tuning.fallSpeedStart) / span).clamp(0.0, 1.0);
  }

  // ── Small helpers ────────────────────────────────────────────────────────────

  TrackFx? _trackOf(int id) {
    for (final t in _tracks) {
      if (t.playerId == id) return t;
    }
    return null;
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}
