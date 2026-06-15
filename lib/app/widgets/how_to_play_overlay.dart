/// Pre-game "how to play" splash shown the moment a minigame opens, before the
/// 3..2..1 countdown. A single centred glass card: the game name, a control
/// glyph, one short localized sentence describing the controls + goal, and a
/// pulsing "tap to start" prompt. A full-screen tap (or the runner's short
/// auto-advance) dismisses it into the countdown.
///
/// Pure presentation: the runner resolves the localized strings and feeds them
/// in, and owns the dismiss. The card is single-orientation (host-readable);
/// each seated player still gets their own rotated action cue during the
/// countdown via [StartCueOverlay].
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'glass_tokens.dart';
import 'start_cue_overlay.dart' show CueKind, cueKindFor;

/// The localized one-line how-to-play text for [gameId] (controls + goal),
/// shown on the pre-game splash. Falls back to '' for an unknown id (the runner
/// then simply skips the sentence rather than showing English in another UI).
String localizedHowTo(AppLocalizations l10n, String gameId) {
  switch (gameId) {
    case 'sumo_smash':
      return l10n.howto_sumo_smash;
    case 'bumper_balls':
      return l10n.howto_bumper_balls;
    case 'one_touch_soccer':
      return l10n.howto_one_touch_soccer;
    case 'tank_duel':
      return l10n.howto_tank_duel;
    case 'archer_pop':
      return l10n.howto_archer_pop;
    case 'chicken_jump':
      return l10n.howto_chicken_jump;
    case 'falling_dodge':
      return l10n.howto_falling_dodge;
    case 'tap_sprint':
      return l10n.howto_tap_sprint;
    case 'tug_of_war':
      return l10n.howto_tug_of_war;
    case 'button_masher':
      return l10n.howto_button_masher;
    case 'reaction_duel':
      return l10n.howto_reaction_duel;
    case 'snake_arena':
      return l10n.howto_snake_arena;
    case 'paint_splash':
      return l10n.howto_paint_splash;
    case 'catch_the_star':
      return l10n.howto_catch_the_star;
    case 'color_memory':
      return l10n.howto_color_memory;
    default:
      return '';
  }
}

/// A Material icon standing in for each control archetype (language-neutral so
/// the glyph reads regardless of locale).
IconData howToGlyphFor(CueKind kind) {
  switch (kind) {
    case CueKind.tap:
      return Icons.touch_app_rounded;
    case CueKind.hold:
      return Icons.back_hand_rounded;
    case CueKind.mash:
      return Icons.ads_click_rounded;
    case CueKind.drag:
      return Icons.open_with_rounded;
  }
}

/// Full-screen pre-game splash. Tapping anywhere calls [onStart].
class HowToPlayOverlay extends StatelessWidget {
  const HowToPlayOverlay({
    super.key,
    required this.gameName,
    required this.howTo,
    required this.tapToStart,
    required this.inputHint,
    required this.onStart,
    required this.repaint,
    this.accent = GlassColors.violet,
  });

  /// Localized game title.
  final String gameName;

  /// Localized one-line controls + goal (may be empty → sentence is omitted).
  final String howTo;

  /// Localized "tap to start" prompt.
  final String tapToStart;

  /// The game's raw input hint (drives the control glyph).
  final String inputHint;

  /// Called when the player taps to begin (or the runner auto-advances).
  final VoidCallback onStart;

  /// Per-frame tick from the runner (its hudTick) that drives the prompt pulse.
  final ValueListenable<int> repaint;

  /// Card accent / border color.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final IconData glyph = howToGlyphFor(cueKindFor(inputHint));
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onStart,
        child: Container(
          // Scrim so the static field + countdown cues underneath read as a
          // dimmed backdrop behind the card.
          color: GlassColors.base.withValues(alpha: 0.72),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
              decoration: BoxDecoration(
                color: GlassColors.baseHigh.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: accent.withValues(alpha: 0.85), width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 34,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    gameName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: 0.5,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Control glyph in a soft accent disc.
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.16),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
                    ),
                    child: Icon(glyph, color: accent, size: 40),
                  ),
                  if (howTo.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    Text(
                      howTo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: GlassColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        height: 1.32,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _StartPrompt(
                    label: tapToStart,
                    accent: GlassColors.cyan,
                    repaint: repaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gently pulsing "tap to start" line. Rides the runner's per-frame
/// [repaint] tick so it breathes without owning an [AnimationController].
class _StartPrompt extends StatelessWidget {
  const _StartPrompt({
    required this.label,
    required this.accent,
    required this.repaint,
  });

  final String label;
  final Color accent;
  final ValueListenable<int> repaint;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repaint,
      builder: (BuildContext context, Widget? child) {
        // hudTick advances ~once per frame; map it to a slow 0..1 breathe.
        final double pulse =
            0.55 + 0.45 * (0.5 + 0.5 * math.sin(repaint.value * 0.12));
        return Opacity(opacity: pulse.clamp(0.0, 1.0), child: child);
      },
      child: Text(
        label.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}
