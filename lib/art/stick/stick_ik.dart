import 'dart:math' as math;
import 'dart:ui';

/// Result of a 2-bone IK solve: the two world-space bone angles.
class IkSolution {
  final double angle1; // root -> mid
  final double angle2; // mid -> end
  const IkSolution(this.angle1, this.angle2);
}

/// Analytic 2-bone inverse kinematics (law of cosines) for placing a hand or
/// foot at [target] from [rootPos], with bone lengths [len1] and [len2].
///
/// [bendSign] chooses the elbow/knee bend direction (+1 / -1). [facing] mirrors
/// the solution so it matches the figure's facing. Returns world-space angles
/// consumable directly as pose angles. Degrades gracefully when the target is
/// out of reach (arm fully extended toward it).
IkSolution solveTwoBoneIk(
  Offset rootPos,
  Offset target,
  double len1,
  double len2, {
  double bendSign = 1,
  double facing = 1,
}) {
  // Work in un-mirrored space: undo facing on the x delta.
  final dx = (target.dx - rootPos.dx) * (facing >= 0 ? 1 : -1);
  final dy = target.dy - rootPos.dy;
  var dist = math.sqrt(dx * dx + dy * dy);
  final maxReach = len1 + len2;
  final minReach = (len1 - len2).abs();
  dist = dist.clamp(minReach + 1e-3, maxReach - 1e-3);

  final baseAngle = math.atan2(dy, dx);

  // Angle at the root between bone-1 and the root->target line.
  final cosA =
      ((len1 * len1 + dist * dist - len2 * len2) / (2 * len1 * dist))
          .clamp(-1.0, 1.0);
  final a = math.acos(cosA);

  // Interior angle at the mid joint.
  final cosB =
      ((len1 * len1 + len2 * len2 - dist * dist) / (2 * len1 * len2))
          .clamp(-1.0, 1.0);
  final b = math.acos(cosB);

  final angle1 = baseAngle - bendSign * a;
  final angle2 = angle1 + bendSign * (math.pi - b);
  return IkSolution(angle1, angle2);
}
