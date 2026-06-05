# ARCHITECTURE — Stick Party

> How the code is organized so a new minigame ships in one file per week without touching the
> rest. Tech stack, layer boundaries, the engine core, the module registry, Flame/forge2d
> integration, and conventions (immutability, errors, tests).

---

## 1. Tech stack

| Concern | Choice | Rationale |
|---|---|---|
| Engine | **Flame** (game loop, components, input) | reused across STICK/DARK; mature 2D loop |
| Physics | **forge2d** (per physics minigame only) | sumo/soccer/bumper need real collisions |
| Rendering | **CustomPainter-style Canvas** inside Flame | reuse `stickman_painter`; testable |
| State (app/meta) | **Riverpod 2.6** | reused from BALL; testable providers |
| Persistence | **Hive 2.2** | reused repos; offline key-value |
| Routing | **go_router 14.6** | reused; deep-link-safe shell |
| Ads | **google_mobile_ads 5.3** | reused `AdService` |
| IAP | **in_app_purchase 3.2** | reused `IapService` |
| Notifications | **flutter_local_notifications 17.2** | reused |
| Analytics/crash | **Firebase analytics + crashlytics** | reused; funnel events |
| i18n | custom map engine (12 langs) | reused from BALL |
| Audio | **audioplayers** | simple SFX |

No networking packages. No backend. Offline by construction.

---

## 2. Layered structure

```
lib/
├── core/            # pure foundations (from STICK): result, math2, rng, constants, ids
├── art/
│   ├── stick/       # stickman skeleton/pose/ik/painter/ragdoll/clips/style (from STICK)
│   └── fx/          # particles/shake/hitstop/popups/ambient/camera (from DARK)
├── engine/          # ★ party core (NEW) — see §3
│   ├── mini_game.dart            # MiniGame interface + Context + Input + WinResult + meta
│   ├── mini_game_registry.dart   # id → factory map (+1/week entry point)
│   ├── mini_game_component.dart  # Flame wrapper: loop + pointer → InputZones → onInput
│   ├── input_zones.dart          # multitouch pointer routing + per-N ZoneLayout
│   ├── player_manager.dart       # PlayerSlot, teams, PlayerManager (immutable)
│   ├── bots.dart                 # BotProfile, BotController, difficulty
│   ├── scoreboard.dart           # per-player/team score accumulation
│   ├── cup_controller.dart       # sequence of games → champion
│   └── helpers/                  # mechanic-family helpers (DRY)
│       ├── tap_mash_meter.dart
│       ├── reaction_gate.dart
│       ├── lane_hopper.dart
│       ├── aim_sweep.dart
│       ├── area_fill_grid.dart
│       └── push_arena.dart       # forge2d arena scaffold
├── minigames/       # ★ one folder/file per game (NEW) — implements MiniGame
│   ├── sumo_smash/sumo_smash.dart
│   ├── tank_duel/tank_duel.dart
│   ├── ... (14 games)            # each <800 lines, self-contained
├── meta/            # retention domain (from BALL): streak, daily, achievements, cosmetics
├── data/            # Hive repositories (from BALL, fields re-shaped)
├── services/        # ad, ad_frequency, iap, purchase_applier, notif, analytics, crosspromo
│   └── cross_promo_service.dart  # ★ house-ads catalog + rotation (NEW, strategic)
├── app/             # shell: router, theme, i18n, providers, screens, widgets (from BALL)
│   ├── screens/     # home, players_setup, game_select, play, cup, shop, daily, stats, settings
│   └── widgets/     # buttons, rotated HUD, dialogs, house_ad_card, more_games_shelf
└── main.dart        # boot: Hive init, error handlers, service init, runApp
```

**Dependency rule (one direction):** `minigames → engine → art/core`. `app → engine + meta +
services`. `engine` never imports a concrete minigame (only the registry maps ids → factories).
`core`/`art` import nothing upward. This keeps each minigame removable/addable in isolation.

---

## 3. Engine core (the new layer)

### 3.1 `MiniGame` contract
Defined in `GAME_DESIGN.md` §6. Interface: `meta`, `status`, `init`, `onInput`, `update`,
`render`, `scores`, `winResult`, `dispose`. Engine-agnostic (Canvas render → testable).

### 3.2 Registry (the +1/week seam)
```dart
// mini_game_registry.dart
final Map<String, MiniGame Function()> kMiniGames = {
  'sumo_smash':  () => SumoSmash(),
  'tank_duel':   () => TankDuel(),
  // add one line per new game →
};
```
Game-select grid + Cup queue are generated from registry metas. Adding a game touches exactly
two files: the new `minigames/<id>/<id>.dart` and this map.

### 3.3 Flame wrapper
`MiniGameComponent` is the only Flame coupling for gameplay. It:
1. owns the active `MiniGame`,
2. converts Flutter pointer events → `InputZones.resolve(pointer) → PlayerInput`,
3. on each tick: feeds bot inputs, computes `scaledDt = dt * hitStop.timeScale`, calls
   `game.update(scaledDt)`, applies `screenShake`/`camera` offset, calls `game.render`,
4. watches `game.winResult` → notifies the session controller.

### 3.4 Input routing (multitouch)
`InputZones` holds the active `ZoneLayout` (list of `PlayerZone`). Raw `PointerDownEvent`/
`Move`/`Up` (tracked by pointer id) → find containing zone → emit `PlayerInput` with that
`playerId` and zone-local normalized position. Supports 2–4 concurrent pointers. Pure routing
logic is unit-tested (no Flutter needed): given zones + point → playerId.

### 3.5 Players & bots
`PlayerManager` (immutable list of `PlayerSlot`). `BotController` reads public game
state/scores + `BotProfile` and emits the same `PlayerInput` a human would — so games never
branch on human-vs-bot. Difficulty scales reaction/error/accuracy.

### 3.6 Session & Cup
- **QuickPlaySession**: one game id, rematch loop.
- **CupController**: ordered `List<gameId>` + cumulative `Scoreboard`; after each `WinResult`
  awards placement points; emits standings; ends with champion. Ad cadence hooks here.

### 3.7 Helpers (DRY mechanic families)
Pure, reusable sub-systems consumed by minigames: `TapMashMeter` (mash → velocity/progress),
`ReactionGate` (signal timing + early-tap penalty), `LaneHopper` (discrete lane state + hop),
`AimSweep` (oscillating angle + fire), `AreaFillGrid` (coverage grid + flood), `PushArena`
(forge2d ring + bodies + fall-off detection). Each unit-tested independently.

---

## 4. App shell & state

- **Riverpod** providers (reused/adapted from BALL): `hiveProvider`, `progressProvider`
  (coins/cosmetics/records/stats), `settingsProvider`, `localeProvider`,
  `cosmeticsOwnershipProvider`, `dailyProvider`, `streakProvider`, plus new
  `playersSetupProvider` (the seat/mode config) and `sessionProvider` (active quick/cup run).
- **Routing** (go_router): `/` home → `/setup` → `/select` (or `/cup`) → `/play` → result →
  back. `/shop`, `/daily`, `/stats`, `/settings`, `/more-games`.
- **Theme/i18n**: reused; party palette + rebuilt string map.
- **Orientation**: gameplay = the device's natural party orientation (likely landscape for 2p
  face-off; portrait quadrants for 4p). Layout-driven, not hardcoded.

---

## 5. Services

| Service | Source | Role |
|---|---|---|
| `AdService` | BALL ✅ | interstitial/rewarded/banner; IDs via dart-define |
| `AdFrequency` | BALL 🔧 | "rounds since last", never mid-round, removeAds-aware |
| `IapService` + `PurchaseApplier` | BALL 🔧 | remove-ads/unlock-all/bundles/coins; restore-safe |
| `NotificationService` | BALL 🔧 | daily/streak/recall reminders |
| `AnalyticsService` | BALL ✅ | funnel + house-ad events |
| **`CrossPromoService`** | NEW ★ | house-ad catalog, weighted rotation, deeplink, caps |

`CrossPromoService` is the strategic centerpiece: a local `List<HouseAd>` (procedural icons),
a rotation policy, a `houseAdShare` knob, and `openStore(id)` (tagged URL) — wired into the
between-round full-screen slot and the "More Games" shelf.

---

## 6. Conventions (enforced)

- **Immutability:** models/state are `@immutable` with `copyWith`; updates return new objects.
  Mutable sim state lives only inside a `MiniGame`/forge2d `World` during a round and is reset
  on `init`/`dispose`.
- **Errors:** boundaries return `Result<T>` (from STICK `result.dart`); services validate
  inputs (player count 1–4, zone bounds, SKU whitelist) and never swallow errors silently.
- **No magic numbers:** tuning in `core/constants.dart` (`Physics`, `Feel`, `Monetize`,
  `Cup`). No secrets in code — ad/IAP IDs via `--dart-define-from-file=release_config.json`
  (gitignored; `release_config.example.json` committed).
- **File size:** <800 lines; one minigame per file; extract helpers when a game grows.
- **Determinism:** all RNG via `SeededRng` from context → reproducible + testable.

---

## 7. Test strategy (TDD, ≥80%)

| Layer | Test type | Notes |
|---|---|---|
| `core/*` | unit | math2/rng already tested in STICK; port tests |
| `engine/input_zones` | unit | pointer→playerId for 1/2/3/4 layouts incl. edges/overlaps |
| `engine/helpers/*` | unit | mash curve, reaction penalty, lane hop, aim fire, fill coverage |
| `engine/cup_controller`, `scoreboard` | unit | placement points, ties, champion selection |
| `engine/bots` | unit | profile → input cadence within difficulty bounds |
| each `MiniGame` | unit + golden | deterministic round via seeded ctx → assert `winResult`; golden-test `render(canvas)` snapshots |
| `services/ad_frequency`, `purchase_applier`, `cross_promo_service` | unit | caps, restore idempotency, rotation weights |
| `meta/*` (streak/daily/achievements) | unit | ported patterns from BALL |
| `data/*` repos | unit | Hive fixtures, serialization round-trips, clamping |

Minigames are testable headless because `MiniGame` takes a `Canvas` and a seeded context — no
Flame/device needed for logic; Flame is exercised only via `mini_game_component` widget tests.

---

## 8. Performance

Borrow DARK patterns: particle soft-cap, object pooling, shader cache by radius, viewport
culling, exp-decay knockback, sub-stepped collision. Target 60fps with 4 stick figures +
ragdolls + particles on mid-range Android. Physics worlds spun only for physics families and
disposed on round end.

---

## 9. Build & release

- Android first (Play). `flutter build apk --release --dart-define-from-file=release_config.json`.
- iOS-ready (no platform-locked code beyond plugins that already support both).
- CI-friendly: pure logic tests run without devices; golden tests for render regressions.
