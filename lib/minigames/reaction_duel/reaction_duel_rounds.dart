// Pure scoring/ranking + small value types for ReactionDuel's "first to N draws
// won" (best-of) structure. Kept in its own file (same game folder) so the
// gameplay module stays under the file-size budget. The helpers hold NO state
// and never mutate their inputs; they are side-effect free.
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

/// Award one finished DRAW. Quick-Draw is a winner-takes-the-draw duel: the
/// single fastest valid tap after GO ([winner], the first tap the gate accepted
/// during its GO window) wins the draw; everyone else — slower tappers,
/// non-tappers, and false-starters — gets nothing that draw. So a draw is won by
/// nerve + speed, never by an early/incidental tap (an early tap is a false
/// start and can never be the [winner]).
///
/// Returns a `{playerId: drawsDelta}` map carrying exactly one `+1` for the
/// [winner] (when present and in [playerIds]) and `0` for every other id, so the
/// caller can fold it straight into a cumulative draw tally. A [winner] of
/// `null` (a draw with no valid tap — e.g. a timed-out GO) awards nothing. Pure:
/// never mutates its inputs, and every id in [playerIds] gets an entry.
Map<int, int> drawAward(List<int> playerIds, int? winner) {
  final delta = <int, int>{for (final id in playerIds) id: 0};
  if (winner != null && delta.containsKey(winner)) {
    delta[winner] = 1;
  }
  return delta;
}

/// True once any player has reached [target] draws won — the match-over test for
/// the "first to N" objective. [target] is clamped to at least 1.
bool matchWon(Map<int, int> drawsWon, int target) {
  final need = target < 1 ? 1 : target;
  for (final won in drawsWon.values) {
    if (won >= need) return true;
  }
  return false;
}

/// Build the final best→worst ranking for a finished duel.
///
/// Order: more [drawsWon] first (the player who won the most draws is the
/// champion); ties broken by the smaller cumulative reaction total across the
/// match ([totalReaction], seconds summed over every valid tap — lower/snappier
/// is better), with players who ever reacted ranked above players who never did;
/// remaining ties keep the input order of [playerIds]. Every id in [playerIds]
/// appears exactly once, so the result is always a complete, unique ranking.
List<int> buildDuelRanking(
  List<int> playerIds,
  Map<int, int> drawsWon,
  Map<int, double> totalReaction,
) {
  final ranked = List<int>.of(playerIds);
  ranked.sort((a, b) {
    final wa = drawsWon[a] ?? 0;
    final wb = drawsWon[b] ?? 0;
    if (wa != wb) return wb.compareTo(wa); // more draws won first

    final ta = totalReaction[a];
    final tb = totalReaction[b];
    if (ta != null && tb != null) return ta.compareTo(tb); // snappier first
    if (ta != null) return -1; // a reacted at least once, b never → a higher
    if (tb != null) return 1; // b reacted at least once, a never → b higher
    return 0; // stable: keep input order
  });
  return ranked;
}
