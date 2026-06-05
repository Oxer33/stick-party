import '../../core/math2.dart';

/// A fixed set of evenly-spaced discrete lanes mapped to a 1-D coordinate.
///
/// "Lane" is the abstract position index; the concrete pixel position is
/// [start] + index * [spacing]. Set [vertical] only for documentation/intent —
/// the math is identical on either axis; the caller decides whether the
/// returned coordinate is an x or a y.
///
/// Used by Falling Dodge (horizontal lanes the player slides between) and
/// Chicken Jump (vertical platforms the player hops up).
class LaneSet {
  /// Number of lanes. Valid indices are `0 .. count - 1`.
  final int count;

  /// Coordinate of lane 0.
  final double start;

  /// Distance between adjacent lane coordinates (may be negative to go "up").
  final double spacing;

  /// Intent flag: true when lanes run along the vertical axis. Purely
  /// descriptive — does not change [coordOf].
  final bool vertical;

  /// Creates a lane set.
  ///
  /// Throws [ArgumentError] when [count] < 1 or when [start]/[spacing] are
  /// non-finite.
  const LaneSet({
    required this.count,
    required this.start,
    required this.spacing,
    this.vertical = false,
  }) : assert(count >= 1, 'count must be >= 1');

  /// Validating factory (use when inputs come from data/config).
  factory LaneSet.checked({
    required int count,
    required double start,
    required double spacing,
    bool vertical = false,
  }) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be >= 1');
    }
    if (!finite(start) || !finite(spacing)) {
      throw ArgumentError('start/spacing must be finite '
          '(start=$start, spacing=$spacing)');
    }
    return LaneSet(
        count: count, start: start, spacing: spacing, vertical: vertical);
  }

  /// Clamp an arbitrary integer to the valid lane range `0 .. count - 1`.
  int clampLane(int lane) {
    if (lane < 0) return 0;
    if (lane > count - 1) return count - 1;
    return lane;
  }

  /// The coordinate of [lane] (clamped to the valid range first).
  double coordOf(int lane) => start + clampLane(lane) * spacing;

  /// Continuous coordinate for a fractional lane position, used to place a
  /// smoothly-animating actor between two lanes. Not clamped to integers, but
  /// clamped to `[0, count - 1]` so it never runs off the track.
  double coordOfVisual(double visualLane) {
    final v = clampD(visualLane, 0, (count - 1).toDouble());
    return start + v * spacing;
  }
}

/// A token that occupies one [LaneSet] lane and hops between lanes, with a
/// separately-smoothed [visualLane] for animation.
///
/// The logical [lane] snaps instantly (it is what gameplay/collision reads),
/// while [visualLane] eases toward it inside [update] so the rendered sprite
/// glides rather than teleports.
class Hopper {
  /// Total number of lanes available to this hopper.
  final int laneCount;

  int _lane;
  double _visualLane;

  /// Creates a hopper starting on [lane] within a track of [laneCount] lanes.
  ///
  /// Throws [ArgumentError] when [laneCount] < 1. The starting [lane] is
  /// clamped into range.
  Hopper({required int lane, required this.laneCount})
      : _lane = 0,
        _visualLane = 0 {
    if (laneCount < 1) {
      throw ArgumentError.value(laneCount, 'laneCount', 'must be >= 1');
    }
    _lane = _clamp(lane);
    _visualLane = _lane.toDouble();
  }

  int _clamp(int lane) {
    if (lane < 0) return 0;
    if (lane > laneCount - 1) return laneCount - 1;
    return lane;
  }

  /// Current logical lane (`0 .. laneCount - 1`). Read this for gameplay.
  int get lane => _lane;

  /// Smoothed lane position used purely for rendering. Eases toward [lane].
  double get visualLane => _visualLane;

  /// True once [visualLane] has effectively caught up to [lane].
  bool get settled => (_visualLane - _lane).abs() < 0.001;

  /// Move by [dir] lanes (default +1). Clamped at the track ends.
  void hop([int dir = 1]) => _lane = _clamp(_lane + dir);

  /// Jump straight to [lane] (clamped). Does not move [visualLane] — call
  /// [update] to animate the transition, or [snapVisual] to teleport.
  void hopTo(int lane) => _lane = _clamp(lane);

  /// Snap [visualLane] to the logical [lane] immediately (e.g. on round reset).
  void snapVisual() => _visualLane = _lane.toDouble();

  /// Ease [visualLane] toward [lane]. [speed] is lanes-per-second of approach
  /// rate; higher = snappier. Non-positive or non-finite [dt] is ignored.
  void update(double dt, {double speed = 12}) {
    if (!dt.isFinite || dt <= 0) return;
    final maxDelta = speed * dt;
    _visualLane = approach(_visualLane, _lane.toDouble(), maxDelta);
  }
}
