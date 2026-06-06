import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/reaction_duel/reaction_duel.dart';

void main() {
  test('render reaction duel preview', () async {
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
    final g = ReactionDuel()..init(ctx);

    // This game resolves fast. The GO signal fires, then the first strike lands
    // ≈ frame 141 for seed 3. By ~frame 156 the blinding flash + STRIKE banner
    // have settled, while the slash arcs are still bright and the losers are
    // airborne in mid-ragdoll over the dark ground — the clean, most
    // action-packed beat. We stop well before the KO linger ends so we capture
    // the strike, not the settled finish. (The on-field "STRIKE!"/"WAIT…" text
    // renders as a placeholder box in the fontless test renderer, so the capture
    // is timed past its fade.)
    for (var i = 0; i < 156 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & size);
    g.render(canvas, size);
    final img = await rec
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('preview/reaction_duel.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    expect(File('preview/reaction_duel.png').existsSync(), isTrue);
  });
}
