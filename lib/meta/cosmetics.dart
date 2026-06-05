/// Pure cosmetic catalog: stick skins, map themes and trails.
///
/// This layer is DATA ONLY — it must NOT import the art/render layer. Each
/// [Cosmetic] carries a raw ARGB palette ([Cosmetic.paletteArgb]); the render
/// layer maps those ints to an actual stick style / theme elsewhere.
library;

import 'package:flutter/foundation.dart';

/// What part of the look a cosmetic changes.
enum CosmeticType { stickSkin, mapTheme, trail }

/// How a cosmetic is obtained.
enum UnlockKind { free, coins }

/// Default skin id every player owns from the start. Must exist in [kCosmetics]
/// and be a free [CosmeticType.stickSkin].
const String kDefaultSkinId = 'skin_classic';

@immutable
class Cosmetic {
  const Cosmetic({
    required this.id,
    required this.name,
    required this.type,
    required this.unlock,
    required this.priceCoins,
    required this.paletteArgb,
  }) : assert(priceCoins >= 0, 'priceCoins must be >= 0');

  final String id;
  final String name;
  final CosmeticType type;
  final UnlockKind unlock;

  /// Coin cost when [unlock] is [UnlockKind.coins]; 0 for free items.
  final int priceCoins;

  /// Raw ARGB ints (e.g. 0xFFRRGGBB). Interpreted by the render layer.
  final List<int> paletteArgb;

  /// True for [UnlockKind.free] items (no purchase needed).
  bool get isFree => unlock == UnlockKind.free;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Cosmetic &&
        other.id == id &&
        other.name == name &&
        other.type == type &&
        other.unlock == unlock &&
        other.priceCoins == priceCoins &&
        listEquals(other.paletteArgb, paletteArgb);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        type,
        unlock,
        priceCoins,
        Object.hashAll(paletteArgb),
      );
}

/// True when [owned] contains [c]'s id, or [c] is free (always owned).
bool isOwned(Set<String> owned, Cosmetic c) => c.isFree || owned.contains(c.id);

/// Looks up a cosmetic by id, or null when unknown.
Cosmetic? cosmeticById(String id) {
  for (final Cosmetic c in kCosmetics) {
    if (c.id == id) return c;
  }
  return null;
}

/// Full cosmetic catalog: 7 stick skins (free + coins) and 3 map themes.
const List<Cosmetic> kCosmetics = <Cosmetic>[
  // ----- Stick skins (free) ------------------------------------------------
  Cosmetic(
    id: kDefaultSkinId,
    name: 'Classic',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.free,
    priceCoins: 0,
    paletteArgb: <int>[0xFF222222, 0xFFFFFFFF],
  ),
  Cosmetic(
    id: 'skin_ember',
    name: 'Ember',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.free,
    priceCoins: 0,
    paletteArgb: <int>[0xFFFF5A5A, 0xFFFFC93C],
  ),
  Cosmetic(
    id: 'skin_aqua',
    name: 'Aqua',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.free,
    priceCoins: 0,
    paletteArgb: <int>[0xFF4D9BFF, 0xFF54E08A],
  ),

  // ----- Stick skins (coins) -----------------------------------------------
  Cosmetic(
    id: 'skin_gold',
    name: 'Gold Rush',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.coins,
    priceCoins: 500,
    paletteArgb: <int>[0xFFFFD54A, 0xFFB8860B],
  ),
  Cosmetic(
    id: 'skin_neon',
    name: 'Neon Pulse',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.coins,
    priceCoins: 750,
    paletteArgb: <int>[0xFF39FF14, 0xFFFF00E5],
  ),
  Cosmetic(
    id: 'skin_shadow',
    name: 'Shadow',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.coins,
    priceCoins: 600,
    paletteArgb: <int>[0xFF1A1A2E, 0xFF7B2FF7],
  ),
  Cosmetic(
    id: 'skin_frost',
    name: 'Frostbite',
    type: CosmeticType.stickSkin,
    unlock: UnlockKind.coins,
    priceCoins: 650,
    paletteArgb: <int>[0xFFB3E5FC, 0xFF0277BD],
  ),

  // ----- Map themes --------------------------------------------------------
  Cosmetic(
    id: 'map_arena',
    name: 'Arena',
    type: CosmeticType.mapTheme,
    unlock: UnlockKind.free,
    priceCoins: 0,
    paletteArgb: <int>[0xFF2B2D42, 0xFF8D99AE],
  ),
  Cosmetic(
    id: 'map_sunset',
    name: 'Sunset Rooftop',
    type: CosmeticType.mapTheme,
    unlock: UnlockKind.coins,
    priceCoins: 800,
    paletteArgb: <int>[0xFFFF8C42, 0xFF6A0572],
  ),
  Cosmetic(
    id: 'map_void',
    name: 'Void',
    type: CosmeticType.mapTheme,
    unlock: UnlockKind.coins,
    priceCoins: 900,
    paletteArgb: <int>[0xFF0B0014, 0xFF3A0CA3],
  ),
];
