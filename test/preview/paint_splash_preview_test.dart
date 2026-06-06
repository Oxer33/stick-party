import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/paint_splash/paint_splash.dart';

void main() {
  test('render paint splash preview', () async {
    const size = Size(900, 1400);
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: size,
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = PaintSplash()..init(ctx);
    for (var i = 0; i < 150; i++) {
      g.update(1 / 60);
    } // ~2.5s of splatting
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & size);
    g.render(canvas, size);
    final img = await rec
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('preview/paint_splash.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    expect(File('preview/paint_splash.png').existsSync(), isTrue);
  });
}
