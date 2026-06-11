/// Global tuning knobs. No magic numbers inline elsewhere. Pure data.
library;

/// Game-feel tuning (juice).
class Feel {
  static const double maxShakePx = 6;
  static const double hitStopDefaultSec = 0.06;
  static const double hitStopHeavySec = 0.14;
  static const int particleSoftCap = 90;
  static const double scorePopupRiseSec = 0.8;

  // ── Cinematic layer (KO / signature moments) ────────────────────────────────
  /// KO freeze: a punchy dip that lingers just long enough to read the hit.
  static const double koHitStopSec = 0.34;
  static const double koHitStopScale = 0.16;

  /// Generic slow-mo for photo-finishes / climaxes (softer, longer than a KO).
  static const double slowMoSec = 0.55;
  static const double slowMoScale = 0.32;

  /// Camera zoom-punch toward the action (1 = no zoom). Snaps in, glides out.
  static const double cameraPunchScale = 1.16;
  static const double cameraPunchSec = 0.55;
  static const double cameraPunchMax = 1.6; // safety clamp

  /// Full-screen color flash on a big event.
  static const double screenFlashSec = 0.22;

  /// Big celebratory center banner ("GOAL!", "FINAL HEAVE!").
  static const double bannerSec = 1.15;
}

/// Cup / tournament tuning.
class Cup {
  static const int defaultGames = 5;
  static const int minGames = 3;
  static const int maxGames = 7;
}

/// Monetization policy. Offline MVP keeps network ads OFF (stub services);
/// real SDK wiring is a later step requiring store IDs (see docs/ROADMAP P4).
class Monetize {
  static const bool networkAdsEnabled = false;
  static const int interstitialMinRoundGap = 2; // rounds between interstitials
  static const int interstitialMinSecondsGap = 30;
  static const int rewardedDailyCap = 18;
  static const double houseAdShare = 0.30; // share of full-screen slots → house ads
}

/// Default logical arena (resolution-independent; scaled to device).
class Arena {
  static const double logicalW = 1000;
  static const double logicalH = 1000;
}

/// Per-player accent colors (ARGB). Index 0..3 = player 1..4.
class PlayerPalette {
  static const List<int> argb = <int>[
    0xFFFF5A5A, // P1 red
    0xFF4D9BFF, // P2 blue
    0xFF54E08A, // P3 green
    0xFFFFC93C, // P4 yellow
  ];
}

/// Soft-currency economy.
class Economy {
  static const int coinsPerRoundWin = 10;
  static const int coinsPerCupWin = 50;
  static const int maxCoins = 999999;
}
