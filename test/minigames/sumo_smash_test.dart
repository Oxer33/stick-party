import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/sumo_smash/sumo_fx.dart';
import 'package:stick_party/minigames/sumo_smash/sumo_smash.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sumo Smash — "Schianto & Brace": TAP = LUNGE (committed dash + recovery),
// HOLD = BRACE (rooted, knockback cut). A lunge into a braced foe is REPELLED +
// STUNNED; a lunge into a non-braced foe LAUNCHES it (ring-out). The headline
// guarantee these tests prove: a blind every-lunge masher LOSES to a measured
// brace-then-counter player.
// ─────────────────────────────────────────────────────────────────────────────

/// Build + run an all-bot round, returning (game, framesElapsed).
(SumoSmash, int) _runCounted(int count, int seed, {int maxFrames = 60 * 80}) {
  final players = [
    for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true),
  ];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(count),
  );
  final g = SumoSmash()..init(ctx);
  var n = 0;
  while (g.status != MiniGameStatus.finished && n < maxFrames) {
    g.update(1 / 60);
    n++;
  }
  return (g, n);
}

SumoSmash _run(int count, int seed) {
  final (g, _) = _runCounted(count, seed);
  return g;
}

/// Drive a deterministic 1v1 (no bots) where [blindId] is a BLIND LUNGER and
/// [skilledId] is a MEASURED BRACE-THEN-COUNTER player, both forced through the
/// `@visibleForTesting` hooks so the only difference is HOW each plays:
///
///  * BLIND  — fires a LUNGE the instant it can act, forever. Each lunge exposes
///    a recovery window; lunging into the skilled player's brace gets it
///    repelled + stunned and drifting toward the rim → it self-rings.
///  * MEASURED — baits with a short BRACE; while braced an incoming lunge is
///    repelled and the masher is stunned. The moment the masher is exposed
///    (stunned / recovering) the measured player drops the brace and counters
///    with ONE lunge, then re-baits. It never flails into open clay.
///
/// Returns the finished game so the caller can compare scores / self-rings.
SumoSmash _blindVsMeasured(
  int seed, {
  required int blindId,
  required int skilledId,
}) {
  final players = [PlayerSlot.defaults(0), PlayerSlot.defaults(1)];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(2),
  );
  final g = SumoSmash()..init(ctx);

  // A forced brace on a non-bot slot does not auto-release, so the measured
  // player holds each brace for a fixed frame budget then releases it.
  var braceFrames = 0; // >0 while the measured player is holding the wall
  var n = 0;
  while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
    // BLIND LUNGER: lunge whenever able, no reads, no waiting — it impales
    // itself on the measured player's brace and is flung toward the rim.
    if (g.debugCanAct(blindId)) g.debugForceLunge(blindId);

    // MEASURED BRACE-WALL-THEN-COUNTER: hold a near-gapless central brace so the
    // masher's lunges rebound (repelled + stunned → flung toward the rim).
    // Counter with a single lunge ONLY when the masher is genuinely STUNNED and
    // the measured player is safely central, so the counter both banks a KO and
    // never over-commits the measured player off the rim.
    final ring = g.debugRingRadius;
    final central = g.debugDistFromCenter(skilledId) < ring * 0.40;
    final foeStunned = g.debugIsStunned(blindId);
    if (g.debugIsBracing(skilledId)) {
      braceFrames--;
      // Drop the wall only to punish a stunned foe from a central spot, else
      // keep it planted (re-arm when the brace budget lapses).
      if ((foeStunned && central) || braceFrames <= 0) {
        g.debugReleaseBrace(skilledId);
      }
    } else if (g.debugCanAct(skilledId)) {
      if (foeStunned && central) {
        g.debugForceLunge(skilledId); // safe, central counter on a stunned foe
      } else {
        g.debugForceBrace(skilledId, holdSec: 1.0);
        braceFrames = 18; // ~0.3s of planted wall, then re-read
      }
    }
    g.update(1 / 60);
  }
  return g;
}

void main() {
  // ── Win model: SCORED BRAWL (most ring-outs), full ranking ──────────────────

  test('sumo finishes with all bots and ranks everyone', () {
    final g = _run(4, 7);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('sumo finishes for 1..3 players with a full ranking', () {
    for (final count in const [1, 2, 3]) {
      final g = _run(count, 11 + count);
      expect(g.status, MiniGameStatus.finished, reason: '$count players');
      expect(g.winResult, isNotNull, reason: '$count players');
      expect(g.winResult!.ranking.toSet(), {
        for (var i = 0; i < count; i++) i,
      }, reason: '$count players');
    }
  });

  test('NO INSTANT WIN: a 1v1 never ends just because one fighter is KO\'d — '
      'the round runs the full ~28s brawl', () {
    // KO\'d wrestlers respawn, so a single fast knockout must NOT end the round.
    // A 1v1 (human + bot) with the human idle (the bot scores freely) must still
    // play a sustained brawl, not ~2s.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    final seconds = n / 60.0;
    expect(g.status, MiniGameStatus.finished);
    expect(seconds, greaterThan(8.0),
        reason: '1v1 ended in ${seconds.toStringAsFixed(2)}s (instant-win regression)');
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('all-bot ranking is always ordered by KO score (winner highest)', () {
    // Final scores are KO counts (a self-ring penalty can dip a player negative).
    // For EVERY seed the ranking must be ordered by score: nobody ranked above
    // the winner can have a higher score.
    for (final seed in const [1, 7, 13, 21, 99]) {
      final (g, _) = _runCounted(4, seed);
      final scores = g.winResult!.finalScores;
      final winner = g.winResult!.ranking.first;
      final winnerScore = (scores[winner] ?? 0).toDouble();
      for (final id in g.winResult!.ranking) {
        expect((scores[id] ?? 0).toDouble(), lessThanOrEqualTo(winnerScore),
            reason: 'seed $seed ranking not ordered by KO score: $scores');
      }
    }
  });

  test('CREDITED RING-OUT: launching an exposed foe off the rim banks a +1 KO '
      'for the launcher (score = ring-outs you CAUSE)', () {
    // A deterministic proof of the last-attacker credit path. P0 is placed just
    // inside the rim with P1 right behind it (further out, EXPOSED — not braced).
    // P0 lunges outward THROUGH P1: the momentum transfer launches P1 off the
    // ring and P0 banks a credited +1. (P0 itself stays inside — it is the body
    // nearer the centre.) This isolates the credit rule from chaotic bot play.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(1),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    g.update(1 / 60);
    final c = g.debugCenter;
    final ring = g.debugRingRadius;
    // P1 sits near the rim (the victim to be ejected outward); P0 starts a clear
    // gap inside it (NOT pre-touching, so the lunge makes a fresh contact rather
    // than a debounced one) and lunges east through P1, on toward the rim.
    g.debugPlace(1, c.translate(ring * 0.88, 0));
    g.debugPlace(0, c.translate(ring * 0.50, 0));
    g.update(1 / 60);
    expect(g.debugScoreOf(0), 0, reason: 'precondition: P0 has not scored yet');
    g.debugLungeToward(0, 0); // lunge east, into P1 and on toward the rim

    var p0Scored = false;
    for (var i = 0; i < 90 && !p0Scored; i++) {
      g.update(1 / 60);
      if (g.debugScoreOf(0) >= 1) p0Scored = true;
    }
    expect(p0Scored, isTrue,
        reason: 'launching an exposed foe off the rim did not credit a KO '
            '(P0 score=${g.debugScoreOf(0)})');
  });

  test('tap and hold inputs never throw and the round still resolves', () {
    final players = [
      for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: i != 0),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(3),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // Quick TAP (down+up same window): a LUNGE at the nearest rival.
      if (n % 20 == 0) {
        expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
        expect(
          () => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      // HOLD with a drag (down → hold ticks → up): a BRACE that re-aims, then
      // unplants on release (fires nothing).
      final h = n % 37;
      if (h == 0) {
        expect(
          () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.85))),
          returnsNormally,
        );
      } else if (h >= 1 && h <= 18) {
        expect(
          () => g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.holdTick,
              normPos: Offset(0.9, 0.55),
            ),
          ),
          returnsNormally,
        );
      } else if (h == 20) {
        expect(
          () => g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.up,
              normPos: Offset(0.9, 0.55),
            ),
          ),
          returnsNormally,
        );
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2});
  });

  test('LUNGE PATH: a sustained tap-lunge cycle resolves a 1v1 with a full '
      'ranking and never throws', () {
    // P0 (human) presses + releases within the brace threshold (a TAP → LUNGE)
    // every ~0.43s across the whole round. The lunge path must accept this
    // sustained input without throwing and the match must converge to a full
    // ranking.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(9),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // TAP cycle: down on one frame, up ~2 frames later (well under the 0.16s
      // brace threshold) → a clean lunge each cycle.
      final phase = n % 26;
      if (phase == 0) {
        expect(
          () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
          returnsNormally,
        );
      } else if (phase == 2) {
        expect(
          () => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('BRACE PATH: a sustained hold-brace cycle resolves a 1v1 with a full '
      'ranking and never throws', () {
    // P0 holds a BRACE (down, many hold-ticks past the threshold, up) every
    // cycle. A brace release fires nothing — the contract must accept this and
    // still resolve a full ranking (the bot supplies the action).
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(15),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      final phase = n % 40;
      if (phase == 0) {
        expect(
          () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
          returnsNormally,
        );
      } else if (phase < 30) {
        // Per-frame hold-ticks (no position) keep the press alive → BRACE.
        expect(
          () => g.onInput(
            const PlayerInput(playerId: 0, phase: InputPhase.holdTick),
          ),
          returnsNormally,
        );
      } else if (phase == 30) {
        expect(
          () => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('render does not throw before or after finish', () {
    final g = SumoSmash()
      ..init(
        MiniGameContext(
          players: [
            for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true),
          ],
          arena: const Size(900, 1400),
          rng: SeededRng(3),
          zones: ZoneLayout.forPlayers(4),
        ),
      );
    final rec = PictureRecorder();
    const size = Size(900, 1400);
    final canvas = Canvas(rec, Offset.zero & size);
    expect(() => g.render(canvas, size), returnsNormally);
    for (var i = 0; i < 60 * 80 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, size), returnsNormally);
  });

  test('RENDER ACROSS STATES: brace / stun / lunge visuals never throw for '
      '1..4 players', () {
    // Drive players into contrasting control states (lunge, brace) and render
    // mid-action so the new BRACE shield, STUN stars and lunge trail all
    // exercise their draw paths without throwing, at every supported count.
    for (final count in const [1, 2, 3, 4]) {
      final players = [for (var i = 0; i < count; i++) PlayerSlot.defaults(i)];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(820, 1300),
        rng: SeededRng(40 + count),
        zones: ZoneLayout.forPlayers(count),
      );
      final g = SumoSmash()..init(ctx);
      final rec = PictureRecorder();
      const size = Size(820, 1300);
      final canvas = Canvas(rec, Offset.zero & size);
      for (var i = 0; i < 60 * 6; i++) {
        // Even ids brace, odd ids lunge — so a brace/stun/launch all occur.
        for (var id = 0; id < count; id++) {
          if (g.debugCanAct(id)) {
            if (id.isEven) {
              g.debugForceBrace(id, holdSec: 0.3);
            } else {
              g.debugForceLunge(id);
            }
          }
        }
        g.update(1 / 60);
        expect(() => g.render(canvas, size), returnsNormally,
            reason: '$count players render threw mid-action');
      }
    }
  });

  test('PACING: an all-bot round plays the full brawl (a real minimum, never '
      'instant) and resolves on the time limit', () {
    for (final seed in const [1, 7, 13, 21, 99]) {
      final (g, frames) = _runCounted(4, seed);
      final seconds = frames / 60;
      expect(
        seconds,
        greaterThan(8.0),
        reason: 'seed $seed ended too fast (${seconds.toStringAsFixed(2)}s)',
      );
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(
        frames,
        lessThan(60 * 32),
        reason: 'seed $seed overran (${seconds.toStringAsFixed(1)}s)',
      );
    }
  });

  // ── The READ: brace repels + stuns a lunge; a braced foe holds ──────────────

  test('THE READ: lunging into a BRACED foe STUNS the lunger and the braced '
      'foe barely moves', () {
    // A direct, deterministic check of the core mechanic. P1 plants a long
    // BRACE; P0 lunges at it repeatedly (closing the gap over a couple of dashes,
    // as real combat does). The first lunge that CONNECTS must STUN the lunger
    // (P0); the braced foe (P1) must hold roughly its ground (never launched off).
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(2),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    g.update(1 / 60); // settle one frame
    final bracedStart = g.debugDistFromCenter(1);

    var sawStun = false;
    var bracedMaxDrift = 0.0;
    for (var i = 0; i < 60 * 4; i++) {
      // Keep P1 planted in a fresh long brace whenever its forced brace lapses.
      if (!g.debugIsBracing(1) && g.debugCanAct(1)) {
        g.debugForceBrace(1, holdSec: 1.0);
      }
      // P0 lunges at the braced foe whenever it can act (it will close in).
      if (g.debugCanAct(0)) g.debugForceLunge(0);
      g.update(1 / 60);
      if (g.debugIsStunned(0)) sawStun = true;
      bracedMaxDrift =
          bracedMaxDrift > (g.debugDistFromCenter(1) - bracedStart).abs()
              ? bracedMaxDrift
              : (g.debugDistFromCenter(1) - bracedStart).abs();
      if (sawStun) break;
    }
    expect(sawStun, isTrue,
        reason: 'a lunge into a brace never stunned the lunger');
    expect(bracedMaxDrift, lessThan(g.debugRingRadius * 0.5),
        reason: 'braced foe was launched (drift $bracedMaxDrift)');
  });

  // ── DESIGN LAW: button-spam (blind lunging) must LOSE to measured play ──────

  test('SPAM LOSES: a blind every-lunge masher finishes BELOW a measured '
      'brace-then-counter player — fewer KOs and more self-rings on the rim, '
      'across seeds and regardless of spawn slot', () {
    // The headline guarantee of the rework, in a clean 1v1 (no bots) so the only
    // variable is HOW each plays. The blind masher lunges forever; the measured
    // player holds a central brace wall and counters the stunned masher. For
    // EVERY trial the masher must never OUT-SCORE the measured player (it may at
    // most tie on a quiet seed); ACROSS trials the measured player must STRICTLY
    // bank more total ring-outs, win the KO race in the clear majority, and the
    // masher must self-ring far more (it is flung off the rim after each rebound).
    var skilledScoreTotal = 0.0;
    var blindScoreTotal = 0.0;
    var blindSelfTotal = 0;
    var skilledSelfTotal = 0;
    var skilledStrictWins = 0;
    var trials = 0;
    for (final seed in const [1, 7, 13, 21, 99]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g =
            _blindVsMeasured(seed, blindId: blindId, skilledId: skilledId);
        expect(g.status, MiniGameStatus.finished);

        final blindScore = g.debugScoreOf(blindId);
        final skilledScore = g.debugScoreOf(skilledId);

        // Per trial the LAW: a blind masher can NEVER out-score measured play
        // (skill is at least as good every time — usually strictly better).
        expect(
          skilledScore,
          greaterThanOrEqualTo(blindScore),
          reason: 'seed $seed swap=$swap: blind masher OUT-SCORED measured '
              '($blindScore > $skilledScore)',
        );

        skilledScoreTotal += skilledScore;
        blindScoreTotal += blindScore;
        blindSelfTotal += g.debugSelfRingsOf(blindId);
        skilledSelfTotal += g.debugSelfRingsOf(skilledId);
        if (skilledScore > blindScore) skilledStrictWins++;
        trials++;
      }
    }
    // ACROSS seeds the measured player STRICTLY dominates: more total ring-outs…
    expect(
      skilledScoreTotal,
      greaterThan(blindScoreTotal),
      reason: 'measured total ($skilledScoreTotal) did not beat the masher '
          'total ($blindScoreTotal) — button-spam is competitive!',
    );
    // …and out-scores the masher in the clear majority of individual trials…
    expect(
      skilledStrictWins * 2,
      greaterThan(trials),
      reason: 'measured out-scored the masher in only $skilledStrictWins of '
          '$trials trials',
    );
    // …and the masher pays the recovery/stun tax by self-ringing far more often.
    expect(
      blindSelfTotal,
      greaterThan(skilledSelfTotal),
      reason: 'blind masher self-rang $blindSelfTotal vs measured '
          '$skilledSelfTotal — the recovery/stun punishment is not biting',
    );
  });

  test('SPAM NEVER OUT-SCORES: a blind masher never finishes with a higher '
      'score than a measured player, across many seeds and spawn slots', () {
    // The robust corollary across a wide seed sweep: whatever the seed, blind
    // mashing can never beat measured play on the scoreboard. (A rare exact tie
    // is allowed — the masher simply cannot come out ahead.)
    for (final seed in const [1, 7, 13, 21, 99, 123, 256, 512, 1024]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g =
            _blindVsMeasured(seed, blindId: blindId, skilledId: skilledId);
        expect(
          g.debugScoreOf(skilledId),
          greaterThanOrEqualTo(g.debugScoreOf(blindId)),
          reason: 'seed $seed swap=$swap: a blind masher out-scored measured',
        );
      }
    }
  });

  group('StarController (chaos pickup)', () {
    StarController build() => StarController(
      radius: 12,
      firstSpawnSec: 2.0,
      respawnSec: 5.0,
      lifeSec: 4.0,
      appearPerSec: 3.0,
      spinPerSec: 3.0,
      spawnSpreadFactor: 0.4,
    );

    test(
      'spawns only after the first-spawn delay and only with >= 2 alive',
      () {
        final c = build();
        final rng = SeededRng(1);
        const center = Offset(400, 600);
        for (var i = 0; i < 200; i++) {
          c.tick(1 / 60, 1, rng, center, 300);
        }
        expect(c.star, isNull, reason: 'solo round stays calm');
        for (var i = 0; i < 60 * 3; i++) {
          c.tick(1 / 60, 2, rng, center, 300);
        }
        expect(c.star, isNotNull);
        expect(
          (c.star!.pos - center).distance,
          lessThanOrEqualTo(300 * 0.4 + 1),
        );
      },
    );

    test('star eases in then despawns if untouched, re-arming the timer', () {
      final c = build();
      final rng = SeededRng(2);
      const center = Offset(400, 600);
      for (var i = 0; i < 60 * 3; i++) {
        c.tick(1 / 60, 2, rng, center, 300);
      }
      final star = c.star;
      expect(star, isNotNull);
      expect(star!.ready, isTrue, reason: 'appear eased to full over ~3s');
      for (var i = 0; i < 60 * 5; i++) {
        c.tick(1 / 60, 2, rng, center, 300);
      }
      expect(c.star == null || !identical(c.star, star), isTrue);
    });

    test('consume clears the live star', () {
      final c = build();
      final rng = SeededRng(3);
      for (var i = 0; i < 60 * 3; i++) {
        c.tick(1 / 60, 2, rng, const Offset(400, 600), 300);
      }
      expect(c.star, isNotNull);
      c.consume();
      expect(c.star, isNull);
    });
  });
}
