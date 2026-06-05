import 'mini_game.dart';
import 'player_manager.dart';

/// Cup-wide points table, accumulated across the minigames of a tournament.
///
/// Immutable: every mutator returns a **new** [Scoreboard]; the original is
/// never changed. This keeps cup progression easy to snapshot, undo and test.
///
/// Points come from per-round placement (see [addResult]). The map is keyed by
/// player id; a player not present yet reads as 0 points.
class Scoreboard {
  /// Player id -> accumulated cup points. Stored unmodifiable.
  final Map<int, int> points;

  /// Creates a scoreboard, optionally seeded with existing [points].
  Scoreboard([Map<int, int>? points])
      : points = Map<int, int>.unmodifiable(points ?? const <int, int>{});

  /// Points for [id] (0 if the player has none yet).
  int pointsOf(int id) => points[id] ?? 0;

  /// Player ids sorted by points descending. Ties are broken by ascending id
  /// so the ordering is deterministic. Players with 0 points are included.
  List<int> standings() {
    final ids = points.keys.toList()
      ..sort((a, b) {
        final byPoints = pointsOf(b).compareTo(pointsOf(a));
        return byPoints != 0 ? byPoints : a.compareTo(b);
      });
    return List<int>.unmodifiable(ids);
  }

  /// The id with the most points, or null when the board is empty. On a points
  /// tie the lowest id wins (consistent with [standings]).
  int? get leader {
    if (points.isEmpty) return null;
    return standings().first;
  }

  /// Returns a new scoreboard with placement points from [result] added.
  ///
  /// Placement points for a round of `R` ranked players: the best place earns
  /// `R`, the next `R - 1`, down to `1` for last. Players that **tie on
  /// [WinResult.finalScores] share the higher placement** — e.g. if two players
  /// tie for first in a 4-player round, both get 4 points and the next distinct
  /// player gets 2 (the third slot).
  ///
  /// [mode] is accepted for forward compatibility (e.g. future team
  /// aggregation); FFA placement scoring does not branch on it today. The
  /// ranking is derived from [WinResult.finalScores] so ties are detected by
  /// score rather than trusting the incoming order. Throws [ArgumentError] if
  /// [WinResult.ranking] is empty.
  Scoreboard addResult(WinResult result, {required GameMode mode}) {
    final ranking = result.ranking;
    if (ranking.isEmpty) {
      throw ArgumentError.value(ranking, 'result.ranking', 'must not be empty');
    }

    final roundPoints = _placementPoints(result);

    final next = Map<int, int>.from(points);
    roundPoints.forEach((id, gained) {
      next[id] = (next[id] ?? 0) + gained;
    });
    return Scoreboard(next);
  }

  /// Compute each player's placement points for a single round, applying the
  /// "ties share the higher placement" rule.
  static Map<int, int> _placementPoints(WinResult result) {
    final ranking = result.ranking;
    final scores = result.finalScores;
    final total = ranking.length;

    // Order ids best -> worst by finalScore (desc). Fall back to the supplied
    // ranking order for any id missing a score, so we never crash on bad data.
    final scoreOf = <int, num>{
      for (var i = 0; i < ranking.length; i++)
        ranking[i]: scores[ranking[i]] ?? (ranking.length - i),
    };
    final ordered = ranking.toList()
      ..sort((a, b) => scoreOf[b]!.compareTo(scoreOf[a]!));

    final out = <int, int>{};
    var index = 0;
    while (index < ordered.length) {
      // Gather the run of players sharing this finalScore (a tie group).
      final groupScore = scoreOf[ordered[index]];
      var end = index;
      while (end < ordered.length && scoreOf[ordered[end]] == groupScore) {
        end++;
      }
      // Higher placement = the best (lowest) index in the group => most points.
      final sharedPoints = total - index;
      for (var k = index; k < end; k++) {
        out[ordered[k]] = sharedPoints;
      }
      index = end;
    }
    return out;
  }
}
