import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

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
  // pick a side and commit; the ramp escalates late so even sharp bots get
  // caught and the round resolves by elimination, not just the time cap.
  //
  // The late ramp is deliberately GENTLE ([fallAccel] tuned down from 46): a
  // steep ramp made hazards traverse a whole band in a couple of frames late
  // game, so the warm→hot→impact read collapsed to an unparseable flash and the
  // central skill became unlearnable. With this accel the end-of-round speed
  // (~886 px/s at the time cap, vs the old ~1406) stays readable. The HOT window
  // itself is decoupled from this entirely — it is gated off a FIXED-PIXEL band
  // ([telegraphSpeedCap]) so its on-screen duration is constant regardless.
  static const double fallSpeedStart = 210; // px/s
  static const double fallAccel = 26; // px/s^2 (gentle late ramp; was 46)

  // ── TELEGRAPH SPEED CAP (the readability fix) ──────────────────────────────
  // The WARM/HOT windows are gated on an ETA, and ETA depends on fall speed. At
  // the old late-game speeds the HOT *pixel band* (speed × hotLead) ballooned
  // past a whole player band, so a hazard was effectively HOT the instant it
  // spawned — a sub-frame flash no human could read. We cap the speed USED FOR
  // THE TELEGRAPH (gating + rendered shadow) so the HOT zone always sits at a
  // FIXED pixel distance above the runner line (~[telegraphSpeedCap]·hotLead px)
  // and lasts a readable, roughly constant on-screen stretch at every difficulty.
  // Hazards still FALL at the true (uncapped) speed — only the telegraph's ETA
  // math is clamped, so the cue stays honest about WHERE the threat is while
  // staying legible about WHEN to dodge.
  static const double telegraphSpeedCap = 360; // px/s ceiling for WARM/HOT ETA

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

  // ── CHASE PRESSURE (calibrated difficulty that INTERPOSES) ─────────────────
  // After grace, hazards increasingly TARGET the runner's CURRENT lane instead
  // of a random one. This is the lever that makes the law hold both ways:
  //  * A STILL player is now actively hunted — stand in one lane and a hazard
  //    drops on YOU, so doing nothing gets you crushed (it no longer "survives").
  //  * A READER is fed a steady supply of in-lane threats to dodge off, so
  //    skilled play has constant chances to bank earned grazes.
  // The chase probability ramps from [chaseProbStart] to [chaseProbMax] across
  // the round, so pressure escalates. A telegraphed drop in your lane that you
  // must read and step off is the whole skill test.
  static const double chaseProbStart = 0.45; // P(target current lane) at grace end
  static const double chaseProbMax = 0.85; // P(target current lane) at climax

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
  // Extra body half-width (in lane-spacing fractions) the runner occupies for
  // collision while it is still gliding between lanes. This is what STOPS the
  // flailer exploit: a hazard that crosses while the runner is mid-hop through
  // its lane still connects — the rendered body physically overlapped the fall.
  static const double hitBodyHalfFrac = 0.34; // runner half-width / lane spacing

  // ── EARNED GRAZE CHAIN + VISIBLE LATE-DODGE WINDOW (the heart of the rework) ─
  // A graze is NOT mere proximity to any passing hazard (that would pay a STILL
  // player for free and let a flailer collect by accident). A graze is an
  // EARNED, LATE DODGE with a VISIBLE timing window:
  //
  //  Each hazard casts a ground SHADOW on the lane it threatens. As the hazard
  //  nears the runner line the shadow SHRINKS and intensifies, then FLIPS HOT
  //  (red) for the final stretch — the "late window". Two ETA thresholds gate it:
  //   * WARM (eta <= [dodgeThreatLeadSec]): the lane is threatened — the shadow
  //     shows and a reader/bot knows to get ready. A hop off here is SAFE but
  //     earns NO chain credit (it's an early bail).
  //   * HOT  (eta <= [dodgeHotLeadSec]): the late window. Stepping OFF a HOT
  //     lane onto a clear adjacent lane is the EARNED dodge — and the ONLY thing
  //     that banks a graze. The skill is the felt "wait… wait… NOW".
  //
  // Consecutive earned (HOT) dodges stack a multiplier, so reading a dense
  // barrage and threading it at the last instant pays exponentially. Over-fleeing
  // (jumping 2+ lanes, or bolting when nothing threatened you) banks nothing AND
  // snaps the chain to zero. Early (warm-only) hops bank nothing but keep the
  // chain — they are simply not the scoring play.
  static const double grazeBaseScore = 6; // points for the 1st dodge in a chain
  static const double grazeStep = 0.85; // extra multiplier per chained dodge
  static const int grazeMaxMult = 6; // multiplier cap (keeps scores sane)
  static const int grazeStreakMilestone = 4; // chain length that earns a banner
  static const double grazeFlashDecay = 5.0; // streak-badge flare decay rate (/s)

  // The two windows that make the dodge a VISIBLE timing test. WARM is the wide
  // "danger here" lookahead (drives the shadow appearing, the bot/reader read,
  // and the idle-hunt). HOT is the narrow late window: a hop only stamps a
  // claimable dodge when the vacated lane was HOT at that instant, so an early
  // bail (warm but not yet hot) is safe-but-unscored and last-instant reads are
  // the whole skill. HOT is set a hair WIDER than the sharpest bot's reaction
  // lead (~0.33s at accuracy 1, see [botLeadBase]/[botLeadPerAccuracy]) so a
  // legitimate hard-bot late-dodge still cashes. The CLAIM WINDOW only needs to
  // outlast the hot lead by a frame or two: once you step off a HOT lane the
  // hazard is <= hot-lead away, so it crosses the vacated lane almost immediately.
  static const double dodgeThreatLeadSec = 0.85; // WARM: lookahead that shows the shadow
  static const double dodgeHotLeadSec = 0.36; // HOT: the late window that scores
  static const double dodgeClaimWindowSec = 0.45; // grace to cash a HOT dodge after hopping

  // LEARN-THE-TIMING: the first [hotCueBudget] times the runner's OWN lane flips
  // HOT, pulse a big "NOW!" flash + scale on that lane so the player LEARNS the
  // felt late-dodge moment. A small budget = training wheels that come off once
  // the timing is taught; deterministic off the sim, fires once per HOT window.
  static const int hotCueBudget = 3; // NOW! cues taught per runner per run

  // Survival is only a gentle tiebreaker so EARNED dodges dominate the ranking:
  // a chicken who survives but never dodges-under-threat still loses to a bold
  // reader who threaded barrages (even one who got crushed a bit early).
  // Survival is a NEGLIGIBLE tiebreak only — the score is driven by EARNED
  // grazes (skill), never by passively existing. Kept tiny so a still player who
  // merely outlasts the clock banks almost nothing and always loses to a reader
  // who threads barrages (and so a crush-slowed clock can't inflate it either).
  static const double survivePerSec = 0.1; // tiny passive survival score / sec

  // Near-miss reward feel.
  static const double nearMissSlowMo = 0.22; // hitStop duration
  static const double nearMissTimeScale = 0.4; // sim time scale during slow-mo
  static const double nearMissFlashSec = 0.35;

  // Knife-edge near-miss: a dodge stamped with at least this fraction of its
  // claim window still left was a last-instant escape → escalate to the full
  // cinematic (deeper slow-mo + zoom-punch + screen flash).
  static const double knifeEdgeFrac = 0.72; // claim-left fraction => knife-edge
  static const double knifeEdgeSlowMo = 0.3; // deeper hitStop on a knife-edge
  static const double knifeEdgeTimeScale = 0.22; // harder time dip
  static const double knifeEdgeFlash = 0.34; // screen-flash strength

  // Hop feel.
  static const double hopHoldSec = 0.16; // jump pose hold after a hop
  static const double dustSizeFactor = 4; // hop dust size / figure scale

  // Crush fling.
  static const double flingX = 150; // horizontal fling / figure scale
  static const double flingY = 120; // upward fling / figure scale

  // Bot reactivity — INVERTED for the late-dodge window. A bot commits a dodge
  // when the nearest threat in its lane is within this lead time, and BETTER
  // accuracy reacts with LESS lead (i.e. LATER): the skill being modeled is
  // nerve, so a hard bot waits until the shadow is HOT and banks the graze chain,
  // while a jumpy easy bot bails early (warm-only) and scores nothing. Tuned so
  //   easy  (acc 0.55) -> ~0.70s lead  (WARM: early bail, no chain)
  //   medium(acc 0.78) -> ~0.46s lead  (mostly early, the odd chain)
  //   hard  (acc 0.93) -> ~0.30s lead  (HOT: a late dodge that chains)
  // The lead is clamped so it can never dip so low the bot can't physically clear
  // the lane in time (it would just eat the hazard).
  static const double botLeadBase = 1.28; // base lead seconds (low accuracy)
  static const double botLeadPerAccuracy = 1.05; // lead REMOVED per accuracy point
  // Grace before any bot reacts, mirroring the human's read time so bots never
  // dodge a hazard the player has not even seen yet (keeps them beatable).
  static const double botWarmupSec = 1.5;

  // Bot mistake shape (drives the easy→hard skill gradient). When a bot fumbles
  // (probability [BotProfile.errorRate]) it does ONE of two REAL mistakes:
  //  * FREEZE — it fails to dodge at all and eats the hazard (a true crush), OR
  //  * WRONG WAY — it steps the wrong direction (may still survive, may not).
  // Easy bots fumble often → they mistime straight into hazards. Hard bots
  // fumble rarely → they thread the barrage. [botFreezeShare] splits a fumble
  // between the two so a chunk of mistakes are outright crushes, not just a
  // harmless wrong step — that is what lets a skilled human out-survive them.
  static const double botFreezeShare = 0.5; // fraction of fumbles that freeze

  static const double scrollPerSec = 220; // band texture scroll rate (visual)

  // ── SCORED RUN: full timer + respawn (no instant "last alive" win) ──────────
  // The round ALWAYS runs the full [timeLimit]; a crushed runner is NOT
  // eliminated — it RESPAWNS [respawnSec] later in the SAFEST lane (the one with
  // no imminent hazard) with a brief [respawnInvulnSec] grace so it can't be
  // re-crushed the instant it returns. So a lone runner plays the WHOLE run,
  // banking graze points the entire time, instead of "winning" the moment the
  // rival is crushed. Ranking is by banked graze score, so the daredevil who
  // grazes wins — a timid runner who only flees still loses.
  static const double respawnSec = 1.2; // delay before a crushed runner returns
  static const double respawnInvulnSec = 0.9; // post-respawn grace (no re-crush)
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
/// crushed ragdolls you.
///
/// SCORED RUN (not last-one-standing): the round runs the FULL [_Tuning.timeLimit]
/// and your SCORE is your banked GRAZE points. A crushed runner is NOT out — it
/// RESPAWNS ~[_Tuning.respawnSec] later in the safest lane with a brief grace, so
/// a lone runner plays the whole run banking grazes instead of instantly
/// "winning" because the rival was crushed. Most banked grazes wins; because the
/// close dodge is the only thing that scores (over-fleeing snaps the chain), the
/// daring grazer out-scores the timid runner who only flees.
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

  /// Cyan accent for the knife-edge near-miss flash + popup (matches the near-
  /// miss sparks so the whole beat reads as one cohesive cue).
  static const Color _knifeEdgeColor = Color(0xFF35E0FF);

  late Juice _juice;
  final List<TrackFx> _tracks = <TrackFx>[];
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for spin/scroll (never scaled)
  double _fallSpeed = _Tuning.fallSpeedStart;
  bool _dangerFired = false; // one-shot FINAL BARRAGE climax cue latch
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
    // Earned-dodge stamp — gated on the HOT (late) window, not mere proximity.
    // A claimable dodge is stamped ONLY if the lane we just left had a hazard
    // that was already HOT (inside [dodgeHotLeadSec]) at this instant: that is
    // the felt "wait… NOW" late step. A graze then banks when that hazard crosses
    // the vacated lane within the claim window. An EARLY bail (the lane was warm
    // but not yet hot) is safe but stamps NOTHING — it keeps the chain (it isn't
    // a reset, just not the scoring play). Hopping with no threat at all also
    // stamps nothing and clears any stale claim.
    if (_laneHotThreatened(t, before)) {
      t.dodgeFromLane = before;
      t.dodgeClaimSec = _Tuning.dodgeClaimWindowSec;
    } else if (!_laneThreatened(t, before)) {
      // No threat on the old lane: clear any stale claim so idle jumping never
      // keeps a live stamp around.
      t.dodgeFromLane = -1;
      t.dodgeClaimSec = 0;
    }
    // (Warm-but-not-hot: leave any existing claim untouched; this hop simply
    // doesn't qualify as the earned, late dodge.)
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
      if (t.invuln > 0) t.invuln = math.max(0, t.invuln - dt);
      if (t.alive) {
        t.aliveSec += dt; // cumulative alive time (gentle tiebreaker)
        // Expire the earned-dodge claim on sim time (matches hazard motion) so a
        // dodge only banks if the hazard crosses the vacated lane while fresh.
        if (t.dodgeClaimSec > 0) {
          t.dodgeClaimSec -= sdt;
          if (t.dodgeClaimSec <= 0) {
            t.dodgeClaimSec = 0;
            t.dodgeFromLane = -1;
          }
        }
        _spawnTick(t, sdt);
        _stepHazards(t, sdt);
        _maybeTeachHotCue(t);
        _tickTokens(t, sdt);
      }
      _tickFigure(t, dt, sdt);
      _tickFlashes(t, dt);
    }
    _tickRespawns(dt);
    _driveBots(dt);
    _checkEnd();
  }

  /// Count down each crushed runner's respawn timer; when it elapses bring the
  /// runner back in the safest lane. Keeps the run going for the full timer so a
  /// lone runner never wins just because the rival was crushed.
  void _tickRespawns(double dt) {
    for (final t in _tracks) {
      if (t.alive || t.respawnTimer <= 0) continue;
      t.respawnTimer -= dt;
      if (t.respawnTimer <= 0) _respawn(t);
    }
  }

  /// Bring a crushed runner back in the SAFEST lane (the one whose nearest
  /// approaching hazard is furthest away), upright and briefly invulnerable so it
  /// cannot be re-crushed the instant it returns. The graze chain restarts from
  /// zero — banked points already stand; a fresh run must re-earn its streak.
  void _respawn(TrackFx t) {
    final lane = _safestLane(t);
    t.alive = true;
    t.respawnTimer = 0;
    t.invuln = _Tuning.respawnInvulnSec;
    t.grazeChain = 0;
    t.grazeBannerAt = 0;
    t.grazeFlash = 0;
    t.hopHold = 0;
    t.hotLaneArmed = false; // re-arm the NOW! cue read after a respawn
    t.hopper.hopTo(lane);
    t.hopper.snapVisual();
    t.figure.exitRagdoll();
    t.figure.setLoco(LocoState.run);
    final at = Offset(t.lanes.coordOf(lane), t.runnerY);
    _juice.particles.burst(
      at: at,
      count: 12,
      color: t.color,
      speed: 200,
      size: 6,
      gravity: 120,
      life: 0.5,
    );
    _juice.popup(
      Offset(t.lanes.coordOf(lane), t.runnerY - 30),
      'BACK!',
      t.color,
      size: 24,
    );
  }

  /// The lane whose nearest approaching hazard is FURTHEST away (or has none) —
  /// the safest place to drop a respawn. Ties resolve to the lower lane index.
  int _safestLane(TrackFx t) {
    var bestLane = 0;
    var bestEta = double.negativeInfinity;
    for (var lane = 0; lane < _Tuning.laneCount; lane++) {
      var eta = double.infinity; // no hazard in this lane → maximally safe
      for (final h in t.hazards) {
        if (h.lane != lane || h.y > t.runnerY) continue;
        final speed = _fallSpeed * h.speedMul;
        if (speed <= 0) continue;
        eta = math.min(eta, (t.runnerY - h.y) / speed);
      }
      if (eta > bestEta) {
        bestEta = eta;
        bestLane = lane;
      }
    }
    return bestLane;
  }

  /// True once the round enters its FINAL BARRAGE (sudden death): two lanes
  /// threatened at once and the spawn rate spikes. The finale visibly ramps.
  /// Mirrors the spawner's gate.
  bool get _inSuddenDeath =>
      _elapsed >= _Tuning.timeLimit * _Tuning.suddenDeathFrac;

  /// Fire the one-shot FINAL BARRAGE climax when sudden death begins: a big
  /// center banner + red screen flash + heavy shake + a slow-mo dip, plus a
  /// "DANGER!" popup over every live runner. An unmistakable, cinematic "the
  /// hardest stretch is HERE" beat — rising tension into the finish.
  void _maybeFireDanger() {
    if (_dangerFired || !_inSuddenDeath) return;
    _dangerFired = true;
    _juice.bigBanner('FINAL BARRAGE!', color: TokenTuning.dangerColor);
    _juice.flashScreen(TokenTuning.dangerColor, strength: 0.42);
    _juice.shake.heavy();
    _juice.slowMo();
    for (final t in _tracks) {
      if (!t.alive) continue;
      final x = t.lanes.coordOfVisual(t.hopper.visualLane);
      FallingFx.dangerPopup(_juice, Offset(x, t.runnerY - t.figureLift - 16));
    }
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
  /// in the first [idleGraceSec]. AFTER grace the spawner hunts: with a ramping
  /// probability ([_chaseProb]) it drops the hazard squarely on the runner's
  /// CURRENT lane (so standing still gets you crushed and a reader gets a threat
  /// to dodge off), otherwise a flat random lane to keep the board varied.
  int _spawnLaneFor(TrackFx t) {
    final current = t.hopper.lane;
    if (_elapsed < _Tuning.idleGraceSec) {
      // Grace: never the current lane — pick uniformly among the others.
      final pick = ctx.rng.intRange(0, _Tuning.laneCount - 1);
      return pick < current ? pick : pick + 1;
    }
    if (ctx.rng.chance(_chaseProb())) return current; // hunt the runner
    return ctx.rng.intRange(0, _Tuning.laneCount); // otherwise anywhere
  }

  /// Probability a post-grace hazard targets the runner's current lane, ramping
  /// from [chaseProbStart] at grace-end to [chaseProbMax] at the time cap so the
  /// hunt tightens as the round climaxes.
  double _chaseProb() {
    final span = _Tuning.timeLimit - _Tuning.idleGraceSec;
    final f = span <= 0
        ? 1.0
        : ((_elapsed - _Tuning.idleGraceSec) / span).clamp(0.0, 1.0);
    return lerpD(_Tuning.chaseProbStart, _Tuning.chaseProbMax, f);
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

  /// A hit is decided by REAL physical overlap, locked to the logical lane the
  /// runner committed to (instant), NOT the lagging visual lane — this is what
  /// closes the flailer exploit. A runner still gliding between lanes physically
  /// straddles BOTH, so a hazard landing in the lane it is leaving OR the lane it
  /// is entering connects if its body still overlaps the fall horizontally. So
  /// hammering taps every frame makes the runner a WIDER, ever-mid-hop target
  /// (more likely to be clipped), never a teleporting one that slips the test. A
  /// just-respawned runner in its invuln grace is never crushed.
  bool _isHit(TrackFx t, HazardFx h) {
    if (t.invuln > 0) return false;
    final runnerX = t.lanes.coordOfVisual(t.hopper.visualLane);
    final hazardX = t.lanes.coordOf(h.lane);
    // Logical-lane gate first: a hazard 2+ logical lanes off can never reach the
    // body. Within 1 lane we fall through to a true horizontal overlap test so a
    // committed step that fully cleared the lane is safe but a mid-glide is not.
    if ((h.lane - t.hopper.lane).abs() > 1) return false;
    final spacing = t.lanes.spacing.abs();
    final bodyHalf = spacing * _Tuning.hitBodyHalfFrac;
    final hazardHalf = h.size * (_Tuning.hitPadFactor + 0.5);
    return (runnerX - hazardX).abs() <= bodyHalf + hazardHalf;
  }

  /// Resolve a hazard that just crossed the runner line WITHOUT crushing the
  /// runner — the moment the EARNED-dodge chain lives or dies. A graze is NOT
  /// awarded for merely being one lane from a passing hazard (that paid a STILL
  /// player and a flailer for free). It is awarded ONLY when the hazard crosses
  /// the exact lane the runner DODGED OFF UNDER THREAT, while that dodge claim is
  /// still live ([dodgeFromLane] / [dodgeClaimSec], stamped in [_commitHop]):
  ///  * Hazard crosses the just-vacated, formerly-threatened lane in time →
  ///    a clean EARNED dodge: bump the chain and bank base × the (capped) chain
  ///    multiplier. Slow-mo + spark + an "x2/x3…" popup sell the building streak.
  ///  * Hazard is 2+ lanes from the runner with NO live dodge claim → the player
  ///    bolted / was never near danger: bank nothing and RESET the chain.
  ///  * Anything else (ambient pass one lane over, dead-on slip-through) →
  ///    neutral: no score, chain preserved. Loitering beside hazards pays zero.
  void _registerNearMiss(TrackFx t, HazardFx h) {
    final earned = h.lane == t.dodgeFromLane && t.dodgeClaimSec > 0;
    if (!earned) {
      // Over-fled: far from every hazard AND not mid-claim → snap the streak.
      if ((h.lane - t.hopper.lane).abs() >= 2 && t.dodgeClaimSec <= 0) {
        t.grazeChain = 0;
        t.grazeBannerAt = 0;
      }
      return; // ambient proximity earns nothing — the dodge must be deliberate
    }
    // How LATE was the escape? A claim stamped this very instant still has
    // almost the whole window left → the runner stepped off at the last possible
    // moment: a knife-edge near-miss worthy of an extra cinematic kick.
    final knifeEdge =
        t.dodgeClaimSec >= _Tuning.dodgeClaimWindowSec * _Tuning.knifeEdgeFrac;
    // Consume the claim so one stamped dodge cannot double-score off two hazards.
    t.dodgeFromLane = -1;
    t.dodgeClaimSec = 0;

    t.grazeChain += 1;
    t.grazeFlash = 1.0; // one-shot badge flare so each new link visibly "levels up"
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

    // KNIFE-EDGE: a last-instant escape gets the full cinematic — a deeper
    // slow-mo, a zoom-punch toward the runner, and a cyan screen flash. The
    // signature "HOW did that miss?!" beat the owner wants on a true near-miss.
    if (knifeEdge) {
      final runnerPos = Offset(
          t.lanes.coordOfVisual(t.hopper.visualLane), t.runnerY - t.figureLift);
      _juice.slowMo(
          dur: _Tuning.knifeEdgeSlowMo, scale: _Tuning.knifeEdgeTimeScale);
      _juice.cameraPunch(runnerPos);
      _juice.flashScreen(_knifeEdgeColor, strength: _Tuning.knifeEdgeFlash);
      _juice.popup(
        Offset(runnerPos.dx, t.runnerY - 52),
        'CLOSE!',
        _knifeEdgeColor,
        size: 20 + 8 * t.figureScale,
      );
    }

    // Signature beat: an ESCALATING streak banner. It first fires at the
    // milestone, then again every +2 links beyond it, so a long thread keeps
    // visibly mounting (STREAK x4 → x6 → x8…) instead of celebrating just once.
    // Latched per-track via [grazeBannerAt] so a given peak only fires once.
    final hitsMilestone = t.grazeChain >= _Tuning.grazeStreakMilestone &&
        t.grazeChain > t.grazeBannerAt &&
        (t.grazeChain == _Tuning.grazeStreakMilestone ||
            (t.grazeChain - _Tuning.grazeStreakMilestone).isEven);
    if (hitsMilestone) {
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
    // Decay the one-shot streak-badge flare (set on each new graze link).
    if (t.grazeFlash > 0) {
      t.grazeFlash = math.max(0, t.grazeFlash - dt * _Tuning.grazeFlashDecay);
    }
    if (t.flashes.isEmpty) return;
    for (final f in t.flashes) {
      f.life -= dt;
    }
    t.flashes.removeWhere((f) => f.life <= 0);
  }

  // ── Bots ─────────────────────────────────────────────────────────────────────

  /// Bots read the same ground telegraph and make a REAL directional choice on
  /// their reaction clock — just like the player picks a side. Better accuracy →
  /// react with more lead time (hard bots thread the barrage). On a fumble
  /// ([errorRate]) the bot makes a REAL mistake: it either FREEZES and eats the
  /// hazard, or steps the WRONG way. Easy bots fumble often, so they mistime
  /// straight into hazards and a skilled human out-survives them; hard bots
  /// fumble rarely and dodge cleanly. No human-vs-bot branch beyond "is bot".
  void _driveBots(double dt) {
    if (_elapsed < _Tuning.botWarmupSec) return; // mirror the human's read time
    for (final t in _tracks) {
      final clock = t.clock;
      if (clock == null || !t.alive) continue;
      if (!clock.tick(dt)) continue;
      clock.arm(ctx.botProfile, ctx.rng);

      if (!_botThreatImminent(t)) continue;
      // A fumble: half the time freeze (no dodge → take the crush), else step
      // the wrong way. Either is a genuine mistake a sharp player avoids.
      if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        if (ctx.rng.chance(_Tuning.botFreezeShare)) continue; // freeze → eats it
        _commitHop(t, -_botDodgeDir(t)); // wrong way
        continue;
      }
      _commitHop(t, _botDodgeDir(t)); // clean dodge off the threatened lane
    }
  }

  /// True when a hazard is bearing down on the bot's current lane within its
  /// (accuracy-scaled) lead window. Better accuracy REMOVES lead, so a sharp bot
  /// holds its nerve into the HOT window and banks the graze, while a jumpy bot
  /// fires early in the WARM band and scores nothing. Clamped so the lead can
  /// never drop below a physically-clearable floor (else it would just eat it).
  bool _botThreatImminent(TrackFx t) {
    final lead = (_Tuning.botLeadBase -
            _Tuning.botLeadPerAccuracy * ctx.botProfile.accuracy.clamp(0.0, 1.0))
        .clamp(_Tuning.dodgeHotLeadSec * 0.7, _Tuning.dodgeThreatLeadSec);
    return _laneThreatened(t, t.hopper.lane, lead: lead);
  }

  /// True when an un-counted hazard is bearing down on [lane] within [lead]
  /// seconds of the runner line — the definition of "this lane is dangerous
  /// RIGHT NOW". Used both to decide a bot should react and to validate that a
  /// human's hop was a genuine dodge OFF a threatened lane (the earned-graze
  /// gate). A hazard already past the runner line no longer threatens.
  bool _laneThreatened(TrackFx t, int lane,
      {double lead = _Tuning.dodgeThreatLeadSec}) {
    for (final h in t.hazards) {
      if (h.lane != lane || h.counted || h.y > t.runnerY) continue;
      // ETA is computed off the TELEGRAPH speed (capped), not the true fall
      // speed, so the WARM/HOT thresholds sit at a FIXED pixel distance above the
      // runner line — the window stays readable at every difficulty. See
      // [_telegraphSpeed].
      final speed = _telegraphSpeed(h.speedMul);
      if (speed <= 0) continue;
      final eta = (t.runnerY - h.y) / speed;
      if (eta >= 0 && eta <= lead) return true;
    }
    return false;
  }

  /// The fall speed USED FOR THE TELEGRAPH (WARM/HOT gating + the rendered
  /// shadow), capped at [_Tuning.telegraphSpeedCap]. Hazards still physically
  /// FALL at the uncapped [_fallSpeed] (see [_stepHazards]); only the ETA that
  /// decides when a lane reads warm/hot is clamped. This pins the HOT zone to a
  /// fixed pixel band above the runner line (~cap·hotLead px) so the late-dodge
  /// cue lasts a readable, roughly constant on-screen stretch no matter how fast
  /// the round has ramped. [speedMul] folds in the per-kind multiplier.
  double _telegraphSpeed(double speedMul) =>
      math.min(_fallSpeed, _Tuning.telegraphSpeedCap) * speedMul;

  /// True when [lane] has a hazard inside the narrow HOT window
  /// ([dodgeHotLeadSec]) — the late "now!" stretch. Stepping OFF a HOT lane is
  /// the ONLY hop that stamps a claimable, score-earning dodge.
  bool _laneHotThreatened(TrackFx t, int lane) =>
      _laneThreatened(t, lane, lead: _Tuning.dodgeHotLeadSec);

  /// LEARN-THE-TIMING: the first [hotCueBudget] times the runner's OWN lane
  /// flips HOT, pulse an unmistakable "NOW!" flash + scale + popup on that lane
  /// so the player FEELS the late-dodge moment and learns to wait for it. Latched
  /// per HOT window via [TrackFx.hotLaneArmed] (re-armed when the lane cools) so
  /// one window teaches exactly once, and capped by the budget so the training
  /// wheels come off. Deterministic off the sim clock; no new Ticker.
  void _maybeTeachHotCue(TrackFx t) {
    if (!t.alive) return;
    final hot = _laneHotThreatened(t, t.hopper.lane);
    if (!hot) {
      t.hotLaneArmed = false; // lane cooled → ready to teach the next window
      return;
    }
    if (t.hotLaneArmed || t.hotCueShown >= _Tuning.hotCueBudget) return;
    t.hotLaneArmed = true;
    t.hotCueShown += 1;
    final x = t.lanes.coordOfVisual(t.hopper.visualLane);
    // Bright lane flash + a punchy NOW! popup right on the threatened lane.
    t.flashes.add(FlashFx(lane: t.hopper.lane, life: _Tuning.nearMissFlashSec));
    _juice.popup(
      Offset(x, t.runnerY - t.figureLift - 18),
      'NOW!',
      const Color(0xFFFF5A4D),
      size: 22 + 8 * t.figureScale,
    );
  }

  // ── Elimination / outcome ────────────────────────────────────────────────────

  /// A hazard crushes a runner: it ragdolls + KOs, but this is NOT a permanent
  /// elimination — its banked graze score already stands and it is queued to
  /// RESPAWN in the safest lane after [respawnSec], so the run continues for the
  /// full timer. Guarded against a double-crush in one frame.
  void _eliminate(TrackFx t, HazardFx h) {
    if (!t.alive) return;
    t.alive = false;
    t.respawnTimer = _Tuning.respawnSec;
    t.hazards.clear();
    t.grazeChain = 0; // a crush ends the streak (no posthumous links)
    t.grazeBannerAt = 0; // re-arm for the streak banner on the next run
    t.grazeFlash = 0;
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
    _juice.popup(Offset(runnerX, t.runnerY - 34), 'CRUSHED!', t.color, size: 30);
  }

  void _checkEnd() {
    // SCORED RUN: the round runs the FULL timer (crushed runners respawn), so it
    // NEVER ends early just because one runner is left — a lone player plays the
    // whole run banking grazes. Only the time cap resolves it.
    if (_elapsed >= _Tuning.timeLimit) _finish();
  }

  void _finish() {
    // Banked GRAZE points are the whole story; survival is only a gentle
    // tiebreaker (cumulative time alive × a small rate) added on top. Because
    // crushed runners respawn, time-alive is accrued in [aliveSec] across the
    // whole run; either way the bonus is tiny next to a real graze chain, so a
    // bold daredevil who racked up streaks outranks a timid runner who only fled.
    for (final t in _tracks) {
      addScore(t.playerId, t.aliveSec * _Tuning.survivePerSec);
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
        // The telegraph (warm/hot shadow) is driven by the CAPPED speed so the
        // rendered cue matches the capped gating exactly — same fixed-pixel HOT
        // band on screen as the scoring rule uses. The per-kind multiplier is
        // applied inside the painter via each hazard's speedMul.
        fallSpeed: math.min(_fallSpeed, _Tuning.telegraphSpeedCap),
        warmLeadSec: _Tuning.dodgeThreatLeadSec,
        hotLeadSec: _Tuning.dodgeHotLeadSec,
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

  // ── Test seams (deterministic gameplay tests + smart-play reference) ─────────
  // These expose exactly the read a careful PLAYER makes by eye, so a test can
  // pilot a genuinely-reading "measured dodger" and prove a blind flailer ends
  // below it. Read-only; never mutate the sim.

  /// The hop direction (-1 left / +1 right) that steps [id] OFF its lane in the
  /// HOT (late) window onto an adjacent lane that is itself not also HOT — i.e.
  /// the skilled "hold your nerve, then dodge at the last instant" play that
  /// banks an earned graze. It deliberately WAITS: it returns 0 while the lane is
  /// only WARM (an early bail would score nothing), firing only once the shadow
  /// goes HOT. Returns 0 when not in the hot window, or when no adjacent lane is
  /// a safe landing (pinned — any step is a gamble). Read-only.
  @visibleForTesting
  int debugSafeHopDir(int id) {
    final t = _trackOf(id);
    if (t == null || !t.alive) return 0;
    final lane = t.hopper.lane;
    // Hold until the late window: only a HOT lane is worth (and scores) a dodge.
    if (!_laneHotThreatened(t, lane)) return 0;
    // A landing lane is safe if it isn't ALSO about to be hit (not hot). A warm
    // neighbour is fine — you'll read and dodge that one when it goes hot.
    final canLeft = lane > 0 && !_laneHotThreatened(t, lane - 1);
    final canRight =
        lane < _Tuning.laneCount - 1 && !_laneHotThreatened(t, lane + 1);
    if (canLeft && canRight) return t.hopDir != 0 ? t.hopDir : 1;
    if (canLeft) return -1;
    if (canRight) return 1;
    return 0; // pinned this frame
  }

  /// The EARLY-PANIC read: the hop direction that bails OFF a merely-WARM lane
  /// (threatened but NOT yet in the HOT scoring window) onto a clear neighbour —
  /// i.e. a jumpy player who flees the instant the shadow appears and never holds
  /// for the late window. It fires while the lane is warm-but-not-hot and returns
  /// 0 otherwise, so a test can pilot a genuine early-bailer and prove it banks
  /// far fewer chains than the HOT-timed reader ([debugSafeHopDir]). Read-only.
  @visibleForTesting
  int debugWarmHopDir(int id) {
    final t = _trackOf(id);
    if (t == null || !t.alive) return 0;
    final lane = t.hopper.lane;
    // Only the WARM (early) band — if it's already HOT, this read declines so it
    // can never accidentally land the scoring window.
    if (!_laneThreatened(t, lane) || _laneHotThreatened(t, lane)) return 0;
    final canLeft = lane > 0 && !_laneThreatened(t, lane - 1);
    final canRight =
        lane < _Tuning.laneCount - 1 && !_laneThreatened(t, lane + 1);
    if (canLeft && canRight) return t.hopDir != 0 ? t.hopDir : 1;
    if (canLeft) return -1;
    if (canRight) return 1;
    return 0;
  }

  /// A full-screen normalized touch x that [_dirFromTouch] resolves to [dir],
  /// so a test can drive a deliberate dodge faithfully through [onInput] (not a
  /// back door). [dir] < 0 → left of the runner; > 0 → right. The band spans the
  /// full width, so an extreme x reads as that side regardless of the lane.
  @visibleForTesting
  Offset debugTouchForDir(int dir) => Offset(dir < 0 ? 0.01 : 0.99, 0.5);

  /// Cumulative seconds [id] has spent alive this run (the survival tiebreaker).
  /// A blind flailer, crushed often, accrues far less than a clean dodger.
  @visibleForTesting
  double debugAliveSec(int id) => _trackOf(id)?.aliveSec ?? 0;
}
