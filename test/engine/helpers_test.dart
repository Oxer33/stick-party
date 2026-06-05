import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/helpers/aim_sweep.dart';
import 'package:stick_party/engine/helpers/area_fill_grid.dart';
import 'package:stick_party/engine/helpers/lane_hopper.dart';
import 'package:stick_party/engine/helpers/push_arena.dart';
import 'package:stick_party/engine/helpers/reaction_gate.dart';
import 'package:stick_party/engine/helpers/tap_mash_meter.dart';

void main() {
  // ===========================================================================
  // TapMashMeter
  // ===========================================================================
  group('TapMashMeter', () {
    test('tap increments value and tapCount', () {
      final m = TapMashMeter(tapImpulse: 0.1, maxValue: 1.0);
      m.tap();
      expect(m.value, closeTo(0.1, 1e-9));
      expect(m.tapCount, 1);
      m.tap();
      expect(m.value, closeTo(0.2, 1e-9));
      expect(m.tapCount, 2);
    });

    test('value caps at maxValue but tapCount keeps counting', () {
      final m = TapMashMeter(tapImpulse: 0.5, maxValue: 1.0);
      m.tap();
      m.tap();
      m.tap(); // would be 1.5 uncapped
      expect(m.value, 1.0);
      expect(m.full, isTrue);
      expect(m.tapCount, 3);
    });

    test('decay reduces value over update', () {
      final m = TapMashMeter(tapImpulse: 0.5, decayPerSec: 0.2, maxValue: 1.0);
      m.tap(); // 0.5
      m.update(1.0); // -0.2 => 0.3
      expect(m.value, closeTo(0.3, 1e-9));
    });

    test('decay floors at 0 and a no-decay meter ignores update', () {
      final decaying =
          TapMashMeter(tapImpulse: 0.1, decayPerSec: 5, maxValue: 1.0);
      decaying.tap();
      decaying.update(10); // huge decay
      expect(decaying.value, 0);

      final flat = TapMashMeter(tapImpulse: 0.1, maxValue: 1.0);
      flat.tap();
      flat.update(100);
      expect(flat.value, closeTo(0.1, 1e-9)); // no decay
    });

    test('negative/non-finite dt cannot add charge', () {
      final m = TapMashMeter(tapImpulse: 0.4, decayPerSec: 1, maxValue: 1.0);
      m.tap();
      m.update(-1);
      m.update(double.nan);
      expect(m.value, closeTo(0.4, 1e-9));
    });

    test('progress is value/maxValue clamped to [0,1]', () {
      final m = TapMashMeter(tapImpulse: 0.25, maxValue: 1.0);
      expect(m.progress, 0);
      m.tap();
      m.tap();
      expect(m.progress, closeTo(0.5, 1e-9));
      m.tap();
      m.tap();
      m.tap();
      expect(m.progress, 1.0);
    });

    test('reset zeroes value and tapCount', () {
      final m = TapMashMeter(tapImpulse: 0.3, maxValue: 1.0);
      m.tap();
      m.tap();
      m.reset();
      expect(m.value, 0);
      expect(m.tapCount, 0);
      expect(m.progress, 0);
    });

    test('rejects invalid construction args', () {
      expect(() => TapMashMeter(maxValue: 0), throwsArgumentError);
      expect(() => TapMashMeter(tapImpulse: -1), throwsArgumentError);
      expect(() => TapMashMeter(decayPerSec: -1), throwsArgumentError);
      expect(() => TapMashMeter(value: -1), throwsArgumentError);
    });
  });

  // ===========================================================================
  // ReactionGate
  // ===========================================================================
  group('ReactionGate', () {
    test('transitions waiting -> go after the rolled delay', () {
      final gate = ReactionGate(SeededRng(1), minDelay: 1.0, maxDelay: 1.0);
      expect(gate.phase, ReactionPhase.waiting);
      gate.update(0.5);
      expect(gate.phase, ReactionPhase.waiting);
      gate.update(0.6); // total 1.1 >= 1.0
      expect(gate.phase, ReactionPhase.go);
    });

    test('a tap during waiting is an early false start and locks the player out',
        () {
      final gate = ReactionGate(SeededRng(1), minDelay: 2.0, maxDelay: 2.0);
      final r = gate.onTap(0);
      expect(r, ReactionTap.early);
      expect(gate.penalized, contains(0));
      // Now drive to GO; the penalized player is ignored, not a winner.
      gate.update(2.0);
      expect(gate.phase, ReactionPhase.go);
      expect(gate.onTap(0), ReactionTap.ignored);
      expect(gate.winner, isNull);
    });

    test('first valid tap after GO becomes the winner with a reaction time', () {
      final gate = ReactionGate(SeededRng(1), minDelay: 1.0, maxDelay: 1.0);
      // The gate freezes _elapsed once GO fires, so the recorded reaction time
      // is the overshoot of the update that crosses goAt (1.2 - 1.0 = 0.2).
      gate.update(1.2); // crosses goAt=1.0 by 0.2 -> phase go, reaction 0.2
      final r = gate.onTap(1);
      expect(r, ReactionTap.valid);
      expect(gate.winner, 1);
      expect(gate.phase, ReactionPhase.done);
      expect(gate.reactionTimes[1], closeTo(0.2, 1e-9));
    });

    test('late taps by other players are recorded but do not change winner', () {
      final gate = ReactionGate(SeededRng(1), minDelay: 1.0, maxDelay: 1.0);
      gate.update(1.0);
      gate.update(0.1);
      gate.onTap(0); // winner
      final r = gate.onTap(2); // someone else taps after
      expect(r, ReactionTap.late);
      expect(gate.winner, 0);
      expect(gate.reactionTimes.containsKey(2), isTrue);
    });

    test('reset rolls a fresh round', () {
      final gate = ReactionGate(SeededRng(1), minDelay: 1.0, maxDelay: 1.0);
      gate.update(1.0);
      gate.onTap(0);
      gate.reset();
      expect(gate.phase, ReactionPhase.waiting);
      expect(gate.winner, isNull);
      expect(gate.penalized, isEmpty);
      expect(gate.reactionTimes, isEmpty);
    });

    test('rejects invalid delays', () {
      expect(() => ReactionGate(SeededRng(1), minDelay: -1), throwsArgumentError);
      expect(
        () => ReactionGate(SeededRng(1), minDelay: 2, maxDelay: 1),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // AimSweep
  // ===========================================================================
  group('AimSweep', () {
    test('angle stays within [min, max] while sweeping', () {
      final s = AimSweep(minAngle: -1.0, maxAngle: 1.0, speed: 3.0);
      for (var i = 0; i < 500; i++) {
        s.update(1 / 60);
        expect(s.angle, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('ping-pongs: direction reverses at the bounds', () {
      final s = AimSweep(minAngle: 0.0, maxAngle: 1.0, speed: 10.0);
      // Walk forward until it reverses (angle stops increasing).
      var prev = s.angle;
      var reversed = false;
      for (var i = 0; i < 200; i++) {
        s.update(1 / 60);
        if (s.angle < prev) {
          reversed = true;
          break;
        }
        prev = s.angle;
      }
      expect(reversed, isTrue, reason: 'sweep should bounce off maxAngle');
    });

    test('progress is 0 at min and stays within [0,1]', () {
      final s = AimSweep(minAngle: 0.0, maxAngle: 2.0, speed: 1.0);
      s.reset();
      expect(s.progress, 0);
      for (var i = 0; i < 1000; i++) {
        s.update(1 / 120);
        expect(s.progress, inInclusiveRange(0.0, 1.0));
      }
    });

    test('direction is the unit vector of angle', () {
      final s = AimSweep(minAngle: 0.0, maxAngle: 0.0); // held at 0
      expect(s.direction.dx, closeTo(1.0, 1e-9));
      expect(s.direction.dy, closeTo(0.0, 1e-9));
    });

    test('degenerate range holds the angle still', () {
      final s = AimSweep(minAngle: 0.5, maxAngle: 0.5, speed: 5);
      s.update(1.0);
      expect(s.angle, 0.5);
      expect(s.progress, 0);
    });

    test('ignores non-positive dt', () {
      final s = AimSweep(minAngle: 0, maxAngle: 1, speed: 1);
      final before = s.angle;
      s.update(0);
      s.update(-1);
      expect(s.angle, before);
    });

    test('rejects invalid construction', () {
      expect(
        () => AimSweep(minAngle: 1, maxAngle: 0),
        throwsArgumentError,
      );
      expect(
        () => AimSweep(minAngle: 0, maxAngle: 1, speed: -1),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // LaneSet
  // ===========================================================================
  group('LaneSet', () {
    test('coordOf maps lane index onto start + index*spacing', () {
      const lanes = LaneSet(count: 4, start: 100, spacing: 50);
      expect(lanes.coordOf(0), 100);
      expect(lanes.coordOf(1), 150);
      expect(lanes.coordOf(3), 250);
    });

    test('clampLane and coordOf clamp out-of-range indices', () {
      const lanes = LaneSet(count: 3, start: 0, spacing: 10);
      expect(lanes.clampLane(-5), 0);
      expect(lanes.clampLane(99), 2);
      expect(lanes.coordOf(-5), 0); // lane 0
      expect(lanes.coordOf(99), 20); // lane 2
    });

    test('coordOfVisual interpolates and clamps to the track', () {
      const lanes = LaneSet(count: 3, start: 0, spacing: 10);
      expect(lanes.coordOfVisual(1.5), closeTo(15, 1e-9));
      expect(lanes.coordOfVisual(-1), 0);
      expect(lanes.coordOfVisual(5), 20);
    });

    test('checked factory rejects bad input', () {
      expect(
        () => LaneSet.checked(count: 0, start: 0, spacing: 1),
        throwsArgumentError,
      );
      expect(
        () => LaneSet.checked(count: 2, start: double.nan, spacing: 1),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // Hopper
  // ===========================================================================
  group('Hopper', () {
    test('hop moves by direction and clamps at the ends', () {
      final h = Hopper(lane: 0, laneCount: 3);
      h.hop(); // 1
      expect(h.lane, 1);
      h.hop(); // 2
      h.hop(); // clamp at 2
      expect(h.lane, 2);
      h.hop(-5); // clamp at 0
      expect(h.lane, 0);
    });

    test('hopTo jumps straight to a clamped lane', () {
      final h = Hopper(lane: 0, laneCount: 5);
      h.hopTo(3);
      expect(h.lane, 3);
      h.hopTo(99);
      expect(h.lane, 4);
      h.hopTo(-1);
      expect(h.lane, 0);
    });

    test('starting lane is clamped into range', () {
      expect(Hopper(lane: 99, laneCount: 3).lane, 2);
      expect(Hopper(lane: -1, laneCount: 3).lane, 0);
    });

    test('visualLane eases toward lane after update', () {
      final h = Hopper(lane: 0, laneCount: 5);
      h.hopTo(4);
      expect(h.visualLane, 0); // not yet animated
      expect(h.settled, isFalse);
      // Drive several frames; visualLane should approach 4.
      for (var i = 0; i < 60; i++) {
        h.update(1 / 60, speed: 12);
      }
      expect(h.visualLane, closeTo(4.0, 0.01));
      expect(h.settled, isTrue);
    });

    test('snapVisual teleports visualLane to lane', () {
      final h = Hopper(lane: 0, laneCount: 5);
      h.hopTo(2);
      h.snapVisual();
      expect(h.visualLane, 2.0);
      expect(h.settled, isTrue);
    });

    test('rejects laneCount < 1', () {
      expect(() => Hopper(lane: 0, laneCount: 0), throwsArgumentError);
    });
  });

  // ===========================================================================
  // AreaFillGrid
  // ===========================================================================
  group('AreaFillGrid', () {
    test('starts empty with totalCells == cols*rows', () {
      final g = AreaFillGrid(cols: 4, rows: 5);
      expect(g.totalCells, 20);
      expect(g.coverageOf(0), 0);
      expect(g.ownerAt(0, 0), kEmptyCell);
    });

    test('paintCircle claims cells near the center', () {
      final g = AreaFillGrid(cols: 10, rows: 10);
      g.paintCircle(0, const Offset(0.5, 0.5), 0.2);
      expect(g.coverageOf(0), greaterThan(0));
      // Center cell must be owned by player 0.
      expect(g.ownerAt(5, 5), 0);
      // A far corner should remain unpainted.
      expect(g.ownerAt(0, 0), kEmptyCell);
    });

    test('coverageOf and fractionOf agree', () {
      final g = AreaFillGrid(cols: 4, rows: 4); // 16 cells
      g.paintCircle(1, const Offset(0.5, 0.5), 5.0); // covers everything
      expect(g.coverageOf(1), 16);
      expect(g.fractionOf(1), 1.0);
    });

    test('last writer wins on overlap', () {
      final g = AreaFillGrid(cols: 6, rows: 6);
      g.paintCircle(0, const Offset(0.5, 0.5), 0.3);
      final firstCoverage = g.coverageOf(0);
      expect(firstCoverage, greaterThan(0));
      // Player 1 paints the same spot -> takes the cells over.
      g.paintCircle(1, const Offset(0.5, 0.5), 0.3);
      expect(g.ownerAt(3, 3), 1);
      expect(g.coverageOf(0), lessThan(firstCoverage));
    });

    test('a zero radius paints nothing; off-grid paint is a no-op', () {
      final g = AreaFillGrid(cols: 5, rows: 5);
      g.paintCircle(0, const Offset(0.5, 0.5), 0);
      expect(g.coverageOf(0), 0);
      g.paintCircle(0, const Offset(5, 5), 0.1); // way off grid
      expect(g.coverageOf(0), 0);
    });

    test('clear resets ownership', () {
      final g = AreaFillGrid(cols: 4, rows: 4);
      g.paintCircle(2, const Offset(0.5, 0.5), 1.0);
      g.clear();
      expect(g.coverageOf(2), 0);
      expect(g.ownerAt(0, 0), kEmptyCell);
    });

    test('ownerAt throws out of range and ctor rejects bad dims', () {
      final g = AreaFillGrid(cols: 3, rows: 3);
      expect(() => g.ownerAt(3, 0), throwsRangeError);
      expect(() => g.ownerAt(0, -1), throwsRangeError);
      expect(() => AreaFillGrid(cols: 0, rows: 3), throwsArgumentError);
      expect(
        () => g.paintCircle(0, const Offset(0.5, 0.5), -1),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // PushArena
  // ===========================================================================
  group('PushArena', () {
    test('ring mode: a body driven past the ring is eliminated', () {
      final arena = PushArena(
        center: const Offset(0, 0),
        ringRadius: 10,
        friction: 1.0, // frictionless so it keeps moving
      );
      final body = Body(
        id: 0,
        pos: const Offset(0, 0),
        vel: const Offset(100, 0), // fast outward
        radius: 1,
      );
      arena.add(body);
      // One step moves it far outside the ring.
      arena.update(1.0);
      expect(body.alive, isFalse);
      expect(arena.aliveBodies, isEmpty);
    });

    test('ring mode: a body inside the ring stays alive', () {
      final arena = PushArena(center: Offset.zero, ringRadius: 100);
      final body = Body(id: 0, pos: Offset.zero, radius: 2);
      arena.add(body);
      arena.update(1 / 60);
      expect(body.alive, isTrue);
    });

    test('two head-on bodies exchange momentum and separate', () {
      final arena = PushArena(
        center: Offset.zero,
        ringRadius: 1000, // huge so nobody falls off
        friction: 1.0,
        restitution: 1.0, // perfectly elastic
      );
      // Equal mass, approaching head-on along x and overlapping.
      final a = Body(
        id: 0,
        pos: const Offset(-1, 0),
        vel: const Offset(5, 0),
        radius: 1.2, // radii sum 2.4 > 2.0 distance => overlapping
      );
      final b = Body(
        id: 1,
        pos: const Offset(1, 0),
        vel: const Offset(-5, 0),
        radius: 1.2,
      );
      arena.add(a);
      arena.add(b);

      arena.update(1 / 60);

      // Equal-mass elastic head-on swap: a now moves left, b moves right.
      expect(a.vel.dx, lessThan(0));
      expect(b.vel.dx, greaterThan(0));
      // Overlap resolved: centers at least their combined radius apart.
      final gap = (b.pos - a.pos).distance;
      expect(gap, greaterThanOrEqualTo(a.radius + b.radius - 1e-6));
    });

    test('rect mode: a body bounces off a wall and stays alive', () {
      final arena = PushArena(
        center: const Offset(50, 50),
        ringRadius: 10, // irrelevant in rect mode
        friction: 1.0,
        restitution: 1.0,
        bounds: const Rect.fromLTRB(0, 0, 100, 100),
      );
      final body = Body(
        id: 0,
        pos: const Offset(95, 50),
        vel: const Offset(50, 0), // heading into the right wall
        radius: 5,
      );
      arena.add(body);
      expect(arena.isRectBounded, isTrue);

      arena.update(1.0);
      // Reflected: now moving left, still inside, never eliminated.
      expect(body.vel.dx, lessThan(0));
      expect(body.pos.dx, lessThanOrEqualTo(100 - body.radius + 1e-6));
      expect(body.alive, isTrue);
    });

    test('impulse changes velocity of matching alive bodies only', () {
      final arena = PushArena(center: Offset.zero, ringRadius: 1000);
      final p0 = Body(id: 0, pos: Offset.zero, radius: 1);
      final p1 = Body(id: 1, pos: const Offset(50, 0), radius: 1);
      arena.add(p0);
      arena.add(p1);

      arena.impulse(0, const Offset(10, 0));
      expect(p0.vel.dx, closeTo(10, 1e-9));
      expect(p1.vel.dx, 0); // unaffected

      // A non-finite delta is ignored.
      arena.impulse(0, const Offset(double.nan, 0));
      expect(p0.vel.dx, closeTo(10, 1e-9));
    });

    test('aliveBodies excludes eliminated bodies; bodies view is unmodifiable',
        () {
      final arena = PushArena(center: Offset.zero, ringRadius: 5);
      final inside = Body(id: 0, pos: Offset.zero, radius: 1);
      final outside = Body(id: 1, pos: const Offset(100, 0), radius: 1);
      arena.add(inside);
      arena.add(outside);
      arena.update(1 / 60); // outside is culled
      expect(arena.aliveBodies.map((b) => b.id), [0]);
      expect(() => arena.bodies.add(inside), throwsUnsupportedError);
    });

    test('rejects invalid construction and bad bodies', () {
      expect(
        () => PushArena(center: Offset.zero, ringRadius: 0),
        throwsArgumentError,
      );
      expect(
        () => PushArena(center: Offset.zero, ringRadius: 5, friction: 0),
        throwsArgumentError,
      );
      expect(
        () => PushArena(center: Offset.zero, ringRadius: 5, restitution: 2),
        throwsArgumentError,
      );
      expect(
        () => Body(id: 0, pos: Offset.zero, radius: 0),
        throwsArgumentError,
      );
      expect(
        () => Body(id: 0, pos: Offset.zero, radius: 1, mass: 0),
        throwsArgumentError,
      );
    });
  });
}
