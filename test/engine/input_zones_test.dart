import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/engine/input_zones.dart';

void main() {
  group('ZoneLayout.forPlayers zone counts', () {
    test('produces one zone per player for 1..4', () {
      // Arrange + Act + Assert
      expect(ZoneLayout.forPlayers(1).zones.length, 1);
      expect(ZoneLayout.forPlayers(2).zones.length, 2);
      expect(ZoneLayout.forPlayers(3).zones.length, 3);
      expect(ZoneLayout.forPlayers(4).zones.length, 4);
    });

    test('clamps out-of-range player counts into 1..4', () {
      // Arrange + Act + Assert
      expect(ZoneLayout.forPlayers(0).zones.length, 1);
      expect(ZoneLayout.forPlayers(-3).zones.length, 1);
      expect(ZoneLayout.forPlayers(9).zones.length, 4);
    });

    test('assigns sequential player ids 0..n-1', () {
      for (final n in [1, 2, 3, 4]) {
        final layout = ZoneLayout.forPlayers(n);
        final ids = layout.zones.map((z) => z.playerId).toSet();
        expect(ids, {for (var i = 0; i < n; i++) i}, reason: 'n=$n');
      }
    });
  });

  group('playerAt resolves zone centers', () {
    test('center of each zone maps to that zone owner for every layout', () {
      for (final n in [1, 2, 3, 4]) {
        final layout = ZoneLayout.forPlayers(n);
        for (final z in layout.zones) {
          // Act
          final hit = layout.playerAt(z.center);
          // Assert
          expect(hit, z.playerId, reason: 'n=$n player=${z.playerId}');
        }
      }
    });

    test('single-player layout owns the whole surface', () {
      final layout = ZoneLayout.forPlayers(1);
      expect(layout.playerAt(const Offset(0.0, 0.0)), 0);
      expect(layout.playerAt(const Offset(0.5, 0.5)), 0);
      expect(layout.playerAt(const Offset(0.99, 0.99)), 0);
    });

    test('two-player split bottom is P0 and top is P1', () {
      final layout = ZoneLayout.forPlayers(2);
      // Bottom half (y > 0.5) belongs to player 0.
      expect(layout.playerAt(const Offset(0.5, 0.75)), 0);
      // Top half (y < 0.5) belongs to player 1.
      expect(layout.playerAt(const Offset(0.5, 0.25)), 1);
    });

    test('four-player quadrants resolve to the right corner owner', () {
      final layout = ZoneLayout.forPlayers(4);
      expect(layout.playerAt(const Offset(0.25, 0.75)), 0); // bottom-left
      expect(layout.playerAt(const Offset(0.75, 0.75)), 1); // bottom-right
      expect(layout.playerAt(const Offset(0.25, 0.25)), 2); // top-left
      expect(layout.playerAt(const Offset(0.75, 0.25)), 3); // top-right
    });
  });

  group('boundary points map to exactly one zone (no overlap)', () {
    test('no normalized grid point is claimed by two zones', () {
      for (final n in [1, 2, 3, 4]) {
        final layout = ZoneLayout.forPlayers(n);
        // Sweep a fine grid; count how many zones contain each point.
        for (var i = 0; i <= 20; i++) {
          for (var j = 0; j <= 20; j++) {
            final p = Offset(i / 20, j / 20);
            final matches = layout.zones.where((z) => z.contains(p)).length;
            // Half-open Rect.contains guarantees at most one owner.
            expect(matches, lessThanOrEqualTo(1),
                reason: 'n=$n point=$p matched $matches zones');
          }
        }
      }
    });

    test('the shared horizontal seam at y=0.5 belongs to one zone only', () {
      // For the 2-player layout the seam y=0.5 is the bottom zone top edge.
      final layout = ZoneLayout.forPlayers(2);
      const seam = Offset(0.5, 0.5);
      final matches = layout.zones.where((z) => z.contains(seam)).length;
      expect(matches, 1);
      // Rect.contains is top-inclusive: y=0.5 lands in the bottom zone (P0).
      expect(layout.playerAt(seam), 0);
    });
  });

  group('points outside all zones return null', () {
    test('negative and >1 coordinates are unowned for every layout', () {
      for (final n in [1, 2, 3, 4]) {
        final layout = ZoneLayout.forPlayers(n);
        expect(layout.playerAt(const Offset(-0.1, 0.5)), isNull, reason: 'n=$n');
        expect(layout.playerAt(const Offset(0.5, -0.1)), isNull, reason: 'n=$n');
        expect(layout.playerAt(const Offset(1.1, 0.5)), isNull, reason: 'n=$n');
        expect(layout.playerAt(const Offset(0.5, 1.1)), isNull, reason: 'n=$n');
      }
    });

    test('the far bottom-right corner (1,1) is exclusive => unowned', () {
      // Rect.fromLTRB is half-open on the high edge, so (1,1) is outside.
      expect(ZoneLayout.forPlayers(1).playerAt(const Offset(1.0, 1.0)), isNull);
    });
  });

  group('rotationQuarters orient HUD per edge', () {
    test('bottom-edge zones are upright (rot 0), top-edge zones flipped (rot 2)',
        () {
      final layout = ZoneLayout.forPlayers(4);
      PlayerZone z(int id) => layout.forPlayer(id)!;
      // Bottom row.
      expect(z(0).rotationQuarters, 0);
      expect(z(1).rotationQuarters, 0);
      // Top row.
      expect(z(2).rotationQuarters, 2);
      expect(z(3).rotationQuarters, 2);
    });

    test('single player is upright', () {
      expect(ZoneLayout.forPlayers(1).forPlayer(0)!.rotationQuarters, 0);
    });

    test('two-player: bottom upright, top flipped', () {
      final layout = ZoneLayout.forPlayers(2);
      expect(layout.forPlayer(0)!.rotationQuarters, 0);
      expect(layout.forPlayer(1)!.rotationQuarters, 2);
    });

    test('top zones sit above bottom zones on screen', () {
      // A rot-2 (top) zone's center y must be smaller than a rot-0 zone's.
      final layout = ZoneLayout.forPlayers(4);
      final topY = layout.forPlayer(2)!.center.dy;
      final bottomY = layout.forPlayer(0)!.center.dy;
      expect(topY, lessThan(bottomY));
    });
  });

  group('forPlayer lookup', () {
    test('returns the matching zone or null for an unknown id', () {
      final layout = ZoneLayout.forPlayers(3);
      expect(layout.forPlayer(0), isNotNull);
      expect(layout.forPlayer(2), isNotNull);
      expect(layout.forPlayer(3), isNull);
      expect(layout.forPlayer(-1), isNull);
    });
  });
}
