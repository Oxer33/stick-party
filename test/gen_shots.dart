// Visual-QA snapshot tool (NOT part of the auto suite — no `_test` suffix, so
// `flutter test` with no args skips it). Run on demand:
//   flutter test test/gen_shots.dart
// Renders a mid-action frame of every registered minigame (all-bot, 4p where
// allowed) to build/shots/<id>.png at a device-like portrait aspect. Output dir
// build/ is gitignored. Use it to eyeball "spectacular in every game".
//
// loadAppFonts() loads the bundled + Material/Cupertino icon fonts. CAVEAT: the
// app draws HUD/score text in the SYSTEM DEFAULT font (none bundled), which the
// headless test engine renders as filled boxes — so GRAPHICS and LAYOUT in these
// shots are faithful, but plain text labels still appear as boxes (not a defect;
// on a real device they are crisp text).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render minigame snapshots', () async {
    await loadAppFonts(); // real glyphs so text labels are faithful, not boxes
    const double w = 720;
    const double h = 1600;
    Directory('build/shots').createSync(recursive: true);

    for (final id in allMiniGameIds) {
      final meta = createMiniGame(id).meta;
      final count = 4.clamp(meta.minPlayers, meta.maxPlayers);
      final players = <PlayerSlot>[
        for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true),
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(w, h),
        rng: SeededRng(7),
        zones: ZoneLayout.forPlayers(count),
      );
      final g = createMiniGame(id)..init(ctx);
      for (var f = 0; f < 240 && g.status != MiniGameStatus.finished; f++) {
        g.update(1 / 60);
      }
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      // Fallback base fill so any unpainted area still reads on brand indigo.
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF0C0A18));
      g.render(canvas, const Size(w, h));
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/shots/$id.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
