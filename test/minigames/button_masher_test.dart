import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/button_masher/button_masher.dart';

void main() {
  MiniGameContext soloCtx(int seed) => MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      );

  /// Run a solo round to the finish, calling [tapOnFrame] once per frame; when it
  /// returns true a single tap is delivered that frame. Deterministic (fixed dt).
  ButtonMasher runSolo(int seed, bool Function(int frame) tapOnFrame) {
    final g = ButtonMasher()..init(soloCtx(seed));
    var f = 0;
    while (g.status != MiniGameStatus.finished && f++ < 60 * 80) {
      if (tapOnFrame(f)) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }
    return g;
  }

  test('finishes with a full ranking inside the pacing bounds (4 bots)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ButtonMasher()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});

    // Sim-length floor + ceiling: the all-bot round must outlast the bot warmup
    // and still resolve inside the (~10s) hard time limit.
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.5));
    expect(simSeconds, lessThanOrEqualTo(11.0));
  });

  test('score tracks puck HEIGHT, not raw tap count', () {
    // A wild masher slams the button every single frame for the whole 10s round
    // (≈600 taps). Under the old "score == tapCount" model that would be a huge
    // score; under the heat/height model the gauge pegs into the RED overheat
    // zone so taps stall and the puck slides back down — the height (and thus the
    // score) stays modest, far below the raw tap count and capped by the
    // height→score scale.
    final spam = runSolo(5, (f) => true);
    final spamScore = spam.scores.of(0);

    expect(spam.status, MiniGameStatus.finished);
    // Not zero — even an overheated tower creeps up a little.
    expect(spamScore, greaterThan(0));
    // Height-based: score is height(0..1) × the scale, so it can never approach
    // the ~600 taps an every-frame masher produced (the old count-score would).
    expect(spamScore, lessThan(600),
        reason: 'a ~600-tap spam must NOT score ~600 — score is height, not taps');

    // An idle player (never taps) never climbs, so it scores nothing.
    final idle = runSolo(5, (f) => false);
    expect(idle.scores.of(0), 0);
  });

  test('steady in-band tapping out-climbs spamming into the redline', () {
    // Steady player: a measured cadence (~5 taps/sec) keeps heat hovering in the
    // GREEN sweet-zone band, so most taps land a full-strength puck kick.
    final steady = runSolo(5, (f) => f % 12 == 0);
    // Spam player: hammering every frame pegs heat into the RED overheat zone,
    // where taps give almost nothing and the puck actively drops.
    final spam = runSolo(5, (f) => true);

    expect(steady.status, MiniGameStatus.finished);
    expect(spam.status, MiniGameStatus.finished);

    // The whole DECISION: easing into the green out-climbs a flat-out mash.
    expect(steady.scores.of(0), greaterThan(spam.scores.of(0)),
        reason: 'a steady in-band player must out-climb a redline masher');
  });

  test('a human tap registers and bots remain competitive climbers', () {
    final players = [
      PlayerSlot.defaults(0), // human
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ButtonMasher()..init(ctx);

    // Human eases into the green with a measured cadence over the round.
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 12 == 0) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    // The bot rode its tower the whole round, so it climbed to a real height.
    expect(g.scores.of(1), greaterThan(0));
  });

  test('render never throws across the round', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(11),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ButtonMasher()..init(ctx);
    final canvas = Canvas(PictureRecorder());

    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    for (var i = 0; i < 300 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0));
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}
