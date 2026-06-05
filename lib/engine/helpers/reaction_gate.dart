import '../../core/rng.dart';

/// Phase of a reaction round.
enum ReactionPhase {
  /// Counting down to the GO signal. Taps now are jumps-the-gun (false starts).
  waiting,

  /// GO is showing. The first valid tap wins.
  go,

  /// Someone has won (or the round was force-ended). No more winners.
  done,
}

/// Classification returned for each tap fed to [ReactionGate.onTap].
enum ReactionTap {
  /// Tapped during [ReactionPhase.waiting] (false start). The player is
  /// recorded in [ReactionGate.penalized].
  early,

  /// The first tap during [ReactionPhase.go]. This player is the winner.
  valid,

  /// A tap during [ReactionPhase.go] after someone already won.
  late,

  /// Tap ignored: the round is already [ReactionPhase.done], or this player
  /// already false-started and is locked out.
  ignored,
}

/// A "wait for the signal, then tap first" gate — the shared mechanic behind
/// quick-draw / reflex minigames (Quick Draw, Don't Blink, etc.).
///
/// On construction it rolls a random GO time in `[minDelay, maxDelay]` from the
/// supplied [SeededRng], so rounds are deterministic in tests and varied in
/// play. The game ticks [update] every frame and forwards taps to [onTap];
/// the gate handles false-start penalties, picks the single winner, and records
/// each valid reaction time.
///
/// Mutable single-round object. Call [reset] to roll a fresh GO time and replay.
class ReactionGate {
  final SeededRng _rng;

  /// Inclusive lower bound (seconds) for the random GO delay.
  final double minDelay;

  /// Inclusive upper bound (seconds) for the random GO delay.
  final double maxDelay;

  double _goAt;
  double _elapsed = 0;
  ReactionPhase _phase = ReactionPhase.waiting;
  int? _winner;
  final Map<int, double> _reactionTimes = <int, double>{};
  final Set<int> _penalized = <int>{};

  /// Creates a gate and rolls the first GO time.
  ///
  /// Throws [ArgumentError] if the delays are negative, non-finite, or if
  /// [maxDelay] < [minDelay].
  ReactionGate(
    SeededRng rng, {
    this.minDelay = 1.0,
    this.maxDelay = 3.5,
  })  : _rng = rng,
        _goAt = 0 {
    if (!minDelay.isFinite || !maxDelay.isFinite || minDelay < 0) {
      throw ArgumentError('delays must be finite and >= 0 '
          '(min=$minDelay, max=$maxDelay)');
    }
    if (maxDelay < minDelay) {
      throw ArgumentError('maxDelay ($maxDelay) < minDelay ($minDelay)');
    }
    _goAt = _rollGoTime();
  }

  double _rollGoTime() =>
      maxDelay == minDelay ? minDelay : _rng.range(minDelay, maxDelay);

  /// Current phase.
  ReactionPhase get phase => _phase;

  /// The winning player id, or null until a [ReactionTap.valid] tap lands.
  int? get winner => _winner;

  /// Reaction time (seconds after GO) for every player that produced a valid
  /// tap. The winner is the minimum; latecomers are also recorded so games can
  /// rank everyone, not just first place. Returns an unmodifiable view.
  Map<int, double> get reactionTimes =>
      Map<int, double>.unmodifiable(_reactionTimes);

  /// Players locked out for tapping during [ReactionPhase.waiting].
  /// Returns an unmodifiable view.
  Set<int> get penalized => Set<int>.unmodifiable(_penalized);

  /// Seconds remaining until GO while [waiting]; 0 once GO has fired.
  double get timeToGo {
    final remaining = _goAt - _elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Advance the clock. Transitions [waiting] -> [go] once the rolled GO time
  /// is reached. Non-positive or non-finite [dt] is ignored.
  void update(double dt) {
    if (!dt.isFinite || dt <= 0) return;
    if (_phase != ReactionPhase.waiting) return;
    _elapsed += dt;
    if (_elapsed >= _goAt) {
      _phase = ReactionPhase.go;
    }
  }

  /// Feed one tap for [playerId] and get its classification.
  ///
  /// * [waiting]  -> [ReactionTap.early]   (player added to [penalized])
  /// * [go], first valid tap -> [ReactionTap.valid] (sets [winner] + records
  ///   the reaction time, phase becomes [done])
  /// * [go], already won -> [ReactionTap.late] (reaction time still recorded)
  /// * already [done], or a penalized player -> [ReactionTap.ignored]
  ReactionTap onTap(int playerId) {
    if (_phase == ReactionPhase.done) {
      // The first valid tap already ended the round, but a slightly-later tap
      // by a *different* player is still meaningful for full-field ranking.
      if (_penalized.contains(playerId)) return ReactionTap.ignored;
      if (playerId == _winner) return ReactionTap.late;
      _reactionTimes.putIfAbsent(playerId, () => _elapsed - _goAt);
      return ReactionTap.late;
    }

    // A player who jumped the gun is locked out for the rest of the round.
    if (_penalized.contains(playerId)) return ReactionTap.ignored;

    if (_phase == ReactionPhase.waiting) {
      _penalized.add(playerId);
      return ReactionTap.early;
    }

    // phase == go and nobody has won yet -> this tap wins.
    final reaction = _elapsed - _goAt;
    _winner = playerId;
    _reactionTimes[playerId] = reaction < 0 ? 0 : reaction;
    _phase = ReactionPhase.done;
    return ReactionTap.valid;
  }

  /// Force the round to end (e.g. a timeout with no winner). Idempotent.
  void forceDone() => _phase = ReactionPhase.done;

  /// Reset to a fresh round: clears winner/penalties/times and rolls a new GO
  /// time from the same RNG stream.
  void reset() {
    _elapsed = 0;
    _phase = ReactionPhase.waiting;
    _winner = null;
    _reactionTimes.clear();
    _penalized.clear();
    _goAt = _rollGoTime();
  }
}
