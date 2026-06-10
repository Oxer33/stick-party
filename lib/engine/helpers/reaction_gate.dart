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
/// **Feints** (depth layer): during the wait it can flash 1–2 brief FAKE GOs —
/// the field lights up "GO!"-green for a [feintFlashSec] blink, then snaps back
/// to red. A feint is **not** the GO: the phase stays [ReactionPhase.waiting],
/// so tapping a feint is an [ReactionTap.early] false start (same penalized
/// lockout). Each fake fires before the real GO with a margin, so it can never
/// be confused with — or overrun — the real signal. Read [feintActive] to draw
/// the green flash. Disable by passing `feints: 0`.
///
/// Mutable single-round object. Call [reset] to roll a fresh GO time and replay.
class ReactionGate {
  final SeededRng _rng;

  /// Inclusive lower bound (seconds) for the random GO delay.
  final double minDelay;

  /// Inclusive upper bound (seconds) for the random GO delay.
  final double maxDelay;

  /// Most fake-GO flashes to schedule before the real GO (0 disables feints).
  final int feints;

  /// How long a single fake-GO flash stays green (seconds).
  final double feintFlashSec;

  double _goAt;
  double _elapsed = 0;
  ReactionPhase _phase = ReactionPhase.waiting;
  int? _winner;
  final Map<int, double> _reactionTimes = <int, double>{};
  final Set<int> _penalized = <int>{};

  /// Scheduled fake-GO flash start times (seconds), strictly before [_goAt].
  final List<double> _fakeGoAt = <double>[];

  /// Index of the fake currently flashing, or -1 when none is lit.
  int _activeFeint = -1;

  /// Margin (seconds) the last feint must finish before the real GO, so a feint
  /// can never bleed into the genuine signal. Comfortably above a fast human
  /// reaction so a feint is a real fake-out, not a disguised GO.
  static const double _feintSafetyGap = 0.45;

  /// Creates a gate and rolls the first GO time (plus any feints).
  ///
  /// Throws [ArgumentError] if the delays are negative, non-finite, or if
  /// [maxDelay] < [minDelay].
  ReactionGate(
    SeededRng rng, {
    this.minDelay = 1.0,
    this.maxDelay = 3.5,
    this.feints = 2,
    this.feintFlashSec = 0.22,
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
    _rollFeints();
  }

  double _rollGoTime() =>
      maxDelay == minDelay ? minDelay : _rng.range(minDelay, maxDelay);

  /// Roll up to [feints] fake-GO flash times into the open window before the
  /// real GO. We only place them in `[minDelay*0.5, _goAt - safety]`, drop any
  /// that don't leave room for the flash + safety gap, and keep them sorted so
  /// [update] can light them in order. Skips entirely when the wait is too
  /// short to host a safe fake.
  void _rollFeints() {
    _fakeGoAt.clear();
    _activeFeint = -1;
    if (feints <= 0) return;
    final latest = _goAt - _feintSafetyGap - feintFlashSec;
    final earliest = minDelay * 0.5;
    if (latest <= earliest) return; // no safe room for a fake
    final count = _rng.intRange(1, feints + 1); // 1..feints
    final times = <double>[];
    for (var i = 0; i < count; i++) {
      times.add(_rng.range(earliest, latest));
    }
    times.sort();
    // Keep fakes spaced so two don't visually merge into one long flash.
    var last = -1.0;
    for (final t in times) {
      if (t - last < feintFlashSec * 1.5) continue;
      _fakeGoAt.add(t);
      last = t;
    }
  }

  /// Current phase.
  ReactionPhase get phase => _phase;

  /// True while a fake-GO flash is currently lit (the field should flash green
  /// even though the phase is still [waiting] — tapping now is a false start).
  bool get feintActive => _activeFeint >= 0;

  /// Scheduled fake-GO start times (read-only view), for cues/telemetry.
  List<double> get fakeGoTimes => List<double>.unmodifiable(_fakeGoAt);

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
  /// is reached. While waiting, it also tracks which (if any) fake-GO flash is
  /// currently lit so the game can paint the feint. Non-positive or non-finite
  /// [dt] is ignored.
  void update(double dt) {
    if (!dt.isFinite || dt <= 0) return;
    if (_phase != ReactionPhase.waiting) return;
    _elapsed += dt;
    if (_elapsed >= _goAt) {
      _phase = ReactionPhase.go;
      _activeFeint = -1; // the real GO supersedes any feint
      return;
    }
    _updateFeint();
  }

  /// Light the fake-GO flash whose [feintFlashSec] window currently contains
  /// [_elapsed] (else clear it). Feints never change [_phase]; they only flip
  /// [feintActive], so a tap landing on one is still an early false start.
  void _updateFeint() {
    _activeFeint = -1;
    for (var i = 0; i < _fakeGoAt.length; i++) {
      final start = _fakeGoAt[i];
      if (_elapsed >= start && _elapsed < start + feintFlashSec) {
        _activeFeint = i;
        return;
      }
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
  /// time (and a fresh set of feints) from the same RNG stream.
  void reset() {
    _elapsed = 0;
    _phase = ReactionPhase.waiting;
    _winner = null;
    _reactionTimes.clear();
    _penalized.clear();
    _goAt = _rollGoTime();
    _rollFeints();
  }
}
