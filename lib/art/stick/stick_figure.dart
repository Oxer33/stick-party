import 'dart:ui';

import 'stick_animator.dart';
import 'stick_clips.dart';
import 'stick_ragdoll.dart';
import 'stick_skeleton.dart';
import 'stick_style.dart';
import 'stickman_painter.dart';
import 'weapon_visual.dart';

/// High-level locomotion state mapped to a locomotion clip.
enum LocoState { idle, run, jump, fall }

/// Binds the skeletal animation pieces (animator + skeleton + style + optional
/// ragdoll) into a single drivable figure. Owns NO world position — callers
/// pass the render [root]; in ragdoll mode the figure renders its own frame.
///
/// Used by the player, enemies, shadow wraiths and bosses (each with a
/// different [StickStyle] / [StickProportions] / [WeaponVisual]).
class StickFigure {
  final StickSkeleton skeleton;
  StickStyle style;
  WeaponVisual weapon;
  double facing; // -1 / +1
  double aimAngle;

  final StickAnimator _anim;
  StickRagdoll? _ragdoll;
  LocoState _loco = LocoState.idle;

  StickFigure({
    StickProportions proportions = StickProportions.hero,
    this.style = StickStyle.hero,
    this.weapon = WeaponVisual.none,
    this.facing = 1,
    this.aimAngle = 0,
  })  : skeleton = StickSkeleton(proportions),
        _anim = StickAnimator(initial: StickClips.idle);

  bool get isRagdoll => _ragdoll != null;
  LocoState get loco => _loco;
  bool get actionPlaying => _anim.actionPlaying;

  void setLoco(LocoState s) {
    if (s == _loco) return;
    _loco = s;
    switch (s) {
      case LocoState.idle:
        _anim.setLocomotion(StickClips.idle);
        break;
      case LocoState.run:
        _anim.setLocomotion(StickClips.run);
        break;
      case LocoState.jump:
        _anim.setLocomotion(StickClips.jump);
        break;
      case LocoState.fall:
        _anim.setLocomotion(StickClips.fall);
        break;
    }
  }

  void attack(int comboIndex) {
    final clip = switch (comboIndex % 3) {
      0 => StickClips.attack1,
      1 => StickClips.attack2,
      _ => StickClips.attack3,
    };
    _anim.playAction(clip, upperOnly: true);
  }

  void special() => _anim.playAction(StickClips.special, upperOnly: true);
  void cast() => _anim.playAction(StickClips.cast, upperOnly: true);
  void hurt() => _anim.playAction(StickClips.hurt, upperOnly: true);
  void dash() => _anim.playAction(StickClips.dash, upperOnly: false);
  void land() => _anim.playAction(StickClips.land, upperOnly: false);

  /// Full-body celebration (arms-up cheer). Play on the match winner so the
  /// round ends on a reaction instead of an idle freeze.
  void victory() => _anim.playAction(StickClips.victory, upperOnly: false);

  /// Switch into ragdoll mode (death / heavy knockback). [root] is the current
  /// render anchor used to seed the ragdoll in the same space; [groundY] is the
  /// floor in that space; [impulse] flings the body.
  void enterRagdoll(Offset root, double groundY, Offset impulse) {
    final frame =
        skeleton.resolve(_anim.current(), root, facing, aimAngle: aimAngle);
    _ragdoll = StickRagdoll.fromFrame(frame, groundY: groundY, impulse: impulse);
  }

  void exitRagdoll() => _ragdoll = null;

  void update(double dt) {
    if (_ragdoll != null) {
      _ragdoll!.update(dt);
    } else {
      _anim.update(dt);
    }
  }

  /// Resolve + paint at [root]. In ragdoll mode [root] is ignored.
  void render(Canvas canvas, Offset root) {
    final StickFrame frame = _ragdoll != null
        ? _ragdoll!.toFrame()
        : skeleton.resolve(_anim.current(), root, facing, aimAngle: aimAngle);
    StickmanPainter.paint(canvas, frame, style, weapon: weapon);
  }
}
