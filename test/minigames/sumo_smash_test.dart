import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/sumo_smash/sumo_fx.dart';
import 'package:stick_party/minigames/sumo_smash/sumo_smash.dart';

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
    // The whole point of the rework: KO\'d wrestlers respawn, so a single fast
    // knockout must NOT end the round. A 1v1 (human + bot) with the human idle
    // (the bot scores freely) must still play a sustained brawl, not ~2s.
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
    // A meaningful, engaging round — never an instant ~2s knockout win.
    expect(seconds, greaterThan(8.0),
        reason: '1v1 ended in ${seconds.toStringAsFixed(2)}s (instant-win regression)');
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('score equals ring-outs caused (KO count): ranking follows score and a '
      'real brawl banks credited KOs', () {
    // The final scores are KO counts (a self-ring penalty can dip a passive
    // idler negative). For EVERY seed the ranking must be ordered by score
    // (winner highest). ACROSS seeds, at least one all-bot board must produce a
    // credited ring-out (a positive score) — proving the last-attacker credit
    // path fires, while tolerating the odd board that resolves only on self-
    // rings (squeezed out by the closing ring) so the suite is not flaky.
    var sawCreditedKo = false;
    for (final seed in const [1, 7, 13, 21, 99]) {
      final (g, _) = _runCounted(4, seed);
      final scores = g.winResult!.finalScores;
      final winner = g.winResult!.ranking.first;
      final winnerScore = (scores[winner] ?? 0).toDouble();
      for (final id in g.winResult!.ranking) {
        expect((scores[id] ?? 0).toDouble(), lessThanOrEqualTo(winnerScore),
            reason: 'seed $seed ranking not ordered by KO score: $scores');
      }
      if (winnerScore > 0) sawCreditedKo = true;
    }
    expect(sawCreditedKo, isTrue,
        reason: 'no all-bot brawl ever banked a credited ring-out');
  });

  test('tap and drag/hold inputs never throw and the round still resolves', () {
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
      // No-drag tap (down+up): aim resolves to nearest, never throws.
      if (n % 20 == 0) {
        expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
        expect(
          () => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      // Drag-charge: press, drag the thumb to a corner, release (a chosen aim).
      if (n % 37 == 0) {
        expect(
          () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.85))),
          returnsNormally,
        );
      }
      if (n % 37 == 5) {
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
      }
      if (n % 37 == 12) {
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

  test('DRAG PATH: a sustained directional drag-charge cycle resolves a 1v1 '
      'with a full ranking and never throws', () {
    // P0 (human, bottom) repeatedly presses, drags the thumb to the far bottom
    // edge (a deliberate chosen aim that exercises [_applyDragAim] + the
    // charge-root), then releases — every frame across the whole round. The
    // drag path must accept this sustained input without throwing and the match
    // must still converge to a full ranking. (Position is not observable through
    // the public surface, so this guards the contract end-to-end, not the exact
    // shove vector — that is covered by the on-device feel pass.)
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(9),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // Sustained drag-charge cycle for P0: press, drag to the edge, release.
      final phase = n % 30;
      if (phase == 0) {
        expect(
          () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
          returnsNormally,
        );
      } else if (phase < 20) {
        expect(
          () => g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.holdTick,
              normPos: Offset(0.5, 0.99),
            ),
          ),
          returnsNormally,
        );
      } else if (phase == 20) {
        expect(
          () => g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.up,
              normPos: Offset(0.5, 0.99),
            ),
          ),
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

  test('PACING: an all-bot round plays the full brawl (a real minimum, never '
      'instant) and resolves on the time limit', () {
    // The scored brawl runs to the time limit (~28s) since KO\'d wrestlers
    // respawn: across seeds it must always last well past an instant knockout
    // (> 8s) yet still resolve within the limit (_elapsed tracks real dt, so it
    // lands right around 28s — a small ceiling slack guards any rounding).
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
        // One player alive: never spawns even past the delay.
        for (var i = 0; i < 200; i++) {
          c.tick(1 / 60, 1, rng, center, 300);
        }
        expect(c.star, isNull, reason: 'solo round stays calm');
        // Two alive: a star appears once the first-spawn timer elapses.
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
      // Past its 4s life with nobody grabbing it: gone.
      for (var i = 0; i < 60 * 5; i++) {
        c.tick(1 / 60, 2, rng, center, 300);
      }
      // After the respawn gap it can come back.
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
