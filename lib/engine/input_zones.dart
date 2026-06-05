import 'dart:ui';

import 'player_manager.dart';

/// One player's slice of the screen, in normalized 0..1 space.
/// [rotationQuarters] rotates that player's HUD/button to face them
/// (0 = upright/bottom edge, 2 = 180°/top edge).
class PlayerZone {
  final int playerId;
  final Rect normRect;
  final int rotationQuarters;

  const PlayerZone({
    required this.playerId,
    required this.normRect,
    this.rotationQuarters = 0,
  });

  bool contains(Offset normPoint) => normRect.contains(normPoint);

  /// Center of the zone in normalized space (handy for HUD anchoring).
  Offset get center => normRect.center;
}

/// Maps touch points to players. Pure routing — unit-testable without Flutter.
class ZoneLayout {
  final List<PlayerZone> zones;

  const ZoneLayout(this.zones);

  /// Resolve a normalized (0..1) point to a player id, or null if outside all.
  /// Rect.contains is half-open, so adjacent zones never both match.
  int? playerAt(Offset normPoint) {
    for (final z in zones) {
      if (z.contains(normPoint)) return z.playerId;
    }
    return null;
  }

  PlayerZone? forPlayer(int id) {
    for (final z in zones) {
      if (z.playerId == id) return z;
    }
    return null;
  }

  /// Build the standard layout for [n] players (1..4).
  /// Flat-device ergonomics: bottom edge upright (rot0), top edge flipped (rot2).
  factory ZoneLayout.forPlayers(int n, {GameMode mode = GameMode.ffa}) {
    switch (n.clamp(1, 4)) {
      case 1:
        return const ZoneLayout([
          PlayerZone(playerId: 0, normRect: Rect.fromLTRB(0, 0, 1, 1)),
        ]);
      case 2:
        return const ZoneLayout([
          PlayerZone(playerId: 0, normRect: Rect.fromLTRB(0, 0.5, 1, 1)),
          PlayerZone(
              playerId: 1,
              normRect: Rect.fromLTRB(0, 0, 1, 0.5),
              rotationQuarters: 2),
        ]);
      case 3:
        return const ZoneLayout([
          PlayerZone(playerId: 0, normRect: Rect.fromLTRB(0, 0.5, 1, 1)),
          PlayerZone(
              playerId: 1,
              normRect: Rect.fromLTRB(0, 0, 0.5, 0.5),
              rotationQuarters: 2),
          PlayerZone(
              playerId: 2,
              normRect: Rect.fromLTRB(0.5, 0, 1, 0.5),
              rotationQuarters: 2),
        ]);
      default: // 4
        return const ZoneLayout([
          PlayerZone(playerId: 0, normRect: Rect.fromLTRB(0, 0.5, 0.5, 1)),
          PlayerZone(playerId: 1, normRect: Rect.fromLTRB(0.5, 0.5, 1, 1)),
          PlayerZone(
              playerId: 2,
              normRect: Rect.fromLTRB(0, 0, 0.5, 0.5),
              rotationQuarters: 2),
          PlayerZone(
              playerId: 3,
              normRect: Rect.fromLTRB(0.5, 0, 1, 0.5),
              rotationQuarters: 2),
        ]);
    }
  }
}
