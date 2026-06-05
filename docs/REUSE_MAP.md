# REUSE MAP — what to copy, from where

> Three source projects were inventoried. This maps each reusable piece to its origin, with a
> copy / adapt / reference verdict and concrete file paths. Goal: build ~70% of the new game
> from battle-tested code, write net-new only for the party-specific layer.

Sources:
- **STICK** = `/Users/danilopapa/Stickman` (action-roguelite) → **procedural stickman art**.
- **BALL** = `/Users/danilopapa/Desktop/Personal project/Ball sort puzzle` → **plumbing / meta / services**.
- **DARK** = `/Users/danilopapa/Desktop/Personal project/Dark Leveling New Era/Code` → **juice / VFX**.

Verdicts: ✅ copy near-verbatim · 🔧 copy + adapt · 📎 reference pattern only.

---

## 1. Procedural stickman art — from STICK

Path: `STICK/lib/game/stick/` + `STICK/lib/core/`.

| File | LOC | Verdict | Notes |
|---|---|---|---|
| `core/result.dart` | 36 | ✅ | `Result<T>` (Ok/Err). Foundation for explicit error handling. |
| `core/math2.dart` | 71 | ✅ | angle/lerp/easing helpers. Already unit-tested. |
| `core/rng.dart` | 34 | ✅ | `SeededRng` — deterministic for tests + bot variance. |
| `core/constants.dart` | 62 | 🔧 | Keep `Physics`; rewrite `Combat/Progress/Monetize` for party game. |
| `stick/stick_pose.dart` | 115 | ✅ | Immutable 10-angle pose + `lerp`. Pure data. |
| `stick/stick_skeleton.dart` | 188 | ✅ | FK solver, `Joint` enum, `StickFrame`. No game coupling. |
| `stick/stick_ik.dart` | 51 | ✅ | 2-bone analytic IK. Pure math. |
| `stick/stick_style.dart` | 116 | ✅ | Visual style (fill/glow/gradient). Skin palettes plug here. |
| `stick/stickman_painter.dart` | 470 | ✅ | Canvas renderer (glow, rim, shadow, taper). Asset-free. |
| `stick/stick_ragdoll.dart` | 160 | ✅ | Verlet ragdoll. **This is our ragdoll** (DARK has none). KO/knockback. |
| `stick/stick_animator.dart` | 82 | 🔧 | Driver is generic; keep. Feeds from new clip set. |
| `stick/stick_clips.dart` | 945 | 🔧 | Keep locomotion (idle/run/jump/fall). **Replace combat clips** (attack/cast/hurt) with party clips: `cheer`, `cry`, `push`, `swing`, `ko`, `kick`, `wave`. |
| `stick/stick_figure.dart` | 104 | 🔧 | Keep `setLoco`/`render`/ragdoll. **Redefine action methods** for party moves. |
| `stick/weapon_visual.dart` | 65 | 🔧 | Keep `WeaponVisual` struct (tank cannon, sword, bat). Drop `weaponVisualFor()` (depends on roguelite weapon model). |
| `stick/shadow_striker.dart` | 100 | 📎 | RiftGame-coupled. Reference only for "StickFigure inside a Flame component". |

**Action:** copy `core/*` + the ✅ stick files verbatim into `lib/art/stick/`. Then fork
`stick_clips.dart` → author party clips; trim `stick_figure.dart` action API.

---

## 2. Plumbing / meta / services — from BALL

Stack confirmed: Riverpod 2.6 + Hive 2.2 + go_router 14.6 + google_mobile_ads 5.3 +
in_app_purchase 3.2 + flutter_local_notifications 17.2 + Firebase. **Adopt this stack.**

### 2a. Monetization (✅ near-verbatim, swap IDs)
| File | LOC | Verdict | Notes |
|---|---|---|---|
| `services/ad_service.dart` | 182 | ✅ | init / interstitial (30s gate) / rewarded→`Future<bool>` / banner. Swap ad-unit IDs via `release_config.json`. |
| `services/ad_frequency.dart` | 35 | 🔧 | Pure policy. Re-key from "levels" to **"rounds since last"**; never mid-round; respect `removeAds`. |
| `services/iap_service.dart` | 154 | ✅ | query / buy / restore / listen. Update SKU whitelist. |
| `services/purchase_applier.dart` | 73 | 🔧 | Re-route SKUs to party grants (remove-ads, unlock-all, coin packs, cosmetic bundles). Keep restore-idempotency. |
| `release_config.example.json` | — | ✅ | Template for prod IDs (gitignored real one). |

### 2b. Persistence (✅ structure reusable)
| File | LOC | Verdict | Notes |
|---|---|---|---|
| `data/repositories/progress_repository.dart` | 342 | 🔧 | Race-safe Hive write-queue + clamping is gold. Replace fields: levels→`coins/ownedCosmetics/selectedSkin/records/cupWins/stats`. |
| `data/repositories/daily_repository.dart` | 129 | ✅ | Daily missions + login-bonus persistence + memoization. Reuse as-is. |

### 2c. Retention (✅ mostly pure)
| File | Verdict | Notes |
|---|---|---|
| `domain/models/streak_model.dart` + `domain/services/streak_service.dart` | ✅ | Win-streak → reuse as **play-streak** (daily). Pure, tested. |
| `domain/models/daily_mission_model.dart` + `domain/services/daily_service.dart` | 🔧 | Deterministic per-day generation. Swap mission types → `playRounds`, `winRounds`, `winCup`, `tryNewGame`, `playWithFriends(2+)`. |
| `domain/services/achievement_service.dart` | 🔧 | Registry pattern. Rewrite entries for party milestones (win 10 cups, KO 50 rivals, play all games). |
| `domain/models/skin_model.dart` | 🔧 | Cosmetic model (free/coins/gems/iap). Generalize from "ball palette" to **stickman `StickStyle` + per-game theme**. |

### 2d. App shell / UI (🔧 structure, replace content)
| File | Verdict | Notes |
|---|---|---|
| `core/router.dart` | 🔧 | go_router setup is production-grade. New routes: home, players-setup, game-select, play, cup, shop, settings, daily, stats. |
| `core/theme.dart` | 🔧 | Material 3 dark + typography. Swap palette to party-bright. |
| `core/i18n/translations.dart` (+ helper, provider) | ✅ | 12-language engine. Reuse engine; rebuild string map. |
| `services/notification_service.dart` | 🔧 | Daily/streak/recall reminders. Swap copy ("Your friends are waiting!"). |
| `services/analytics_service.dart` + `firebase_service.dart` | ✅ | Event logging + crash. Add funnel events (house-ad click, round_start, cup_win). |
| `main.dart` | 🔧 | Boot sequence (Hive init, error handlers, service init). Reorder for party game. |

### 2e. Tests (📎 patterns)
17 test files; copy the **patterns** (ProviderContainer + Hive fixtures, pure-service unit
tests, serialization round-trips, `ad_frequency_test`, `daily_repository_test`,
`purchase_applier_test`). Game-specific tests not reusable.

---

## 3. Juice / VFX — from DARK

Paths: `DARK/lib/game/effects/` + `DARK/lib/game/postfx/`. Engine: Flame (no box2d).

| File | LOC | Verdict | Notes |
|---|---|---|---|
| `effects/particle_effect.dart` | 1289 | ✅ | Particle engine, soft-cap 80, shapes/variants. Adapt color palettes. |
| `effects/hit_burst.dart` | 87 | ✅ | Radial impact ring + sparks. Generic hit feedback. |
| `effects/screen_shake.dart` | 121 | ✅ | Stacking pulses, ease-out, accessibility-aware. Zero coupling. |
| `effects/hit_stop.dart` | 47 | ✅ | Time-scale freeze on impact. `scaledDt = dt * hitStop.timeScale`. |
| `effects/damage_number.dart` | 331 | 🔧 | Repurpose as **floating score/combo popups** ("+1", "KO!", "WIN!"). |
| `effects/footstep_dust.dart` | 93 | ✅ | Pooled dust puffs. Enable for runners. |
| `effects/effects_manager.dart` | 160 | 🔧 | Facade aggregating the above. Adapt method names/presets. |
| `postfx/camera_director.dart` | 141 | ✅ | Snap-follow + zoom-pulse + edge-clamp. For camera'd minigames (sumo, soccer). |
| `postfx/ambient_particles.dart` | 218 | ✅ | Background ambiance (11 flavors) per map theme. |

**Physics patterns (📎 borrow, don't copy whole components):**
- Knockback: accumulate velocity + exp decay + sub-stepping. (`player_component.dart`)
- Per-axis collision probing (slide along walls).
- Object pooling (FootstepDust), shader cache by radius, viewport culling, particle soft-cap.

> **Ragdoll note:** DARK has **no ragdoll**. Use STICK `stick_ragdoll.dart` (Verlet). DARK
> contributes the *impact feel around* the ragdoll (shake + hit-stop + particles).

---

## 4. New code to write (no source — party-specific layer)

These have no reuse origin; build fresh (see `ARCHITECTURE.md` §3):
- `MiniGame` interface + `MiniGameContext` + `MiniGameRegistry`.
- `PlayerManager` (1–4 slots, teams, bots) + `BotProfile`.
- `InputZones` (multitouch pointer → player zone routing) + per-N layouts.
- `Scoreboard` + `CupController` (sequence → champion).
- `CrossPromoService` + `HouseAd` catalog (the strategic core).
- Each minigame module (`lib/minigames/<id>/`) — one file per game.
- Mechanic-family helpers (`TapMashMeter`, `ReactionGate`, `LaneHopper`, `AimSweep`,
  `AreaFillGrid`, `PushArena`) — DRY across families.

---

## 5. Copy order (matches ROADMAP P0–P1)

1. `core/*` (STICK) → `lib/core/`.
2. stick art ✅ files (STICK) → `lib/art/stick/`.
3. juice ✅ files (DARK) → `lib/art/fx/`.
4. services (BALL: ad/iap/notif/analytics) → `lib/services/`.
5. persistence + retention (BALL) → `lib/data/`, `lib/meta/`.
6. router/theme/i18n/main (BALL) → `lib/app/`.
7. write new party-core (§4) → `lib/engine/`.
8. first minigame to validate the interface end-to-end.
