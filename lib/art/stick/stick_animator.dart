import '../../core/math2.dart';
import 'stick_clips.dart';
import 'stick_pose.dart';

/// Drives skeletal animation: a looping locomotion clip (idle/run/jump/fall)
/// with crossfade on change, plus an optional one-shot upper-body action clip
/// (attack/cast/hurt/dash) layered on top. Pure logic — no rendering.
class StickAnimator {
  StickClip _loco;
  double _locoTime = 0;

  // Crossfade between locomotion clips.
  StickPose? _blendFrom;
  double _blend = 1; // 1 = fully on target
  static const double _blendDur = 0.12;

  // One-shot action layered over the upper body.
  StickClip? _action;
  double _actionTime = 0;
  bool _actionUpperOnly = true;

  StickPose _lastLoco;

  StickAnimator({StickClip? initial})
      : _loco = initial ?? StickClips.idle,
        _lastLoco = (initial ?? StickClips.idle).sample(0);

  bool get actionPlaying => _action != null;
  String get locomotionName => _loco.name;

  /// Switch the looping locomotion clip with a short crossfade. No-op if already
  /// on [clip].
  void setLocomotion(StickClip clip) {
    if (identical(clip, _loco)) return;
    _blendFrom = _lastLoco;
    _blend = 0;
    _loco = clip;
    _locoTime = 0;
  }

  /// Play a one-shot action. [upperOnly] true layers it over the upper body so
  /// the legs keep running; false replaces the whole pose (dash/roll).
  void playAction(StickClip clip, {bool upperOnly = true}) {
    _action = clip;
    _actionTime = 0;
    _actionUpperOnly = upperOnly;
  }

  void clearAction() {
    _action = null;
  }

  void update(double dt) {
    if (dt <= 0) return;
    final d = dt.clamp(0.0, 0.1);
    _locoTime += d;
    if (_blend < 1) {
      _blend = (_blend + d / _blendDur).clamp(0.0, 1.0);
    }
    if (_action != null) {
      _actionTime += d;
      if (!_action!.loop && _actionTime >= _action!.duration) {
        _action = null;
      }
    }
  }

  /// The composed pose for this frame.
  StickPose current() {
    var loco = _loco.sample(_locoTime);
    if (_blend < 1 && _blendFrom != null) {
      loco = _blendFrom!.lerp(loco, easeInOut(_blend));
    }
    _lastLoco = loco;

    final action = _action;
    if (action == null) return loco;

    final actionPose = action.sample(_actionTime);
    return _actionUpperOnly ? loco.withUpperFrom(actionPose) : actionPose;
  }
}
