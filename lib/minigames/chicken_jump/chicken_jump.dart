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
import 'chicken_render.dart';

/// Numeric tuning — no magic numbers inline. Times in seconds, speeds px/s.
class _Tuning {
  // Round length. Tight, not padded: the lava is CAPPED below the reachable top
  // (see [lavaCapRungs]) so it never swallows the tower, which means the climb
  // stays a live race for the WHOLE round. ~14s keeps it punchy — long enough to
  // climb high and hold, short enough to never go stale.
  static const double timeLimit = 14;

  // A short "GET SET" beat: the lava holds just below the lowest rung and bots
  // stay put, so everyone gets a moment to read the board before the climb. The
  // host also shows a 3-2-1-GO overlay; this in-sim warmup makes the all-bot /
  // test path fair too and lets the lava "build" dramatically before it rises.
  // Kept generous (~2s) so the first hop is never a surprise.
  static const double warmupSec = 1.9;

  static const int platformCount = 16; // rungs in each player's tower
  static const double topInset = 96; // px from the top to the highest platform
  static const double bottomInset = 150; // px from the bottom to the lowest

  // Rising lava (after the warmup): starts calm and accelerates to keep pace
  // pressure mounting — but it is HARD-CAPPED below the reachable top (see
  // [lavaCapRungs]) so it can never engulf the tower. There is always headroom
  // to keep climbing and to risk the HOLD double-leap.
  static const double lavaRiseStart = 40; // px/s initial climb (gentle start)
  static const double lavaAccel = 8.0; // px/s^2 ramp
  static const double lavaStartGap = 10; // px the lava starts below the lowest

  // LAVA CAP: the lava surface is clamped so it never rises above this many
  // rung-spacings BELOW the top reachable rung. The climber always has at least
  // ~this much clear tower above the lava to keep climbing and to use the risky
  // HOLD double-leap. ~1.5 spacings keeps the top a tense-but-reachable refuge,
  // never an agency-free death-strobe.
  static const double lavaCapRungs = 1.5; // clear rung-spacings kept above lava

  // CLIMAX: once the round passes [climaxFrac] of its life the renderer reads
  // max heat for a hot finale — but the lava SPEED is NOT surged (it would just
  // slam the cap), so the cap holds and the climb stays live to the buzzer.
  static const double climaxFrac = 0.72; // fraction of timeLimit → climax begins

  // COMEBACK (kid-assist): the single climber sitting on the lowest rung among
  // the living gets its lava held back a touch, so a younger / behind player is
  // never the obvious first-out. Subtle and only ever helps ONE trailing player.
  static const double comebackLavaMul = 0.82; // trailing column lava × this

  static const double hopAnimSpeed = 16; // lane ease rate (snappy take-off)
  static const double jumpHoldSec = 0.22; // how long the jump pose shows
  static const double landHoldSec = 0.12; // brief squash on landing

  // ── THE GAUNTLET: spike-gated rungs (the interposing obstacle) ───────────────
  // From [spikeStartRung] up, every rung is guarded by a SPIKE that cycles
  // SAFE → WARN → DEADLY → SAFE on a fixed clock. Hopping ONTO a rung whose
  // spikes are OUT (deadly) impales the climber: it is knocked DOWN
  // [spikeKnockbackRungs] rungs and STUNNED ([spikeStunSec]) so its taps are
  // ignored. A WARN beat ([spikeWarnSec]) flashes the spikes before they arm, so
  // a reading player always gets a tell and can wait the half-beat for the rung
  // to go safe. The cycle runs FASTER higher up (a calibrated ramp), so the top
  // is a real gauntlet. The bottom [spikeStartRung] rungs are an always-safe
  // run-up so the first hops are never a trap. Phases are STAGGERED per rung so
  // adjacent rungs are rarely deadly together — a reader always has a path up,
  // but a blind masher taps straight into an armed spike, gets knocked down, and
  // taps into it again (it nets negative through the gauntlet and stalls low).
  static const int spikeStartRung = 3; // rungs below this never spike (run-up)
  static const double spikeCycleLo = 1.6; // full SAFE→DEADLY→SAFE period, low up
  static const double spikeCycleHi = 1.0; // period near the top (faster danger)
  static const double spikeDeadlyFrac = 0.34; // fraction of the cycle spikes are out
  static const double spikeWarnSec = 0.34; // telegraph beat before spikes arm
  static const double spikePhaseStep = 0.41; // per-rung phase stagger (cycles)
  // A spike hit is HEAVY: it must cost a masher MORE rungs than a blind tap can
  // regain before the next rung's spike catches it, so a frame-spammer nets
  // negative in the gauntlet and never tops out. A reading climber eats one
  // ~never.
  static const int spikeKnockbackRungs = 3; // rungs lost on a spike hit
  static const double spikeStunSec = 0.5; // taps ignored after a spike hit

  // How reliably a bot HEEDS a spike tell (waits it out) = base + slope·accuracy.
  // A poor reader steps into spikes; a sharp one threads the safe windows.
  static const double botSpikeHeedBase = 0.4;
  static const double botSpikeHeedSlope = 0.6;

  // ── HOP CADENCE: a step takes time (you cannot teleport up the tower) ─────────
  // A fresh TAP can only fire once [hopCooldownSec] has passed since the last hop
  // — the climber has to plant a foot before the next step. This is the linchpin
  // that makes spam LOSE: it caps the climb rate so a frame-masher CANNOT
  // front-run the spike gauntlet while the rungs happen to be safe; instead it
  // steps in cadence straight into rungs whose spikes have rotated out, eating
  // hit after hit and stalling LOW. A measured player taps in the same cadence
  // but only into SAFE rungs, so it climbs clean and holds high. The DOUBLE-LEAP
  // bonus hop is part of one press gesture, so it is exempt from this gate.
  // ~0.22s ≈ a brisk but human ~4.5 steps/s — kid-comfortable, well above the
  // 60 taps/s a masher throws away.
  static const double hopCooldownSec = 0.22;

  // ── THE GAMBLE: safe single hop vs risky DOUBLE LEAP ────────────────────────
  // A plain TAP hops ONE rung and is always safe. KEEP HOLDING past
  // [doubleLeapHoldSec] after that hop and the climber springs a DOUBLE LEAP: a
  // second rung in one bound that clears more lava — but it lands on a CRACKED
  // rung that crumbles. Linger on a cracked rung longer than [crackHoldSec] and
  // it gives way: you drop back one rung. The leap itself can also misfire
  // ([leapMissChance]) and only manage the single rung, so going big is a real
  // bet, not a free upgrade. Kid-readable: "hold = big scary jump".
  static const double doubleLeapHoldSec = 0.16; // hold this long → springs +1
  static const double crackHoldSec = 0.62; // linger on a cracked rung → drop
  static const double leapMissChance = 0.16; // odds a double leap fizzles to +1
  static const double crackWarnSec = 0.26; // crack flashes harder in its last beat

  // Bots gamble on the double leap when the lava is closing on them: within
  // [botLeapGapPx] of their rung they attempt the big jump instead of a single
  // hop. Better bots judge the cracked landing and hop off in time; weaker bots
  // (low accuracy) sometimes linger and crumble, so the leap stays a real bet
  // even for the AI.
  static const double botLeapGapPx = 132; // lava this close → a bot risks a leap

  // Figure scaling tracks column width so 1..4 towers all read clearly.
  static const double figureScaleMin = 0.85; // narrow 4-up columns
  static const double figureScaleMax = 1.7; // single wide column
  static const double figureScaleLoColumn = 150; // column px at min scale
  static const double figureScaleHiColumn = 560; // column px at max scale
  static const double figureLiftExtra = 6; // raise feet above the platform top

  // Danger / near-catch feel.
  static const double dangerGapPx = 170; // lava within this → danger glow ramps
  static const double nearCatchGapPx = 30; // lava this close → tension shake
  static const double nearCatchShakeGap = 0.5; // min seconds between tics

  // Anticipation: the rung directly above the climber always shows a cue so the
  // player can never miss where the next hop lands (readability), and it
  // brightens with danger so it screams "jump NOW" as the lava closes in.
  static const double nextRungPulseHz = 3.2; // pulse speed of the next rung cue
  static const double nextRungFloor = 0.4; // min cue strength when safe

  // Bots time their hops with the reaction clock; they jump when the lava is
  // within a safety buffer of their rung, and occasionally fumble (errorRate).
  // Easy bots keep a *smaller* buffer (cut it closer) AND fumble more, so a
  // steady human out-climbs them; strong bots keep a wide, safe buffer.
  static const double botSafetyGapPx = 86; // base buffer before a bot hops
  static const double botBufferPerAccuracy = 1.25; // better bots keep more buffer

  // Elimination fling.
  static const double flingX = 130; // horizontal fling / figure scale
  static const double flingY = 200; // upward fling / figure scale

  // ── SCORED RUN: full timer + respawn (no instant "last alive" win) ──────────
  // The round ALWAYS runs the full [timeLimit]; a climber caught by the lava is
  // NOT eliminated — it RESPAWNS [respawnSec] later on a safe rung a few rungs
  // ABOVE the lava (a checkpoint that keeps the run going for more score) with a
  // brief [respawnInvulnSec] grace so the lava can't immediately re-catch it. A
  // lone climber therefore plays the WHOLE run, scored on how high it CLIMBS AND
  // HOLDS — never an instant win because the other player died.
  static const double respawnSec = 1.2; // delay before a caught climber returns
  static const double respawnInvulnSec = 0.9; // post-respawn grace (no re-catch)
  static const int respawnRungsAboveLava =
      3; // checkpoint rungs above the lava surface on respawn

  // ── SCORING: ALTITUDE HELD over the run (height = how high you STAY) ─────────
  // The score is the time-integral of the climber's rung while alive: each frame
  // it banks (current rung × dt) × [scoreHeightRate]. This rewards CLIMBING HIGH
  // AND HOLDING — not a single lucky peak. It is what makes skill beat spam under
  // the law: a masher battered DOWN the spike gauntlet spends its time low and
  // banks little; a reader that threads the safe windows climbs clean and holds
  // near the top, banking far more. The double-leap, by reaching higher sooner,
  // also banks more dwell-at-altitude — so the bold climber still out-scores the
  // safe one. (A pure "highest rung ever" metric saturates and can't separate
  // skill from spam over a long timer; altitude-held does.)
  static const double scoreHeightRate = 4.0; // score per (rung·second) held alive
}

/// One climber: occupies a rung in its own tower and hops upward to outrun the
/// rising lava. Mutable, round-scoped value.
class _Climber {
  final int playerId;
  final Color color;
  final Rect column; // this player's vertical band
  final LaneSet rungs; // platform y-ladder (lane 0 = lowest)
  final double columnX; // horizontal track center
  final double figureScale;
  final double figureLift; // pelvis lift so feet plant on the rung top
  final Hopper hopper;
  final StickFigure figure;

  bool alive = true;
  double jumpHold = 0; // jump pose timer after a hop
  double landHold = 0; // squash timer after landing
  double stun = 0; // taps ignored while > 0 (post-spike-hit lockout)
  double hopCd = 0; // cooldown until the next fresh tap can fire (cadence gate)
  double heightTime = 0; // ∫ rung·dt while alive — the altitude-held score
  int topReached = 0; // highest rung EVER touched this run (peak, for cues/tests)
  double respawnTimer = 0; // seconds until a caught climber returns (0 = none)
  double invuln = 0; // post-respawn grace: lava can't catch (seconds)
  double sinceShake = _Tuning.nearCatchShakeGap; // throttle near-catch shakes
  double lavaY = 0; // lava surface y for this column (rising = decreasing y)
  ReactionClock? clock;

  // ── The gamble (double-leap) state ──
  bool holdActive = false; // a finger is held down since the last hop
  double holdSec = 0; // how long that hold has lasted
  bool leapPending = false; // a held hop has already sprung its bonus rung
  int crackedRung = -1; // rung currently crumbling under the climber (-1 = none)
  double crackTimer = 0; // time left before the cracked rung gives way
  bool crackPanicked = false; // latched once the crack-warn panic flinch fires

  _Climber({
    required this.playerId,
    required this.color,
    required this.column,
    required this.rungs,
    required this.columnX,
    required this.figureScale,
    required this.figureLift,
    required this.hopper,
    required this.figure,
    this.clock,
  });

  double rungYOf(int lane) => rungs.coordOf(lane);
  double visualRungY() => rungs.coordOfVisual(hopper.visualLane);
}

/// Chicken Jump — a vertical climb a young child reads instantly: **TAP to hop
/// up one platform, but only step onto a rung when its SPIKES are down — and
/// outrun the rising lava.**
///
/// OBJECTIVE (obvious from the scene): climb HIGH and STAY high before the
/// timer. Your score is the ALTITUDE you HOLD over the run (how high, how long).
///
/// INTERPOSING DIFFICULTY — SPIKE-GATED rungs: from a few rungs up, every rung
/// is guarded by a spike trap that cycles SAFE → (flashing) WARN → DEADLY →
/// SAFE. Hop ONTO a rung while its spikes are OUT and you are impaled: knocked
/// DOWN several rungs and briefly STUNNED (taps ignored). Each spike WARNS
/// (flashes) before it arms, so a reading player gets a tell and waits the
/// half-beat for the rung to go safe. Spikes cycle FASTER higher up, so the top
/// is a real gauntlet. A step also takes a beat ([_Tuning.hopCooldownSec]) — you
/// cannot teleport up — so RAW SPAM can't front-run the gauntlet: a blind masher
/// steps in cadence straight into armed spikes, is knocked down again and again,
/// and STALLS LOW (banking little altitude). A player who READS the spikes and
/// TIMES each hop threads a clean path and HOLDS high. Reading beats mashing.
///
/// THE GAMBLE (risk/reward, optional): a plain TAP hops ONE rung. KEEP HOLDING
/// after a hop and the climber springs a risky DOUBLE LEAP: a second rung in one
/// bound that clears more lava — but it vaults TWO spike gates at once (so it can
/// land on an armed spike) and lands on a CRACKED rung that crumbles if you
/// linger. The leap can also misfire to a single rung. Big height, bigger risk.
/// Lava floods up from the bottom of every tower, accelerating so the round
/// always converges — pure pace pressure, never the thing you tap against.
///
/// SCORED RUN (not last-one-standing): the round runs the FULL [_Tuning.timeLimit]
/// and your SCORE is the ALTITUDE HELD over the run (∫ rung·dt while alive) — it
/// rewards climbing high AND holding, not a single lucky peak. A climber caught
/// by the lava is NOT out — it RESPAWNS ~[_Tuning.respawnSec] later on a safe
/// rung above the lava (a checkpoint) with a brief grace, so a lone climber plays
/// the whole run instead of instantly "winning" because the rival fell. Most
/// altitude held over the run wins; a masher battered down the spike gauntlet
/// spends its time low and banks little, so SKILL out-scores SPAM. (A pure
/// "highest rung ever" metric saturates over a long timer and can't separate the
/// two; altitude-held does.)
///
/// Bots read the same rising lava and hop on a [BotProfile]-timed reaction
/// clock: better accuracy keeps a larger safety buffer, while [errorRate] makes
/// them hesitate. When the lava is closing fast a bot GAMBLES the double leap
/// like a human — and a sloppy bot can dither on the cracked rung and crumble —
/// so they feel reactive, not scripted, and easy bots are beatable.
class ChickenJump extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'chicken_jump',
        name: 'Chicken Jump',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  final List<_Climber> _climbers = <_Climber>[];
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for ambient FX (never scaled)
  double _lavaSpeed = _Tuning.lavaRiseStart;
  bool _climaxFired = false; // one-shot "HURRY!" finale cue latch
  bool _winnerCheered = false; // one-shot: the top survivor cheers atop the tower

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildTowers();
    begin();
  }

  // ── World build ─────────────────────────────────────────────────────────────

  void _buildTowers() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    final colW = arena.width / count;
    final lowestY = arena.height - _Tuning.bottomInset;
    final span = lowestY - _Tuning.topInset;
    final spacing = -(span / (_Tuning.platformCount - 1)); // negative = upward

    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final column = Rect.fromLTWH(colW * i, 0, colW, arena.height);
      final scale = _figureScaleFor(colW);
      final rungs = LaneSet(
        count: _Tuning.platformCount,
        start: lowestY,
        spacing: spacing,
        vertical: true,
      );
      final climber = _Climber(
        playerId: p.id,
        color: Color(p.colorArgb),
        column: column,
        rungs: rungs,
        columnX: column.center.dx,
        figureScale: scale,
        figureLift: _footReach(scale) + _Tuning.figureLiftExtra,
        hopper: Hopper(lane: 0, laneCount: _Tuning.platformCount),
        figure: StickFigure(
          proportions: StickProportions.hero.scaled(scale),
          style: _climberStyle(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.idle),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      );
      climber.lavaY = arena.height + _Tuning.lavaStartGap;
      _climbers.add(climber);
    }
  }

  /// Scale the climber to the column width so 1..4 towers all read clearly.
  double _figureScaleFor(double colW) {
    final t = ((colW - _Tuning.figureScaleLoColumn) /
            (_Tuning.figureScaleHiColumn - _Tuning.figureScaleLoColumn))
        .clamp(0.0, 1.0);
    return lerpD(_Tuning.figureScaleMin, _Tuning.figureScaleMax, t);
  }

  /// Pelvis→foot reach at rest (legs near-vertical), used to plant the feet.
  double _footReach(double scale) {
    final pr = StickProportions.hero.scaled(scale);
    return pr.thigh + pr.shin;
  }

  StickStyle _climberStyle(Color color) => StickStyle.hero.copyWith(
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
    if (status != MiniGameStatus.running) return;
    switch (input.phase) {
      case InputPhase.down:
        // A TAP commits a SINGLE hop with zero latency — subject only to the
        // cadence gate (a step needs a planted foot) and the spike gate (a hop
        // into armed spikes is impaled, not a free climb). The press also starts
        // a hold timer; keep holding and it upgrades into a risky DOUBLE LEAP.
        _jump(input.playerId);
        _beginHold(input.playerId);
      case InputPhase.holdTick:
        // Frame-rate-independent hold time accrues in update(); nothing to do.
        break;
      case InputPhase.up:
        _releaseHold(input.playerId);
    }
  }

  /// Begin tracking a held press on [id]'s climber (resets the hold clock and
  /// arms the one bonus rung the hold can still spend).
  void _beginHold(int id) {
    final c = _climberOf(id);
    if (c == null || !c.alive) return;
    c.holdActive = true;
    c.holdSec = 0;
    c.leapPending = true; // the upcoming hold may still spring its bonus rung
  }

  /// Release a held press: the gamble window closes (no bonus rung after this).
  void _releaseHold(int id) {
    final c = _climberOf(id);
    if (c == null) return;
    c.holdActive = false;
    c.holdSec = 0;
    c.leapPending = false;
  }

  void _jump(int id) {
    final c = _climberOf(id);
    if (c == null || !c.alive || c.stun > 0) return; // stunned → taps ignored
    if (c.hopCd > 0) return; // cadence gate: a step needs a planted foot first
    _hopOnce(c, cracked: false);
  }

  /// Hop the climber up exactly one rung. When [cracked] is set the rung it
  /// lands on is flagged as crumbling (the bonus rung of a DOUBLE LEAP).
  ///
  /// THE GATE: if the destination rung's spikes are OUT (deadly), the hop
  /// IMPALES the climber instead of landing — it is knocked back down and
  /// stunned (see [_spikeHit]) and gains NO height. This is what makes blind
  /// mashing lose: a masher taps into armed spikes and nets negative, while a
  /// reader times the hop to a safe/warning rung and climbs clean.
  void _hopOnce(_Climber c, {required bool cracked}) {
    final before = c.hopper.lane;
    final target = before + 1;
    if (target >= c.rungs.count) return; // already at the top rung
    if (_spikeDeadly(target, c.rungs.count)) {
      _spikeHit(c, target);
      return;
    }
    c.hopper.hop(); // up one platform
    if (c.hopper.lane == before) return; // already at the top rung

    c.hopCd = _Tuning.hopCooldownSec; // plant a foot before the next step
    c.topReached = math.max(c.topReached, c.hopper.lane);
    if (cracked) {
      c.crackedRung = c.hopper.lane;
      c.crackTimer = _Tuning.crackHoldSec;
      c.crackPanicked = false; // arm the panic flinch for this new cracked rung
    } else if (c.hopper.lane != c.crackedRung) {
      // Hopped off a cracked rung onto solid stone — clear the crumble timer.
      c.crackedRung = -1;
      c.crackTimer = 0;
      c.crackPanicked = false; // safe now — re-arm for the next crack
    }

    c.jumpHold = _Tuning.jumpHoldSec;
    if (!c.figure.isRagdoll) c.figure.setLoco(LocoState.jump);

    // Take-off dust at the rung we launched from.
    _juice.particles.burst(
      at: Offset(c.columnX, c.rungYOf(before)),
      count: 6,
      color: const Color(0xFFE8EEF6),
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.7,
      size: ChickenRenderer.dustSize * c.figureScale,
      gravity: 480,
      life: 0.3,
    );
  }

  /// A hop landed on an ARMED spike rung: the climber is impaled, knocked DOWN
  /// [spikeKnockbackRungs] rungs (never below the lowest) and STUNNED so its taps
  /// are ignored for [spikeStunSec]. It gains no height and is dragged low — this
  /// is the penalty that makes blind mashing lose: a masher knocked down the
  /// gauntlet spends its time on low rungs, so its ALTITUDE-HELD score stays
  /// small, while a reader that times its hops holds high and out-banks it.
  void _spikeHit(_Climber c, int spikeLane) {
    final before = c.hopper.lane;
    final landing =
        (before - _Tuning.spikeKnockbackRungs).clamp(0, c.rungs.count - 1);
    c.hopper.hopTo(landing);
    c.stun = _Tuning.spikeStunSec;
    c.hopCd = _Tuning.hopCooldownSec; // also re-arm the cadence gate
    // Knocked off any cracked rung it was on.
    c.crackedRung = -1;
    c.crackTimer = 0;
    c.crackPanicked = false;
    c.holdActive = false;
    c.leapPending = false;
    c.jumpHold = 0;
    c.landHold = 0;
    if (!c.figure.isRagdoll) {
      c.figure.setLoco(LocoState.fall);
      c.figure.hurt();
    }
    _juice.shake.light();
    final at = Offset(c.columnX, c.rungYOf(spikeLane));
    _juice.particles.burst(
      at: at,
      count: 10,
      color: ChickenRenderer.spikeColor,
      speed: 200,
      baseAngle: -math.pi / 2,
      spread: math.pi,
      size: ChickenRenderer.dustSize * c.figureScale,
      gravity: 360,
      life: 0.35,
    );
    _juice.popup(
      Offset(c.columnX, c.rungYOf(spikeLane) - c.figureLift - 12),
      'SPIKED!',
      ChickenRenderer.spikeColor,
      size: 22,
    );
  }

  /// Spring the DOUBLE LEAP bonus rung once a press has been held long enough.
  /// Clears the gamble window so a single hold can only ever buy ONE extra rung.
  /// The leap can misfire ([leapMissChance]) and fail to gain the bonus rung —
  /// the risk side of the bet — but the cracked-landing penalty is skipped on a
  /// miss so a fizzle is never worse than a plain hop.
  void _springDoubleLeap(_Climber c) {
    c.leapPending = false;
    // Was the lava bearing down on the rung this leap launched from? A leap
    // sprung from a near-catch is the "clutch escape" beat.
    final clutch = (c.lavaY - c.visualRungY()) <= _Tuning.nearCatchGapPx;
    final missed = ctx.rng.chance(_Tuning.leapMissChance);
    if (missed) {
      _juice.popup(
        Offset(c.columnX, c.visualRungY() - c.figureLift - 14),
        'SLIP!',
        ChickenRenderer.slipColor,
        size: 20,
      );
      return;
    }
    _hopOnce(c, cracked: true);
    // Signature beat: a successful, clutch double-leap out of the lava's reach
    // earns a one-shot flash + zoom-punch toward the climber. Fires per leap
    // event (not per-frame); the clutch gate keeps it to genuine escapes.
    if (clutch && c.alive) {
      final climberPos =
          Offset(c.columnX, c.visualRungY() - c.figureLift);
      _juice.flashScreen(c.color, strength: 0.35);
      _juice.cameraPunch(climberPos);
    }
  }

  _Climber? _climberOf(int id) {
    for (final c in _climbers) {
      if (c.playerId == id) return c;
    }
    return null;
  }

  // ── The gauntlet: spike-gated rungs ──────────────────────────────────────────

  /// Whether [lane] is a spike-gated rung at all (the bottom run-up is exempt).
  /// The very top rung is never gated so the summit is always reachable.
  bool _isGated(int lane, int rungCount) =>
      lane >= _Tuning.spikeStartRung && lane < rungCount - 1;

  /// The spike CYCLE period for [lane] — shorter (faster danger) higher up.
  double _spikeCycle(int lane, int rungCount) {
    final maxLane = (rungCount - 1).toDouble();
    final t = maxLane <= 0 ? 0.0 : (lane / maxLane).clamp(0.0, 1.0);
    return lerpD(_Tuning.spikeCycleLo, _Tuning.spikeCycleHi, t);
  }

  /// Phase 0..1 through [lane]'s spike cycle right now. Driven by the shared
  /// post-warmup clock so every column reads the SAME gauntlet (fair race), with
  /// a per-rung stagger so adjacent rungs are rarely deadly at once.
  double _spikePhase(int lane, int rungCount) {
    final cycle = _spikeCycle(lane, rungCount);
    if (cycle <= 0) return 0;
    final runT = math.max(0.0, _elapsed - _Tuning.warmupSec);
    final staggered = runT / cycle + lane * _Tuning.spikePhaseStep;
    final p = staggered % 1.0;
    return p < 0 ? p + 1.0 : p;
  }

  /// True when [lane]'s spikes are OUT (deadly) right now. The deadly window is
  /// the LAST [spikeDeadlyFrac] of the cycle; the warn beat sits just before it.
  /// Never deadly during the warmup (the board reads calm first) or on an
  /// ungated rung.
  bool _spikeDeadly(int lane, int rungCount) {
    if (_inWarmup || !_isGated(lane, rungCount)) return false;
    return _spikePhase(lane, rungCount) >= (1.0 - _Tuning.spikeDeadlyFrac);
  }

  /// True when [lane]'s spikes are in their WARN beat (telegraphing, still safe
  /// to land on): the [spikeWarnSec] window immediately before they arm.
  bool _spikeWarning(int lane, int rungCount) {
    if (_inWarmup || !_isGated(lane, rungCount)) return false;
    final cycle = _spikeCycle(lane, rungCount);
    if (cycle <= 0) return false;
    final p = _spikePhase(lane, rungCount);
    final deadlyStart = 1.0 - _Tuning.spikeDeadlyFrac;
    final warnStart = deadlyStart - (_Tuning.spikeWarnSec / cycle);
    return p >= warnStart && p < deadlyStart;
  }

  /// 0..1 spike "armed-ness" of [lane] for the renderer: 0 fully retracted,
  /// ramps through the warn beat, 1 fully out (deadly). Lets the art telegraph
  /// the trap and show the spikes physically extend.
  double _spikeLevel(int lane, int rungCount) {
    if (_inWarmup || !_isGated(lane, rungCount)) return 0;
    final cycle = _spikeCycle(lane, rungCount);
    if (cycle <= 0) return 0;
    final p = _spikePhase(lane, rungCount);
    final deadlyStart = 1.0 - _Tuning.spikeDeadlyFrac;
    if (p >= deadlyStart) return 1.0; // fully out
    final warnStart = deadlyStart - (_Tuning.spikeWarnSec / cycle);
    if (p < warnStart) return 0.0; // retracted
    // Rising through the warn beat: spikes visibly creep out as the tell plays.
    return ((p - warnStart) / (deadlyStart - warnStart)).clamp(0.0, 1.0);
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

    // During the warmup beat the lava holds; afterward it accelerates. Measuring
    // the ramp from the post-warmup clock keeps the early reaction window fair.
    final runT = math.max(0.0, _elapsed - _Tuning.warmupSec);
    _lavaSpeed = _Tuning.lavaRiseStart + _Tuning.lavaAccel * runT;
    // No end-surge: the lava is capped below the reachable top (see [_lavaFloorY]
    // / [_stepClimber]) so the climb stays live to the buzzer. The climax only
    // drives the renderer's heat + the one-shot "HURRY!" cue.
    _maybeFireClimax();

    // COMEBACK: the single living climber on the lowest rung gets held lava.
    final trailingId = _trailingClimberId();

    _tickRespawns(dt);
    _driveBots(dt);
    for (final c in _climbers) {
      _stepClimber(c, dt, sdt, comeback: c.playerId == trailingId);
    }
    _checkEnd();
  }

  /// Count down each caught climber's respawn timer; when it elapses bring the
  /// climber back on a safe checkpoint rung above the lava. Keeps the run going
  /// for the full timer so a lone climber never wins by the rival merely falling.
  void _tickRespawns(double dt) {
    for (final c in _climbers) {
      if (c.alive) continue;
      if (c.respawnTimer <= 0) continue; // already resolved / not queued
      c.respawnTimer -= dt;
      if (c.respawnTimer <= 0) _respawn(c);
    }
  }

  /// Bring a caught climber back on a safe rung a few rungs ABOVE the current
  /// lava surface (clamped into the tower), upright and briefly invulnerable so
  /// the lava cannot re-catch it the instant it lands. The altitude it already
  /// banked ([heightTime]) is kept — the respawn only lets it keep climbing for
  /// more, never refunds the height-time it lost while down.
  void _respawn(_Climber c) {
    final lavaLane = _laneAtOrAboveLava(c);
    final safeLane =
        (lavaLane + _Tuning.respawnRungsAboveLava).clamp(0, c.rungs.count - 1);
    c.alive = true;
    c.respawnTimer = 0;
    c.invuln = _Tuning.respawnInvulnSec;
    c.hopper.hopTo(safeLane);
    c.hopper.snapVisual();
    // NOTE: a respawn parks the climber on a checkpoint but does NOT bank that
    // height for free — score accrues only from rungs the climber HOLDS while
    // alive (it stopped banking while down). So the safety net keeps a behind
    // player in the run without ever inflating its score; active climbing stays
    // the only way up the ranking.
    // Clear any gamble / pose state carried from before the catch.
    c.holdActive = false;
    c.holdSec = 0;
    c.leapPending = false;
    c.crackedRung = -1;
    c.crackTimer = 0;
    c.crackPanicked = false;
    c.stun = 0; // a fresh checkpoint is never still stunned
    c.hopCd = 0; // free to climb again the instant it lands
    c.jumpHold = 0;
    c.landHold = 0;
    c.figure.exitRagdoll();
    c.figure.setLoco(LocoState.idle);
    final at = Offset(c.columnX, c.visualRungY() - c.figureLift);
    _juice.particles.burst(
      at: at,
      count: 12,
      color: c.color,
      speed: 200,
      size: 6,
      gravity: 120,
      life: 0.5,
    );
    _juice.popup(
      Offset(c.columnX, c.visualRungY() - c.figureLift - 12),
      'BACK!',
      c.color,
      size: 24,
    );
  }

  /// The lowest rung whose top is still ABOVE the lava surface in [c]'s column
  /// (i.e. a rung the climber would be safe standing on right now). Falls back to
  /// the lowest rung when the lava is below the whole tower.
  int _laneAtOrAboveLava(_Climber c) {
    for (var lane = 0; lane < c.rungs.count; lane++) {
      if (c.rungYOf(lane) < c.lavaY) return lane; // rung top above the lava
    }
    return c.rungs.count - 1;
  }

  /// The lowest the lava SURFACE may ever sit (largest y = highest it may rise):
  /// [_Tuning.lavaCapRungs] rung-spacings BELOW the top reachable rung. Keeping
  /// the surface at or under this y guarantees clear tower above it for the whole
  /// round, so the climb never becomes an agency-free death-strobe.
  double _lavaFloorY(_Climber c) {
    final topRungY = c.rungYOf(c.rungs.count - 1); // smallest y (highest rung)
    final spacingMag = c.rungs.spacing.abs(); // px between adjacent rungs
    return topRungY + _Tuning.lavaCapRungs * spacingMag; // below the top rung
  }

  /// True once the round passes the climax fraction of its life — the renderer
  /// reads max escalation (heat / cue). The lava SPEED is not surged.
  bool get _inClimax => _elapsed >= _Tuning.timeLimit * _Tuning.climaxFrac;

  /// Fire the one-shot "HURRY!" finale cue over every live climber.
  void _maybeFireClimax() {
    if (_climaxFired || !_inClimax) return;
    _climaxFired = true;
    for (final c in _climbers) {
      if (!c.alive) continue;
      _juice.popup(
        Offset(c.columnX, c.visualRungY() - c.figureLift - 18),
        'HURRY!',
        ChickenRenderer.hurryColor,
        size: 26,
      );
    }
    _juice.shake.medium();
  }

  /// The id of the single living climber sitting lowest (fewest rungs climbed),
  /// or null if the field is empty / tied at the bottom is broken by first found.
  /// Only ONE player is ever helped, so a runaway leader gets no handicap and a
  /// trailing kid gets a gentle hand — never enough to overtake on its own.
  int? _trailingClimberId() {
    _Climber? worst;
    for (final c in _climbers) {
      if (!c.alive) continue;
      if (worst == null || c.hopper.lane < worst.hopper.lane) worst = c;
    }
    return worst?.playerId;
  }

  bool get _inWarmup => _elapsed < _Tuning.warmupSec;

  void _stepClimber(_Climber c, double dt, double sdt, {bool comeback = false}) {
    // Lava holds during the warmup, then rises (even for the dead, so the scene
    // keeps escalating). The lone trailing climber gets its lava eased a touch
    // (kid-assist) so a behind player stays in the race a little longer.
    if (!_inWarmup) {
      final mul = comeback ? _Tuning.comebackLavaMul : 1.0;
      c.lavaY -= _lavaSpeed * mul * sdt;
      // HARD CAP: never let the lava rise above ~[lavaCapRungs] spacings below the
      // top reachable rung. Smaller y = higher, so the floor is the LARGEST y the
      // surface may reach. This guarantees clear tower above the lava all round —
      // the climber always has somewhere to climb and room to risk the double-leap.
      final floorY = _lavaFloorY(c);
      if (c.lavaY < floorY) c.lavaY = floorY;
    }
    c.sinceShake += dt;
    if (c.invuln > 0) c.invuln = math.max(0, c.invuln - dt);
    if (c.stun > 0) c.stun = math.max(0, c.stun - dt);
    if (c.hopCd > 0) c.hopCd = math.max(0, c.hopCd - dt);

    if (!c.alive) {
      c.figure.update(dt);
      return;
    }

    // SCORE: bank altitude held this frame (rung × dt). Only while alive and
    // past the warmup, so the calm GET-SET beat doesn't pad the score and a
    // climber earns only the height it actually CLIMBS AND HOLDS.
    if (!_inWarmup) {
      c.heightTime += c.hopper.lane * dt * _Tuning.scoreHeightRate;
    }

    c.hopper.update(sdt, speed: _Tuning.hopAnimSpeed);
    _tickHold(c, dt);
    _tickCrack(c, dt);
    _tickPose(c, dt);

    c.figure.update(dt);
    _checkLava(c);
  }

  /// Accrue a held press; once it passes [doubleLeapHoldSec] spring the bonus
  /// rung (the DOUBLE LEAP). Frame-rate independent — driven by real dt, not the
  /// hold-tick event — so a long-press always reads the same regardless of fps.
  void _tickHold(_Climber c, double dt) {
    if (!c.holdActive || c.stun > 0) return; // stunned → the gamble is frozen too
    c.holdSec += dt;
    if (c.leapPending && c.holdSec >= _Tuning.doubleLeapHoldSec) {
      _springDoubleLeap(c);
    }
  }

  /// Tick a crumbling rung. While the climber lingers on its cracked rung the
  /// timer drains; if it runs out the rung gives way and the climber drops back
  /// one rung (with a puff + a light shake). Hopping off in time clears it.
  void _tickCrack(_Climber c, double dt) {
    if (c.crackedRung < 0 || c.hopper.lane != c.crackedRung) return;
    if (!c.hopper.settled) return; // only counts down once actually standing
    c.crackTimer -= dt;
    // Charm: in the final warn beat before the rung gives way the climber panics
    // — a one-shot [hurt] jitter so kids read "GET OFF!" before it crumbles.
    // Latched per crack (re-armed when the climber lands on a fresh rung).
    if (!c.crackPanicked && c.crackTimer <= _Tuning.crackWarnSec) {
      c.crackPanicked = true;
      if (!c.figure.isRagdoll) c.figure.hurt();
    }
    if (c.crackTimer > 0) return;
    _crumble(c);
  }

  /// The cracked rung collapses: drop the climber back one rung (never below the
  /// lowest), clear the crack, and sell the give-way with dust + a light shake.
  void _crumble(_Climber c) {
    c.crackedRung = -1;
    c.crackTimer = 0;
    c.crackPanicked = false; // crack resolved — re-arm for any future crack
    final before = c.hopper.lane;
    c.hopper.hop(-1); // fall back one rung
    if (c.hopper.lane == before) return; // already at the lowest rung
    if (!c.figure.isRagdoll) c.figure.setLoco(LocoState.fall);
    c.landHold = _Tuning.landHoldSec;
    _landPuff(c);
    _juice.shake.light();
    _juice.popup(
      Offset(c.columnX, c.visualRungY() - c.figureLift - 12),
      'CRUMBLE!',
      ChickenRenderer.slipColor,
      size: 18,
    );
  }

  void _tickPose(_Climber c, double dt) {
    if (c.jumpHold > 0) {
      c.jumpHold -= dt;
      if (c.jumpHold <= 0 && c.hopper.settled) {
        // Land: brief squash then idle.
        c.landHold = _Tuning.landHoldSec;
        if (!c.figure.isRagdoll) c.figure.land();
        _landPuff(c);
      }
    } else if (c.landHold > 0) {
      c.landHold -= dt;
      if (c.landHold <= 0 && !c.figure.isRagdoll) {
        c.figure.setLoco(LocoState.idle);
      }
    }
  }

  void _landPuff(_Climber c) {
    // A wide, flat puff that sprays sideways off the rung so the plant reads as
    // a solid impact — dust hugs the platform rather than fountaining up.
    _juice.particles.burst(
      at: Offset(c.columnX, c.visualRungY()),
      count: 8,
      color: const Color(0xFFE3EBF6),
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 1.5,
      size: ChickenRenderer.dustSize * c.figureScale * 0.9,
      gravity: 320,
      life: 0.3,
    );
  }

  void _checkLava(_Climber c) {
    final rungY = c.visualRungY();
    final gap = c.lavaY - rungY; // positive while the lava is still below

    // Tension: a near-catch nudges a light shake (throttled) for drama.
    if (gap <= _Tuning.nearCatchGapPx &&
        gap > 0 &&
        c.sinceShake >= _Tuning.nearCatchShakeGap) {
      _juice.shake.light();
      c.sinceShake = 0;
    }

    // Caught once the lava surface reaches the logical rung the climber owns —
    // unless it is in its post-respawn grace, so a fresh checkpoint is never an
    // instant re-catch.
    if (c.invuln <= 0 && c.lavaY <= c.rungYOf(c.hopper.lane)) {
      _eliminate(c);
    }
  }

  // ── Bots ─────────────────────────────────────────────────────────────────────

  /// Bots hop on their reaction clock when the lava nears their rung. Better
  /// accuracy keeps a larger safety buffer; [errorRate] makes them hesitate.
  /// When the lava is closing fast a bot GAMBLES the DOUBLE LEAP (the same
  /// cracked-landing bet a human takes) instead of a single hop — better bots
  /// clear the cracked rung in time, weaker ones sometimes linger and crumble.
  void _driveBots(double dt) {
    if (_inWarmup) return; // let everyone read the board first (fair beat)
    for (final c in _climbers) {
      final clock = c.clock;
      if (clock == null || !c.alive) continue;
      if (c.stun > 0 || c.hopCd > 0) continue; // can't act while locked / mid-step
      if (!clock.tick(dt)) continue;
      _driveBotMove(c);
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  /// One bot decision: bail off a cracked rung first (so it isn't caught when the
  /// stone gives way), otherwise hop to outrun the lava — risking the double leap
  /// when the lava is close enough to be worth the gamble.
  ///
  /// READS THE GAUNTLET: before committing a hop the bot checks the rung above
  /// for spikes. A skilled bot ([accuracy]) waits when that rung is DEADLY or
  /// telegraphing-into-deadly, threading the safe windows like a good human; a
  /// sloppy one ([errorRate]) sometimes steps anyway and eats the spike. So easy
  /// bots impale themselves on the gauntlet and a measured human out-climbs them.
  void _driveBotMove(_Climber c) {
    // On a cracked rung: a competent bot hops off promptly; a sloppy one (high
    // errorRate) may dither and let it crumble — keeps the bet real for the AI.
    if (c.crackedRung == c.hopper.lane && c.crackedRung >= 0) {
      if (!ctx.rng.chance(ctx.botProfile.errorRate)) _jump(c.playerId);
      return;
    }
    final rungY = c.rungYOf(c.hopper.lane);
    final gap = c.lavaY - rungY; // positive while the lava is still below
    final buffer = _Tuning.botSafetyGapPx *
        (0.45 + _Tuning.botBufferPerAccuracy * ctx.botProfile.accuracy);
    final lavaForcing = gap <= buffer; // must move soon or be caught
    // Read the rung we'd hop onto. A skilled bot won't step into live or
    // about-to-be-live spikes; it waits for the window. A weak bot reads poorly
    // (its accuracy gates how reliably it heeds the tell) and walks into them.
    final target = c.hopper.lane + 1;
    if (target < c.rungs.count && _botWouldImpale(c, target)) {
      // Heeds the spike (waits) unless it reads poorly. When the lava is forcing
      // a move a panicking bot is likelier to leap anyway — a real bad-spot bet.
      final heeds = ctx.rng.chance(_Tuning.botSpikeHeedBase +
          _Tuning.botSpikeHeedSlope * ctx.botProfile.accuracy);
      if (heeds && !lavaForcing) return; // wait for the spikes to retract
    }
    if (!lavaForcing) return; // safe for now — hold position
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate (fumble)
    // Lava closing in: gamble the double leap to clear more distance at once.
    if (gap <= _Tuning.botLeapGapPx) {
      _springDoubleLeap(c);
    } else {
      _jump(c.playerId);
    }
  }

  /// Whether hopping onto [lane] now would land a bot on armed (or imminently
  /// arming) spikes — the danger window a reading bot avoids.
  bool _botWouldImpale(_Climber c, int lane) =>
      _spikeDeadly(lane, c.rungs.count) || _spikeWarning(lane, c.rungs.count);

  // ── Elimination / outcome ────────────────────────────────────────────────────

  /// The lava catches a climber: it ragdolls + KOs, but this is NOT a permanent
  /// elimination — the altitude it has banked ([heightTime]) is kept and it is
  /// queued to RESPAWN on a safe checkpoint after [respawnSec], so the run
  /// continues for the full timer (a caught climber simply stops banking height
  /// while down). Guarded against a double-catch in one frame (already-dead /
  /// mid-respawn climbers are skipped).
  void _eliminate(_Climber c) {
    if (!c.alive) return;
    c.alive = false;
    c.respawnTimer = _Tuning.respawnSec;
    c.holdActive = false;
    c.leapPending = false;
    c.crackedRung = -1;
    final rungY = c.visualRungY();
    final at = Offset(c.columnX, rungY);
    final away = ctx.rng.sign();
    c.figure.enterRagdoll(
      Offset(c.columnX, rungY - c.figureLift),
      rungY,
      Offset(away * _Tuning.flingX * c.figureScale,
          -_Tuning.flingY * c.figureScale),
    );
    _juice.ko(at, c.color);
    _juice.popup(Offset(c.columnX, rungY - 34), 'CAUGHT!', c.color, size: 30);
  }

  void _checkEnd() {
    // SCORED RUN: the round runs the FULL timer (caught climbers respawn), so it
    // NEVER ends early just because one climber is left — a lone player plays the
    // whole run and is scored on how high it got. Only the time cap resolves it.
    if (_elapsed >= _Tuning.timeLimit) _finish();
  }

  void _finish() {
    // SCORED RUN: rank by ALTITUDE HELD over the whole run (the ∫ rung·dt each
    // climber banked), highest first. A lone player is scored on how high it
    // climbed AND held, never on merely outliving a fallen rival; and because a
    // masher battered down the spike gauntlet spends its time low while a reader
    // holds high, skill out-scores spam. The double-leap, reaching altitude
    // sooner, banks more dwell-up — so the bold climber still out-scores the safe
    // one.
    for (final c in _climbers) {
      setScore(c.playerId, c.heightTime.round());
    }
    // Rank by altitude held, highest first; ties break by id so the full set is
    // always preserved in a stable order.
    final ranked = _climbers.toList()
      ..sort((a, b) {
        final byHeld = b.heightTime.compareTo(a.heightTime);
        return byHeld != 0 ? byHeld : a.playerId.compareTo(b.playerId);
      });
    // Charm: the highest climber reacts atop the tower instead of freezing — a
    // full-body arms-up cheer. Fires once; a climber mid-fall / caught is a
    // ragdoll, so only an upright winner celebrates.
    if (!_winnerCheered && ranked.isNotEmpty) {
      _winnerCheered = true;
      final top = ranked.first;
      if (!top.figure.isRagdoll) top.figure.victory();
    }
    _juice.confetti(ctx.arena);
    finishByOrder(_dedupe([for (final c in ranked) c.playerId]));
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

    ChickenRenderer.drawBackground(canvas, size, _escalation());

    for (final c in _climbers) {
      _drawTower(canvas, c);
    }

    _juice.render(canvas);
    canvas.restore();

    _juice.renderOverlay(canvas, size);
  }

  /// 0..1 escalation, used for ambient heat — ramps with the lava speed and
  /// pins to full during the climax so the finale background glows hottest.
  double _escalation() {
    if (_inClimax) return 1;
    final span = _Tuning.lavaAccel * _Tuning.timeLimit;
    if (span <= 0) return 0;
    return ((_lavaSpeed - _Tuning.lavaRiseStart) / span).clamp(0.0, 1.0);
  }

  void _drawTower(Canvas canvas, _Climber c) {
    final danger = _dangerLevel(c);

    ChickenRenderer.drawColumnBackdrop(
      canvas,
      c.column,
      c.color,
      _parallax(c),
      danger,
      c.alive,
    );

    // The rung the climber will hop to next — always cued so the player sees the
    // target; sharpens with danger to read as "jump now".
    final nextLane = c.hopper.lane + 1;
    final showNext = c.alive && c.hopper.settled && nextLane < c.rungs.count;

    // Platforms.
    for (var lane = 0; lane < c.rungs.count; lane++) {
      final anticipate = (showNext && lane == nextLane)
          ? _anticipationPulse(danger)
          : 0.0;
      final cracked = (c.alive && lane == c.crackedRung) ? _crackLevel(c) : 0.0;
      ChickenRenderer.drawPlatform(
        canvas,
        Offset(c.columnX, c.rungYOf(lane)),
        c.column.width,
        c.color,
        lit: lane == c.hopper.lane && c.alive,
        anticipate: anticipate,
        cracked: cracked,
      );
    }

    // SPIKE GATES (drawn over the stone so the trap reads on top). Every gated
    // rung shows its spikes creep up through the warn beat and stand tall when
    // live — the telegraphed hazard a reader times their hops around.
    final climberRefY = c.rungYOf(c.hopper.lane);
    for (var lane = _Tuning.spikeStartRung; lane < c.rungs.count; lane++) {
      final level = _spikeLevel(lane, c.rungs.count);
      if (level <= 0) continue;
      final ry = c.rungYOf(lane);
      // Rungs above the climber recede into the distance (dim + short); the gate
      // at the climber's height is full foreground. ~520px = fully receded.
      final depth = ((climberRefY - ry) / 520.0).clamp(0.0, 1.0);
      ChickenRenderer.drawSpikes(
        canvas,
        Offset(c.columnX, ry),
        c.column.width,
        level,
        depth: depth,
      );
    }

    // Lava with a bubbling surface + embers, plus a danger glow as it nears.
    ChickenRenderer.drawLava(canvas, c.column, c.lavaY, _animClock, danger);

    // Climber contact shadow + figure.
    final rungY = c.visualRungY();
    if (!c.figure.isRagdoll) {
      ChickenRenderer.drawContactShadow(
        canvas,
        Offset(c.columnX, rungY),
        c.column.width * 0.22,
        c.alive,
      );
    }
    ChickenRenderer.drawClimber(
      canvas,
      c.figure,
      Offset(c.columnX, rungY - c.figureLift),
    );

    // Cadence "plant your foot" tell: while the hop cooldown runs, a small arc at
    // the climber's feet fills back up — so a tap eaten by the cadence gate reads
    // as "wait a beat", not as input lag. (A hidden cooldown feels broken.)
    if (c.alive && !c.figure.isRagdoll && c.hopCd > 0 && !_inWarmup) {
      final frac = (1.0 - c.hopCd / _Tuning.hopCooldownSec).clamp(0.0, 1.0);
      final r = c.column.width * 0.16;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(c.columnX, rungY), radius: r),
        -math.pi / 2,
        math.pi * 2 * frac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.3)
          ..strokeCap = StrokeCap.round
          ..color = c.color.withValues(alpha: 0.55),
      );
    }

    // A bobbing "TAP to hop" arrow over the climber during the warmup so the one
    // control is unmistakable before the lava starts to rise.
    if (c.alive && _inWarmup) {
      ChickenRenderer.drawTapHint(
        canvas,
        Offset(c.columnX, rungY - c.figureLift),
        c.column.width,
        c.color,
        _animClock,
      );
    }

    // Altitude indicator + player pip in the column corner.
    ChickenRenderer.drawAltitude(
      canvas,
      c.column,
      _heightFraction(c),
      c.color,
      c.alive,
    );
  }

  /// Parallax phase for a column: how far the climber has ascended (px), so the
  /// cave background drifts down as the climber rises.
  double _parallax(_Climber c) {
    final lowest = c.rungYOf(0);
    return (lowest - c.visualRungY()).clamp(0.0, c.column.height);
  }

  /// 0..1 how close the lava is to the climber's rung — drives the danger glow.
  double _dangerLevel(_Climber c) {
    if (!c.alive) return 0;
    final gap = c.lavaY - c.visualRungY();
    if (gap <= 0) return 1;
    return (1.0 - (gap / _Tuning.dangerGapPx)).clamp(0.0, 1.0);
  }

  /// 0..1 urgency of the cracked rung the climber is standing on: starts low and
  /// swells as its crumble timer drains, flashing hardest in the final
  /// [crackWarnSec] beat so "GET OFF" reads. Zero when no crack is active.
  double _crackLevel(_Climber c) {
    if (c.crackedRung < 0 || c.crackTimer <= 0) return 0;
    final drained = (1.0 - c.crackTimer / _Tuning.crackHoldSec).clamp(0.0, 1.0);
    if (c.crackTimer > _Tuning.crackWarnSec) {
      return (0.35 + 0.4 * drained).clamp(0.0, 1.0);
    }
    // Final beat: hard flash so the give-way is unmistakable.
    final flash = 0.5 + 0.5 * math.sin(_animClock * 26);
    return (0.75 + 0.25 * flash).clamp(0.0, 1.0);
  }

  /// 0..1 strength of the next-rung anticipation cue: a calm pulse (never below
  /// [nextRungFloor], so the target is always visible) that swells (and pulses
  /// faster, via the phase) as the lava closes in.
  double _anticipationPulse(double danger) {
    final d = danger.clamp(0.0, 1.0);
    final hz = _Tuning.nextRungPulseHz * (1.0 + d);
    final throb = 0.5 + 0.5 * math.sin(_animClock * hz * math.pi);
    final base = _Tuning.nextRungFloor + (1.0 - _Tuning.nextRungFloor) * d;
    return (base * (0.7 + 0.3 * throb)).clamp(0.0, 1.0);
  }

  /// 0..1 fraction of the tower climbed (for the altitude bar).
  double _heightFraction(_Climber c) {
    final maxLane = (c.rungs.count - 1).toDouble();
    if (maxLane <= 0) return 0;
    return (c.hopper.visualLane / maxLane).clamp(0.0, 1.0);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  // ── Test seams (read-only) ──────────────────────────────────────────────────

  /// The logical rung [id]'s climber currently stands on (0 = lowest), or -1 if
  /// there is no such climber. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  int heightLaneOf(int id) => _climberOf(id)?.hopper.lane ?? -1;

  /// The rung currently crumbling under [id]'s climber, or -1 when none is
  /// cracked / no such climber. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  int crackedRungOf(int id) => _climberOf(id)?.crackedRung ?? -1;

  /// The peak rung [id]'s climber ever reached this run (a readability/cue value,
  /// NOT the score), or -1 for no such climber. Read-only; for deterministic
  /// gameplay tests.
  @visibleForTesting
  int peakLaneOf(int id) => _climberOf(id)?.topReached ?? -1;

  /// The altitude-held score [id]'s climber has banked so far (∫ rung·dt), or 0
  /// for no such climber. This is what the run is ranked on. Read-only; for the
  /// anti-spam test (a masher stalled low banks far less than a reader).
  @visibleForTesting
  double heldScoreOf(int id) => _climberOf(id)?.heightTime ?? 0;

  /// Whether the rung directly above [id]'s climber has its spikes OUT (DEADLY)
  /// right now — i.e. a hop into it would be impaled. Read-only; for the spike
  /// test (distinct from [nextRungSafeOf], which also excludes the harmless WARN
  /// beat). False when there is no such climber or it is already atop.
  @visibleForTesting
  bool nextRungDeadlyOf(int id) {
    final c = _climberOf(id);
    if (c == null) return false;
    final target = c.hopper.lane + 1;
    if (target >= c.rungs.count) return false;
    return _spikeDeadly(target, c.rungs.count);
  }

  /// Seconds of post-spike stun left on [id]'s climber (0 = free to act), or 0
  /// for no such climber. Read-only; for deterministic gameplay tests.
  @visibleForTesting
  double stunOf(int id) => _climberOf(id)?.stun ?? 0;

  /// Whether hopping UP one rung right now would land [id]'s climber on a SAFE
  /// rung (spikes retracted, not telegraphing-into-deadly). A measured climber
  /// only taps when this is true; a blind masher ignores it. Read-only; for the
  /// anti-spam test. False when there is no such climber or it is already atop.
  @visibleForTesting
  bool nextRungSafeOf(int id) => nextNRungsSafeOf(id, 1);

  /// Whether the next [n] rungs above [id]'s climber are ALL currently safe
  /// (none deadly or telegraphing). A holder timing a DOUBLE LEAP (which crosses
  /// two rungs) checks n=2 so neither the step nor the bonus rung is spiked.
  /// Read-only; for deterministic gameplay tests.
  @visibleForTesting
  bool nextNRungsSafeOf(int id, int n) {
    final c = _climberOf(id);
    if (c == null) return false;
    for (var i = 1; i <= n; i++) {
      final lane = c.hopper.lane + i;
      if (lane >= c.rungs.count) return false;
      if (_spikeDeadly(lane, c.rungs.count) ||
          _spikeWarning(lane, c.rungs.count)) {
        return false;
      }
    }
    return true;
  }

  /// The first gated rung (the bottom of the gauntlet). Exposed so the anti-spam
  /// test can target the hazard band. Read-only.
  @visibleForTesting
  int get spikeStartRung => _Tuning.spikeStartRung;
}
