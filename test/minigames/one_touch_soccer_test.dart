import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/one_touch_soccer/one_touch_soccer.dart';
import 'package:stick_party/minigames/one_touch_soccer/soccer_fx.dart';
import 'package:stick_party/minigames/one_touch_soccer/striker.dart';

/// Builds an all-bot 4-player soccer round and advances it at a fixed 60 fps
/// step until it finishes (or a hard cap is hit), returning the elapsed seconds.
double _runToFinish(OneTouchSoccer g, {int maxFrames = 60 * 80}) {
  const step = 1 / 60;
  var frames = 0;
  while (g.status != MiniGameStatus.finished && frames < maxFrames) {
    g.update(step);
    frames++;
  }
  return frames * step;
}

OneTouchSoccer _buildAllBots(int seed) {
  final players = [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)];
  // Tall portrait arena so the NORTH/SOUTH pitch fills the vertical screen.
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(4),
  );
  return OneTouchSoccer()..init(ctx);
}

void main() {
  test('one touch soccer finishes with all bots (N/S pitch)', () {
    final g = _buildAllBots(7);
    _runToFinish(g);

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('an all-bot round lasts past the bot warmup and finishes within limit',
      () {
    // PACING guard: with bots warming up + a dead-center kickoff the ball is
    // never instantly scored, so the round must run a real contest (well past
    // the 1.5 s warmup) yet still resolve inside the time limit (45 s budget).
    for (final seed in [1, 7, 13, 21, 99]) {
      final g = _buildAllBots(seed);
      final elapsed = _runToFinish(g, maxFrames: 60 * 50);

      expect(g.status, MiniGameStatus.finished,
          reason: 'seed $seed should resolve within the time limit');
      expect(elapsed, greaterThan(1.5),
          reason: 'seed $seed ended too fast (no real match)');
      expect(elapsed, lessThanOrEqualTo(45.0),
          reason: 'seed $seed overran the match budget');
    }
  });

  test('bots trap-then-shoot, so an all-bot match still puts the ball in a net',
      () {
    // BEHAVIOR guard for the TRAP/KICK rework: bots never tap, so the game arms
    // their kick directly. Across seeds at least one all-bot round must actually
    // SCORE (some side ends above zero) — proof the trap-then-shoot bot path
    // still drives the ball into a goal, not just times out at 0–0.
    var anyScored = false;
    for (final seed in const [1, 3, 7, 13, 21, 42, 99]) {
      final g = _buildAllBots(seed);
      _runToFinish(g);
      final scores = g.scores;
      if (scores.of(0) > 0 || scores.of(1) > 0) {
        anyScored = true;
        break;
      }
    }
    expect(anyScored, isTrue,
        reason: 'bot trap-then-shoot never scored across seeds');
  });

  test('a quick TAP keeps the round running and never crashes (shoot path)', () {
    // AGENCY guard: a single human striker presses (a TAP arms a shot for the
    // next ball contact), releases, then runs on. A lone player cannot end the
    // round on their own before the timer, so the game must still be running and
    // must accept the tap without error and never drive the score negative.
    final ctx = MiniGameContext(
      players: const [PlayerSlot(id: 0, name: 'P1', colorArgb: 0xFFFFFFFF)],
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = OneTouchSoccer()..init(ctx);

    g.update(1 / 60); // a beat before acting
    // Tap toward the top goal: down then an immediate up (a snap tap = shoot).
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.45)));
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.up, normPos: Offset(0.5, 0.45)));
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.running);
    expect(g.scores.of(0), greaterThanOrEqualTo(0));
  });

  test('a held joystick steers + dribbles, keeps running and never crashes', () {
    // The dribble half of the rework: HOLDING the joystick (well past the tap
    // threshold) steers the striker up-field and any ball it reaches is TRAPPED
    // and carried, not booted. A lone player cannot end the round early, so it
    // must still be running and the score must never go negative.
    final ctx = MiniGameContext(
      players: const [PlayerSlot(id: 0, name: 'P1', colorArgb: 0xFFFFFFFF)],
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = OneTouchSoccer()..init(ctx);

    g.update(1 / 60);

    // Steer hard UP for ~1 second (a sustained hold ⇒ a dribble, not a shot).
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.8)));
    for (var i = 0; i < 60; i++) {
      g.onInput(const PlayerInput(
          playerId: 0, phase: InputPhase.holdTick, normPos: Offset(0.5, 0.5)));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.running);
    expect(g.scores.of(0), greaterThanOrEqualTo(0));
  });

  group('Joystick (TRAP vs KICK decision)', () {
    test('a press arms a kick for the next contact', () {
      final joy = Joystick();
      expect(joy.kickArmed, isFalse);
      joy.press(const Offset(0.5, 0.5));
      expect(joy.kickArmed, isTrue, reason: 'a tap queues a shot');
      expect(joy.active, isTrue);
    });

    test('holding past the tap threshold lapses the kick into a dribble', () {
      final joy = Joystick()..press(const Offset(0.5, 0.5));
      // A short hold (under threshold) keeps the shot armed.
      joy.tick(0.1, tapHoldSec: 0.22);
      expect(joy.kickArmed, isTrue);
      // Held longer than the threshold ⇒ it is a steer-hold, so it disarms and
      // the next contact will TRAP instead of shoot.
      joy.tick(0.2, tapHoldSec: 0.22);
      expect(joy.kickArmed, isFalse);
    });

    test('consumeKick clears the arm; armNextKick re-arms (the bot path)', () {
      final joy = Joystick()..press(const Offset(0.5, 0.5));
      joy.consumeKick();
      expect(joy.kickArmed, isFalse, reason: 'a fired shot reverts to trapping');
      joy.armNextKick(); // bots never tap; the game arms them directly
      expect(joy.kickArmed, isTrue);
    });

    test('touch charge ramps from ~0 right after a touch toward 1 when settled',
        () {
      final joy = Joystick()..armKick(0.18); // marks a touch (charge reset)
      expect(joy.touchChargeFrac(0.9), closeTo(0.0, 1e-9));
      // Let time pass without another touch: the shot charge climbs to full.
      for (var i = 0; i < 60; i++) {
        joy.tick(1 / 60, tapHoldSec: 0.22);
      }
      expect(joy.touchChargeFrac(0.9), closeTo(1.0, 1e-9),
          reason: 'a long-settled ball reaches full shot power');
    });
  });

  group('uneven-teams fairness handicap', () {
    OneTouchSoccer buildRoster(List<PlayerSlot> players) {
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(3),
        zones: ZoneLayout.forPlayers(players.length),
      );
      return OneTouchSoccer()..init(ctx);
    }

    test('3p (1-vs-2) boosts the short-handed side and weakens the big keeper',
        () {
      // Even ids attack TOP, odd ids attack BOTTOM: ids 0 & 2 → top (2 players),
      // id 1 → bottom (alone). So BOTTOM is short-handed and must run faster +
      // shoot harder, while the larger TOP side's keeper tracks softer.
      final g = buildRoster([
        PlayerSlot.defaults(0, isBot: true), // top
        PlayerSlot.defaults(1, isBot: true), // bottom (lone underdog)
        PlayerSlot.defaults(2, isBot: true), // top
      ]);

      // The lone bottom striker is handicapped UP; the 2-strong top side is not.
      expect(g.speedFactorForTest(1), greaterThan(1.0),
          reason: 'short-handed striker runs faster');
      expect(g.shotFactorForTest(1), greaterThan(1.0),
          reason: 'short-handed striker shoots harder');
      expect(g.speedFactorForTest(0), 1.0,
          reason: 'the larger side gets no speed boost');
      expect(g.shotFactorForTest(2), 1.0,
          reason: 'the larger side gets no shot boost');

      // The bigger (top) side's keeper is weaker; the short side's keeper is not.
      expect(g.keeperLaneGainForTest(true), lessThan(0.5),
          reason: 'the bigger side defends a softer net');
      expect(g.keeperLaneGainForTest(false), 0.5,
          reason: 'the short side keeper is unchanged');
    });

    test('balanced rosters (1+CPU 1v1, 2v2) keep every factor neutral', () {
      // 1v1 (id 0 top, id 1 bottom) and 2v2 (ids 0,2 top, 1,3 bottom) are even,
      // so the handicap is exactly neutral — balanced modes are untouched.
      final duel = buildRoster([
        PlayerSlot.defaults(0, isBot: true),
        PlayerSlot.defaults(1, isBot: true),
      ]);
      expect(duel.speedFactorForTest(0), 1.0);
      expect(duel.shotFactorForTest(1), 1.0);
      expect(duel.keeperLaneGainForTest(true), 0.5);
      expect(duel.keeperLaneGainForTest(false), 0.5);

      final team = buildRoster([
        for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
      ]);
      expect(team.speedFactorForTest(0), 1.0);
      expect(team.speedFactorForTest(1), 1.0);
      expect(team.shotFactorForTest(2), 1.0);
      expect(team.keeperLaneGainForTest(true), 0.5);
      expect(team.keeperLaneGainForTest(false), 0.5);
    });
  });

  group('SpeedPadController (chaos pickup)', () {
    final field = const Rect.fromLTRB(40, 60, 760, 1140);
    SpeedPadController make() => SpeedPadController(
          radius: 24,
          firstSpawnSec: 3.0,
          respawnSec: 5.0,
          lifeSec: 6.0,
          appearPerSec: 4.0,
          phasePerSec: 3.0,
        );

    test('spawns inside the field central band after its delay', () {
      final c = make();
      final rng = SeededRng(7);
      for (var i = 0; i < 60 * 4; i++) {
        c.tick(1 / 60, rng, field);
      }
      final pad = c.pad;
      expect(pad, isNotNull);
      expect(pad!.ready, isTrue);
      // Inside the field, and within the central band (never in a goal third).
      expect(field.contains(pad.pos), isTrue);
      expect(pad.pos.dy, greaterThan(field.top + field.height * 0.33));
      expect(pad.pos.dy, lessThan(field.bottom - field.height * 0.33));
    });

    test('tryTrigger fires only when the ball overlaps, returns a unit dir', () {
      final c = make();
      final rng = SeededRng(8);
      for (var i = 0; i < 60 * 4; i++) {
        c.tick(1 / 60, rng, field);
      }
      final pad = c.pad!;
      // Ball far away: no trigger.
      final miss = c.tryTrigger(
        ballPos: pad.pos + const Offset(400, 0),
        ballVel: const Offset(0, -100),
        ballRadius: 10,
        minBallSpeed: 30,
        topLine: field.top,
        bottomLine: field.bottom,
      );
      expect(miss, isNull);
      expect(c.pad, isNotNull, reason: 'a miss must not consume the pad');
      // Ball on the pad while moving: returns its travel direction (unit).
      final dir = c.tryTrigger(
        ballPos: pad.pos,
        ballVel: const Offset(0, -200),
        ballRadius: 10,
        minBallSpeed: 30,
        topLine: field.top,
        bottomLine: field.bottom,
      );
      expect(dir, isNotNull);
      expect(dir!.distance, closeTo(1.0, 1e-6));
      expect(dir.dy, lessThan(0), reason: 'kept the upward travel heading');
      expect(c.pad, isNull, reason: 'a hit consumes the pad');
    });

    test('a nearly-still ball is kicked toward the nearer goal', () {
      final c = make();
      final rng = SeededRng(9);
      for (var i = 0; i < 60 * 4; i++) {
        c.tick(1 / 60, rng, field);
      }
      final pad = c.pad!;
      final dir = c.tryTrigger(
        ballPos: pad.pos,
        ballVel: Offset.zero, // dead ball
        ballRadius: 10,
        minBallSpeed: 30,
        topLine: field.top,
        bottomLine: field.bottom,
      );
      expect(dir, isNotNull);
      expect(dir!.dx, 0); // straight up or down a goal line
      expect(dir.dy.abs(), 1);
    });
  });

  group('spam-proofing (objective + interposing skill)', () {
    test('the EARNED shot economy: power and aim climb only with possession', () {
      // The core lever. A poke with no banked possession (what a masher always
      // gets) sits at the powerless, aimless floor; a controlled, settled shot
      // (skill) reaches full power AND a goalward assist. So skill out-shoots
      // spam by construction — proven deterministically, no noisy match needed.
      final g = OneTouchSoccer()
        ..init(MiniGameContext(
          players: const [PlayerSlot(id: 0, name: 'P1', colorArgb: 0xFFFFFFFF)],
          arena: const Size(800, 1200),
          rng: SeededRng(1),
          zones: ZoneLayout.forPlayers(1),
        ));

      final floorPower = g.shotPowerFracForTest(0);
      final fullPower = g.shotPowerFracForTest(10); // long-controlled
      expect(floorPower, lessThan(0.2), reason: 'a no-possession poke is feeble');
      expect(fullPower, greaterThan(0.9), reason: 'a controlled shot blasts');
      expect(fullPower, greaterThan(floorPower * 3),
          reason: 'control multiplies shot power several-fold');

      expect(g.goalAssistForTest(0), 0.0,
          reason: 'a poke gets ZERO goalward assist — the player must aim it');
      expect(g.goalAssistForTest(10), greaterThan(0.0),
          reason: 'only a controlled shot earns a goalward curl');
    });

    test('a lone player CAN score (goal credited to the side that attacks it)',
        () {
      // Guards the scoring-attribution fix: previously a goal in a net was
      // credited to the WRONG side, so a solo player (or any side shooting at the
      // net it actually attacks) could never put a goal on its own board. A lone
      // all-bot striker trap-dribble-shoots into the net it attacks and must end
      // with a positive score.
      final g = OneTouchSoccer()
        ..init(MiniGameContext(
          players: [PlayerSlot.defaults(0, isBot: true)],
          arena: const Size(800, 1200),
          rng: SeededRng(7),
          zones: ZoneLayout.forPlayers(1),
          difficulty: BotDifficulty.hard,
        ));
      _runToFinish(g);
      expect(g.scores.of(0), greaterThan(0),
          reason: 'a solo striker must be able to score in the net it attacks');
    });

    test('a chase-and-mash spammer can never score and loses to a hard bot', () {
      // The decisive proof of the law. Seat 0 is a realistic button-masher:
      // it chases the live ball (with human-like lag + wobble) and re-taps every
      // ~0.08 s, so it NEVER traps/controls the ball — only floor pokes. Seat 1
      // is a hard bot that traps, dribbles and shoots. Across many seeds the
      // masher must score ZERO (its pokes never reach goal speed) and must lose
      // the vast majority (a 0–0 is broken by possession, which the masher has
      // none of), confirming: skill beats spam, and spam cannot win by mashing.
      const step = 1 / 60;
      var masherGoals = 0;
      var botWins = 0;
      const seeds = 24;
      for (var s = 1; s <= seeds; s++) {
        final seed = s * 7 + 1;
        final g = OneTouchSoccer()
          ..init(MiniGameContext(
            players: [
              const PlayerSlot(id: 0, name: 'SPAM', colorArgb: 0xFFFFFFFF),
              PlayerSlot.defaults(1, isBot: true),
            ],
            arena: const Size(800, 1200),
            rng: SeededRng(seed),
            zones: ZoneLayout.forPlayers(2),
            difficulty: BotDifficulty.hard,
          ));
        final rng = SeededRng(seed * 31 + 5);
        var dir = const Offset(0, -1);
        var f = 0;
        while (g.status != MiniGameStatus.finished && f < 60 * 80) {
          if (f % 9 == 0) {
            final to = g.ballPosNormForTest() - g.strikerPosNormForTest(0);
            final d = to.distance;
            var nd = d < 1e-6 ? const Offset(0, -1) : to / d;
            final a = rng.jitter(0.5); // human-like aim wobble
            nd = Offset(nd.dx * math.cos(a) - nd.dy * math.sin(a),
                nd.dx * math.sin(a) + nd.dy * math.cos(a));
            dir = nd;
          }
          const anchor = Offset(0.5, 0.5);
          if (f % 5 == 0) {
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.up, normPos: anchor));
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.down, normPos: anchor));
          }
          g.onInput(PlayerInput(
              playerId: 0, phase: InputPhase.holdTick, normPos: anchor + dir * 0.16));
          g.update(step);
          f++;
        }
        masherGoals += g.scores.of(0).round();
        if (g.winResult!.winner != 0) botWins++;
      }
      expect(masherGoals, 0,
          reason: 'mashing produces only floor pokes — it can never score');
      expect(botWins, greaterThanOrEqualTo(15),
          reason: 'skilled trap-and-shoot must beat the masher across seeds');
    });
  });
}
