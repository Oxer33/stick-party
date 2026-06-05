# GAME DESIGN — Stick Party

> The keystone design doc. Covers: control philosophy, core loop, multitouch layouts, the
> minigame catalog, the `MiniGame` module contract, Cup mode, players/teams/bots, shop &
> cosmetics, monetization + cross-promo, the procedural art system, retention, and game feel.

---

## 1. Design philosophy — the golden rule

**One touch, one player, one second to learn.** Every minigame must be:
- Controllable with a **single touch** in the player's own screen zone (tap, hold, or mash).
- Understandable in **≤1 second** from a single glance — no text tutorial required.
- Playable by a **child**. If a 6-year-old can't win a round by accident, it's too complex.
- A source of **shared laughter** — "rovina-amicizie" moments (knockouts, near-misses, upsets).

If a mechanic needs two fingers, a swipe gesture, or on-screen text to explain, **redesign it**.

---

## 2. Core loop (three rings)

| Ring | Duration | Loop | Reward |
|---|---|---|---|
| **Round** | 15–45s | tap → chaos → win/lose → instant rematch | dopamine, "+1", KO, podium |
| **Session** | 5–15 min | Cup of N games OR rematch streak | coins, cup trophy, records |
| **Meta** | days/weeks | daily reward, unlock skins/maps/games, +1 game/week | collection, progression, FOMO-free events |

Between rounds: result screen → (capped interstitial or house-ad) → next round / podium.
**Never interrupt a live round.**

---

## 3. Controls — input model

One-touch, but a few input *flavors* cover all minigames:

| Flavor | Gesture | Used by |
|---|---|---|
| **Tap** | single down event in zone | tank fire, jump, turn, reaction, catch, attack |
| **Hold** | press-and-hold duration | paint expand, charge, brake |
| **Mash** | rapid repeated taps | sprint, tug-of-war, masher |

The engine delivers a `PlayerInput` (tapDown / tapUp / hold-tick) tagged with the resolving
`playerId`. A minigame consumes only the flavor it needs; everything else is ignored. No
swipes, no multi-finger-per-player, no virtual joysticks in MVP.

---

## 4. Multitouch layout per N players

The device is **laid flat** (table) or **held by 2**. Each player owns a screen **zone**;
their UI/button is **rotated** to face them. The `InputZones` layer routes each raw pointer to
the zone that contains it → up to 4 simultaneous touches tracked independently.

```
1 PLAYER (vs bots)            2 PLAYERS (face-off, flat device)
┌─────────────────┐           ┌─────────────────┐
│                 │           │   P2 (rot 180°) │  ← player sits this side
│        P1       │           ├─────────────────┤
│   (full screen) │           │   P1 (rot 0°)   │  ← player sits this side
└─────────────────┘           └─────────────────┘
  full-screen zone              top half / bottom half

3 PLAYERS                      4 PLAYERS (quadrants)
┌────────┬────────┐           ┌────────┬────────┐
│  P2↺   │   P3↻  │           │ P3 ↺   │  P4 ↻  │
│ (rot270)(rot90) │           │(rot270) (rot90) │
├────────┴────────┤           ├────────┼────────┤
│     P1 (rot0)   │           │ P1     │  P2     │
└─────────────────┘           │(rot0)  │ (rot0)  │
  bottom wide + 2 top          └────────┴────────┘
```

- **Zone model:** `PlayerZone { playerId, Rect normRect, int rotationQuarters }`.
  `normRect` in 0..1 space (resolution-independent); `rotationQuarters` rotates that player's
  HUD/button so it faces them.
- **Layouts are data**, selected by player count + mode (`ZoneLayout.forPlayers(n, mode)`).
- Some minigames override the layout (e.g., Tug-of-War always splits left/right for 1v1).
- A minigame may also be a **shared arena** (all players act on one common field, e.g. Snake)
  while each still taps only in their own zone.

---

## 5. Minigame catalog (MVP)

14 minigames grouped into **mechanic families**. Each family shares a helper (DRY), so adding
games within a family is cheap — fueling the **+1/week** cadence.

Legend — **P**: players · **In**: input · **Win**: condition · **Reuse**: art/engine source.

### Family A — Push physics (forge2d arena) · helper `PushArena`
1. **Sumo Smash** — P:1–4 FFA/1v1 · In:Tap(dash-shove) · Win:last stick on the ring ·
   Reuse: STICK figure+ragdoll, DARK shake/particles, `camera_director`.
2. **Bumper Balls** — P:1–4 · In:Tap(burst toward center-out) · Win:last not knocked off ·
   Reuse: same arena, round bodies instead of sticks.

### Family B — Aim sweep + fire on tap · helper `AimSweep`
3. **Tank Duel** — P:1v1/2v2 · In:Tap(fire shell on auto-sweeping barrel) · Win:hit rival N× ·
   Reuse: `WeaponVisual` cannon, DARK `hit_burst`/shake, projectile arc.
4. **Archer Pop** — P:1–4 · In:Tap(release arrow at swinging angle) · Win:most targets/hits ·
   Reuse: STICK bow pose, particle pops.

### Family C — Lane hop / gravity timing · helper `LaneHopper`
5. **Chicken Jump** — P:1–4 · In:Tap(hop to next platform; floor rises) · Win:last alive ·
   Reuse: STICK jump clip, ragdoll fall, footstep dust.
6. **Falling Dodge** — P:1–4 · In:Tap(swap lane) · Win:last un-squashed by falling blocks ·
   Reuse: STICK run/ko, DARK shake on squash.

### Family D — Rapid-tap meter · helper `TapMashMeter`
7. **Tap Sprint** — P:1–4 · In:Mash · Win:first across finish · Reuse: STICK run clip, dust.
8. **Tug of War** — P:1v1/2v2 · In:Mash · Win:drag rope marker past your line ·
   Reuse: STICK pull pose, ragdoll on loss (loser flies).
9. **Button Masher** — P:1–4 · In:Mash · Win:most taps in 10s (cup tiebreaker) · Reuse: minimal.

### Family E — Reaction / timing gate · helper `ReactionGate`
10. **Reaction Duel** — P:1–4 · In:Tap(first after GO; early=penalty) · Win:fastest valid ·
    Reuse: big procedural signal, screen flash.
11. **Catch the Star** — P:1–4 · In:Tap(when your catcher overlaps moving star) · Win:most
    catches in time · Reuse: particle sparkle, score popups.

### Family F — Continuous one-touch steer / fill
12. **Snake Arena** — P:1–4 shared field · In:Tap(turn 90°) · Win:last alive / longest ·
    Reuse: geometric trail painter, DARK particles on crash.
13. **One-Touch Soccer** — P:1v1/2v2 forge2d · In:Tap(lunge/kick toward ball) · Win:most goals ·
    Reuse: STICK figure, `PushArena` ball physics, `camera_director`.
14. **Paint Splash** — P:1–4 · In:Hold(expand your blob) · Win:cover most area at timeout ·
    Reuse: `AreaFillGrid`, color particles.

**Optional 15 (stretch):** **Color Memory** (Simon) — P:1–4 · In:Tap(repeat your color seq) ·
Win:last to break the pattern · helper `SequenceGate`.

> Catalog is intentionally family-clustered: 6 helpers cover 14 games. Roadmap to 30–50 reuses
> the same helpers (e.g., new push games, new reaction games) → minimal new code per addition.

---

## 6. The `MiniGame` module contract

Every minigame is a self-contained module behind one interface. The engine knows nothing about
any specific game; it only drives this contract. **Adding a game = 1 new file + 1 registry line.**

```dart
/// Immutable setup passed once at init.
class MiniGameContext {
  final List<PlayerSlot> players;   // 1..4, each with id, team, isBot, botProfile, cosmetics
  final Size arena;                 // logical render size (resolution-independent)
  final SeededRng rng;              // deterministic → testable + replayable
  final GameMode mode;             // ffa | duel1v1 | team2v2 | team3v3
  final ZoneLayout zones;          // per-player input zones (or arena override)
  final BotDifficulty difficulty;
}

/// One input event already resolved to a player.
class PlayerInput {
  final int playerId;
  final InputPhase phase;           // down | up | holdTick
  final Offset normPos;             // 0..1 within that player's zone (most games ignore)
  final double dt;                  // for holdTick
}

enum MiniGameStatus { loading, ready, running, finished }

/// Ordered result; rank[0] = winner. Ties allowed via shared rank.
class WinResult {
  final List<int> ranking;          // playerIds best→worst
  final Map<int, num> finalScores;
}

abstract class MiniGame {
  MiniGameMeta get meta;            // id, displayKey, min/maxPlayers, supportedModes, themeId, icon
  MiniGameStatus get status;

  void init(MiniGameContext ctx);   // build world (forge2d if needed), figures, layout
  void onInput(PlayerInput input);  // route one-touch event (bots feed synthetic inputs)
  void update(double dt);           // advance sim; engine pre-scales dt by hit-stop
  void render(Canvas canvas, Size size); // draw bg + entities + per-player HUD (rotated)

  ScoreSnapshot get scores;         // live per-player score (for on-field HUD)
  WinResult? get winResult;         // non-null exactly when status == finished
  void dispose();                   // release forge2d world, pools, listeners
}
```

Design notes:
- **Engine-agnostic rendering:** `render(canvas,size)` draws to a raw `Canvas`, so a minigame is
  **unit-testable without Flame** (golden-test the canvas). A single Flame
  `MiniGameComponent` wraps any `MiniGame` for the real game loop + pointer input.
- **Physics is internal:** physics games own a private `forge2d` `World`; the contract is
  unchanged. Non-physics games (reaction, memory, paint) carry zero physics cost.
- **Determinism:** all randomness flows through `ctx.rng` → reproducible rounds, easy tests.
- **Bots:** the engine synthesizes `PlayerInput` for `isBot` slots via a `BotController` that
  reads `scores`/public game state and a `BotProfile` (reaction delay, error rate, accuracy by
  difficulty). Bot logic that needs game internals lives in the module via an optional
  `BotHints` it exposes; default bots just tap on a profile-jittered timer.
- **Lifecycle:** `init → ready → running → finished`. Engine reads `winResult` once finished,
  shows result, advances (Quick Play rematch or Cup next).

`MiniGameRegistry`: `Map<String,MiniGame Function()>` factories. One entry per game; the
game-select grid is generated from registry `meta`. This registry is the **+1/week enabler**.

---

## 7. Modes & Cup/Tournament

**Modes:**
- **Quick Play** — pick one game, play, instant rematch. Best-of optional.
- **Cup / Tournament** — the meta headliner. A curated/random **sequence of K minigames**
  (default K=5). Placement each game → cup points (4p: 1st=4 … 4th=1; or win=1). After K
  games, highest total = **champion** → podium with ragdoll celebration + confetti particles.
- **Team configs:** 1v1, 2v2, 3v3, FFA. Team mode aggregates teammate scores.

**Cup flow:** `CupController` holds the game queue + cumulative `Scoreboard`. Between games:
result → standings → (interstitial/house-ad, capped) → next. End: champion screen, coin
payout, rewarded "double coins", rematch / new cup. Cup is the natural ad cadence anchor.

---

## 8. Players, teams, bots

- **`PlayerManager`**: 1–4 `PlayerSlot`s. Each: `id (0–3)`, `displayName`, `colorId`, `isBot`,
  `botProfile?`, `cosmetics` (skin/style id, accessory, per-game theme). Immutable; setup
  screen builds a new list on each change.
- **Setup screen:** tap empty seats to add players, toggle human/bot, pick color/skin, choose
  mode. Odd counts auto-suggest a bot to balance teams.
- **Bots:** `BotProfile { reactionMs, errorRate, accuracy }` by `BotDifficulty {easy,med,hard}`.
  Shared across games for consistent feel; per-family helpers expose hooks (e.g., `AimSweep`
  bot fires when predicted angle error < threshold ± jitter).

---

## 9. Monetization + cross-promo (strategic core)

Hybrid-light, funnel-first. **Cross-promo is the point** (see PRD §2).

**Ads (network — AdMob via reused `AdService`):**
- **Interstitial:** only **between rounds / between cup games**, after a result is shown,
  never after a single demoralizing loss-sting, never mid-round. Cap: ≤1 per N rounds + 30s
  min gap (reused `ad_frequency`), disabled by remove-ads.
- **Banner:** menus only (home, shop, settings). Never on the play field.
- **Rewarded (opt-in only):** unlock a skin, **2× cup coins**, try a locked minigame once,
  unlock a map theme for the session. 6–10/session soft cap.

**House ads / cross-promo (`CrossPromoService` — first-class):**
- Local catalog of **own games**: `HouseAd { id, titleKey, blurbKey, iconPainter, storeUrl,
  weight }`. Icons drawn procedurally (no assets). Targets: drink-sort puzzle, stickman RPG.
- **Slots:** (a) a permanent "More Games" shelf in the home menu; (b) a share of the
  between-round full-screen slot rotates a house ad **instead of** a network interstitial —
  especially when network fill is low or to deliberately push the funnel; (c) a one-time
  "from the makers of…" card after the first cup.
- **Policy:** weighted rotation, frequency-capped like network ads, click → open `storeUrl`
  (tagged for attribution). Tracked via analytics (`house_ad_impression`, `house_ad_click`).
- **Tuning knob:** `houseAdShare` (e.g., 30% of full-screen slots are house ads) — the dial
  that trades a little ad revenue for catalog installs (the strategic objective).

**IAP (reused `IapService` + `purchase_applier`):**
- **Remove ads** — one-time (~$3.99). Removes network interstitial + banner (house-ad "More
  Games" shelf stays — it's content, not an interruption).
- **Unlock all** — all minigames + base skins.
- **Cosmetic bundles** — stickman skins, tank/ball trails, map themes, KO effects.
- **Coin packs** — soft currency (also earned by playing).
- Restore-idempotent (consumables not re-granted on restore).

**Ethics (EU/AGCM — see `LEGAL_GUARDRAILS.md`):** real-currency prices always shown, no
virtual-only pricing, no progression gates behind purchase (cosmetics only), no aggressive
timers, rating Everyone.

---

## 10. Shop & cosmetics

- **Currencies:** **coins** (soft, earned by playing/daily/missions), optional **gems** (hard,
  IAP) — keep economy simple (KISS); MVP can ship coins-only + IAP bundles.
- **Cosmetic types:**
  - **Stickman skins** — a `StickStyle` palette/glow + optional accessory (hat, cape) drawn
    procedurally. Per player slot.
  - **Per-game cosmetics** — tank skin, ball/snake trail, KO burst color, map theme.
  - **Map themes** — gradient + geometric + `ambient_particles` flavor.
- **Unlock paths** (reused `Skin` model): free / coins / gems / IAP / rewarded.
- **No pay-to-win:** cosmetics never affect gameplay. Explicitly enforced.

---

## 11. Procedural art system (no external assets)

| Layer | Source | Implementation |
|---|---|---|
| **Stickman** | STICK | skeleton (FK) + pose + IK + `stickman_painter` (glow/rim/shadow) + Verlet `stick_ragdoll`. Party clip set (idle/run/jump/cheer/cry/push/swing/ko/kick/wave). |
| **VFX** | DARK | `particle_effect`, `hit_burst`, `screen_shake`, `hit_stop`, score popups, `ambient_particles`, `camera_director`. |
| **Backgrounds/maps** | new + BALL style | gradient + geometric shapes per theme; ambient particles; parallax-lite. |
| **UI** | BALL theme | procedural buttons/panels, per-player rotated HUD, `flutter_animate` transitions. |
| **Weapons/props** | STICK `WeaponVisual` | cannon, bow, sword, bat, ball — path-drawn. |

Art principles: cohesive neon-on-dark base with bright per-player accent colors; juice over
detail (movement/shake/particles sell quality, not texture). All resolution-independent
(0..1 logical space scaled to device).

---

## 12. Retention systems (reuse BALL)

- **Daily reward** — login bonus (7-day cycle, reused `daily_service`).
- **Play-streak** — consecutive-day play (reused `streak_service`), badge at 3/5/7.
- **Daily missions** — party-flavored (`playRounds`, `winRounds`, `winCup`, `tryNewGame`,
  `playWithFriends(2+)`); deterministic per-day generation.
- **Unlocks** — skins / map themes / minigames; the +1/week game is itself a retention event.
- **Records & stats** — per-game bests, total cups won, KOs, games played; stats screen.
- **Achievements** — milestones (win 10 cups, KO 50 rivals, play every game).
- **Notifications** — daily/streak/recall reminders ("Your friends are waiting!").
- **Events (FOMO-free):** cosmetic-only time-limited skins; never gate progression.

---

## 13. Game feel / juice (the "succo")

Mandatory polish on every minigame (reuse DARK):
- **Screen shake** on impacts/KO (accessibility scalable, capped).
- **Hit-stop** on big hits (engine pre-scales `dt` so all games inherit it).
- **Particles** on hit/score/KO/win; **ambient particles** per map.
- **Ragdoll** on KO/elimination (sticks fly + flop — the comedy core).
- **Score popups** ("+1", "KO!", "WIN!") via repurposed damage-number system.
- **Sound** (procedural/simple SFX via audioplayers) — taps, hits, whistle, crowd cheer.
- **Anticipation/celebration:** countdown "3·2·1·GO!", podium confetti, loser cry animation.

---

## 14. FTUE (first session)

- Cold start → home in <2s → "Quick Play" one tap → auto 1 human + 1 bot → a simple game
  (Tap Sprint or Sumo) → fun in **5 seconds**.
- No text tutorial; a pulsing hint ("TAP!") in your zone for the first round only.
- Ads **delayed** until after the first full cup (don't burn the first impression).
- Soft monetization only after first "aha" (a single, dismissible cosmetic teaser).
