import 'dart:ui';

import '../core/rng.dart';
import 'bots.dart';
import 'input_zones.dart';
import 'player_manager.dart';

/// Lifecycle of a single round.
enum MiniGameStatus { loading, ready, running, finished }

/// Kind of touch event already resolved to a player.
enum InputPhase { down, up, holdTick }

/// One input event for one player. Most games only care about [down].
class PlayerInput {
  final int playerId;
  final InputPhase phase;
  final Offset normPos; // full-screen 0..1 position of the touch
  final double dt; // elapsed time for holdTick events

  const PlayerInput({
    required this.playerId,
    required this.phase,
    this.normPos = Offset.zero,
    this.dt = 0,
  });

  factory PlayerInput.down(int id, [Offset pos = Offset.zero]) =>
      PlayerInput(playerId: id, phase: InputPhase.down, normPos: pos);
}

/// Live per-player score (read by the on-field HUD).
class ScoreSnapshot {
  final Map<int, num> byPlayer;
  const ScoreSnapshot(this.byPlayer);
  num of(int id) => byPlayer[id] ?? 0;
}

/// Final ordered outcome. [ranking] is best→worst; ties share adjacent ranks.
class WinResult {
  final List<int> ranking;
  final Map<int, num> finalScores;
  const WinResult({required this.ranking, required this.finalScores});

  int? get winner => ranking.isEmpty ? null : ranking.first;
}

/// Static description used to build the select grid and validate setup.
class MiniGameMeta {
  final String id;
  final String name;
  final int minPlayers;
  final int maxPlayers;
  final List<GameMode> modes;
  final String themeId;
  final String inputHint; // "TAP" | "HOLD" | "MASH"

  const MiniGameMeta({
    required this.id,
    required this.name,
    this.minPlayers = 1,
    this.maxPlayers = 4,
    this.modes = const [GameMode.ffa],
    this.themeId = 'default',
    this.inputHint = 'TAP',
  });

  bool supportsPlayers(int n) => n >= minPlayers && n <= maxPlayers;
}

/// Immutable setup passed once to [MiniGame.init].
class MiniGameContext {
  final List<PlayerSlot> players;
  final Size arena;
  final SeededRng rng;
  final GameMode mode;
  final ZoneLayout zones;
  final BotDifficulty difficulty;
  final BotProfile botProfile;

  MiniGameContext({
    required this.players,
    required this.arena,
    required this.rng,
    required this.zones,
    this.mode = GameMode.ffa,
    this.difficulty = BotDifficulty.medium,
  }) : botProfile = BotProfile.forDifficulty(difficulty);

  int get playerCount => players.length;
  Iterable<PlayerSlot> get bots => players.where((p) => p.isBot);
  Iterable<PlayerSlot> get humans => players.where((p) => !p.isBot);
}

/// The contract every minigame implements. The engine drives only this.
abstract class MiniGame {
  MiniGameMeta get meta;
  MiniGameStatus get status;

  void init(MiniGameContext ctx);
  void onInput(PlayerInput input);
  void update(double dt);
  void render(Canvas canvas, Size size);

  ScoreSnapshot get scores;
  WinResult? get winResult;
  void dispose();
}

/// Optional base that handles status, scoring and finish bookkeeping so each
/// game implements only init/onInput/update/render. Holds mutable round state
/// (allowed: lives only for the duration of one round).
abstract class MiniGameBase implements MiniGame {
  late MiniGameContext ctx;
  MiniGameStatus _status = MiniGameStatus.loading;
  WinResult? _win;
  final Map<int, num> _score = <int, num>{};

  @override
  MiniGameStatus get status => _status;

  @override
  ScoreSnapshot get scores => ScoreSnapshot(Map<int, num>.unmodifiable(_score));

  @override
  WinResult? get winResult => _win;

  /// Call from your init() after building the world.
  void prepare(MiniGameContext context) {
    ctx = context;
    for (final p in context.players) {
      _score[p.id] = 0;
    }
    _status = MiniGameStatus.ready;
  }

  void begin() => _status = MiniGameStatus.running;

  void setScore(int id, num value) => _score[id] = value;
  void addScore(int id, num delta) => _score[id] = (_score[id] ?? 0) + delta;
  num scoreOf(int id) => _score[id] ?? 0;

  void finishWith(WinResult result) {
    _win = result;
    _status = MiniGameStatus.finished;
  }

  /// Finish, ranking players by current score.
  void finishByScore({bool higherWins = true}) {
    final ids = ctx.players.map((p) => p.id).toList()
      ..sort((a, b) {
        final sa = scoreOf(a), sb = scoreOf(b);
        return higherWins ? sb.compareTo(sa) : sa.compareTo(sb);
      });
    finishWith(WinResult(
      ranking: ids,
      finalScores: Map<int, num>.from(_score),
    ));
  }

  /// Finish with an explicit survival order (best→worst).
  void finishByOrder(List<int> survivalOrder) {
    finishWith(WinResult(
      ranking: survivalOrder,
      finalScores: Map<int, num>.from(_score),
    ));
  }

  @override
  void dispose() {}
}
