import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/catch_the_star/catch_the_star.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  void runToEnd(CatchTheStar g) {
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
  }

  test('four bots finish with a full ranking', () {
    final g = CatchTheStar()..init(ctxFor(4, 7));
    runToEnd(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot 4p round lasts >1.5s and finishes within the time limit', () {
    // Guards a regression that would end the round early or never. The round is a
    // ~32s sprint (or an early finish once a bot hits the target), so we assert it
    // spans (1.5s, 33s].
    const dt = 1 / 60;
    for (final seed in [1, 2, 3, 7, 21]) {
      final g = CatchTheStar()..init(ctxFor(4, seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5), reason: 'seed=$seed ended too fast');
      expect(frames * dt, lessThanOrEqualTo(33.0),
          reason: 'seed=$seed exceeded the time limit');
    }
  });

  test('finishes for 1..3 players', () {
    for (final n in [1, 2, 3]) {
      final g = CatchTheStar()..init(ctxFor(n, 13 + n));
      runToEnd(g);
      expect(g.status, MiniGameStatus.finished, reason: 'n=$n');
      expect(g.winResult!.ranking.toSet(), {for (var p = 0; p < n; p++) p});
    }
  });

  test('bots catch stars and accumulate a score over a full round', () {
    // Bots steer their basket under the nearest star (and dodge bombs); over a
    // full round the field should bank at least some points.
    final g = CatchTheStar()..init(ctxFor(4, 21));
    runToEnd(g);
    final total = [for (var p = 0; p < 4; p++) g.scores.of(p)]
        .fold<num>(0, (a, b) => a + b);
    expect(total, greaterThan(0));
  });

  test('a human who positions the basket under stars (and dodges bombs) scores',
      () {
    // The core new mechanic: catching is PURE OVERLAP at the catch line. A solo
    // human who slides the basket under each descending STAR — and slides off any
    // descending BOMB — must bank catches. Uses the test-only star/bomb x views so
    // the positioning is deterministic, not luck.
    final g = CatchTheStar()..init(ctxFor(1, 7));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      _trackStarsDodgeBombs(g, 0);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(0),
        reason: 'positioning under stars must land catches');
  });

  test(
      'ANTI-SPAM: a tracking player outscores a static/flailing one who eats bombs',
      () {
    // The design law: button-spam / no-skill play MUST LOSE. We pit two HUMANS in
    // a fair 2-lane split (no bots, identical falling-field ramp per lane, same
    // seed) and differ ONLY in input strategy:
    //   * Player 0 TRACKS: each frame it slides under the nearest STAR and slides
    //     OFF any imminent bomb — deliberate reading + positioning.
    //   * Player 1 FLAILS: it ignores every item and just sweeps its basket back
    //     and forth blindly (the "spam" play), so it catches stars only by random
    //     coincidence AND blunders under bombs.
    // The tracker must win clearly, and the flailer must even eat bombs — proving
    // success requires skill and cannot happen by accident.
    final g = CatchTheStar()
      ..init(MiniGameContext(
        players: [
          PlayerSlot.defaults(0), // human tracker
          PlayerSlot.defaults(1), // human flailer
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(7),
        zones: ZoneLayout.forPlayers(2),
      ));

    var frames = 0;
    var flailerBombHits = 0;
    num flailerPrev = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      g.update(1 / 60);
      _trackStarsDodgeBombs(g, 0); // P0: deliberate skill
      _flailBlindly(g, 1, frames); // P1: blind spam sweep
      // Count frames where the flailer's score DROPS — i.e. it just ate a bomb.
      final now = g.scores.of(1);
      if (now < flailerPrev) flailerBombHits++;
      flailerPrev = now;
    }

    expect(g.status, MiniGameStatus.finished);
    final tracker = g.scores.of(0);
    final flailer = g.scores.of(1);
    expect(tracker, greaterThan(flailer),
        reason: 'reading + positioning ($tracker) must beat blind flailing '
            '($flailer)');
    // A comfortable margin so it is skill, not noise.
    expect(tracker, greaterThanOrEqualTo(flailer + 3),
        reason: 'the tracker must win by a clear margin');
    // The flailer must actually be punished by bombs at least once — proof the
    // bombs interpose and that ignoring positioning costs you.
    expect(flailerBombHits, greaterThan(0),
        reason: 'a flailing player who ignores bombs must eat at least one');
    // The winner is the tracker.
    expect(g.winResult!.ranking.first, 0,
        reason: 'the skilled player must win the round');
  });

  test('a basket stays clamped to its own lane even when dragged outside it', () {
    // Lanes confine each basket so nobody reaches into a rival's column. In a 2p
    // split player 0 owns the BOTTOM half but the basket only moves horizontally,
    // so the meaningful clamp is the x-range of its zone (full width here). We drag
    // player 0's basket far beyond the left/right edges every frame; its x must
    // never leave [0,1] and must stay inside its own zone bounds.
    final g = CatchTheStar()
      ..init(MiniGameContext(
        players: [
          PlayerSlot.defaults(0),
          PlayerSlot.defaults(1, isBot: true),
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(3),
        zones: ZoneLayout.forPlayers(2),
      ));
    final zone = ZoneLayout.forPlayers(2).forPlayer(0)!.normRect;

    Offset outsideAt(int f) {
      final t = f / 60.0;
      // Aim well beyond both horizontal edges, alternating.
      return Offset(-0.5 + 2.0 * (0.5 + 0.5 * math.sin(t * 7.0)), 0.75);
    }

    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, outsideAt(frames)));
      final x = g.basketXForTest(0)!;
      expect(x, inInclusiveRange(0.0, 1.0),
          reason: 'basket left the board at frame $frames');
      expect(x, greaterThanOrEqualTo(zone.left),
          reason: 'basket crossed the left lane wall at frame $frames');
      expect(x, lessThanOrEqualTo(zone.right),
          reason: 'basket crossed the right lane wall at frame $frames');
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('render does not throw', () {
    final g = CatchTheStar()..init(ctxFor(3, 4));
    final canvas = Canvas(PictureRecorder());
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    g.update(1 / 60);
    g.onInput(PlayerInput.down(0, const Offset(0.25, 0.75)));
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('BOMB STORM finish: the final window still scores (climax)', () {
    // CLIMAX mechanic. A solo human tracks stars + dodges bombs for the whole
    // round. We snapshot the score the moment the storm begins (the last 7s of the
    // 32s round) and require a meaningful gain across it — the finish is a live,
    // dodge-heavy storm rather than a dead tail. Tracking is deterministic via the
    // test-only views. (Solo so it never ends early on the target.)
    final g = CatchTheStar()..init(ctxFor(1, 7));
    var frames = 0;
    num scoreAtStormStart = -1;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      _trackStarsDodgeBombs(g, 0);
      // The storm is the last 7s of the 32s round → starts at ~25s.
      if (scoreAtStormStart < 0 && frames / 60.0 >= 25.0) {
        scoreAtStormStart = g.scores.of(0);
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(scoreAtStormStart, greaterThanOrEqualTo(0));
    expect(g.scores.of(0) - scoreAtStormStart, greaterThan(0),
        reason: 'the BOMB STORM must keep scoring to the very end');
  });

  test('finishes within the limit with constant blind tapping', () {
    // Blind input must not break termination: still a fixed ~32s sprint (or an
    // earlier target-reached finish, which only makes it shorter).
    final g = CatchTheStar()..init(ctxFor(4, 21));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      _flailBlindly(g, 0, frames);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(frames / 60.0, greaterThan(1.5));
    expect(frames / 60.0, lessThanOrEqualTo(33.0));
  });
}

/// Skilled play for [id]: slide the basket toward the nearest descending STAR;
/// if a bomb is the more imminent threat near the basket, slide OFF it instead.
/// Fed every frame so the inertial basket eases onto the target. Uses only the
/// test-only x views — deterministic, not luck.
void _trackStarsDodgeBombs(CatchTheStar g, int id) {
  final lineY = g.catchLineYForTest(id);
  if (lineY == null) return;
  final starX = g.nextStarXForTest(id);
  final bombX = g.nextBombXForTest(id);
  final basket = g.basketXForTest(id) ?? 0.5;

  // Pursue the next STAR first — chasing stars is the skill and naturally keeps
  // the basket mostly clear of bombs without thrashing between targets.
  if (starX != null) {
    g.onInput(PlayerInput.down(id, Offset(starX, lineY)));
    return;
  }
  // No star to chase: if a bomb sits under the basket, step aside.
  if (bombX != null && (bombX - basket).abs() < 0.14) {
    final dodge = bombX < 0.5 ? bombX + 0.24 : bombX - 0.24;
    g.onInput(PlayerInput.down(id, Offset(dodge.clamp(0.02, 0.98), lineY)));
    return;
  }
  // Nothing falling: hold under the basket's current x (still no luck involved).
  g.onInput(PlayerInput.down(id, Offset(basket, lineY)));
}

/// Blind "spam" play for [id]: ignore every item and just sweep the basket back
/// and forth across the lane on a fixed sinusoid, so any star caught is pure
/// coincidence and bombs are walked into. The full-screen x maps onto the lane.
void _flailBlindly(CatchTheStar g, int id, int frame) {
  final t = frame / 60.0;
  final x = 0.5 + 0.45 * math.sin(t * 9.0);
  g.onInput(PlayerInput.down(id, Offset(x, 0.75)));
}
