// One-off icon generator (NOT a real test). Run explicitly:
//   flutter test test/gen_icon.dart
// Renders the "Sumo shove" app icon to assets/icon/app_icon.png (full) and
// app_icon_foreground.png (figures-only, transparent, for the adaptive layer).
// Deleted after the source PNGs are produced.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _flame = Color(0xFFFB7234);
const _cyan = Color(0xFF22D3EE);
const _dark = Color(0xFF0C0A18);
const _white = Color(0xFFFFFFFF);

Paint _stroke(double w, Color col) => Paint()
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
    ..lineTo(-26, 4)
    ..lineTo(-40, 28); // wide back leg
  c.drawPath(body, _stroke(10, glow.withValues(alpha: 0.22))); // neon halo
  c.drawPath(body, _stroke(4.6, glow)); // core
  c.drawPath(body, _stroke(1.7, Color.lerp(glow, _white, 0.6)!.withValues(alpha: 0.9))); // hot highlight
  // Mawashi belt nub.
  final belt = Path()
    ..moveTo(2, -20)
    ..lineTo(-12, -12);
  c.drawPath(belt, _stroke(6, const Color(0xFFF3ECFF)));
  c.drawPath(belt, _stroke(2.4, glow.withValues(alpha: 0.9)));
  // Head: halo ring -> dark fill -> neon ring -> inner highlight.
  const hc = Offset(16, -56);
  const hr = 15.0;
  c.drawCircle(hc, hr, _stroke(9, glow.withValues(alpha: 0.22)));
  c.drawCircle(hc, hr, Paint()..color = _dark);
  c.drawCircle(hc, hr, _stroke(3.6, glow));
  c.drawCircle(hc, hr - 2.4, _stroke(1.4, Color.lerp(glow, _white, 0.7)!.withValues(alpha: 0.85)));
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
  final rayLong = _stroke(6, const Color(0xFFFFE9B8));
  final rayShort = _stroke(3.4, const Color(0xFFFFF6DE));
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
  sh(253, 662, 150);
  sh(771, 662, 150);
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
  const ctr = Offset(512, 656);
  Rect e(double rx, double ry) => Rect.fromCenter(center: ctr, width: rx * 2, height: ry * 2);
  Paint ring(double w, Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = col;
  c.drawOval(e(270, 62), Paint()..color = const Color(0x14FBBF24)); // clay platform
  c.drawOval(e(270, 62), ring(16, const Color(0x2EFBBF24))); // outer halo
  c.drawOval(e(270, 62), ring(6, const Color(0x80FBBF24))); // mid ring
  c.drawOval(e(270, 62), ring(2.6, const Color(0xCCFFE6B0))); // bright rim
  c.drawOval(e(202, 46), ring(3, const Color(0x40FB7234))); // inner raked ring
}

void _bg(Canvas c) {
  const r = Rect.fromLTWH(0, 0, 1024, 1024);
  c.drawRect(
    r,
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

void _icon(Canvas c, bool withBg) {
  if (withBg) _bg(c);
  _dohyo(c);
  _clashHalo(c);
  _footShadows(c, withBg ? 0.30 : 0.22);
  _wrestler(c, 397, 554, 3.6, 1, _flame);
  _wrestler(c, 627, 554, 3.6, -1, _cyan);
  _dust(c);
  _clashCore(c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate icon source PNGs', () async {
    Future<void> render(bool withBg, String path) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 1024, 1024));
      _icon(canvas, withBg);
      final img = await rec.endRecording().toImage(1024, 1024);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await render(true, 'assets/icon/app_icon.png');
    await render(false, 'assets/icon/app_icon_foreground.png');
  });
}
