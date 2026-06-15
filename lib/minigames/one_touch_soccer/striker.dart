import 'dart:ui';

/// Per-player control state for One-Touch Soccer: a **virtual joystick** that
/// STEERS the striker, plus a brief kick [trail] for the shot streak. Mutable
/// round-scoped state (allowed for the duration of one round — the game
/// integrates these in place every frame).
///
/// CONTROL MODEL (full 2-D agency, still one touch):
///  * On touch-down the game anchors [origin] at the touch point.
///  * While held, [current] follows the finger; the vector [origin] → [current]
///    is the desired move direction and its (clamped) magnitude is the speed.
///  * On release the joystick deactivates and the striker decelerates.
///
/// What a touch DOES with the ball is decided by the GAME, not here: the active
/// TRAP (claiming a loose ball) and the SHOOT (firing an owned ball) live in the
/// game's input handler + sim, so this control object stays a pure steering +
/// trail primitive (no possession state of its own).
class Joystick {
  /// Anchor point (full-screen, normalized 0..1) set on touch-down.
  Offset origin;

  /// Latest finger point (full-screen, normalized 0..1) while held.
  Offset current;

  /// True while a touch is held (the joystick is steering the striker).
  bool active;

  /// The current kick trail anchor, or null when none is active.
  DashTrail? trail;

  Joystick({
    this.origin = Offset.zero,
    this.current = Offset.zero,
    this.active = false,
  });

  /// Begin steering: anchor [origin] (and [current]) at the touch point.
  void press(Offset normPos) {
    origin = normPos;
    current = normPos;
    active = true;
  }

  /// Update the live finger position while held (ignores empty per-frame ticks).
  void drag(Offset normPos) {
    if (active) current = normPos;
  }

  /// Stop steering (striker decelerates to rest).
  void release() {
    active = false;
  }

  /// Raw joystick vector (current − origin) in normalized full-screen space.
  Offset get _rawVector => active ? current - origin : Offset.zero;

  /// Steering output in 0..1, where 1 = full deflection at [maxRadius] and
  /// beyond. Direction is the joystick vector; magnitude maps deflection to
  /// speed. Returns [Offset.zero] when idle or inside the [deadZone].
  Offset steer({required double maxRadius, required double deadZone}) {
    final v = _rawVector;
    final d = v.distance;
    if (!d.isFinite || d <= deadZone) return Offset.zero;
    final dir = v / d;
    final strength = ((d - deadZone) / (maxRadius - deadZone)).clamp(0.0, 1.0);
    return dir * strength;
  }

  /// Advance the trail life by [dt], retiring it once spent.
  void tick(double dt) {
    final t = trail;
    if (t != null) {
      t.life -= dt;
      if (t.life <= 0) trail = null;
    }
  }
}

/// A short-lived directional trail anchor for an auto-kick, used by the renderer
/// to streak motion behind the striker. Mutable round-scoped state.
class DashTrail {
  final Offset from;
  final Offset dir;
  double life;
  final double maxLife;

  DashTrail({required this.from, required this.dir, required this.life})
      : maxLife = life;

  /// 0..1 remaining strength with a linear fade.
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}
