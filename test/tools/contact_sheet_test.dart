// Composes the 15 minigame preview PNGs into one labelled contact sheet
// (preview/_contact.png) so all games can be reviewed at a glance.
//
//   flutter test test/tools/contact_sheet_test.dart
//
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _ids = <String>[
  'sumo_smash', 'bumper_balls', 'one_touch_soccer', 'tank_duel', 'archer_pop',
  'chicken_jump', 'falling_dodge', 'tap_sprint', 'tug_of_war', 'button_masher',
  'reaction_duel', 'snake_arena', 'paint_splash', 'catch_the_star',
  'color_memory',
];

Future<ui.Image> _load(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  test('build contact sheet', () async {
    const cols = 5, rows = 3;
    const cw = 240.0, ch = 384.0, pad = 8.0, label = 26.0;
    final sheetW = cols * cw + (cols + 1) * pad;
    final sheetH = rows * (ch + label) + (rows + 1) * pad;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, sheetW, sheetH));
    canvas.drawRect(Rect.fromLTWH(0, 0, sheetW, sheetH),
        Paint()..color = const Color(0xFF0C0A18));

    for (var i = 0; i < _ids.length; i++) {
      final col = i % cols, row = i ~/ cols;
      final x = pad + col * (cw + pad);
      final y = pad + row * (ch + label + pad);
      final f = File('preview/${_ids[i]}.png');
      if (f.existsSync()) {
        final img = await _load(f.path);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(x, y, cw, ch),
          Paint(),
        );
      }
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
          fontSize: 16,
          textAlign: TextAlign.center,
          fontWeight: FontWeight.w700))
        ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
        ..addText('${i + 1}. ${_ids[i]}');
      final p = pb.build()..layout(ui.ParagraphConstraints(width: cw));
      canvas.drawParagraph(p, Offset(x, y + ch + 4));
    }

    final img = await rec.endRecording().toImage(sheetW.toInt(), sheetH.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('preview/_contact.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    expect(File('preview/_contact.png').existsSync(), isTrue);
  });
}
