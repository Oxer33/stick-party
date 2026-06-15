// Procedural app-icon generator (run as a test so the icon stays reproducible
// AND can never silently drift — it regenerates identical deterministic bytes):
// renders the "Sumo shove" launcher icon to assets/icon/ for
// flutter_launcher_icons. No external art assets.
//
//   flutter test test/tools/gen_icon_test.dart
//
// Two stick wrestlers (flame vs cyan) locked head-to-head in a grapple, a clash
// starburst between them, on a glowing dohyo ring over brand indigo. Full icon
// = app_icon.png; figures-only-on-transparent = app_icon_foreground.png (the
// Android adaptive foreground, kept inside the safe circle).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 1024;

const _flame = Color(0xFFFB7234);
const _cyan = Color(0xFF22D3EE);
const _dark = Color(0xFF0C0A18);
const _white = Color(0xFFFFFFFF);

// Foreground "camera": the whole fight group (dohyo→clash) is scaled about this
// pivot so the two wrestlers fill more of the frame. Pivot sits on the grapple
// mass; zoom kept so the adaptive foreground still fits the safe circle (r≤313).
const _fgPivot = Offset(512, 520);
const double _fgZoom = 1.3;

Paint _strokePaint(double w, Color col) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..color = col
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _wrestler(Canvas c, double px, double py, double s, double mirror, Color glow) {
  c.save();
  c.translate(px, py);
  c.scale(mirror * s, s);
  final body = Path()
    ..moveTo(10, -48)
    ..lineTo(-8, -14) // torso (heavy forward lean)
    ..moveTo(10, -46)
    ..lineTo(32, -34) // upper grappling arm
    ..moveTo(8, -42)
    ..lineTo(32, -22) // lower grappling arm
    ..moveTo(-8, -14)
    ..lineTo(14, 6)
    ..lineTo(28, 28) // front planted leg
    ..moveTo(-8, -14)
    ..lineTo(-22, 4)
    ..lineTo(-30, 28); // braced back leg
  c.drawPath(body, _strokePaint(10, glow.withValues(alpha: 0.22))); // neon halo
  c.drawPath(body, _strokePaint(4.6, glow)); // core
  c.drawPath(body, _strokePaint(1.7, Color.lerp(glow, _white, 0.6)!.withValues(alpha: 0.9)));
  // Mawashi belt nub.
  final belt = Path()
    ..moveTo(2, -20)
    ..lineTo(-12, -12);
  c.drawPath(belt, _strokePaint(6, const Color(0xFFF3ECFF)));
  c.drawPath(belt, _strokePaint(2.4, glow.withValues(alpha: 0.9)));
  // Head: halo ring -> dark fill -> neon ring -> inner highlight.
  const hc = Offset(16, -56);
  const hr = 15.0;
  c.drawCircle(hc, hr, _strokePaint(9, glow.withValues(alpha: 0.22)));
  c.drawCircle(hc, hr, Paint()..color = _dark);
  c.drawCircle(hc, hr, _strokePaint(3.6, glow));
  c.drawCircle(hc, hr - 2.4, _strokePaint(1.4, Color.lerp(glow, _white, 0.7)!.withValues(alpha: 0.85)));
  c.restore();
}

void _clashHalo(Canvas c) {
  c.drawCircle(
    const Offset(512, 432),
    112,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(512, 432), 112,
          const <Color>[Color(0x42FFFFFF), Color(0x00FFFFFF)]),
  );
  c.drawCircle(const Offset(512, 432), 64, Paint()..color = const Color(0x40FBBF24));
  c.drawCircle(const Offset(512, 432), 36, Paint()..color = const Color(0x4DFB7234));
}

void _clashCore(Canvas c) {
  const ctr = Offset(512, 432);
  final rayLong = _strokePaint(6, const Color(0xFFFFE9B8));
  final rayShort = _strokePaint(3.4, const Color(0xFFFFF6DE));
  for (var i = 0; i < 12; i++) {
    final a = i * math.pi / 6;
    final long = i.isEven;
    final r1 = long ? 18.0 : 14.0;
    final r2 = long ? 58.0 : 36.0;
    c.drawLine(
      Offset(ctr.dx + math.cos(a) * r1, ctr.dy + math.sin(a) * r1),
      Offset(ctr.dx + math.cos(a) * r2, ctr.dy + math.sin(a) * r2),
      long ? rayLong : rayShort,
    );
  }
  c.drawCircle(ctr, 18, Paint()..color = const Color(0xFFFBBF24));
  c.drawCircle(ctr, 11, Paint()..color = _white);
}

void _footShadows(Canvas c, double a) {
  void sh(double x, double y, double w) => c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.26),
        Paint()..color = const Color(0xFF000000).withValues(alpha: a),
      );
  sh(289, 662, 150);
  sh(735, 662, 150);
  sh(500, 664, 120);
  sh(524, 664, 120);
}

void _dust(Canvas c) {
  const d = Color(0xFFC9C4DA);
  void puff(double x, double y, double w, double op) => c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.42),
        Paint()..color = d.withValues(alpha: op),
      );
  puff(240, 650, 90, 0.16);
  puff(784, 650, 90, 0.16);
  puff(300, 664, 60, 0.12);
  puff(724, 664, 60, 0.12);
  final sp = Paint()..color = d.withValues(alpha: 0.22);
  for (final o in const <Offset>[Offset(232, 612), Offset(792, 612), Offset(262, 628), Offset(762, 628)]) {
    c.drawCircle(o, 5, sp);
  }
}

void _dohyo(Canvas c) {
  const ctr = Offset(512, 648);
  Rect e(double rx, double ry) => Rect.fromCenter(center: ctr, width: rx * 2, height: ry * 2);
  Paint ring(double w, Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = col;
  c.drawOval(e(195, 50), Paint()..color = const Color(0x14FBBF24)); // clay platform
  c.drawOval(e(195, 50), ring(16, const Color(0x2EFBBF24))); // outer halo
  c.drawOval(e(195, 50), ring(6, const Color(0x80FBBF24))); // mid ring
  c.drawOval(e(195, 50), ring(2.6, const Color(0xCCFFE6B0))); // bright rim
  c.drawOval(e(145, 38), ring(3, const Color(0x40FB7234))); // inner raked ring
}

void _bg(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 1024, 1024);
  c.drawRRect(
    RRect.fromRectAndRadius(r, const Radius.circular(180)),
    Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 1024),
          const <Color>[Color(0xFF1C1430), Color(0xFF0A0816)]),
  );
  c.drawRect(
    r,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(512, 470), 440,
          const <Color>[Color(0x338B5CF6), Color(0x008B5CF6)]),
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(512, 656), width: 620, height: 130),
    Paint()..color = const Color(0x1AFB7234),
  );
  c.drawRect(
    const Rect.fromLTWH(0, 0, 1024, 380),
    Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 380),
          const <Color>[Color(0x14FFFFFF), Color(0x00FFFFFF)]),
  );
  c.drawRect(
    r,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(512, 512), 780,
          const <Color>[Color(0x00000000), Color(0x66000000)], const <double>[0.6, 1.0]),
  );
}

Future<ui.Image> _render({required bool withBackground}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 1024, 1024));
  if (withBackground) _bg(canvas);
  // Zoom the fight group toward the camera (bg stays full-bleed).
  canvas.save();
  canvas.translate(_fgPivot.dx, _fgPivot.dy);
  canvas.scale(_fgZoom);
  canvas.translate(-_fgPivot.dx, -_fgPivot.dy);
  _dohyo(canvas);
  _clashHalo(canvas);
  _footShadows(canvas, withBackground ? 0.30 : 0.22);
  _wrestler(canvas, 397, 554, 3.6, 1, _flame);
  _wrestler(canvas, 627, 554, 3.6, -1, _cyan);
  _dust(canvas);
  _clashCore(canvas);
  canvas.restore();
  return rec.endRecording().toImage(_size, _size);
}

Future<void> _writePng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('generate app icons', () async {
    await _writePng(await _render(withBackground: true), 'assets/icon/app_icon.png');
    await _writePng(await _render(withBackground: false), 'assets/icon/app_icon_foreground.png');
    expect(File('assets/icon/app_icon.png').existsSync(), isTrue);
    expect(File('assets/icon/app_icon_foreground.png').existsSync(), isTrue);
  });
}
