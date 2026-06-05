import '../core/rng.dart';
import 'mini_game.dart';
import 'player_manager.dart';
import 'scoreboard.dart';

/// Drives a tournament: an ordered list of minigame ids plus the running
/// [Scoreboard]. Advancing through the list and accumulating points is the
/// whole job.
///
/// Immutable: [recordResult] returns a **new** controller with the board
/// updated and the [index] advanced. The original is untouched, so a cup screen
/// can keep prior states for animation/undo and tests can assert on snapshots.
class CupController {
  /// The minigame ids to play, in order.
  final List<String> gameIds;

  /// Running points table.
  final Scoreboard board;

  /// Index of the current game (== [total] once the cup is complete).
  final int index;

  /// Creates a controller positioned at [index] (default 0) over [gameIds].
  ///
  /// Throws [ArgumentError] when [gameIds] is empty or [index] is negative /
  /// beyond `gameIds.length`.
  CupController({
    required List<String> gameIds,
    Scoreboard? board,
    this.index = 0,
  })  : gameIds = List<String>.unmodifiable(gameIds),
        board = board ?? Scoreboard() {
    if (gameIds.isEmpty) {
      throw ArgumentError.value(gameIds, 'gameIds', 'must not be empty');
    }
    if (index < 0 || index > gameIds.length) {
      throw ArgumentError.value(
          index, 'index', 'must be in 0..${gameIds.length}');
    }
  }

  /// Builds a cup of [count] distinct ids chosen from [allGameIds] using [rng]
  /// (deterministic for a fixed seed). [count] is clamped to
  /// `1 .. allGameIds.length`. Selection is an unbiased Fisher-Yates shuffle,
  /// then the first [count] ids — so order is randomized too.
  ///
  /// Throws [ArgumentError] when [allGameIds] is empty or [count] < 1.
  factory CupController.random(
    List<String> allGameIds,
    int count,
    SeededRng rng,
  ) {
    if (allGameIds.isEmpty) {
      throw ArgumentError.value(allGameIds, 'allGameIds', 'must not be empty');
    }
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be >= 1');
    }
    final take = count > allGameIds.length ? allGameIds.length : count;

    // Fisher-Yates over a copy; pull random elements from the unshuffled tail.
    final pool = List<String>.from(allGameIds);
    for (var i = pool.length - 1; i > 0; i--) {
      final j = rng.intRange(0, i + 1);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return CupController(gameIds: pool.sublist(0, take));
  }

  /// Total number of games in the cup.
  int get total => gameIds.length;

  /// The id of the game to play now, or null once the cup [isComplete].
  String? get currentGameId => isComplete ? null : gameIds[index];

  /// True once every game has been played ([index] reached [total]).
  bool get isComplete => index >= total;

  /// The cup winner's player id once [isComplete], else null. Reads the board
  /// leader (lowest id breaks a points tie).
  int? get champion => isComplete ? board.leader : null;

  /// Records the finished current game: returns a new controller with [result]
  /// folded into the board and [index] advanced by one.
  ///
  /// Throws [StateError] if the cup is already [isComplete].
  CupController recordResult(WinResult result, {required GameMode mode}) {
    if (isComplete) {
      throw StateError('cup is already complete; no game to record');
    }
    return CupController(
      gameIds: gameIds,
      board: board.addResult(result, mode: mode),
      index: index + 1,
    );
  }
}
