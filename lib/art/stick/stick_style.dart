import 'dart:ui';

/// Visual style for a stickman: fill, neon outline, glow, thickness, optional
/// glowing core (shadow wraiths). Pure data — the painter consumes it.
class StickStyle {
  final Color fill;
  final Color outline;
  final double glowSigma; // 0 = no glow pass
  final double lineWidth; // bone thickness multiplier (1 = use frame width)
  final Color? coreColor; // glowing chest core (shadows/charged states)
  final double alpha; // 0..1 overall

  // ---- New optional premium fields (all have safe defaults) ------------------

  /// Multiplier for the faint rim stroke drawn over each bone (0 = no rim).
  final double rimAlpha;

  /// Opacity of the ground drop-shadow ellipse (0 = no shadow).
  final double shadowAlpha;

  /// How much darker the bottom of the torso fill gradient is (0 = flat fill).
  final double gradientBottom;

  /// 0..1 pulse amplitude for the chest core glow radius. Driven externally
  /// (e.g. set to `sin(t)*0.5+0.5` each frame). Defaults to 0 (no pulse).
  final double corePulse;

  /// 0..1 strength of velocity-based limb smear ghost. 0 = disabled.
  final double smearAlpha;

  /// When true, draw per-style flourishes: boss shoulder/brow horns; shadow
  /// ground-wisps. Defaults to false so generic enemies stay cheap.
  final bool flourish;

  const StickStyle({
    required this.fill,
    required this.outline,
    this.glowSigma = 4,
    this.lineWidth = 1,
    this.coreColor,
    this.alpha = 1,
    this.rimAlpha = 0.18,
    this.shadowAlpha = 0.45,
    this.gradientBottom = 0.55,
    this.corePulse = 0,
    this.smearAlpha = 0.22,
    this.flourish = false,
  });

  StickStyle copyWith({
    Color? fill,
    Color? outline,
    double? glowSigma,
    double? lineWidth,
    Color? coreColor,
    double? alpha,
    double? rimAlpha,
    double? shadowAlpha,
    double? gradientBottom,
    double? corePulse,
    double? smearAlpha,
    bool? flourish,
  }) =>
      StickStyle(
        fill: fill ?? this.fill,
        outline: outline ?? this.outline,
        glowSigma: glowSigma ?? this.glowSigma,
        lineWidth: lineWidth ?? this.lineWidth,
        coreColor: coreColor ?? this.coreColor,
        alpha: alpha ?? this.alpha,
        rimAlpha: rimAlpha ?? this.rimAlpha,
        shadowAlpha: shadowAlpha ?? this.shadowAlpha,
        gradientBottom: gradientBottom ?? this.gradientBottom,
        corePulse: corePulse ?? this.corePulse,
        smearAlpha: smearAlpha ?? this.smearAlpha,
        flourish: flourish ?? this.flourish,
      );

  // ---- Presets ---------------------------------------------------------------

  /// The hunter: dark body, cyan neon outline.
  static const hero = StickStyle(
    fill: Color(0xFF12161F),
    outline: Color(0xFF35E0FF),
    glowSigma: 5,
    coreColor: Color(0xFFBDF4FF),
    rimAlpha: 0.22,
    shadowAlpha: 0.5,
    gradientBottom: 0.6,
    smearAlpha: 0.22,
  );

  /// Hunter in a charged/ultimate state: amber rim.
  static const heroCharged = StickStyle(
    fill: Color(0xFF1A130A),
    outline: Color(0xFFFFB23A),
    glowSigma: 7,
    coreColor: Color(0xFFFFE6B0),
    rimAlpha: 0.28,
    shadowAlpha: 0.55,
    gradientBottom: 0.65,
    smearAlpha: 0.28,
  );

  /// Generic enemy: muted red-violet outline.
  static const enemy = StickStyle(
    fill: Color(0xFF1B1016),
    outline: Color(0xFFE0556B),
    glowSigma: 3,
    rimAlpha: 0.14,
    shadowAlpha: 0.35,
    gradientBottom: 0.5,
    smearAlpha: 0.16,
  );

  /// Boss: heavier, hot magenta, with flourishes.
  static const boss = StickStyle(
    fill: Color(0xFF1C0A18),
    outline: Color(0xFFFF3DD0),
    glowSigma: 8,
    lineWidth: 1.4,
    coreColor: Color(0xFFFFB6F0),
    rimAlpha: 0.3,
    shadowAlpha: 0.6,
    gradientBottom: 0.7,
    smearAlpha: 0.25,
    flourish: true,
  );

  /// Umbral shadow soldier silhouette (tier tint applied via [shadow]).
  static StickStyle shadow(Color tint) => StickStyle(
        fill: const Color(0xF00A0612),
        outline: tint,
        glowSigma: 6,
        coreColor: const Color(0xFFE0F0FF),
        alpha: 0.96,
        rimAlpha: 0.2,
        shadowAlpha: 0.45,
        gradientBottom: 0.6,
        smearAlpha: 0.2,
        flourish: true,
      );
}
