import 'dart:ui';

/// Shape family for the procedurally-drawn prop held in the front hand
/// (tank cannon, bow, sword, bat, etc.). Pure data — no gameplay coupling.
enum WeaponShape {
  none,
  sword,
  greatsword,
  dagger,
  spear,
  scythe,
  hammer,
  gauntlet,
  whip,
  twin,
}

/// Lightweight descriptor for rendering a held prop at the front hand.
/// Party games build these directly (no weapon model dependency).
class WeaponVisual {
  final WeaponShape shape;
  final Color color;
  final Color edge; // bright edge / neon
  final double length;
  final double width;

  const WeaponVisual({
    required this.shape,
    required this.color,
    required this.edge,
    this.length = 28,
    this.width = 4,
  });

  static const none = WeaponVisual(
    shape: WeaponShape.none,
    color: Color(0x00000000),
    edge: Color(0x00000000),
    length: 0,
    width: 0,
  );

  WeaponVisual copyWith({
    WeaponShape? shape,
    Color? color,
    Color? edge,
    double? length,
    double? width,
  }) =>
      WeaponVisual(
        shape: shape ?? this.shape,
        color: color ?? this.color,
        edge: edge ?? this.edge,
        length: length ?? this.length,
        width: width ?? this.width,
      );
}
