# ROADMAP — Stick Party (phased)

> Phased plan from empty repo to soft-launch, then the +1-minigame/week treadmill. Each phase
> ends with a verifiable gate. TDD throughout (write tests first, ≥80%).

---

## P0 — Scaffold & reuse harvest (foundation)

**Goal:** runnable empty app + all reused code ported and compiling + test harness green.

- Init Flutter project, pubspec with the adopted stack (Riverpod/Hive/go_router/flame/forge2d/
  ads/iap/notif/firebase/audioplayers), analysis_options, `release_config.example.json`.
- Port `core/*` (STICK) + their tests.
- Port `art/stick/*` ✅ files (STICK) + `art/fx/*` ✅ files (DARK).
- Port `services/*` (BALL: ad/ad_frequency/iap/purchase_applier/notif/analytics) — swap to env
  IDs, no real secrets.
- Port `data/*` repos + `meta/*` retention (BALL), reshape fields.
- App shell (router/theme/i18n/main) booting to a placeholder home.
- **Gate:** `flutter analyze` clean; ported unit tests pass; app launches to home.

## P1 — Engine core + first minigame (vertical slice)

**Goal:** prove the `MiniGame` contract end-to-end with one game, 1–4 players + bots.

- Write `engine/`: `mini_game.dart` (contract), `player_manager`, `input_zones` (+ layouts
  1/2/3/4), `bots`, `scoreboard`, `mini_game_component` (Flame wrapper), registry.
- Implement **Sumo Smash** (Family A, forge2d via `push_arena` helper) as the reference game:
  multitouch, ragdoll KO, shake/particles, win detection.
- Players-setup screen → play screen → result.
- **Gate:** play Sumo with 2–4 fingers + bots; deterministic seeded test asserts `winResult`;
  golden test of `render`; input-routing tests for all layouts.

## P2 — Minigame batch to MVP count (content)

**Goal:** 12–15 minigames across all families; helpers proven reusable.

- Build family helpers: `tap_mash_meter`, `reaction_gate`, `lane_hopper`, `aim_sweep`,
  `area_fill_grid` (push_arena already from P1).
- Implement remaining games (one file each, registry line each):
  Tank Duel, Archer Pop, Chicken Jump, Falling Dodge, Tap Sprint, Tug of War, Button Masher,
  Reaction Duel, Catch the Star, Snake Arena, One-Touch Soccer, Paint Splash (+ optional
  Bumper Balls / Color Memory).
- Game-select grid generated from registry meta.
- **Gate:** every game has a seeded logic test + golden; all reachable from select grid; each
  file <800 lines.

## P3 — Modes, Cup & meta (depth)

**Goal:** the session/meta loop that drives retention.

- `cup_controller` + Cup flow (queue → placement points → champion podium with confetti/ragdoll).
- Team modes (1v1/2v2/3v3/FFA) wired through scoreboard.
- Retention: daily reward, play-streak, daily missions, achievements, records/stats screen.
- Cosmetics: stickman skins (StickStyle), per-game cosmetics, shop screen, coin economy.
- **Gate:** full Cup playable; daily/streak/missions persist across restart; cosmetics
  equip + persist; cup/scoreboard unit tests.

## P4 — Monetization + cross-promo (the strategic objective)

**Goal:** funnel-first monetization live, ethical, capped.

- Wire `AdService`: interstitial between rounds/cup-games (capped, never mid-round), menu
  banners, rewarded (skin/2× coins/try-locked/map-theme).
- Build **`CrossPromoService`** + `HouseAd` catalog (procedural icons, drink-puzzle + stickman
  RPG), "More Games" shelf, between-round house-ad slot with `houseAdShare` knob, tagged
  deeplinks, analytics events.
- IAP: remove-ads, unlock-all, cosmetic bundles, coin packs; restore.
- Apply `LEGAL_GUARDRAILS.md`: real-currency prices, no dark patterns, Families compliance.
- **Gate:** ad caps + frequency tests; house-ad rotation tests; purchase_applier restore
  tests; manual buy/restore on device; no ad ever during a round.

## P5 — Polish, QA & soft-launch (ship)

**Goal:** store-ready Android build.

- FTUE pass (fun in 5s, delayed ads, one-time hint), juice pass (shake/hitstop/particles on
  every game), audio (simple SFX), accessibility (shake/particle scaling, reduce motion).
- Performance pass (60fps mid-range, soft-caps, pooling), crash hardening.
- ASO: title, icon (procedural export), screenshots/video from real gameplay (RICERCA §5),
  store listing, Data Safety, content rating (Everyone), privacy policy.
- Localization launch set; Firebase funnel verified.
- **Gate:** crash-free ≥99.5% in internal test; release APK builds with dart-define;
  launch checklist (below) complete → closed testing → soft-launch (Tier-1 geos, RICERCA §2).

---

## Post-launch — the treadmill (+1 minigame / week)

The genre's retention engine. Each week:
1. Pick a family (reuse its helper) → new `minigames/<id>/<id>.dart` + 1 registry line.
2. Tests (seeded logic + golden) first.
3. Optional themed cosmetic.
4. Ship via update; announce as a content event (notification + "NEW" badge).

Target trajectory: **14 → 30 → 50** minigames. Layer in: cosmetic seasonal events
(FOMO-free), more languages, more map themes, periodic house-ad catalog refresh.

---

## Launch checklist (P5 exit)

- [ ] `flutter analyze` clean, tests ≥80%, golden tests pass.
- [ ] No secrets in repo; `release_config.json` gitignored; example committed.
- [ ] Ads: never mid-round; caps verified; banner menus only; rewarded opt-in.
- [ ] House-ads live; deeplinks tagged; "More Games" shelf present.
- [ ] IAP buy + restore verified on device; prices in real currency.
- [ ] Rating Everyone; Data Safety form; privacy policy URL; Families ad-SDK self-cert.
- [ ] Daily/streak/notifications working; offline verified (airplane mode).
- [ ] 60fps on mid-range; crash-free ≥99.5%.
- [ ] Store assets from real gameplay; ASO keywords set; Tier-1 targeting.
