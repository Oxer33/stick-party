import '../../core/math2.dart';

/// Immutable skeletal pose for a side-view stickman.
///
/// All angles are WORLD-space radians (y-down screen convention): `0` points
/// +x (right), `pi/2` points down, `-pi/2` points up. Facing is applied later
/// at render time by mirroring the x component, so a pose authored "facing
/// right" works for both directions.
///
/// A figure has two limbs per side for depth ("back" = farther from camera,
/// drawn behind + dimmer; "front" = nearer, drawn in front). 10 bone angles +
/// a vertical bob ([rootDy]) fully describe a frame.
class StickPose {
  final double spine; // pelvis -> chest
  final double neck; // chest -> head
  final double armBackUpper; // chest -> back elbow
  final double armBackFore; // back elbow -> back hand
  final double armFrontUpper; // chest -> front elbow
  final double armFrontFore; // front elbow -> front hand
  final double legBackThigh; // pelvis -> back knee
  final double legBackShin; // back knee -> back foot
  final double legFrontThigh; // pelvis -> front knee
  final double legFrontShin; // front knee -> front foot

  /// Vertical bob of the pelvis (px, +down). Used for breathing/run bounce.
  final double rootDy;

  const StickPose({
    required this.spine,
    required this.neck,
    required this.armBackUpper,
    required this.armBackFore,
    required this.armFrontUpper,
    required this.armFrontFore,
    required this.legBackThigh,
    required this.legBackShin,
    required this.legFrontThigh,
    required this.legFrontShin,
    this.rootDy = 0,
  });

  StickPose copyWith({
    double? spine,
    double? neck,
    double? armBackUpper,
    double? armBackFore,
    double? armFrontUpper,
    double? armFrontFore,
    double? legBackThigh,
    double? legBackShin,
    double? legFrontThigh,
    double? legFrontShin,
    double? rootDy,
  }) =>
      StickPose(
        spine: spine ?? this.spine,
        neck: neck ?? this.neck,
        armBackUpper: armBackUpper ?? this.armBackUpper,
        armBackFore: armBackFore ?? this.armBackFore,
        armFrontUpper: armFrontUpper ?? this.armFrontUpper,
        armFrontFore: armFrontFore ?? this.armFrontFore,
        legBackThigh: legBackThigh ?? this.legBackThigh,
        legBackShin: legBackShin ?? this.legBackShin,
        legFrontThigh: legFrontThigh ?? this.legFrontThigh,
        legFrontShin: legFrontShin ?? this.legFrontShin,
        rootDy: rootDy ?? this.rootDy,
      );

  /// Shortest-arc interpolation between two poses ([t] in 0..1).
  StickPose lerp(StickPose o, double t) => StickPose(
        spine: lerpAngle(spine, o.spine, t),
        neck: lerpAngle(neck, o.neck, t),
        armBackUpper: lerpAngle(armBackUpper, o.armBackUpper, t),
        armBackFore: lerpAngle(armBackFore, o.armBackFore, t),
        armFrontUpper: lerpAngle(armFrontUpper, o.armFrontUpper, t),
        armFrontFore: lerpAngle(armFrontFore, o.armFrontFore, t),
        legBackThigh: lerpAngle(legBackThigh, o.legBackThigh, t),
        legBackShin: lerpAngle(legBackShin, o.legBackShin, t),
        legFrontThigh: lerpAngle(legFrontThigh, o.legFrontThigh, t),
        legFrontShin: lerpAngle(legFrontShin, o.legFrontShin, t),
        rootDy: lerpD(rootDy, o.rootDy, t),
      );

  /// Compose: keep THIS pose's legs + rootDy, take the upper body (spine, neck,
  /// both arms) from [upper]. Used to layer an attack/cast action over a
  /// running locomotion pose.
  StickPose withUpperFrom(StickPose upper) => StickPose(
        spine: upper.spine,
        neck: upper.neck,
        armBackUpper: upper.armBackUpper,
        armBackFore: upper.armBackFore,
        armFrontUpper: upper.armFrontUpper,
        armFrontFore: upper.armFrontFore,
        legBackThigh: legBackThigh,
        legBackShin: legBackShin,
        legFrontThigh: legFrontThigh,
        legFrontShin: legFrontShin,
        rootDy: rootDy,
      );

  /// Neutral standing pose (facing right). Limbs are slightly staggered so the
  /// front/back pair reads as depth rather than overlapping.
  static final StickPose rest = StickPose(
    spine: rad(-90), // torso straight up
    neck: rad(-90), // head straight up
    armBackUpper: rad(98),
    armBackFore: rad(104),
    armFrontUpper: rad(82),
    armFrontFore: rad(88),
    legBackThigh: rad(96),
    legBackShin: rad(92),
    legFrontThigh: rad(84),
    legFrontShin: rad(90),
  );
}
