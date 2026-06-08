/// Stick Party entrypoint.
///
/// Initializes Hive-backed persistence, then runs the app inside a Riverpod
/// [ProviderScope] with the live [Persistence] injected. Persistence failure is
/// non-fatal: we fall back to a best-effort box, and only if even that is
/// impossible do we surface a friendly error screen instead of crashing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/result.dart';
import 'data/persistence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log framework errors instead of failing silently.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[STICK_PARTY] FlutterError: ${details.exceptionAsString()}');
  };

  // Lock to portrait: every minigame is designed for the tall (north/south)
  // screen, with the device held upright and shared around it.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  final Persistence? persistence = await _openPersistence();

  if (persistence == null) {
    runApp(const _StartupErrorApp());
    return;
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        persistenceProvider.overrideWithValue(persistence),
      ],
      child: const StickPartyApp(),
    ),
  );
}

/// Opens the persistence box, tolerating failure. Returns null only when no box
/// could be opened at all (extremely rare; e.g. no writable storage).
Future<Persistence?> _openPersistence() async {
  final Result<Persistence> result = await Persistence.init();
  final Persistence? primary = result.valueOrNull;
  if (primary != null) return primary;

  // Best-effort fallback: Hive may already be initialized from the failed
  // attempt; try opening the box directly.
  try {
    final Box<dynamic> box = await Hive.openBox<dynamic>(Persistence.boxName);
    return Persistence.withBox(box);
  } catch (e) {
    debugPrint('[STICK_PARTY] fallback box open failed: $e');
    return null;
  }
}

/// Minimal app shown only if persistence could not be opened at all.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0F13),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFFC93C), size: 48),
                SizedBox(height: 16),
                Text(
                  'Could not start storage.\nPlease restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFF4F5F7), fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
