# PRD — Stick Party: 2 3 4 Player Games

> **Working title:** "Stick Party: 2 3 4 Player Games" (modifiable).
> **Status:** Pre-production / planning.
> **Owner:** Indie studio (Flutter stack, Italy/EU).
> **Companion research:** `RICERCA_MOBILE_GAMES_2026.md` (market + player psychology).

---

## 1. Vision

A pick-up-and-play **local multiplayer party game**: 1–4 players share a single phone/tablet
screen and compete in dozens of tiny one-touch minigames. Procedural stickman art, juicy
feedback, "friendship-ruining" chaos. 100% offline, no networking, no external assets.

**One-line pitch:** *"234 Player Games meets Stickman — couch chaos in your pocket."*

---

## 2. Strategic goal (read this first)

This game is **not** a standalone cash-cow. It is a **viral funnel + cross-promo engine** for
the studio catalog.

- **Genre economics:** low ARPU, huge potential download volume (the "2 3 4 player games"
  category is download-driven, see RICERCA §3). We monetize on **ad volume + light IAP**.
- **Primary KPI is not revenue — it is installs driven to the rest of the catalog** via
  house ads (cross-promo). Examples of catalog targets: the drink-sort puzzle (Ball Sort
  lineage) and the stickman action-roguelite (Dark Leveling lineage).
- Every design decision is weighed against: *does it grow the funnel and push cross-promo?*

**Consequence:** the cross-promo system (`CrossPromoService`, house-ad slots) is a
first-class feature, not an afterthought. See `GAME_DESIGN.md` §9.

---

## 3. Target audience

- **Primary:** kids, teens, families, friend groups physically together (couch, classroom,
  commute). Ages broad — rating **Everyone / E10**.
- **Player motivation (RICERCA §7):** *Action-Social* cluster — immediacy, adrenaline,
  social laughter. Not the relaxed "Gardener" of the puzzle game; this is loud, fast, shared.
- **Session shape:** very short rounds (15–45s each), played in bursts of 5–15 min, often
  repeatedly ("best of"/rematch loop).

---

## 4. Core pillars

1. **One-touch, learnable in 1 second.** One zone/button per player. No tutorial walls.
   Playable by children. (Genre golden rule — see `GAME_DESIGN.md` §4.)
2. **Instant start.** Tap → pick players → pick game → play. Fun in the first 5 seconds
   (RICERCA §9 FTUE).
3. **Juicy chaos.** Screen shake, hit-stop, particles, ragdoll KOs. "Rovina-amicizie."
4. **Modular content treadmill.** Each minigame is an isolated module behind a common
   interface; cadence **+1 minigame per week**. This is the retention engine of the genre.
5. **Ethical, family-safe monetization.** EU/AGCM-compliant (RICERCA §11). No dark patterns.

---

## 5. Scope — MVP (soft-launch)

| Area | MVP target |
|---|---|
| Minigames | **12–15** across reusable mechanic families (see `GAME_DESIGN.md` §5) |
| Players | 1–4 local, same device; vs **bot AI** in single/odd counts |
| Modes | Quick Play (single game), **Cup/Tournament** (sequence → champion), 1v1 / 2v2 / FFA |
| Meta | Daily reward, play-streak, records/stats, soft currency (coins) |
| Shop | Cosmetics: stickman skins, per-game cosmetics (tank/ball/map themes), starter set |
| Monetization | Interstitial between rounds (capped), banner in menus, rewarded (opt-in), IAP (remove-ads, unlock-all, cosmetic bundles), **house-ads cross-promo** |
| Art | Fully procedural (stickman skeleton + ragdoll + VFX + gradient/geometric maps + UI) |
| Platforms | Android first (Google Play), iOS-ready architecture |
| Offline | 100% — no networking, no backend, zero infra cost |

**Out of MVP (roadmap):** 30–50 minigames, seasonal cosmetic events, more languages beyond
launch set. **Online play is never in scope** — explicitly excluded.

---

## 6. Non-goals (explicit)

- ❌ No networking / online / server / backend. Same-device only.
- ❌ No external art/audio assets. Everything procedural in code.
- ❌ No interstitial **during** a minigame — only between rounds.
- ❌ No complex controls. One-touch per player is mandatory.
- ❌ No dark patterns, no aggressive FOMO, no virtual-currency-only pricing.
- ❌ No gore/blood/adult content (cartoon violence only → Everyone/E10).

---

## 7. Success metrics

Because the strategic goal is funnel + cross-promo, we track two tiers.

**Tier 1 — Funnel & cross-promo (north star):**
- House-ad CTR and **installs attributed to catalog games** (via store deeplink + tagged URLs).
- Viral coefficient proxies: sessions/day, rounds/session, share/rate prompts accepted.

**Tier 2 — Standard health (RICERCA §12):**
- Retention: **D1 35–45%**, D7, D30 ≥5%.
- Engagement: rounds/session, session length, players-per-session (2+ = social hook working).
- Monetization: ARPDAU (expected low, $0.03–0.08 casual-social), rewarded views/session,
  IAP conversion (remove-ads + cosmetics).
- Stability: crash-free sessions ≥99.5%.

---

## 8. Constraints (engineering)

From global rules — enforced throughout:
- **Immutability** (new objects, never mutate state in place).
- **KISS / DRY / YAGNI.**
- Files **< 800 lines**, many small files (**one file per minigame**).
- Explicit error handling (`Result<T>`), input validation at boundaries.
- **No hardcoded secrets** (ad/IAP IDs via `--dart-define-from-file`, gitignored).
- **Test ≥ 80%, TDD.** Pure game logic must be unit-testable without Flame/UI.

---

## 9. Key risks

| Risk | Mitigation |
|---|---|
| One-touch too shallow → low retention | Deep content treadmill (+1/wk), Cup meta, cosmetics, records |
| Multitouch routing bugs (2–4 fingers) | Dedicated `InputZones` layer, raw pointer routing, heavy tests |
| Ad fatigue kills funnel | Strict frequency caps, never mid-round, prioritize house-ads for own funnel |
| Low ARPU disappoints if judged standalone | Re-frame: success = catalog installs, not this game's revenue |
| Procedural art looks cheap | Reuse polished stickman painter + Dark Leveling juice (shake/particles/ragdoll) |
| EU/AGCM compliance | `LEGAL_GUARDRAILS.md` baked into shop/ads from day one |

---

## 10. Deliverables map

| Doc | Content |
|---|---|
| `PRD.md` (this) | Vision, strategy, scope, metrics, risks |
| `GAME_DESIGN.md` | Minigame list + mechanics, controls/multitouch layout, MiniGame interface, Cup, shop/cosmetics, monetization + cross-promo, procedural art, retention, game feel |
| `ARCHITECTURE.md` | Tech stack, layers, core systems, registry, Flame/forge2d, conventions, test strategy |
| `REUSE_MAP.md` | What to copy from Stickman / Ball Sort / Dark Leveling, with paths + adaptation notes |
| `ROADMAP.md` | Phased plan P0→P5, +1 minigame/week cadence, launch checklist |
| `LEGAL_GUARDRAILS.md` | EU/AGCM ethics, Families policy, rating, ad-SDK rules |
