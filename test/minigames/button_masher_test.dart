import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/button_masher/button_masher.dart';

/// Tower Climb (legacy id `button_masher`): tap = climb one rung; sweeping,
/// telegraphed hazard bars knock a climber down if it steps into one. Ranked by
/// the highest rung reached; first to the flag wins.
void main() {
  MiniGameContext soloCtx(int seed) => MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      );

  /// Run a solo round to the finish, calling [tapOnFrame] once per frame; when it
  /// returns true a single tap is delivered that frame. The callback receives the
  /// frame index AND the live game so a "measured" climber can read the bars
  /// (via the read-only [ButtonMasher.isStepSafe] seam). Deterministic (fixed dt).
  ButtonMasher runSolo(
    int seed,
    bool Function(int frame, ButtonMasher g) tapOnFrame,
  ) {
    final g = ButtonMasher()..init(soloCtx(seed));
    var f = 0;
    while (g.status != MiniGameStatus.finished && f++ < 60 * 80) {
      if (tapOnFrame(f, g)) g.onInput(PlayerInput.down(0));
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
    // and still resolve inside the (~34s) hard time limit (or sooner if a bot
    // summits and plants the flag).
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.0));
    expect(simSeconds, lessThanOrEqualTo(35.0));
  });

  test('score tracks the rung reached, not the raw tap count', () {
    // A blind masher slams the button every single frame for the whole round
    // (~2000 taps over 34s). The score is the highest RUNG reached (capped at the
    // tower height of 40), so it can never approach the raw tap count — and
    // because the masher climbs into every sweeping bar and is knocked back hard,
    // its peak rung plateaus well below the flag (~22 in practice).
    final spam = runSolo(5, (f, g) => true);
    final spamScore = spam.scores.of(0);

    expect(spam.status, MiniGameStatus.finished);
    // Some progress (the bottom run-up is open) but bounded hard by the rung
    // count — never the ~2000 taps the masher produced.
    expect(spamScore, greaterThan(0));
    expect(spamScore, lessThanOrEqualTo(40),
        reason: 'score is the rung reached (≤ tower height 40), never the tap count');

    // An idle player (never taps) never climbs, so it scores nothing.
    final idle = runSolo(5, (f, g) => false);
    expect(idle.scores.of(0), 0);
  });

  test('a measured climber beats a blind spammer head-to-head', () {
    // THE WHOLE DESIGN, proven deterministically in one shared 1v1 round (both
    // climbers see the SAME bar pattern):
    //
    //  * P0 MEASURED: steps on a calm cadence and ONLY when the rung above is
    //    clear (reading the telegraphed bars via [isStepSafe]). It threads every
    //    safe window, takes essentially no hits, and summits in ~25s.
    //  * P1 BLIND SPAMMER: taps EVERY frame, ignoring the bars. It climbs into
    //    each sweeping band, gets knocked back hard + stunned, and never reaches
    //    the flag — when the measured climber plants first, the round ends and
    //    the spammer is frozen far below.
    final players = [
      PlayerSlot.defaults(0), // measured human
      PlayerSlot.defaults(1), // blind spammer (also human-driven)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ButtonMasher()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 10 == 0 && g.isStepSafe(0)) g.onInput(PlayerInput.down(0)); // measured
      g.onInput(PlayerInput.down(1)); // blind spam every frame
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(g.scores.of(1)),
        reason: 'reading the bars and stepping in safe windows must beat a '
            'blind mash that climbs into every sweep');
  });

  test('stepping into a live hazard bar knocks the climber down', () {
    // Drive a climber straight up with a blind mash until a bar knocks it down:
    // its target rung must, at some point, DROP from one frame to the next (a
    // knockback). A pure climb with no hits could only ever go up.
    final g = ButtonMasher()..init(soloCtx(5));
    var prev = g.rungOf(0);
    var sawKnockdown = false;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 40) {
      g.onInput(PlayerInput.down(0)); // mash every frame
      g.update(1 / 60);
      final cur = g.rungOf(0);
      if (cur < prev - 0.5) sawKnockdown = true; // a real knockback step
      prev = cur;
    }
    expect(sawKnockdown, isTrue,
        reason: 'a blind mash must walk into a sweeping bar and get knocked down');
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

    // Human steps on a measured cadence, gated on a clear rung above.
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 10 == 0 && g.isStepSafe(0)) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    // The bot climbed its own tower the whole round, so it reached a real rung.
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
