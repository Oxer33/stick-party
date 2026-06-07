import 'dart:math' as math;
import 'dart:ui';

/// Per-player control state for One-Touch Soccer: a sweeping [aim], a [charge]
/// that fills while the touch is held, a recovery [cooldown] and a short dash
/// [trail]. Mutable round-scoped state (allowed for the duration of one round —
/// the game integrates these in place every frame).
///
/// The owning game decides what to do with these: sweep [aim] when idle, fill
/// [charge] while [charging], and on release commit a dash (low charge) or a
/// power-kick lunge (high charge) in the [aim] direction. Nothing here homes
/// onto the ball — the player aims everything.
class Striker {
  /// Current aim angle in radians (the direction of the next dash / kick).
  double aim;

  /// True while the touch is held (aim locks, [charge] fills).
  bool charging = false;

  /// Charge level in 0..1 while held; mapped to dash↔power-kick strength.
  double charge = 0;

  /// Cooldown remaining (seconds) before the next action is allowed.
  double _cooldown = 0;

  /// Ground-ring flash 0..1 that brightens briefly after an action.
  double _flash = 0;

  /// The current dash trail anchor, or null when none is active.
  DashTrail? trail;

  Striker({required this.aim});

  /// True when off cooldown (ready to start charging / act).
  bool get ready => _cooldown <= 0;

  /// 0..1 ground-ring flash for the renderer.
  double get flash => _flash.clamp(0.0, 1.0);

  /// Advance cooldown, flash decay and the trail life by [dt].
  void tick(double dt) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (_flash > 0) _flash = math.max(0, _flash - _flashDecayPerSec * dt);
    final t = trail;
    if (t != null) {
      t.life -= dt;
      if (t.life <= 0) trail = null;
    }
  }

  /// Start the recovery cooldown and raise the ground-ring flash to [charge].
  void fire(double cooldownSec, {double charge = 0}) {
    _cooldown = cooldownSec;
    final f = charge.clamp(0.0, 1.0);
    if (f > _flash) _flash = f;
  }

  static const double _flashDecayPerSec = 5.0;
}

/// A short-lived directional trail anchor for a dash / kick, used by the
/// renderer to streak motion behind a striker. Mutable round-scoped state.
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
