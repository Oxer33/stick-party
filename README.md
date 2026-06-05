# Stick Party — 2 3 4 Player Games

A local-multiplayer party game: **1–4 players on one phone**, dozens of one-touch
minigames, procedural stickman art, juicy "ruin-a-friendship" chaos. **100% offline** —
no networking, no backend, no external assets (everything drawn in code).

> Working title. Built with Flutter + a custom Canvas engine. Rating: Everyone / E10.

## Features (MVP)

- **15 minigames** across 6 reusable mechanic families (sumo, tank duel, soccer, snake,
  tap-sprint, tug-of-war, reaction, paint, memory, …).
- **1–4 players** same device, with **bot AI** (3 difficulties). FFA / 1v1 / 2v2.
- **Cup / Tournament** mode: a sequence of minigames → a champion.
- **Multitouch** zones (2–4 simultaneous touches), per-player rotated HUD.
- **Meta**: daily reward, play-streak, daily missions, achievements, records, cosmetics shop.
- **Monetization (ethical, EU/AGCM-aware)**: ad/IAP stubs + **cross-promo house-ads** to the
  studio catalog (the strategic objective). Offline build keeps network ads off.

## Architecture

Every minigame is a self-contained module behind one interface — `MiniGame`
(`init / onInput / update / render / scores / winResult`) — registered in
`lib/engine/registry.dart`. **Adding a game = one file + one registry line.** The engine
(input zones, players, bots, scoreboard, cup, mechanic-family helpers) knows nothing about
any concrete game. See `docs/ARCHITECTURE.md`.

```
lib/
  core/        foundations (result, math2, rng, constants)
  art/stick/   procedural stickman skeleton + ragdoll + painter
  art/fx/      particles, screen-shake, hit-stop, score popups (juice)
  engine/      MiniGame contract, registry, input zones, bots, scoreboard, cup, helpers/
  minigames/   one folder per game (15)
  meta/        streak, daily, achievements, cosmetics, progress
  data/        Hive persistence
  services/    ad / iap / cross-promo / analytics (offline stubs + pure policy)
  app/         theme, router, providers, screens, the gameplay runner, main
```

## Run / build / test

```bash
flutter pub get
flutter run                       # play it
flutter test                      # 335 unit/logic tests
flutter test --coverage           # ~89% on pure-logic units
flutter build apk --release       # → build/app/outputs/flutter-apk/app-release.apk
```

## Docs

`docs/` — `PRD.md`, `GAME_DESIGN.md`, `ARCHITECTURE.md`, `REUSE_MAP.md`, `ROADMAP.md`,
`LEGAL_GUARDRAILS.md`.

## Status

MVP complete: 15 minigames, Cup, meta, shop, cross-promo, offline. Release APK builds.
Roadmap: +1 minigame/week toward 30–50, then real ad/IAP SDK wiring (P4) for store launch.
