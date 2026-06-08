// Pure scoring/ranking + small value types for ReactionDuel's best-of round
// structure. Kept in its own file (same game folder) so the gameplay module
// stays under the file-size budget. The ranking helper holds NO state and never
// mutates its inputs; it is side-effect free.
import 'dart:ui';

/// A short-lived slash arc from the winner's blade to a loser's chest.
/// Round-scoped mutable effect state (only [life] changes, decaying 1 → 0).
class Slash {
  final Offset from;
  final Offset to;
  final Color color;
  double life; // 1 → 0
  Slash({
    required this.from,
    required this.to,
    required this.color,
    required this.life,
  });
}

/// Build the final best→worst ranking for a finished duel.
///
/// Order: more cumulative [points] first; ties broken by the faster valid
/// reaction in the last round ([lastReactionTimes], seconds after GO — lower is
/// better), with players who reacted ranked above players who did not; remaining
/// ties keep the input order of [playerIds]. Every id in [playerIds] appears
/// exactly once, so the result is always a complete, unique ranking.
List<int> buildDuelRanking(
  List<int> playerIds,
  Map<int, int> points,
  Map<int, double> lastReactionTimes,
) {
  final ranked = List<int>.of(playerIds);
  ranked.sort((a, b) {
    final pa = points[a] ?? 0;
    final pb = points[b] ?? 0;
    if (pa != pb) return pb.compareTo(pa); // more points first

    final ta = lastReactionTimes[a];
    final tb = lastReactionTimes[b];
    if (ta != null && tb != null) return ta.compareTo(tb); // faster first
    if (ta != null) return -1; // a reacted, b didn't → a higher
    if (tb != null) return 1; // b reacted, a didn't → b higher
    return 0; // stable: keep input order
  });
  return ranked;
}
