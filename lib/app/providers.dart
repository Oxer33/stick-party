/// Riverpod wiring for the Stick Party shell.
///
/// All app state flows through here: persistence, immutable [Progress] with
/// persisting mutators, the session roster, bot difficulty, shake intensity,
/// and the stubbed monetization/analytics services.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/persistence.dart';
import '../engine/bots.dart';
import '../engine/player_manager.dart';
import '../meta/cosmetics.dart';
import '../meta/progress_store.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/cross_promo_service.dart';
import '../services/iap_service.dart';
import '../services/purchase_applier.dart';

/// Persistence handle. MUST be overridden at app start (see `main.dart`) with a
/// concrete [Persistence]. Throwing here makes a missing override loud rather
/// than silently using a broken store.
final Provider<Persistence> persistenceProvider = Provider<Persistence>(
  (Ref ref) => throw UnimplementedError(
    'persistenceProvider must be overridden in ProviderScope (see main.dart)',
  ),
);

/// Repository over the shared [Persistence] box.
final Provider<ProgressRepository> progressRepositoryProvider =
    Provider<ProgressRepository>(
  (Ref ref) => ProgressRepository(ref.watch(persistenceProvider)),
);

/// Immutable [Progress] + persisting mutators.
final StateNotifierProvider<ProgressController, Progress> progressProvider =
    StateNotifierProvider<ProgressController, Progress>(
  (Ref ref) => ProgressController(ref.watch(progressRepositoryProvider)),
);

/// Owns the player's [Progress]. Every mutator updates the in-memory state AND
/// persists via the repository (best-effort; the repo never throws into the UI).
class ProgressController extends StateNotifier<Progress> {
  ProgressController(this._repo) : super(_repo.load());

  final ProgressRepository _repo;

  /// Adds coins to the winner of a round.
  Future<void> awardRoundWin() => addCoins(Economy.coinsPerRoundWin);

  /// Adds coins for winning a cup and bumps the cup counter.
  Future<void> awardCupWin() async {
    state = await _repo.addCoins(state, Economy.coinsPerCupWin);
    state = await _repo.incCupsWon(state);
  }

  /// Adds (or removes) coins, clamped by the repository.
  Future<void> addCoins(int delta) async {
    state = await _repo.addCoins(state, delta);
  }

  /// Attempts to buy a coin-unlocked cosmetic: checks affordability, deducts
  /// coins, then unlocks. Returns true on success, false if unaffordable /
  /// unknown / already owned.
  Future<bool> buyCosmetic(String cosmeticId) async {
    final Cosmetic? c = cosmeticById(cosmeticId);
    if (c == null || c.unlock != UnlockKind.coins) return false;
    if (isOwned(state.ownedCosmetics, c)) return false;
    if (state.coins < c.priceCoins) return false;

    state = await _repo.addCoins(state, -c.priceCoins);
    state = await _repo.unlockCosmetic(state, cosmeticId);
    return true;
  }

  /// Selects an owned stick skin.
  Future<void> selectSkin(String skinId) async {
    state = await _repo.setSelectedSkin(state, skinId);
  }

  /// Records a per-game best and increments the rounds-played counter, plus the
  /// max-players-in-session high-water mark.
  Future<void> recordResult({
    required String gameId,
    required int score,
    required int playerCount,
  }) async {
    state = await _repo.recordResult(state, gameId, score);
    state = await _repo.incRounds(state);
    state = await _repo.recordSessionPlayers(state, playerCount);
  }

  /// Increments the knockout counter by [by].
  Future<void> addKnockouts(int by) async {
    state = await _repo.incKnockouts(state, by: by);
  }

  /// Applies a purchase grant (coins / cosmetic unlocks) to progress. The
  /// offline MVP has no ad-removal state field, so [PurchaseGrant.removeAds] is
  /// intentionally a no-op here.
  Future<void> applyPurchaseGrant(PurchaseGrant grant) async {
    if (grant.coins > 0) {
      state = await _repo.addCoins(state, grant.coins);
    }
    if (grant.unlockAll) {
      for (final Cosmetic c in kCosmetics) {
        if (c.unlock == UnlockKind.coins) {
          state = await _repo.unlockCosmetic(state, c.id);
        }
      }
    }
    for (final String id in grant.cosmeticIds) {
      state = await _repo.unlockCosmetic(state, id);
    }
  }

  /// Persists an arbitrary new progress (used by the daily/login flows that
  /// compute a new Progress directly).
  Future<void> replace(Progress next) async {
    state = next;
    await _repo.save(next);
  }

  /// Wipes all progress back to a fresh player.
  Future<void> resetAll() async {
    final Progress fresh = Progress.initial();
    state = fresh;
    await _repo.save(fresh);
  }
}

/// Session roster + game mode. Starts from the quick-play default.
final StateNotifierProvider<PlayersSetupController, PlayerManager>
    playersSetupProvider =
    StateNotifierProvider<PlayersSetupController, PlayerManager>(
  (Ref ref) => PlayersSetupController(),
);

/// Mutable-by-replacement controller over the immutable [PlayerManager].
class PlayersSetupController extends StateNotifier<PlayerManager> {
  PlayersSetupController() : super(PlayerManager.quickDefault());

  /// Adds one seat (bot by default) up to the 4-player cap.
  void addPlayer({bool isBot = true}) {
    state = _withValidMode(state.addSlot(isBot: isBot));
  }

  /// Removes the last seat (keeps at least one).
  void removePlayer() {
    state = _withValidMode(state.removeLast());
  }

  /// Keeps [PlayerManager.mode] consistent with the seat count after a roster
  /// change. A 2-seat match is always a 1-v-1 (no FFA distinction); 1/3 seats are
  /// free-for-all; 4 seats keep an explicitly chosen team mode, else FFA.
  PlayerManager _withValidMode(PlayerManager m) {
    final GameMode next = switch (m.count) {
      2 => GameMode.duel1v1,
      4 => m.mode == GameMode.team2v2 ? GameMode.team2v2 : GameMode.ffa,
      _ => GameMode.ffa,
    };
    return m.mode == next ? m : m.withMode(next);
  }

  /// Flips the human/CPU flag for the seat at [index].
  void toggleBot(int index) {
    if (index < 0 || index >= state.count) return;
    final slot = state.slots[index];
    state = state.replace(index, slot.copyWith(isBot: !slot.isBot));
  }

  /// Cycles the seat's accent color to the next palette entry.
  void cycleColor(int index) {
    if (index < 0 || index >= state.count) return;
    final slot = state.slots[index];
    final int current = PlayerPalette.argb.indexOf(slot.colorArgb);
    final int next =
        PlayerPalette.argb[(current + 1) % PlayerPalette.argb.length];
    state = state.replace(index, slot.copyWith(colorArgb: next));
  }

  /// Sets the match mode (FFA / duel / team).
  void setMode(GameMode mode) {
    state = state.withMode(mode);
  }

  /// Replaces the whole roster (e.g. presets).
  void setManager(PlayerManager manager) {
    state = manager;
  }
}

/// Bot difficulty for the session (shared by all bot slots). Default medium.
final StateProvider<BotDifficulty> difficultyProvider =
    StateProvider<BotDifficulty>((Ref ref) => BotDifficulty.medium);

/// Shake / screen-jolt intensity, 0..1 (default full).
final StateProvider<double> shakeIntensityProvider =
    StateProvider<double>((Ref ref) => 1.0);

// ---------------------------------------------------------------------------
// Services (offline stubs)
// ---------------------------------------------------------------------------

/// Ad service (offline no-op stub).
final Provider<AdService> adServiceProvider =
    Provider<AdService>((Ref ref) => const StubAdService());

/// IAP service (offline stub with a static catalog).
final Provider<IapService> iapServiceProvider =
    Provider<IapService>((Ref ref) => const StubIapService());

/// Cross-promo / house-ad service. Kept alive for in-memory impression counts.
final Provider<CrossPromoService> crossPromoProvider =
    Provider<CrossPromoService>((Ref ref) => CrossPromoService());

/// Analytics (offline debug stub).
final Provider<AnalyticsService> analyticsProvider =
    Provider<AnalyticsService>((Ref ref) => const StubAnalyticsService());

// ---------------------------------------------------------------------------
// Daily login-bonus persistence
// ---------------------------------------------------------------------------

/// Persistence keys owned by the shell (distinct from [ProgressKeys]).
class ShellKeys {
  ShellKeys._();

  /// ISO `YYYY-MM-DD` of the last claimed login bonus ('' if never).
  static const String dailyLastClaimDay = 'daily_last_claim_day';

  /// 0-based login-cycle index for the next claim.
  static const String dailyLoginIndex = 'daily_login_index';

  /// BCP-47-ish locale code for the chosen UI language ('' = follow system).
  static const String appLocaleTag = 'app_locale';
}

/// Selected UI [Locale], or `null` to follow the device's system language.
///
/// Read from persistence on first watch ('' ⇒ system default ⇒ `null`). The
/// settings screen updates this notifier AND persists the tag so the choice
/// survives a relaunch.
final StateProvider<Locale?> localeProvider = StateProvider<Locale?>((Ref ref) {
  final String tag =
      ref.watch(persistenceProvider).getString(ShellKeys.appLocaleTag);
  return tag.isEmpty ? null : Locale(tag);
});

/// Thin read/write helper for the daily login-bonus claim state. Wraps the
/// shared [Persistence] box; all reads are corruption-tolerant by [Persistence].
class DailyClaimStore {
  DailyClaimStore(this._p);

  final Persistence _p;

  /// ISO day the bonus was last claimed, '' when never.
  String get lastClaimDayIso => _p.getString(ShellKeys.dailyLastClaimDay);

  /// 0-based login-cycle index for the next reward.
  int get loginIndex => _p.getInt(ShellKeys.dailyLoginIndex, min: 0);

  /// Marks [iso] claimed and advances the cycle index. Best-effort.
  Future<void> markClaimed(String iso, int nextIndex) async {
    await _p.putString(ShellKeys.dailyLastClaimDay, iso);
    await _p.putInt(ShellKeys.dailyLoginIndex, nextIndex, min: 0);
  }
}

/// Provider for the daily-claim store over the shared persistence box.
final Provider<DailyClaimStore> dailyClaimStoreProvider =
    Provider<DailyClaimStore>(
  (Ref ref) => DailyClaimStore(ref.watch(persistenceProvider)),
);
