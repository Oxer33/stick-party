import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
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
      'ANTI-SPAM: reading the crossings beats blind flailing (and eats far fewer '
      'bombs)', () {
    // The design law: button-spam / no-skill play MUST LOSE. We pit two HUMANS in
    // a fair 2-lane split (no bots, identical angled-crossing ramp per lane, same
    // seed) across several seeds, differing ONLY in input strategy:
    //   * Player 0 INTERCEPTS: each frame it slides to where the next STAR will
    //     CROSS the catch line and bails late off a converging bomb — reading the
    //     crossing, the entire new skill.
    //   * Player 1 FLAILS: it ignores every item and sweeps its basket back and
    //     forth blindly (the "spam" play), so a star is caught only by coincidence
    //     AND it routinely drifts under the converging crossing bombs.
    // For EVERY seed the intercepter must win by a clear margin, and — the proof
    // the crossings are a real read — the flailer must eat STRICTLY MORE bombs
    // than the intercepter (and several of them), so success cannot be accidental.
    for (final seed in [7, 1, 21, 42, 99]) {
      final g = CatchTheStar()
        ..init(MiniGameContext(
          players: [
            PlayerSlot.defaults(0), // human intercepter
            PlayerSlot.defaults(1), // human flailer
          ],
          arena: const Size(800, 1200),
          rng: SeededRng(seed),
          zones: ZoneLayout.forPlayers(2),
        ));

      var frames = 0;
      var flailerBombHits = 0;
      var trackerBombHits = 0;
      num flailerPrev = 0;
      num trackerPrev = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(1 / 60);
        _trackStarsDodgeBombs(g, 0); // P0: read + intercept
        _flailBlindly(g, 1, frames); // P1: blind spam sweep
        // A score DROP means that player just ate a bomb (penalty).
        final fNow = g.scores.of(1);
        if (fNow < flailerPrev) flailerBombHits++;
        flailerPrev = fNow;
        final tNow = g.scores.of(0);
        if (tNow < trackerPrev) trackerBombHits++;
        trackerPrev = tNow;
      }

      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      final tracker = g.scores.of(0);
      final flailer = g.scores.of(1);
      expect(tracker, greaterThan(flailer),
          reason: 'seed=$seed: reading the crossings ($tracker) must beat blind '
              'flailing ($flailer)');
      // A comfortable margin so it is skill, not noise.
      expect(tracker, greaterThanOrEqualTo(flailer + 4),
          reason: 'seed=$seed: the intercepter must win by a clear margin');
      // The flailer is the one the crossings punish: it must eat several bombs…
      expect(flailerBombHits, greaterThanOrEqualTo(3),
          reason: 'seed=$seed: a flailer that ignores the crossings must eat '
              'several bombs');
      // …and STRICTLY more than the player who actually reads the crossing.
      expect(trackerBombHits, lessThan(flailerBombHits),
          reason: 'seed=$seed: reading the crossing ($trackerBombHits) must eat '
              'fewer bombs than flailing ($flailerBombHits)');
      // The winner is the intercepter.
      expect(g.winResult!.ranking.first, 0,
          reason: 'seed=$seed: the skilled player must win the round');
    }
  });

  test(
      'COMPETITIVE: skill gradient + beatable-but-tough hard bot (1v1, 12 seeds)',
      () {
    // The rework PROVES spam loses; this PROVES it is competitively BALANCED.
    // A SKILLED human-sim (the deliberate intercepter, _trackStarsDodgeBombs)
    // sits in seat 0 and plays a clean 1v1 against ONE bot in seat 1, for each
    // difficulty via BotProfile.forDifficulty(d). We measure seat-0 win-rate and
    // per-seed score margins over a fixed 12-seed set and require:
    //   * EASY clearly beatable (a kid wins most of the time),
    //   * HARD beatable-but-tough (neither an unwinnable wall nor a pushover),
    //   * a real difficulty GRADIENT (winEasy >= winMed >= winHard, easy > hard),
    //   * the easy result is reliable (skill, not luck),
    //   * and HARD outcomes VARY across seeds (no single fixed blowout).
    // 1v1 is used for a clean head-to-head read (a 4p win-rate measures
    // "beat the best of three independent bots", which muddies the gradient).
    const seeds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

    final easy = _skilledVsBot1v1(BotDifficulty.easy, seeds);
    final medium = _skilledVsBot1v1(BotDifficulty.medium, seeds);
    final hard = _skilledVsBot1v1(BotDifficulty.hard, seeds);

    final n = seeds.length;
    final winEasy = easy.wins / n;
    final winMedium = medium.wins / n;
    final winHard = hard.wins / n;

    // EASY clearly beatable: the skilled player wins the large majority.
    expect(winEasy, greaterThanOrEqualTo(0.70),
        reason: 'easy bot must be clearly beatable (win-rate $winEasy)');

    // HARD beatable-but-tough: not a wall (>0) and not a trivial pushover (<1).
    expect(winHard, greaterThanOrEqualTo(0.15),
        reason: 'hard bot must not be an unwinnable wall (win-rate $winHard)');
    expect(winHard, lessThanOrEqualTo(0.90),
        reason: 'hard bot must not be a trivial pushover (win-rate $winHard)');

    // GRADIENT: difficulty must matter, monotonically, with a real spread.
    expect(winEasy, greaterThanOrEqualTo(winMedium),
        reason: 'easy ($winEasy) must be >= medium ($winMedium)');
    expect(winMedium, greaterThanOrEqualTo(winHard),
        reason: 'medium ($winMedium) must be >= hard ($winHard)');
    expect(winEasy, greaterThan(winHard),
        reason: 'difficulty must matter: easy ($winEasy) > hard ($winHard)');

    // NOT luck-dominated: vs easy, the skilled player wins RELIABLY — most seeds,
    // and on average by a clear positive score margin.
    expect(easy.wins, greaterThanOrEqualTo((n * 0.7).ceil()),
        reason: 'easy wins must be reliable across seeds (${easy.wins}/$n)');
    final easyAvgMargin =
        easy.margins.fold<num>(0, (a, b) => a + b) / easy.margins.length;
    expect(easyAvgMargin, greaterThan(0),
        reason: 'skilled play must beat easy by a positive avg margin');

    // NO runaway: HARD outcomes must VARY across seeds — there must exist BOTH a
    // seed the skilled player clearly WINS and a seed it clearly LOSES, so it is
    // a genuine contest rather than one repeated fixed blowout.
    expect(hard.margins.any((m) => m >= 5), isTrue,
        reason: 'vs hard, some seed must be a clear skilled WIN (margin >= +5)');
    expect(hard.margins.any((m) => m <= -5), isTrue,
        reason: 'vs hard, some seed must be a clear skilled LOSS (margin <= -5)');
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

/// Skilled play for [id]: READ THE CROSSING and INTERCEPT. Each frame it steers
/// the basket toward where the next STAR will cross the catch line (its intercept
/// x, not its spawn x — paths are angled). When a converging BOMB's intercept is
/// about to arrive over the basket and the star is not the nearer thing, it BAILS
/// off the bomb — the "commit early, bail late" thread the rework demands. Fed
/// every frame so the inertial basket eases onto the target. Uses only the
/// test-only INTERCEPT views — deterministic, not luck.
void _trackStarsDodgeBombs(CatchTheStar g, int id) {
  final lineY = g.catchLineYForTest(id);
  if (lineY == null) return;
  final starX = g.nextStarXForTest(id); // intercept x of the next star
  final bombX = g.nextBombXForTest(id); // intercept x of the next bomb
  final basket = g.basketXForTest(id) ?? 0.5;

  // Catch range (basket half-mouth + item half-width); a bomb intercept within
  // this of the basket would be SCOOPED, so it must be avoided.
  const danger = 0.16;

  // A converging bomb's intercept is sitting on the basket and the star is NOT
  // the nearer target → bail late off the bomb (the read that threads the cross).
  final bombOnBasket = bombX != null && (bombX - basket).abs() < danger;
  final starNearer = starX != null &&
      bombX != null &&
      (starX - basket).abs() <= (bombX - basket).abs();
  if (bombOnBasket && !starNearer) {
    final dodge = bombX < 0.5 ? bombX + 0.26 : bombX - 0.26;
    g.onInput(PlayerInput.down(id, Offset(dodge.clamp(0.02, 0.98), lineY)));
    return;
  }
  // Commit to the next STAR's intercept — the core interception skill — BUT a
  // responsive glide basket would sweep THROUGH a bomb sitting between it and a
  // far star. A real reader does not barrel across a live bomb: if the bomb's
  // intercept lies in the path to the star (and the star is not already in hand),
  // stop short on the near side of the bomb and let the bomb cross first.
  if (starX != null) {
    if (bombX != null) {
      final bombInPath = (bombX - basket).sign == (starX - basket).sign &&
          (bombX - basket).abs() < (starX - basket).abs() &&
          (bombX - basket).abs() < 0.45; // only a bomb genuinely on the way
      final starInHand = (starX - basket).abs() < danger;
      if (bombInPath && !starInHand) {
        // Halt on the near side of the bomb until it has crossed; do not transit.
        final hold = bombX > basket ? bombX - danger * 1.25 : bombX + danger * 1.25;
        g.onInput(PlayerInput.down(id, Offset(hold.clamp(0.02, 0.98), lineY)));
        return;
      }
    }
    g.onInput(PlayerInput.down(id, Offset(starX, lineY)));
    return;
  }
  // No star to chase: if a bomb's intercept sits under the basket, step aside.
  if (bombX != null && (bombX - basket).abs() < danger) {
    final dodge = bombX < 0.5 ? bombX + 0.24 : bombX - 0.24;
    g.onInput(PlayerInput.down(id, Offset(dodge.clamp(0.02, 0.98), lineY)));
    return;
  }
  // Nothing falling: hold under the basket's current x (still no luck involved).
  g.onInput(PlayerInput.down(id, Offset(basket, lineY)));
}

/// Aggregate outcome of a skilled-vs-bot sweep across seeds: how many seeds the
/// skilled seat-0 won and the per-seed score margin (seat0 - bot).
class _DuelStats {
  final int wins;
  final List<num> margins;
  const _DuelStats(this.wins, this.margins);
}

/// Run a clean 1v1 for every [seed]: SKILLED human-sim in seat 0 (the deliberate
/// intercepter, [_trackStarsDodgeBombs]) vs ONE bot in seat 1 at difficulty [d]
/// (which sets [MiniGameContext.botProfile] via BotProfile.forDifficulty). Both
/// lanes are fed the SAME calibrated angled-crossing ramp from the same seeded
/// rng, so the only edge is skill. Returns seat-0 wins + per-seed margins.
_DuelStats _skilledVsBot1v1(BotDifficulty d, List<int> seeds) {
  var wins = 0;
  final margins = <num>[];
  for (final seed in seeds) {
    final g = CatchTheStar()
      ..init(MiniGameContext(
        players: [
          PlayerSlot.defaults(0), // skilled human
          PlayerSlot.defaults(1, isBot: true), // bot at difficulty d
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
        difficulty: d,
      ));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      g.update(1 / 60);
      _trackStarsDodgeBombs(g, 0); // seat 0 reads + intercepts every frame
    }
    final me = g.scores.of(0);
    final bot = g.scores.of(1);
    if (me > bot) wins++;
    margins.add(me - bot);
  }
  return _DuelStats(wins, margins);
}

/// Blind "spam" play for [id]: ignore every item and just sweep the basket back
/// and forth across the lane on a fixed sinusoid, so any star caught is pure
/// coincidence and bombs are walked into. The full-screen x maps onto the lane.
void _flailBlindly(CatchTheStar g, int id, int frame) {
  final t = frame / 60.0;
  final x = 0.5 + 0.45 * math.sin(t * 9.0);
  g.onInput(PlayerInput.down(id, Offset(x, 0.75)));
}
