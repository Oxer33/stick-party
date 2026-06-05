/// Drives the gameplay runner to completion for an all-bot button-masher round
/// and asserts the finish callback fires with a result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/app/widgets/mini_game_view.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';

void main() {
  testWidgets('runs an all-bot round to a finish', (WidgetTester tester) async {
    WinResult? finished;

    final PlayerManager players = PlayerManager(<PlayerSlot>[
      for (int i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 1200,
            child: MiniGameView(
              gameId: 'button_masher',
              players: players,
              difficulty: BotDifficulty.medium,
              seed: 42,
              showInputHints: false,
              onFinish: (WinResult r) => finished = r,
            ),
          ),
        ),
      ),
    );

    // First frame builds the game (LayoutBuilder measures the size).
    await tester.pump();

    // Drive the Ticker. dt is clamped to ~1/30s per frame, so each pump
    // advances sim time by at most ~33ms. The countdown (~2.8s) plus the
    // button-masher window (10s) need ~13s of sim time → pump generously.
    const Duration step = Duration(milliseconds: 33);
    const int maxFrames = 1200; // ~40s of sim time; ample headroom.
    int frames = 0;
    while (finished == null && frames < maxFrames) {
      await tester.pump(step);
      frames++;
    }

    expect(finished, isNotNull,
        reason: 'onFinish should fire after the round completes');
    expect(finished!.ranking.toSet(), <int>{0, 1, 2, 3});

    // Let the widget settle / dispose cleanly.
    await tester.pump();
  });

  testWidgets('builds and paints without throwing', (WidgetTester tester) async {
    final PlayerManager players = PlayerManager(<PlayerSlot>[
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 900,
            child: MiniGameView(
              gameId: 'sumo_smash',
              players: players,
              difficulty: BotDifficulty.easy,
              seed: 1,
              onFinish: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 33));

    // A CustomPaint exists (the game field) and no exception was thrown.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
