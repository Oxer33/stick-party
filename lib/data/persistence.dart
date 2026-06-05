/// Hive-backed key/value store for all meta progress.
///
/// One RAW box named [boxName] holds only primitives, [List] and [Map] — NO
/// codegen, NO TypeAdapters. Every accessor is corruption-tolerant: a missing
/// key, a wrong runtime type or a thrown Hive error collapses to a documented
/// default instead of crashing the game loop (see core/result.dart rationale).
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/result.dart';

/// Thin, typed wrapper over a single Hive box.
///
/// Construct via [Persistence.init] in app code, or [Persistence.withBox] in
/// unit tests with an injected in-memory/temp [Box].
class Persistence {
  Persistence.withBox(this._box);

  /// Name of the single backing box. Public so tests can open the same box.
  static const String boxName = 'stick_party';

  final Box<dynamic> _box;

  /// Underlying box (escape hatch for advanced/diagnostic use). Read-only.
  Box<dynamic> get box => _box;

  /// Initialise Hive and open the shared box.
  ///
  /// Returns [Ok] with a ready [Persistence], or [Err] describing the failure.
  /// Never throws into the app: callers may fold the [Err] into a degraded
  /// (in-memory only is not possible here, so they surface the message).
  static Future<Result<Persistence>> init() async {
    try {
      await Hive.initFlutter();
      final Box<dynamic> box = await Hive.openBox<dynamic>(boxName);
      return Ok<Persistence>(Persistence.withBox(box));
    } catch (e) {
      debugPrint('[STICK_PARTY] Persistence.init failed: $e');
      return Err<Persistence>('Failed to open store "$boxName"', cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // int
  // ---------------------------------------------------------------------------

  /// Reads an int, falling back to [fallback] on miss/corruption, then clamps
  /// to [min].. [max] when provided.
  int getInt(String key, {int fallback = 0, int? min, int? max}) {
    int value = fallback;
    try {
      final dynamic raw = _box.get(key);
      if (raw is int) {
        value = raw;
      } else if (raw is num) {
        value = raw.toInt();
      }
    } catch (e) {
      debugPrint('[STICK_PARTY] getInt("$key") failed: $e');
      value = fallback;
    }
    return _clampInt(value, min, max);
  }

  /// Writes an int after clamping to [min].. [max] when provided.
  Future<void> putInt(String key, int value, {int? min, int? max}) =>
      _put(key, _clampInt(value, min, max));

  // ---------------------------------------------------------------------------
  // bool
  // ---------------------------------------------------------------------------

  bool getBool(String key, {bool fallback = false}) {
    try {
      final dynamic raw = _box.get(key);
      return raw is bool ? raw : fallback;
    } catch (e) {
      debugPrint('[STICK_PARTY] getBool("$key") failed: $e');
      return fallback;
    }
  }

  Future<void> putBool(String key, bool value) => _put(key, value);

  // ---------------------------------------------------------------------------
  // String
  // ---------------------------------------------------------------------------

  String getString(String key, {String fallback = ''}) {
    try {
      final dynamic raw = _box.get(key);
      return raw is String ? raw : fallback;
    } catch (e) {
      debugPrint('[STICK_PARTY] getString("$key") failed: $e');
      return fallback;
    }
  }

  Future<void> putString(String key, String value) => _put(key, value);

  // ---------------------------------------------------------------------------
  // List<String>
  // ---------------------------------------------------------------------------

  /// Reads a list of strings, skipping any non-string entries. Returns a fresh
  /// list (never the stored instance) so callers cannot mutate the box.
  List<String> getStringList(String key, {List<String>? fallback}) {
    final List<String> safeFallback =
        fallback == null ? <String>[] : List<String>.of(fallback);
    try {
      final dynamic raw = _box.get(key);
      if (raw is! List) return safeFallback;
      final List<String> out = <String>[];
      for (final dynamic e in raw) {
        if (e is String) out.add(e);
      }
      return out;
    } catch (e) {
      debugPrint('[STICK_PARTY] getStringList("$key") failed: $e');
      return safeFallback;
    }
  }

  /// Writes a defensive copy of [value] so later caller mutations cannot leak
  /// into the box.
  Future<void> putStringList(String key, List<String> value) =>
      _put(key, List<String>.of(value));

  // ---------------------------------------------------------------------------
  // Map<String, dynamic>
  // ---------------------------------------------------------------------------

  /// Reads a string-keyed map. Non-string keys are dropped. Returns a fresh map.
  Map<String, dynamic> getMap(String key, {Map<String, dynamic>? fallback}) {
    final Map<String, dynamic> safeFallback = fallback == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.of(fallback);
    try {
      final dynamic raw = _box.get(key);
      if (raw is! Map) return safeFallback;
      final Map<String, dynamic> out = <String, dynamic>{};
      raw.forEach((dynamic k, dynamic v) {
        if (k is String) out[k] = v;
      });
      return out;
    } catch (e) {
      debugPrint('[STICK_PARTY] getMap("$key") failed: $e');
      return safeFallback;
    }
  }

  /// Writes a defensive copy of [value].
  Future<void> putMap(String key, Map<String, dynamic> value) =>
      _put(key, Map<String, dynamic>.of(value));

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Removes a single key. Swallows store errors (best-effort cleanup).
  Future<void> remove(String key) async {
    try {
      await _box.delete(key);
    } catch (e) {
      debugPrint('[STICK_PARTY] remove("$key") failed: $e');
    }
  }

  /// Clears the whole box. Best-effort; never throws.
  Future<void> clear() async {
    try {
      await _box.clear();
    } catch (e) {
      debugPrint('[STICK_PARTY] clear failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  Future<void> _put(String key, Object? value) async {
    try {
      await _box.put(key, value);
    } catch (e) {
      // Persistence write failure is non-fatal: surface for diagnostics, keep
      // the game running with the in-memory state the caller already holds.
      debugPrint('[STICK_PARTY] put("$key") failed: $e');
    }
  }

  static int _clampInt(int value, int? min, int? max) {
    int out = value;
    if (min != null && out < min) out = min;
    if (max != null && out > max) out = max;
    return out;
  }
}
