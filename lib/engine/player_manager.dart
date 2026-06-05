import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Match shape. Drives zone layout, scoring aggregation and bot balancing.
enum GameMode { ffa, duel1v1, team2v2, team3v3 }

/// Team membership. [none] = free-for-all.
enum Team { a, b, none }

/// One participant seat. Immutable — setup screen builds a new list on change.
@immutable
class PlayerSlot {
  final int id; // 0..3, stable index into PlayerPalette
  final String name;
  final int colorArgb;
  final bool isBot;
  final Team team;
  final String skinId; // cosmetic / stick style id

  const PlayerSlot({
    required this.id,
    required this.name,
    required this.colorArgb,
    this.isBot = false,
    this.team = Team.none,
    this.skinId = 'default',
  });

  /// A default seat for player [id] (0-based) using the shared palette.
  factory PlayerSlot.defaults(int id, {bool isBot = false}) {
    final safeId = id.clamp(0, PlayerPalette.argb.length - 1);
    return PlayerSlot(
      id: id,
      name: isBot ? 'CPU ${id + 1}' : 'P${id + 1}',
      colorArgb: PlayerPalette.argb[safeId],
      isBot: isBot,
    );
  }

  PlayerSlot copyWith({
    int? id,
    String? name,
    int? colorArgb,
    bool? isBot,
    Team? team,
    String? skinId,
  }) =>
      PlayerSlot(
        id: id ?? this.id,
        name: name ?? this.name,
        colorArgb: colorArgb ?? this.colorArgb,
        isBot: isBot ?? this.isBot,
        team: team ?? this.team,
        skinId: skinId ?? this.skinId,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayerSlot &&
      other.id == id &&
      other.name == name &&
      other.colorArgb == colorArgb &&
      other.isBot == isBot &&
      other.team == team &&
      other.skinId == skinId;

  @override
  int get hashCode => Object.hash(id, name, colorArgb, isBot, team, skinId);
}

/// Immutable roster + mode for a session. Validates 1..4 players.
@immutable
class PlayerManager {
  final List<PlayerSlot> slots;
  final GameMode mode;

  const PlayerManager._(this.slots, this.mode);

  /// Build a validated roster. Throws [ArgumentError] outside 1..4.
  factory PlayerManager(List<PlayerSlot> slots, {GameMode mode = GameMode.ffa}) {
    if (slots.isEmpty || slots.length > 4) {
      throw ArgumentError('player count must be 1..4, got ${slots.length}');
    }
    return PlayerManager._(List.unmodifiable(slots), mode);
  }

  /// Quick-play default: one human + one bot, FFA.
  factory PlayerManager.quickDefault() => PlayerManager(
        [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      );

  int get count => slots.length;
  int get humanCount => slots.where((s) => !s.isBot).length;
  int get botCount => slots.where((s) => s.isBot).length;

  PlayerSlot byId(int id) => slots.firstWhere(
        (s) => s.id == id,
        orElse: () => throw ArgumentError('no player id $id'),
      );

  List<PlayerSlot> teamMembers(Team t) =>
      slots.where((s) => s.team == t).toList(growable: false);

  PlayerManager withMode(GameMode m) => PlayerManager(slots, mode: m);

  PlayerManager addSlot({bool isBot = false}) {
    if (count >= 4) return this;
    final next = [...slots, PlayerSlot.defaults(count, isBot: isBot)];
    return PlayerManager(next, mode: mode);
  }

  PlayerManager removeLast() {
    if (count <= 1) return this;
    return PlayerManager(slots.sublist(0, count - 1), mode: mode);
  }

  PlayerManager replace(int index, PlayerSlot slot) {
    if (index < 0 || index >= count) return this;
    final next = [...slots]..[index] = slot;
    return PlayerManager(next, mode: mode);
  }
}
