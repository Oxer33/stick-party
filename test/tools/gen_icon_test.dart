// Procedural app-icon generator (run as a test): renders the stickman painter
// to PNGs under assets/icon/ for flutter_launcher_icons. No external art assets.
//
//   flutter test test/tools/gen_icon_test.dart
//
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/art/stick/stick_pose.dart';
import 'package:stick_party/art/stick/stick_skeleton.dart';
import 'package:stick_party/art/stick/stick_style.dart';
import 'package:stick_party/art/stick/stickman_painter.dart';
import 'package:stick_party/art/stick/weapon_visual.dart';
import 'package:stick_party/core/constants.dart';
import 'package:stick_party/core/math2.dart';

const int _size = 1024;

/// A celebratory "arms up" V pose (world-space radians, y-down: up = -pi/2).
StickPose _cheerPose() => StickPose(
      spine: rad(-90),
      neck: rad(-90),
      armBackUpper: rad(-124),
      armBackFore: rad(-134),
      armFrontUpper: rad(-56),
      armFrontFore: rad(-46),
      legBackThigh: rad(110),
      legBackShin: rad(98),
      legFrontThigh: rad(70),
      legFrontShin: rad(86),
    );

Future<ui.Image> _render({
  required bool withBackground,
  required double figureScale,
  required double rootYFactor,
}) async {
  final rec = ui.PictureRecorder();
  final side = _size.toDouble();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, side, side));
  final size = Size(side, side);

  if (withBackground) {
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(side, side),
        const [Color(0xFF211A3A), Color(0xFF5B1F9E), Color(0xFFC2228A)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(180)),
      bg,
    );
    // Soft spotlight behind the figure.
    canvas.drawCircle(
      Offset(side / 2, side * 0.52),
      side * 0.46,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(side / 2, side * 0.52),
          side * 0.46,
          const [Color(0x55FFFFFF), Color(0x00FFFFFF)],
        ),
    );
    // Confetti in player colors.
    const spots = [
      Offset(0.16, 0.20), Offset(0.84, 0.18), Offset(0.26, 0.84),
      Offset(0.78, 0.82), Offset(0.50, 0.10), Offset(0.10, 0.54),
      Offset(0.90, 0.50),
    ];
    for (var i = 0; i < spots.length; i++) {
      canvas.drawCircle(
        Offset(spots[i].dx * side, spots[i].dy * side),
        side * 0.021,
        Paint()..color = Color(PlayerPalette.argb[i % PlayerPalette.argb.length]),
      );
    }
  }

  final proportions = StickProportions.hero.scaled(figureScale);
  final frame = StickSkeleton(proportions).resolve(
    _cheerPose(),
    Offset(side / 2, side * rootYFactor),
    1,
  );
  const style = StickStyle(
    fill: Color(0xFFFFD23C),
    outline: Color(0xFF1A1030),
    glowSigma: 6,
    lineWidth: 2.6,
    rimAlpha: 0.0,
    shadowAlpha: 0.0,
    gradientBottom: 0.25,
  );
  StickmanPainter.paint(canvas, frame, style, weapon: WeaponVisual.none);

  return rec.endRecording().toImage(_size, _size);
}

Future<void> _writePng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('generate app icons', () async {
    final full = await _render(
        withBackground: true, figureScale: 9.5, rootYFactor: 0.82);
    await _writePng(full, 'assets/icon/app_icon.png');

    final foreground = await _render(
        withBackground: false, figureScale: 7.5, rootYFactor: 0.76);
    await _writePng(foreground, 'assets/icon/app_icon_foreground.png');

    expect(File('assets/icon/app_icon.png').existsSync(), isTrue);
    expect(File('assets/icon/app_icon_foreground.png').existsSync(), isTrue);
  });
}
