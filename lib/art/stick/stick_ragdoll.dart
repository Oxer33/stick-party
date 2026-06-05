import 'dart:math' as math;
import 'dart:ui';

import 'stick_skeleton.dart';

class _Particle {
  Offset pos;
  Offset prev;
  _Particle(this.pos, this.prev);
}

class _Bone {
  final Joint a;
  final Joint b;
  final double len;
  final double stiffness;
  const _Bone(this.a, this.b, this.len, [this.stiffness = 1.0]);
}

/// Lightweight Verlet ragdoll. One particle per [Joint], distance constraints
/// for bones (+ a stiffener for the spine), gravity, floor collision with
/// friction, and global damping. Seeded from a live [StickFrame] plus an impulse
/// so a killed/knocked stickman flings and tumbles (juice).
///
/// Operates in whatever coordinate space the seed frame lives in; [groundY] is
/// in that same space. No external physics dependency.
class StickRagdoll {
  final Map<Joint, _Particle> _pts = {};
  final List<_Bone> _bones;
  final double groundY;
  final double headRadius;
  final double torsoWidth;
  final double limbWidth;
  final double facing;

  double _age = 0;
  static const double _gravity = 1800;
  static const double _damping = 0.992;
  static const double _floorFriction = 0.7;
  static const int _iterations = 6;

  StickRagdoll._(this._bones, this.groundY, this.headRadius, this.torsoWidth,
      this.limbWidth, this.facing);

  double get age => _age;

  /// Build a ragdoll from a live frame. [impulse] is applied as an initial
  /// velocity (encoded into the verlet prev-position offset).
  factory StickRagdoll.fromFrame(
    StickFrame f, {
    required double groundY,
    Offset impulse = Offset.zero,
  }) {
    final bones = <_Bone>[
      _Bone(Joint.pelvis, Joint.chest, (f.pelvis - f.chest).distance, 1.0),
      _Bone(Joint.chest, Joint.head, (f.chest - f.headCenter).distance, 1.0),
      _Bone(Joint.chest, Joint.backElbow, (f.chest - f.backElbow).distance),
      _Bone(Joint.backElbow, Joint.backHand, (f.backElbow - f.backHand).distance),
      _Bone(Joint.chest, Joint.frontElbow, (f.chest - f.frontElbow).distance),
      _Bone(Joint.frontElbow, Joint.frontHand, (f.frontElbow - f.frontHand).distance),
      _Bone(Joint.pelvis, Joint.backKnee, (f.pelvis - f.backKnee).distance),
      _Bone(Joint.backKnee, Joint.backFoot, (f.backKnee - f.backFoot).distance),
      _Bone(Joint.pelvis, Joint.frontKnee, (f.pelvis - f.frontKnee).distance),
      _Bone(Joint.frontKnee, Joint.frontFoot, (f.frontKnee - f.frontFoot).distance),
      // Stiffener keeps the torso from collapsing.
      _Bone(Joint.pelvis, Joint.head, (f.pelvis - f.headCenter).distance, 0.4),
    ];
    final rd = StickRagdoll._(bones, groundY, f.headRadius, f.torsoWidth,
        f.limbWidth, f.facing);

    // prev = pos - impulse*scaled so initial velocity ~ impulse.
    final imp = impulse * (1 / 60.0);
    void put(Joint j, Offset p, {Offset extra = Offset.zero}) {
      rd._pts[j] = _Particle(p, p - imp - extra);
    }

    put(Joint.pelvis, f.pelvis);
    put(Joint.chest, f.chest);
    put(Joint.head, f.headCenter, extra: Offset(imp.dx * 0.4, 0));
    put(Joint.backElbow, f.backElbow);
    put(Joint.backHand, f.backHand, extra: Offset(0, -imp.dy * 0.3));
    put(Joint.frontElbow, f.frontElbow);
    put(Joint.frontHand, f.frontHand, extra: Offset(0, -imp.dy * 0.3));
    put(Joint.backKnee, f.backKnee);
    put(Joint.backFoot, f.backFoot);
    put(Joint.frontKnee, f.frontKnee);
    put(Joint.frontFoot, f.frontFoot);
    return rd;
  }

  void update(double dt) {
    if (dt <= 0) return;
    final d = dt.clamp(0.0, 0.033);
    _age += d;
    final g = _gravity * d * d;

    for (final p in _pts.values) {
      final vx = (p.pos.dx - p.prev.dx) * _damping;
      final vy = (p.pos.dy - p.prev.dy) * _damping;
      p.prev = p.pos;
      p.pos = Offset(p.pos.dx + vx, p.pos.dy + vy + g);
    }

    for (var i = 0; i < _iterations; i++) {
      _solveBones();
      _solveFloor();
    }
  }

  void _solveBones() {
    for (final b in _bones) {
      final pa = _pts[b.a];
      final pb = _pts[b.b];
      if (pa == null || pb == null) continue;
      final delta = pb.pos - pa.pos;
      final dist = delta.distance;
      if (dist <= 1e-6) continue;
      final diff = (dist - b.len) / dist * b.stiffness;
      final half = delta * 0.5 * diff;
      pa.pos = pa.pos + half;
      pb.pos = pb.pos - half;
    }
  }

  void _solveFloor() {
    for (final p in _pts.values) {
      if (p.pos.dy > groundY) {
        // Friction: pull x toward prev.x to kill horizontal slide on contact.
        final fx = p.prev.dx + (p.pos.dx - p.prev.dx) * _floorFriction;
        p.pos = Offset(p.pos.dx, groundY);
        p.prev = Offset(fx, groundY);
      }
    }
  }

  Offset _pos(Joint j) => _pts[j]?.pos ?? Offset.zero;

  /// Rebuild a [StickFrame] from current particle positions for rendering.
  StickFrame toFrame() {
    final aim = facing > 0 ? 0.0 : math.pi;
    return StickFrame(
      pelvis: _pos(Joint.pelvis),
      chest: _pos(Joint.chest),
      headCenter: _pos(Joint.head),
      backElbow: _pos(Joint.backElbow),
      backHand: _pos(Joint.backHand),
      frontElbow: _pos(Joint.frontElbow),
      frontHand: _pos(Joint.frontHand),
      backKnee: _pos(Joint.backKnee),
      backFoot: _pos(Joint.backFoot),
      frontKnee: _pos(Joint.frontKnee),
      frontFoot: _pos(Joint.frontFoot),
      headRadius: headRadius,
      torsoWidth: torsoWidth,
      limbWidth: limbWidth,
      facing: facing,
      aimAngle: aim,
    );
  }
}
