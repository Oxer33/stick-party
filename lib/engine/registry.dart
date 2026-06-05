import 'mini_game.dart';

import '../minigames/archer_pop/archer_pop.dart';
import '../minigames/bumper_balls/bumper_balls.dart';
import '../minigames/button_masher/button_masher.dart';
import '../minigames/catch_the_star/catch_the_star.dart';
import '../minigames/chicken_jump/chicken_jump.dart';
import '../minigames/color_memory/color_memory.dart';
import '../minigames/falling_dodge/falling_dodge.dart';
import '../minigames/one_touch_soccer/one_touch_soccer.dart';
import '../minigames/paint_splash/paint_splash.dart';
import '../minigames/reaction_duel/reaction_duel.dart';
import '../minigames/snake_arena/snake_arena.dart';
import '../minigames/sumo_smash/sumo_smash.dart';
import '../minigames/tank_duel/tank_duel.dart';
import '../minigames/tap_sprint/tap_sprint.dart';
import '../minigames/tug_of_war/tug_of_war.dart';

/// Builds a fresh [MiniGame] instance.
typedef MiniGameFactory = MiniGame Function();

/// The single source of truth for which minigames exist. Adding a game = one
/// import + one entry here (+ the game file itself). The select grid and Cup
/// queue are generated from this map — nothing else in the engine references a
/// concrete game.
final Map<String, MiniGameFactory> kMiniGameFactories =
    <String, MiniGameFactory>{
  'sumo_smash': () => SumoSmash(),
  'bumper_balls': () => BumperBalls(),
  'one_touch_soccer': () => OneTouchSoccer(),
  'tank_duel': () => TankDuel(),
  'archer_pop': () => ArcherPop(),
  'chicken_jump': () => ChickenJump(),
  'falling_dodge': () => FallingDodge(),
  'tap_sprint': () => TapSprint(),
  'tug_of_war': () => TugOfWar(),
  'button_masher': () => ButtonMasher(),
  'reaction_duel': () => ReactionDuel(),
  'snake_arena': () => SnakeArena(),
  'paint_splash': () => PaintSplash(),
  'catch_the_star': () => CatchTheStar(),
  'color_memory': () => ColorMemory(),
};

/// All registered minigame ids, in display order.
List<String> get allMiniGameIds =>
    kMiniGameFactories.keys.toList(growable: false);

/// Number of registered minigames.
int get miniGameCount => kMiniGameFactories.length;

/// Create a minigame by id. Throws [ArgumentError] for an unknown id.
MiniGame createMiniGame(String id) {
  final factory = kMiniGameFactories[id];
  if (factory == null) {
    throw ArgumentError.value(id, 'id', 'unknown minigame');
  }
  return factory();
}

/// Metadata for every game (used to build the select grid). Cheap: a fresh
/// instance is created only to read its const-ish [MiniGame.meta].
List<MiniGameMeta> allMiniGameMetas() =>
    allMiniGameIds.map((id) => createMiniGame(id).meta).toList(growable: false);

/// Ids that support the given player count.
List<String> miniGameIdsForPlayers(int playerCount) => allMiniGameIds
    .where((id) => createMiniGame(id).meta.supportsPlayers(playerCount))
    .toList(growable: false);
