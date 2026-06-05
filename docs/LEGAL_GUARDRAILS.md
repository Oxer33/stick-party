# LEGAL & ETHICAL GUARDRAILS — Stick Party

> Binding constraints for a family-rated, EU/Italy-operating, ad-funded game. Derived from
> RICERCA §11 (AGCM 2026, dark-pattern taxonomy, Families policy). These are requirements,
> not suggestions — they shape the shop, ads, and rating from day one.

---

## 1. Rating: Everyone / E10

- Cartoon violence only (stick figures bonk/ragdoll). **No blood, no gore, no death framing,
  no adult content, no gambling themes.**
- KO = comedic flop, not injury. Loser animations are silly (cry, dizzy), never graphic.
- Target audience includes children → **Google Play Families** requirements apply.

## 2. Google Play Families compliance

- Only **self-certified, Families-compliant ad SDKs** (AdMob with appropriate settings).
- Tag ad requests as child-directed / mixed-audience as required; no behavioral targeting of
  minors; no collection of personal data from children.
- Neutral age screen if mixed-audience design requires it.
- No ads that lead off-platform to age-inappropriate content. House-ads point only to our own
  Everyone-rated catalog titles.

## 3. Monetization ethics (AGCM / EU consumer protection)

The AGCM (Italy) opened 2026 probes into deceptive/aggressive purchase-pushing design. We
treat dark patterns as **consumer-protection risk**, not just policy. Hard rules:

**Pricing transparency**
- Always show **real-currency price** on every purchase. **No virtual-currency-only pricing**
  that hides real cost.
- For coin/gem packs, show the real-money price clearly; avoid confusing "mystery" bundles.

**No progression gates**
- IAP and rewarded ads unlock **cosmetics and convenience only**. **Nothing required to
  play/progress** is locked behind payment. No "pay to continue / pay to win".
- Minigames may be unlocked with **soft currency earned by playing** or IAP — but the game is
  fully enjoyable without spending (enough free games + earnable unlocks).

**No aggressive FOMO / fake scarcity**
- No countdown timers pressuring purchase of progression. Time-limited content is
  **cosmetic-only** and clearly optional.
- No repeated nag pop-ups; purchase prompts are dismissible and infrequent.

**No manipulative UI**
- No disguised buttons, no hidden cancel, no childish UI around payment prompts, no
  accidental one-tap buys. Confirmation before any charge.

**Variable-ratio / RNG**
- Avoid gambling-style variable-ratio spend mechanics. If any RNG cosmetic exists, **disclose
  odds** and never target minors. (MVP: prefer direct-purchase cosmetics, no loot boxes.)

**Spend safeguards**
- Respect platform parental controls. Consider optional spend awareness for large packs.

## 4. Ads placement ethics

- **Never during a live round.** Interstitials only between rounds/cup-games, after a result,
  frequency-capped (RICERCA §10). Never after a single demoralizing loss-sting.
- Banners in menus only, never on the play field.
- Rewarded ads are **opt-in only**, clearly labeled, with a stated reward.
- Respect remove-ads purchase everywhere (network ads off; the "More Games" content shelf is
  not an ad interruption and may remain).

## 5. Privacy & data

- Offline game, no accounts, no networking for gameplay. Minimize data collection.
- Publish a **privacy policy** URL; complete Play **Data Safety** form accurately (analytics +
  ads SDKs disclosed).
- No PII from children. Analytics events are aggregate/behavioral game metrics, not identity.

## 6. The business case (why this pays off)

RICERCA §11: ethical design traded ~-8% short-term ARPDAU for **+12% D180 retention, halved
refunds**, better sentiment, lower legal risk. For a funnel/cross-promo game, **retention and
trust are the product** (they feed catalog installs) — ethics is aligned with the strategy.

## 7. Implementation hooks

| Guardrail | Enforced in |
|---|---|
| Real-currency prices | shop screen + `IapService` product display |
| No mid-round ads | `mini_game_component` / `cup_controller` ad cadence; `ad_frequency` |
| Cosmetic-only purchases | `purchase_applier` (no gameplay grants); cosmetics model |
| Caps & opt-in rewarded | `ad_frequency`, rewarded call sites |
| Families ad config | `AdService` init flags + Play console |
| Data Safety / privacy | store listing + analytics config |
| House-ads → own Everyone titles only | `CrossPromoService` catalog |
