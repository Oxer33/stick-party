import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/app/widgets/how_to_play_overlay.dart';
import 'package:stick_party/engine/registry.dart';
import 'package:stick_party/l10n/app_localizations.dart';

void main() {
  testWidgets('every registered minigame has a non-empty localized how-to (en)',
      (WidgetTester tester) async {
    final AppLocalizations l10n =
        await AppLocalizations.delegate.load(const Locale('en'));
    // The splash must explain EVERY game — a missing string would fall back to
    // '' and ship a blank card, so guard the whole registry.
    for (final String id in allMiniGameIds) {
      expect(localizedHowTo(l10n, id), isNotEmpty,
          reason: 'missing how-to line for "$id"');
    }
    expect(l10n.howto_tap_to_start, isNotEmpty);
    // An unknown id falls back to '' (the runner then omits the sentence).
    expect(localizedHowTo(l10n, 'not_a_game'), isEmpty);
  });

  testWidgets('how-to is localized per locale (it differs from en)',
      (WidgetTester tester) async {
    final AppLocalizations en =
        await AppLocalizations.delegate.load(const Locale('en'));
    final AppLocalizations it =
        await AppLocalizations.delegate.load(const Locale('it'));
    // Italian must actually be translated, not the English fallback.
    expect(localizedHowTo(it, 'sumo_smash'), isNotEmpty);
    expect(localizedHowTo(it, 'sumo_smash'),
        isNot(equals(localizedHowTo(en, 'sumo_smash'))));
  });

  testWidgets('HowToPlayOverlay renders for each control kind and a tap starts',
      (WidgetTester tester) async {
    for (final String hint in const <String>[
      'TAP',
      'HOLD',
      'MASH',
      'DRAG',
      'DRAG / HOLD'
    ]) {
      var started = false;
      final ValueNotifier<int> repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(children: <Widget>[
          Builder(
            builder: (BuildContext context) {
              final AppLocalizations l10n = AppLocalizations.of(context);
              return HowToPlayOverlay(
                gameName: 'Test Game',
                howTo: localizedHowTo(l10n, 'sumo_smash'),
                tapToStart: l10n.howto_tap_to_start,
                inputHint: hint,
                onStart: () => started = true,
                repaint: repaint,
              );
            },
          ),
        ]),
      ));
      expect(find.byType(HowToPlayOverlay), findsOneWidget, reason: hint);
      await tester.tap(find.byType(HowToPlayOverlay));
      expect(started, isTrue, reason: 'tap should start ($hint)');
    }
  });
}
