/// Smoke test: the app boots to the home menu with a temp Hive-backed store.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:stick_party/app/app.dart';
import 'package:stick_party/app/providers.dart';
import 'package:stick_party/data/persistence.dart';

void main() {
  late Persistence persistence;

  setUpAll(() async {
    final Directory dir =
        Directory.systemTemp.createTempSync('stick_party_test');
    Hive.init(dir.path);
    final Box<dynamic> box = await Hive.openBox<dynamic>(Persistence.boxName);
    persistence = Persistence.withBox(box);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('boots to the STICK PARTY home menu', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          persistenceProvider.overrideWithValue(persistence),
        ],
        child: const StickPartyApp(),
      ),
    );
    // The home screen has a continuously-animating mesh background + title
    // shimmer, so pumpAndSettle would never settle. Pump a few fixed frames to
    // let the entrance animations and first build complete instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Title is split into two words on the home screen.
    expect(find.text('STICK'), findsOneWidget);
    expect(find.text('PARTY'), findsOneWidget);
    expect(find.text('QUICK PLAY'), findsOneWidget);
    expect(find.text('CUP'), findsOneWidget);
  });
}
