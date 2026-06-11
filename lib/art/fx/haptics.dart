/// Tactile feedback bus. A thin, fire-and-forget wrapper over the platform
/// haptics so game logic (pure dart, no widgets) can buzz on big moments
/// without importing the Flutter widget layer.
///
/// All calls are gated by [enabled] (wired to the settings toggle) and wrapped
/// so they can never throw — on platforms or test bindings without a haptics
/// channel they are silent no-ops.
library;

import 'package:flutter/services.dart';

/// Static, stateless haptics facade. Cheap to call from any game.
class Haptics {
  Haptics._();

  /// Master switch (mirrors the settings "vibration" toggle). When false every
  /// call below is a no-op.
  static bool enabled = true;

  /// Light tap — UI selection, a scored point, a pickup.
  static void light() => _fire(HapticFeedback.lightImpact);

  /// Medium thud — a solid hit, a goal, a round-beat landing.
  static void medium() => _fire(HapticFeedback.mediumImpact);

  /// Heavy slam — a KO, an elimination, a signature climax.
  static void heavy() => _fire(HapticFeedback.heavyImpact);

  /// Crisp selection click — menu / toggle feedback.
  static void select() => _fire(HapticFeedback.selectionClick);

  static void _fire(Future<void> Function() impulse) {
    if (!enabled) return;
    // Fire-and-forget. The platform call is async, so a missing binding (e.g.
    // a pure-`test` unit test) surfaces as a REJECTED FUTURE, not a sync throw
    // — swallow both so haptics can never crash a frame or a test.
    try {
      impulse().catchError((Object _) {});
    } catch (_) {
      // No haptics channel here — silent.
    }
  }
}
