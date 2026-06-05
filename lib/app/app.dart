/// Root application widget. Wires the party theme to the [GoRouter].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class StickPartyApp extends ConsumerStatefulWidget {
  const StickPartyApp({super.key});

  @override
  ConsumerState<StickPartyApp> createState() => _StickPartyAppState();
}

class _StickPartyAppState extends ConsumerState<StickPartyApp> {
  // Built once and held so navigation state survives rebuilds.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Stick Party',
      debugShowCheckedModeBanner: false,
      theme: stickPartyTheme(),
      routerConfig: _router,
    );
  }
}
