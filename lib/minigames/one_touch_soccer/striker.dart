import 'dart:math' as math;
import 'dart:ui';

/// Per-player control state for One-Touch Soccer: a **virtual joystick** that
/// both STEERS the striker and decides what happens on ball contact, plus a
/// short kick [cooldown] and a brief kick [trail]. Mutable round-scoped state
/// (allowed for the duration of one round — the game integrates these in place
/// every frame).
///
/// CONTROL MODEL (full agency, still one touch — the heart of the game):
///  * On touch-down the game anchors [origin] at the touch point AND arms a
///    KICK ([kickArmed] true): one tap = "shoot the next time I reach the ball".
///  * While held, [current] follows the finger; the vector [origin] → [current]
///    is the desired move direction and its (clamped) magnitude is the speed.
///  * On release the joystick deactivates and the striker decelerates.
///
/// Ball contact is then a real DECISION, not an automatic boot:
///  * DEFAULT (no armed kick) → the game TRAPS the ball: it kills most of the
///    ball's speed and keeps it at the striker's feet so you carry / dribble it.
///  * If a KICK is armed ([kickArmed]) → the game shoots, consuming the arm via
///    [consumeKick]; shot power scales with [touchChargeFrac] (time since the
///    last touch of this ball), so a settled ball blasts and a fresh poke nudges.
///
/// Bots never tap, so the game arms their kick directly ([armKick]); they still
/// trap-and-shoot and therefore still score.
class Joystick {
  /// Anchor point (full-screen, normalized 0..1) set on touch-down.
  Offset origin;

  /// Latest finger point (full-screen, normalized 0..1) while held.
  Offset current;

  /// True while a touch is held (the joystick is steering the striker).
  bool active;

  /// True when a KICK is queued for the next ball contact (else contact traps).
  bool kickArmed = false;

  /// Seconds the CURRENT touch has been held active. A quick TAP (released or
  /// resolved before the hold threshold) shoots; holding past it is read as a
  /// steer-to-dribble and disarms the kick so contact traps instead.
  double _heldSec = 0;

  /// Cooldown remaining (seconds) before the striker may touch the ball again.
  double _kickCooldown = 0;

  /// Seconds since this striker last touched the ball, used to charge a shot:
  /// a freshly-touched ball shoots soft, a settled one shoots hard. Grows while
  /// the striker is NOT in contact and is reset to 0 on every touch.
  double _sinceTouch = 0;

  /// The current kick trail anchor, or null when none is active.
  DashTrail? trail;

  Joystick({
    this.origin = Offset.zero,
    this.current = Offset.zero,
    this.active = false,
  });

  /// True when the striker is off its touch cooldown (may trap or kick again).
  bool get canKick => _kickCooldown <= 0;

  /// 0..1 shot charge from time-since-last-touch, saturating at [fullSec]: a
  /// settled ball (no recent touch) returns ~1, a fresh poke returns ~0.
  double touchChargeFrac(double fullSec) =>
      fullSec <= 0 ? 1.0 : (_sinceTouch / fullSec).clamp(0.0, 1.0);

  /// Begin steering: anchor [origin] (and [current]) at the touch point. A press
  /// ARMS a kick for the next contact; if the touch is then HELD past the tap
  /// threshold (see [tick]) it lapses to a dribble, so a quick tap shoots and a
  /// sustained hold carries the ball.
  void press(Offset normPos) {
    origin = normPos;
    current = normPos;
    active = true;
    kickArmed = true;
    _heldSec = 0;
  }

  /// Update the live finger position while held (ignores empty per-frame ticks).
  void drag(Offset normPos) {
    if (active) current = normPos;
  }

  /// Stop steering (striker decelerates to rest).
  void release() {
    active = false;
  }

  /// Directly arm a kick for the next contact (used for bots, which never tap).
  void armNextKick() {
    kickArmed = true;
  }

  /// Consume the queued kick (called when a kick fires) so the touch reverts to
  /// trapping until the player taps again.
  void consumeKick() {
    kickArmed = false;
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

  /// Advance the touch cooldown, the shot charge and the trail life by [dt]. A
  /// touch held active longer than [tapHoldSec] is treated as a dribble-hold and
  /// disarms the queued kick (a quick tap, released sooner, keeps it armed).
  void tick(double dt, {required double tapHoldSec}) {
    if (_kickCooldown > 0) _kickCooldown = math.max(0, _kickCooldown - dt);
    _sinceTouch += dt;
    if (active) {
      _heldSec += dt;
      if (kickArmed && _heldSec > tapHoldSec) kickArmed = false;
    }
    final t = trail;
    if (t != null) {
      t.life -= dt;
      if (t.life <= 0) trail = null;
    }
  }

  /// Mark a ball touch (trap or kick): start the contact recovery cooldown and
  /// reset the shot charge so the next shot must build power again.
  void armKick(double cooldownSec) {
    _kickCooldown = cooldownSec;
    _sinceTouch = 0;
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
