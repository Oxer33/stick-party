import 'dart:math' as math;
import 'dart:ui';

import 'stick_pose.dart';

/// Joint index used by the ragdoll (one verlet particle per joint).
enum Joint {
  pelvis,
  chest,
  head,
  backElbow,
  backHand,
  frontElbow,
  frontHand,
  backKnee,
  backFoot,
  frontKnee,
  frontFoot,
}

/// Bone lengths/widths in local px. Scale up for bigger enemies/bosses.
class StickProportions {
  final double spine;
  final double neck;
  final double head; // head radius
  final double upperArm;
  final double foreArm;
  final double thigh;
  final double shin;
  final double torsoWidth;
  final double limbWidth;

  const StickProportions({
    required this.spine,
    required this.neck,
    required this.head,
    required this.upperArm,
    required this.foreArm,
    required this.thigh,
    required this.shin,
    required this.torsoWidth,
    required this.limbWidth,
  });

  /// Default hunter proportions (~52 px tall).
  static const hero = StickProportions(
    spine: 30,
    neck: 12,
    head: 9,
    upperArm: 20,
    foreArm: 18,
    thigh: 22,
    shin: 22,
    torsoWidth: 6.5,
    limbWidth: 4.5,
  );

  StickProportions scaled(double s) => StickProportions(
        spine: spine * s,
        neck: neck * s,
        head: head * s,
        upperArm: upperArm * s,
        foreArm: foreArm * s,
        thigh: thigh * s,
        shin: shin * s,
        torsoWidth: torsoWidth * s,
        limbWidth: limbWidth * s,
      );
}

/// Resolved joint positions in render space (after FK + facing + root).
class StickFrame {
  final Offset pelvis;
  final Offset chest;
  final Offset headCenter;
  final Offset backElbow;
  final Offset backHand;
  final Offset frontElbow;
  final Offset frontHand;
  final Offset backKnee;
  final Offset backFoot;
  final Offset frontKnee;
  final Offset frontFoot;
  final double headRadius;
  final double torsoWidth;
  final double limbWidth;
  final double facing; // -1 / +1
  final double aimAngle; // weapon aim from front hand (world radians)

  const StickFrame({
    required this.pelvis,
    required this.chest,
    required this.headCenter,
    required this.backElbow,
    required this.backHand,
    required this.frontElbow,
    required this.frontHand,
    required this.backKnee,
    required this.backFoot,
    required this.frontKnee,
    required this.frontFoot,
    required this.headRadius,
    required this.torsoWidth,
    required this.limbWidth,
    required this.facing,
    required this.aimAngle,
  });

  Offset jointPos(Joint j) {
    switch (j) {
      case Joint.pelvis:
        return pelvis;
      case Joint.chest:
        return chest;
      case Joint.head:
        return headCenter;
      case Joint.backElbow:
        return backElbow;
      case Joint.backHand:
        return backHand;
      case Joint.frontElbow:
        return frontElbow;
      case Joint.frontHand:
        return frontHand;
      case Joint.backKnee:
        return backKnee;
      case Joint.backFoot:
        return backFoot;
      case Joint.frontKnee:
        return frontKnee;
      case Joint.frontFoot:
        return frontFoot;
    }
  }
}

/// Forward kinematics: resolve a [StickPose] into world-space joint positions.
///
/// [root] is the pelvis anchor. [facing] mirrors the x axis (+1 right, -1 left).
/// [aimAngle] is an optional weapon aim override (defaults to "forward").
class StickSkeleton {
  final StickProportions p;
  const StickSkeleton([this.p = StickProportions.hero]);

  Offset _seg(double angle, double len, double facing) =>
      Offset(math.cos(angle) * len * facing, math.sin(angle) * len);

  StickFrame resolve(
    StickPose pose,
    Offset root,
    double facing, {
    double? aimAngle,
  }) {
    final pelvis = root + Offset(0, pose.rootDy);
    final chest = pelvis + _seg(pose.spine, p.spine, facing);
    final headBase = chest + _seg(pose.neck, p.neck, facing);
    final headCenter = headBase + _seg(pose.neck, p.head, facing);

    final backElbow = chest + _seg(pose.armBackUpper, p.upperArm, facing);
    final backHand = backElbow + _seg(pose.armBackFore, p.foreArm, facing);
    final frontElbow = chest + _seg(pose.armFrontUpper, p.upperArm, facing);
    final frontHand = frontElbow + _seg(pose.armFrontFore, p.foreArm, facing);

    final backKnee = pelvis + _seg(pose.legBackThigh, p.thigh, facing);
    final backFoot = backKnee + _seg(pose.legBackShin, p.shin, facing);
    final frontKnee = pelvis + _seg(pose.legFrontThigh, p.thigh, facing);
    final frontFoot = frontKnee + _seg(pose.legFrontShin, p.shin, facing);

    return StickFrame(
      pelvis: pelvis,
      chest: chest,
      headCenter: headCenter,
      backElbow: backElbow,
      backHand: backHand,
      frontElbow: frontElbow,
      frontHand: frontHand,
      backKnee: backKnee,
      backFoot: backFoot,
      frontKnee: frontKnee,
      frontFoot: frontFoot,
      headRadius: p.head,
      torsoWidth: p.torsoWidth,
      limbWidth: p.limbWidth,
      facing: facing,
      aimAngle: aimAngle ?? (facing > 0 ? 0 : math.pi),
    );
  }
}
