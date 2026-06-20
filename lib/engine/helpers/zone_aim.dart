import 'dart:math' as math;
import 'dart:ui';

import '../input_zones.dart';

/// Result of resolving a manual-aim gesture inside a player's zone.
///
/// [angle] is in radians in SCREEN space (atan2 convention: +x right, +y down,
/// so "up the screen" is a negative angle near -pi/2). [pullFrac] is the drag
/// strength normalized to 0..1. [hasDrag] is false when the finger has not yet
/// moved past the deadzone (caller can then fall back to auto-aim).
class ZoneAim {
  final double angle;
  final double pullFrac;
  final bool hasDrag;

  const ZoneAim({
    required this.angle,
    required this.pullFrac,
    required this.hasDrag,
  });
}

/// Resolve a finger-anchored, rotation-corrected, zone-relative aim.
///
/// WHY THIS EXISTS
/// In 2-4 player splits the screen is divided into per-player [PlayerZone]s.
/// The runner routes a touch to a player by which zone it landed in, but the
/// central-arena games (sumo/bumper/tank/archer) then computed aim from the
/// avatar's WORLD/screen position. Two bugs followed:
///   (a) A player's finger is confined to their own zone while their avatar is
///       central, so avatar-relative aim could only ever point back toward that
///       player's own rim. Manual aim was unusable.
///   (b) Rotation was ignored, so a top-seat (rotationQuarters == 2) player's
///       "drag away from my body / into the arena" came out INVERTED.
///
/// THE FIX
/// Aim is computed purely from the gesture WITHIN the zone, anchored to where
/// the finger went down (press) rather than to the avatar. The vector is then
/// rotation-corrected so "drag away from my body edge" means "into the arena"
/// for every seat, regardless of where the avatar sits.
///
/// Distance is measured against the player's ZONE size (its shorter side), so a
/// small quarter-zone (4p) still reaches full power with a short drag.
///
/// - [pressNorm]/[curNorm]: 0..1 FULL-SCREEN normalized points (press = finger
///   down, cur = current finger position).
/// - [arena]: pixel size used to de-skew the angle (so aspect ratio doesn't
///   distort direction).
/// - [deadzoneFrac]/[maxPullFrac]: fractions of the zone's reference side.
ZoneAim resolveZoneAim({
  required PlayerZone zone,
  required Offset pressNorm,
  required Offset curNorm,
  required Size arena,
  double deadzoneFrac = 0.05,
  double maxPullFrac = 0.32,
}) {
  // 1. Convert normalized full-screen points to pixels so the angle is not
  //    skewed by the screen aspect ratio.
  final pressPx =
      Offset(pressNorm.dx * arena.width, pressNorm.dy * arena.height);
  final curPx = Offset(curNorm.dx * arena.width, curNorm.dy * arena.height);

  // 2. Gesture vector, anchored to the press point (NOT the avatar).
  final raw = curPx - pressPx;

  // 3. Rotation-correct so "away from my body edge" == "into the arena" for
  //    every seat. Only rot0 and rot2 occur in this game, but a general
  //    rotate-by-quarters keeps it correct for 1 and 3 too.
  final corrected = _rotateByQuarters(raw, zone.rotationQuarters);

  // 4. Distance reference = shorter side of the zone in pixels, so a small
  //    quarter-zone still reaches full power on a short drag.
  final zoneWidthPx = zone.normRect.width * arena.width;
  final zoneHeightPx = zone.normRect.height * arena.height;
  final refSide = math.min(zoneWidthPx, zoneHeightPx);

  final dist = corrected.distance;
  final pullFrac =
      (refSide <= 0) ? 0.0 : (dist / (refSide * maxPullFrac)).clamp(0.0, 1.0);
  final hasDrag = refSide > 0 && dist >= refSide * deadzoneFrac;

  // 5. Angle in screen space. Returned even when !hasDrag; the caller decides
  //    whether to use it or fall back to auto-aim.
  final angle = math.atan2(corrected.dy, corrected.dx);

  return ZoneAim(angle: angle, pullFrac: pullFrac, hasDrag: hasDrag);
}

/// Rotate [v] clockwise by [quarters] * 90 degrees in screen space (+x right,
/// +y down). q%4: 0 = identity, 1 = 90 CW, 2 = 180, 3 = 270 CW.
Offset _rotateByQuarters(Offset v, int quarters) {
  switch (quarters % 4) {
    case 1:
      return Offset(-v.dy, v.dx);
    case 2:
      return Offset(-v.dx, -v.dy);
    case 3:
      return Offset(v.dy, -v.dx);
    default:
      return v;
  }
}
