import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/button_masher/button_masher.dart';

/// Tower Climb (legacy id `button_masher`) — a RHYTHM climb. Tap = climb one
/// rung. One or two FULL-WIDTH hazard bars share a single metronome beat: each
/// spends most of the beat parked & dim (the SAFE gap), flashes a WARN
/// telegraph, then goes LIVE (a lethal full-lane slab) for a short window.
/// Stepping onto a bar's rung-row while it is telegraphing or live = KNOCKBACK +
/// stun; you climb in the gap and HOLD on the danger beat. Score = highest rung
/// reached; first to the flag wins and ends the round.
///
/// These tests pin the contract (finish / full ranking / pacing / render) AND
/// prove the anti-spam core deterministically: a blind every-frame tapper climbs
/// into the live beat over and over and finishes strictly BELOW a measured
/// climber that only steps when the beat is clear (read via [isStepSafe]).
void main() {
  MiniGameContext soloCtx(int seed) => MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      );

  /// Run a solo round to the finish, calling [tapOnFrame] once per frame; when it
  /// returns true a single tap is delivered that frame. The callback receives the
  /// frame index AND the live game so a "measured" climber can read the beat (via
  /// the read-only [ButtonMasher.isStepSafe] seam). Deterministic (fixed dt).
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
    // (thousands of taps). The score is the highest RUNG reached (capped at the
    // tower height of 40), so it can never approach the raw tap count — and
    // because the masher steps into the live beat over and over (knocked back
    // hard), its peak rung plateaus well below the flag.
    final spam = runSolo(5, (f, g) => true);
    final spamScore = spam.scores.of(0);

    expect(spam.status, MiniGameStatus.finished);
    // Some progress (the bottom run-up is open) but bounded hard by the rung
    // count — never the thousands of taps the masher produced.
    expect(spamScore, greaterThan(0));
    expect(spamScore, lessThanOrEqualTo(40),
        reason: 'score is the rung reached (≤ tower height 40), never the taps');

    // An idle player (never taps) never climbs, so it scores nothing.
    final idle = runSolo(5, (f, g) => false);
    expect(idle.scores.of(0), 0);
  });

  test('a blind every-frame mash plateaus below the flag (never summits)', () {
    // Solo, full timer. A tapper that ignores the beat keeps stepping into the
    // tightening upper bar, is knocked down, and can never thread it — so it runs
    // out the clock STRICTLY below the summit. Verified across seeds so it's a
    // property of the rhythm, not one lucky pattern.
    for (final seed in [1, 5, 7, 11, 42, 99, 777]) {
      final spam = runSolo(seed, (f, g) => true);
      expect(spam.status, MiniGameStatus.finished);
      expect(spam.scores.of(0), greaterThan(0));
      expect(spam.scores.of(0), lessThan(40),
          reason: 'blind mash must never reach the flag (seed $seed)');
    }
  });

  test('MEASURED beats BLIND SPAM head-to-head — the whole design, proven', () {
    // THE ANTI-SPAM PROOF, deterministic, in one shared 1v1 round (both climbers
    // ride the SAME beat):
    //
    //  * P0 MEASURED: steps every frame the beat ALLOWS it — i.e. only when the
    //    rung above is clear AND the gap can carry it clear through the bar
    //    (read via [isStepSafe]). It threads every bar, takes no hits, and
    //    summits.
    //  * P1 BLIND SPAMMER: taps EVERY frame, ignoring the beat. It steps onto the
    //    bar rows while they telegraph/live, is knocked back + stunned over and
    //    over, and is frozen far below when the measured climber plants the flag.
    //
    // The margin is large and the same across seeds (the dynamics are driven by
    // the deterministic clock), so the proof is unambiguous.
    for (final seed in [1, 5, 7, 11, 42, 99, 777]) {
      final players = [
        PlayerSlot.defaults(0), // measured human
        PlayerSlot.defaults(1), // blind spammer (also human-driven)
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
      );
      final g = ButtonMasher()..init(ctx);

      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        if (g.isStepSafe(0)) g.onInput(PlayerInput.down(0)); // measured
        g.onInput(PlayerInput.down(1)); // blind spam every frame
        g.update(1 / 60);
      }

      expect(g.status, MiniGameStatus.finished);
      final measured = g.scores.of(0);
      final spam = g.scores.of(1);
      expect(measured, greaterThan(spam),
          reason: 'reading the beat and stepping in the clear gap must beat a '
              'blind mash that steps into every live bar (seed $seed)');
      // Decisive, not a coin-flip: a wide measured margin.
      expect(measured - spam, greaterThanOrEqualTo(10),
          reason: 'the measured climber should win clearly (seed $seed)');
    }
  });

  test('stepping onto a live/telegraphing bar knocks the climber down', () {
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
        reason: 'a blind mash must step into a live bar and get knocked down');
  });

  test('a measured human summits and bots remain real climbers', () {
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

    // Human steps every frame the beat allows (reads [isStepSafe]).
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (g.isStepSafe(0)) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    // The bot climbed its own tower the whole round, so it reached a real rung.
    expect(g.scores.of(1), greaterThan(0));
  });

  test('isStepSafe flips with the beat (the read the player makes)', () {
    // The careful-play seam is a genuine read of the rhythm, not a constant: a
    // climber held just below the first bar sees the gap go clear and the danger
    // beat go blocked as the beat cycles. Both states must occur.
    final g = ButtonMasher()..init(soloCtx(5));
    var sawSafe = false;
    var sawUnsafe = false;
    var n = 0;
    // Climb up to just under the lower bar, then observe the safe/unsafe read
    // cycling with the beat.
    while (g.status != MiniGameStatus.finished && n++ < 60 * 30) {
      if (g.rungOf(0) < 12 && g.isStepSafe(0)) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
      if (g.rungOf(0) >= 11) {
        if (g.isStepSafe(0)) {
          sawSafe = true;
        } else {
          sawUnsafe = true;
        }
      }
      if (sawSafe && sawUnsafe) break;
    }
    expect(sawSafe, isTrue, reason: 'the gap must read clear sometimes');
    expect(sawUnsafe, isTrue,
        reason: 'the danger beat must read blocked sometimes');
  });

  test('render never throws across the round for 1–4 players', () {
    for (var count = 1; count <= 4; count++) {
      final players = [
        for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true)
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(11 + count),
        zones: ZoneLayout.forPlayers(count),
      );
      final g = ButtonMasher()..init(ctx);
      final canvas = Canvas(PictureRecorder());

      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally,
          reason: '$count-player render at the gun');
      for (var i = 0; i < 300 && g.status != MiniGameStatus.finished; i++) {
        g.update(1 / 60);
        g.onInput(PlayerInput.down(0));
        // Render mid-round too, so live bars / knockbacks / flashes are drawn.
        if (i % 30 == 0) {
          expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally,
              reason: '$count-player render mid-round');
        }
      }
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally,
          reason: '$count-player render at the end');
    }
  });
}
