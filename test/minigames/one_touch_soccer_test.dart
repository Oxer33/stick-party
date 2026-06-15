import 'dart:math' as math;
import 'dart:ui';

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

/// Advances a round at a fixed 60 fps step until it finishes (or a hard cap is
/// hit), returning the elapsed seconds.
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

OneTouchSoccer _buildSolo(int seed, {bool isBot = false, BotDifficulty? diff}) {
  final player = isBot
      ? PlayerSlot.defaults(0, isBot: true)
      : const PlayerSlot(id: 0, name: 'P1', colorArgb: 0xFFFFFFFF);
  final ctx = MiniGameContext(
    players: [player],
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(1),
    difficulty: diff ?? BotDifficulty.medium,
  );
  return OneTouchSoccer()..init(ctx);
}

/// Steer human seat [id] toward the live ball through the REAL input path with a
/// gentle deflection (a held drag — a MOVE, not a tap), for [frames] frames. The
/// ball is not trapped (a drag never claims).
void _driveTowardBall(OneTouchSoccer g, int id, int frames) {
  const step = 1 / 60;
  const anchor = Offset(0.5, 0.5);
  g.onInput(const PlayerInput(
      playerId: 0, phase: InputPhase.down, normPos: anchor));
  for (var i = 0; i < frames; i++) {
    final to = g.ballPosNormForTest() - g.strikerPosNormForTest(id);
    final d = to.distance;
    final dir = d < 1e-6 ? const Offset(0, -1) : to / d;
    // A real steer drag well past the tap-drag threshold so it reads as a MOVE.
    g.onInput(PlayerInput(
        playerId: id, phase: InputPhase.holdTick, normPos: anchor + dir * 0.16));
    g.update(step);
  }
}

/// Issue a clean stationary TAP for seat [id] (down then up at the same anchor
/// within the tap window) — the active TRAP / SHOOT gesture.
void _tap(OneTouchSoccer g, int id, {Offset anchor = const Offset(0.5, 0.5)}) {
  g.onInput(PlayerInput(playerId: id, phase: InputPhase.down, normPos: anchor));
  g.onInput(PlayerInput(playerId: id, phase: InputPhase.up, normPos: anchor));
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

  test('bots actively trap-then-shoot, so an all-bot match still scores', () {
    // BEHAVIOR guard for the ACTIVE-TRAP rework: bots claim a loose ball with the
    // same active trap a human reads (timed by accuracy), then carry + shoot.
    // Across seeds at least one all-bot round must actually SCORE (some side ends
    // above zero) — proof the trap-then-shoot bot path still drives the ball into
    // a goal, not just times out at 0–0.
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
        reason: 'bot active-trap-then-shoot never scored across seeds');
  });

  test('a quick TAP keeps the round running and never crashes (shoot path)', () {
    // AGENCY guard: a single human striker taps (an active intent — a trap claim
    // or a shoot), then runs on. A lone player cannot end the round on their own
    // before the timer, so the game must still be running and must accept the tap
    // without error and never drive the score negative.
    final g = _buildSolo(5);

    g.update(1 / 60); // a beat before acting
    _tap(g, 0, anchor: const Offset(0.5, 0.45));
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.running);
    expect(g.scores.of(0), greaterThanOrEqualTo(0));
  });

  test('a held joystick steers + carries, keeps running and never crashes', () {
    // The MOVE half of the rework: HOLDING the joystick (a real drag, never a
    // tap) steers the striker up-field. It never traps (a drag is a move), so the
    // ball is not claimed by merely running at it. A lone player cannot end the
    // round early, so it must still be running and the score never go negative.
    final g = _buildSolo(5);
    g.update(1 / 60);
    _driveTowardBall(g, 0, 60);

    expect(g.status, MiniGameStatus.running);
    expect(g.scores.of(0), greaterThanOrEqualTo(0));
  });

  group('Joystick (steering + trail primitive)', () {
    test('press anchors origin/current and activates; release deactivates', () {
      final joy = Joystick();
      expect(joy.active, isFalse);
      joy.press(const Offset(0.4, 0.6));
      expect(joy.active, isTrue);
      expect(joy.origin, const Offset(0.4, 0.6));
      expect(joy.current, const Offset(0.4, 0.6));
      joy.release();
      expect(joy.active, isFalse);
    });

    test('steer maps deflection to a 0..1 magnitude in the drag direction', () {
      final joy = Joystick()..press(const Offset(0.5, 0.5));
      // Inside the dead zone → no steer.
      joy.drag(const Offset(0.505, 0.5));
      expect(joy.steer(maxRadius: 0.16, deadZone: 0.02), Offset.zero);
      // Full deflection right → unit-ish vector pointing +x at full strength.
      joy.drag(const Offset(0.5 + 0.2, 0.5));
      final s = joy.steer(maxRadius: 0.16, deadZone: 0.02);
      expect(s.dx, greaterThan(0.9));
      expect(s.dy.abs(), lessThan(1e-9));
    });

    test('tick retires the kick trail once its life is spent', () {
      final joy = Joystick()
        ..trail = DashTrail(from: Offset.zero, dir: const Offset(0, -1), life: 0.1);
      joy.tick(0.05);
      expect(joy.trail, isNotNull);
      joy.tick(0.1);
      expect(joy.trail, isNull, reason: 'a spent trail clears');
    });
  });

  group('active trap (the claim is taken, never gifted)', () {
    test('a clean tap CLAIMS a loose ball once positioned on it', () {
      // The heart of the rework: position a human onto the dead kickoff ball with
      // a steer (a MOVE — which does NOT claim), then issue a clean stationary
      // TAP. Only the tap claims, so possession flips to the tapper.
      final g = _buildSolo(5);
      g.update(1 / 60);
      // Steer onto the ball but do NOT trap (a drag is a move).
      _driveTowardBall(g, 0, 90);
      expect(g.possessorForTest(), isNull,
          reason: 'running at the ball must NOT auto-claim it');
      // Now an active tap claims it (give a couple frames for the window).
      _tap(g, 0);
      for (var i = 0; i < 4; i++) {
        g.update(1 / 60);
      }
      expect(g.possessorForTest(), 0,
          reason: 'a clean tap on the ball in range claims it');
    });

    test('a tap with NO ball in range whiffs — nothing is claimed', () {
      // A lone striker spawns far from the dead center ball. A tap there finds no
      // ball in range, so the trap whiffs and possession stays null (a turnover
      // risk, never a free claim).
      final g = _buildSolo(5);
      g.update(1 / 60);
      expect(
          (g.ballPosNormForTest() - g.strikerPosNormForTest(0)).distance,
          greaterThan(0.1),
          reason: 'sanity: the striker starts well off the ball');
      _tap(g, 0);
      for (var i = 0; i < 6; i++) {
        g.update(1 / 60);
      }
      expect(g.possessorForTest(), isNull,
          reason: 'a tap with no ball in range claims nothing');
    });

    test('a tap WHILE possessing SHOOTS — the ball goes loose again', () {
      // Once owned, a tap fires the ball: possession returns to null (the shot is
      // travelling) and the round keeps running.
      final g = _buildSolo(5);
      g.update(1 / 60);
      _driveTowardBall(g, 0, 90);
      _tap(g, 0); // trap
      for (var i = 0; i < 4; i++) {
        g.update(1 / 60);
      }
      expect(g.possessorForTest(), 0, reason: 'precondition: trapped');
      _tap(g, 0); // shoot
      g.update(1 / 60);
      expect(g.possessorForTest(), isNull,
          reason: 'a tap while possessing shoots the ball loose');
      expect(g.status, MiniGameStatus.running);
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

  group('spam-proofing (objective + active-trap skill)', () {
    test('the EARNED shot economy: shot power climbs only with settled possession',
        () {
      // The core lever. A shot fired the instant you trap (no settled possession)
      // sits at the powerless floor (and dies on the goal-speed gate); a carried,
      // settled ball reaches full power. So a measured trap-carry-shoot out-shoots
      // a panic re-tap by construction — proven deterministically, no noisy match.
      // (Aim is a fixed, readable HYBRID — mostly at the goal, bent by run dir —
      // not a possession-scaled assist, so it is verified in play, not here.)
      final g = _buildSolo(1);

      final floorPower = g.shotPowerFracForTest(0);
      final fullPower = g.shotPowerFracForTest(10); // long-settled
      expect(floorPower, lessThan(0.2), reason: 'a no-possession tap is feeble');
      expect(fullPower, greaterThan(0.9), reason: 'a settled carry blasts');
      expect(fullPower, greaterThan(floorPower * 3),
          reason: 'settled possession multiplies shot power several-fold');
    });

    test('a lone player CAN score (goal credited to the side that attacks it)',
        () {
      // Guards the scoring-attribution fix: a lone all-bot striker actively traps,
      // carries and shoots into the net it attacks and must end with a positive
      // score — proof the active-trap bot path can put a goal on its own board.
      final g = _buildSolo(7, isBot: true, diff: BotDifficulty.hard);
      _runToFinish(g);
      expect(g.scores.of(0), greaterThan(0),
          reason: 'a solo striker must be able to score in the net it attacks');
    });

    test('a chase-and-mash spammer never scores and loses to a hard bot', () {
      // The decisive proof of the law. Seat 0 is a realistic button-masher: it
      // chases the live ball (with human-like lag + wobble) and mashes rapid TAPS
      // (down/up every ~0.08 s). Under the active-trap model those taps almost
      // never line up with the ball loose + in range + slow, so it rarely claims;
      // and any accidental claim is THROWN AWAY by the very next mash tap (a shot
      // at ~zero charge). Seat 1 is a hard bot that traps, carries and shoots.
      // Across many seeds the masher must score ZERO (its pokes never reach goal
      // speed) and must lose the vast majority (a 0–0 is broken by possession,
      // which the masher banks ~none of): skill beats spam, spam cannot mash a win.
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
          // Mash rapid taps: a down+up burst (the spam claim/shoot attempt) plus a
          // steer toward the ball — the realistic "chase and hammer the button".
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

  group('COMPETITIVE: skill gradient + beatable-but-tough hard bot', () {
    // A SKILLED but HUMAN sim drives seat 0 (id 0 → even → attacks the TOP
    // goal) in a clean 1v1 (duel) vs ONE bot. It is competent — traps the loose
    // ball, carries it goalward, places a charged shot — but NOT frame-perfect:
    // it reacts on a ~150 ms cadence with a touch of steering wobble and has to
    // physically run, the same lag+wobble the spam test models. Measured (16
    // seeds/tier, two disjoint windows + an 8-window robustness sweep offline):
    //   easy   : win-rate 1.00  (clearly beatable)
    //   medium : win-rate 1.00
    //   hard   : win-rate 0.62–0.88  (beatable-but-tough; bot wins ~15–40%)
    // so the bands below are robust supersets validated on disjoint seeds. This
    // is the permanent lock against the game drifting into a pushover (hard → 1)
    // or a wall (hard → 0). 2v2 reads the same shape (hard ≈ 0.69) and is noted
    // in the audit; the 1v1 duel is the clean competitive read asserted here.
    const decisionEvery = 9; // ~150 ms human decision cadence
    const wobbleRad = 0.18; // skilled-but-human steering wobble

    Offset wobble(Offset dir, SeededRng rng) {
      final a = rng.jitter(wobbleRad);
      return Offset(dir.dx * math.cos(a) - dir.dy * math.sin(a),
          dir.dx * math.sin(a) + dir.dy * math.cos(a));
    }

    OneTouchSoccer buildDuel(int seed, BotDifficulty diff) => OneTouchSoccer()
      ..init(MiniGameContext(
        players: [
          const PlayerSlot(id: 0, name: 'SKILL', colorArgb: 0xFFFFFFFF),
          PlayerSlot.defaults(1, isBot: true),
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
        mode: GameMode.duel1v1,
        difficulty: diff,
      ));

    // The skilled-human duel runner, returning the seat-0 win-rate, win count
    // and the SET of distinct seat-0 final scores across [seeds]. Drives the
    // REAL input path for seat 0: chase the loose ball → stationary TAP to TRAP
    // → carry it goalward → release + TAP to place a charged shot near goal.
    ({double rate, int wins, int total, Set<int> seat0Scores}) measure(
        BotDifficulty diff, List<int> seeds) {
      var wins = 0;
      final scores = <int>{};
      for (final seed in seeds) {
        final g = buildDuel(seed, diff);
        // Re-run once to capture the win, once to read the score set cheaply is
        // wasteful — instead inline a single run and read both.
        final rng = SeededRng(seed * 977 + 41);
        const step = 1 / 60;
        const anchor = Offset(0.5, 0.5);
        const goalNorm = Offset(0.5, 0.04);
        var f = 0;
        var pressedDown = false;
        var shootCd = 0;
        var steer = const Offset(0, -1);
        while (g.status != MiniGameStatus.finished && f < 60 * 80) {
          final ballN = g.ballPosNormForTest();
          final meN = g.strikerPosNormForTest(0);
          final possessor = g.possessorForTest();
          final iOwn = possessor == 0;
          final toBall = ballN - meN;
          final ballDist = toBall.distance;
          final decide = f % decisionEvery == 0;
          if (shootCd > 0) shootCd--;
          if (iOwn) {
            if (decide) {
              final toGoal = goalNorm - meN;
              final gd = toGoal.distance;
              final raw = gd < 1e-6 ? const Offset(0, -1) : toGoal / gd;
              steer = wobble(raw, rng);
            }
            if (!pressedDown) {
              g.onInput(const PlayerInput(
                  playerId: 0, phase: InputPhase.down, normPos: anchor));
              pressedDown = true;
            }
            g.onInput(PlayerInput(
                playerId: 0,
                phase: InputPhase.holdTick,
                normPos: anchor + steer * 0.16));
            g.update(step);
            f++;
            if (meN.dy < 0.30 && shootCd == 0) {
              g.onInput(PlayerInput(
                  playerId: 0,
                  phase: InputPhase.up,
                  normPos: anchor + steer * 0.16));
              pressedDown = false;
              g.onInput(const PlayerInput(
                  playerId: 0, phase: InputPhase.down, normPos: anchor));
              g.onInput(const PlayerInput(
                  playerId: 0, phase: InputPhase.up, normPos: anchor));
              shootCd = 18;
            }
            continue;
          }
          const trapNormRange = 0.072;
          if (possessor == null && ballDist <= trapNormRange) {
            if (pressedDown) {
              g.onInput(const PlayerInput(
                  playerId: 0, phase: InputPhase.up, normPos: anchor));
              pressedDown = false;
            }
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.down, normPos: anchor));
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.up, normPos: anchor));
            g.update(step);
            f++;
            continue;
          }
          if (decide) {
            final raw =
                ballDist < 1e-6 ? const Offset(0, -1) : toBall / ballDist;
            steer = wobble(raw, rng);
          }
          if (!pressedDown) {
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.down, normPos: anchor));
            pressedDown = true;
          }
          g.onInput(PlayerInput(
              playerId: 0,
              phase: InputPhase.holdTick,
              normPos: anchor + steer * 0.16));
          g.update(step);
          f++;
        }
        if (g.winResult!.ranking.first == 0) wins++;
        scores.add(g.scores.of(0).round());
      }
      return (
        rate: wins / seeds.length,
        wins: wins,
        total: seeds.length,
        seat0Scores: scores
      );
    }

    // Two DISJOINT 16-seed windows: assert the bands hold on both.
    final windowA = [for (var i = 0; i < 16; i++) i * 7 + 3];
    final windowB = [for (var i = 0; i < 16; i++) i * 13 + 101];

    for (final entry in {'A': windowA, 'B': windowB}.entries) {
      final label = entry.key;
      final seeds = entry.value;
      test('window $label — easy beatable, hard tough, monotone gradient', () {
        final easy = measure(BotDifficulty.easy, seeds);
        final medium = measure(BotDifficulty.medium, seeds);
        final hard = measure(BotDifficulty.hard, seeds);

        // EASY clearly beatable.
        expect(easy.rate, greaterThanOrEqualTo(0.70),
            reason: '[$label] a skilled human should crush the easy bot '
                '(got ${easy.wins}/${easy.total})');

        // HARD beatable-but-tough: neither a wall (0) nor a pushover (1).
        expect(hard.rate, greaterThanOrEqualTo(0.15),
            reason: '[$label] the hard bot must not be an unbeatable wall '
                '(human won only ${hard.wins}/${hard.total})');
        expect(hard.rate, lessThanOrEqualTo(0.90),
            reason: '[$label] the hard bot must not be a pushover '
                '(human won ${hard.wins}/${hard.total}) — it has to win some');

        // MONOTONE skill gradient, with a strict easy>hard separation.
        expect(easy.rate, greaterThanOrEqualTo(medium.rate),
            reason: '[$label] easy must be at least as winnable as medium');
        expect(medium.rate, greaterThanOrEqualTo(hard.rate),
            reason: '[$label] medium must be at least as winnable as hard');
        expect(easy.rate, greaterThan(hard.rate),
            reason: '[$label] easy must be strictly more winnable than hard');

        // NOT luck-dominated: vs easy the skilled human wins reliably (the
        // 0.70 floor above already encodes this on a robust band).
        // NO runaway: vs hard the outcome VARIES across seeds (the bot steals
        // games and pushes others close — a comeback exists), so the seat-0
        // hard score is not a single pinned value.
        expect(hard.wins, lessThan(hard.total),
            reason: '[$label] the hard bot must win at least one duel');
        expect(hard.seat0Scores.length, greaterThan(1),
            reason: '[$label] hard outcomes must vary across seeds (no runaway '
                'pin) — got scores ${hard.seat0Scores}');
      });
    }
  });
}
