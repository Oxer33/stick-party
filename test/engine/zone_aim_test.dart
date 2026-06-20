import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/engine/helpers/zone_aim.dart';
import 'package:stick_party/engine/input_zones.dart';

/// Normalize an angle into (-pi, pi].
double _wrap(double a) {
  var r = a % (2 * math.pi);
  if (r > math.pi) r -= 2 * math.pi;
  if (r <= -math.pi) r += 2 * math.pi;
  return r;
}

void main() {
  const arena = Size(400, 800);

  // Bottom seat (upright): the standard 2p layout bottom half.
  const bottomZone = PlayerZone(
    playerId: 0,
    normRect: Rect.fromLTRB(0, 0.5, 1, 1),
  );
  // Top seat (flipped 180): the standard 2p layout top half.
  const topZone = PlayerZone(
    playerId: 1,
    normRect: Rect.fromLTRB(0, 0, 1, 0.5),
    rotationQuarters: 2,
  );

  group('rotation correction', () {
    test('rot0 drag UP the screen aims into the arena (negative dy)', () {
      // Arrange: finger drags from lower point to a higher point on screen.
      const press = Offset(0.5, 0.8);
      const cur = Offset(0.5, 0.6); // smaller y == higher on screen

      // Act
      final aim = resolveZoneAim(
        zone: bottomZone,
        pressNorm: press,
        curNorm: cur,
        arena: arena,
      );

      // Assert: angle points up => sin(angle) < 0 (screen +y is down).
      expect(math.sin(aim.angle), lessThan(0));
      expect(aim.hasDrag, isTrue);
    });

    test('rot2 inverts: same raw drag yields rot0 angle + pi (mod 2pi)', () {
      // Arrange: identical RAW screen drag for both seats.
      const press = Offset(0.5, 0.4);
      const cur = Offset(0.5, 0.2);

      // Act
      final bottom = resolveZoneAim(
        zone: bottomZone,
        pressNorm: press,
        curNorm: cur,
        arena: arena,
      );
      final top = resolveZoneAim(
        zone: topZone,
        pressNorm: press,
        curNorm: cur,
        arena: arena,
      );

      // Assert: top angle == bottom angle + pi (mod 2pi).
      final diff = _wrap(top.angle - bottom.angle);
      expect(diff.abs(), closeTo(math.pi, 1e-9));
    });
  });

  group('pullFrac scaling', () {
    test('scales with drag distance', () {
      const press = Offset(0.5, 0.8);
      final small = resolveZoneAim(
        zone: bottomZone,
        pressNorm: press,
        curNorm: const Offset(0.5, 0.78),
        arena: arena,
      );
      final big = resolveZoneAim(
        zone: bottomZone,
        pressNorm: press,
        curNorm: const Offset(0.5, 0.68),
        arena: arena,
      );

      expect(big.pullFrac, greaterThan(small.pullFrac));
    });

    test('clamps at 1.0 for a large drag', () {
      // Arrange: drag spanning the whole zone height -> way past maxPull.
      final aim = resolveZoneAim(
        zone: bottomZone,
        pressNorm: const Offset(0.5, 0.99),
        curNorm: const Offset(0.5, 0.51),
        arena: arena,
      );

      expect(aim.pullFrac, 1.0);
    });

    test('tiny sub-deadzone drag gives hasDrag == false', () {
      // refSide for full-width 2p bottom zone = min(400, 400) = 400 px.
      // deadzone = 400 * 0.05 = 20 px. A 4 px drag is well under.
      final aim = resolveZoneAim(
        zone: bottomZone,
        pressNorm: const Offset(0.5, 0.8),
        curNorm: const Offset(0.51, 0.8), // 0.01 * 400 = 4 px
        arena: arena,
      );

      expect(aim.hasDrag, isFalse);
      expect(aim.pullFrac, lessThan(1.0));
    });
  });

  group('zone-relative reference', () {
    test('small quarter-zone (0.5x0.5) can still reach pullFrac 1.0', () {
      // 4p bottom-left zone: 0.5 wide x 0.5 tall.
      // refSide = min(0.5*400, 0.5*800) = min(200, 400) = 200 px.
      // maxPull span = 200 * 0.32 = 64 px = 0.16 of width (0.16*400=64).
      const quarterZone = PlayerZone(
        playerId: 0,
        normRect: Rect.fromLTRB(0, 0.5, 0.5, 1),
      );

      // Drag 0.25 full-screen norm = 100 px >> 64.
      final aim = resolveZoneAim(
        zone: quarterZone,
        pressNorm: const Offset(0.1, 0.75),
        curNorm: const Offset(0.35, 0.75),
        arena: arena,
      );

      expect(aim.pullFrac, 1.0);
      expect(aim.hasDrag, isTrue);
    });
  });
}
