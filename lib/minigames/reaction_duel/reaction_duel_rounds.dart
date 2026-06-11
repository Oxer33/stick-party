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

/// Award DESCENDING placement points for one finished round, so every duelist
/// races for position (not just the single fastest tap). Players finish in this
/// order, best → worst:
///   1. the round [winner] (the first valid draw), if any;
///   2. everyone else who produced a valid reaction, fastest first
///      ([reactionTimes], seconds after GO — lower is better);
///   3. everyone who never reacted or false-started, keeping [playerIds] order.
/// The k-th finisher (0-based) of N players earns `(N-1-k)` base points, so a
/// 4-field pays 3/2/1/0 and a 2-field pays 1/0; last place always scores 0. Each
/// award is multiplied by [pointsScale] (1 for a normal round, 2 for the
/// double-points LIGHTNING final). Pure: never mutates its inputs, and every id
/// in [playerIds] gets an entry (0 if unplaced), so callers can fold it straight
/// into a cumulative tally.
Map<int, int> roundPlacementPoints(
  List<int> playerIds,
  int? winner,
  Map<int, double> reactionTimes, {
  int pointsScale = 1,
}) {
  // Finish order: winner, then other reactors fastest-first, then the rest.
  final reactors = playerIds
      .where((id) => id != winner && reactionTimes.containsKey(id))
      .toList()
    ..sort((a, b) => reactionTimes[a]!.compareTo(reactionTimes[b]!));
  final rest = playerIds
      .where((id) => id != winner && !reactionTimes.containsKey(id))
      .toList();
  final order = <int>[
    if (winner != null && playerIds.contains(winner)) winner,
    ...reactors,
    ...rest,
  ];

  final n = playerIds.length;
  final points = <int, int>{for (final id in playerIds) id: 0};
  for (var k = 0; k < order.length; k++) {
    points[order[k]] = (n - 1 - k) * pointsScale;
  }
  return points;
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
