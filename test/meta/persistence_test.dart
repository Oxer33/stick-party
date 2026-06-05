import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:stick_party/data/persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<dynamic> box;
  late Persistence p;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('stick_party_persist_');
    Hive.init(dir.path);
  });

  setUp(() async {
    box = await Hive.openBox<dynamic>(
        'persist_test_${DateTime.now().microsecondsSinceEpoch}');
    p = Persistence.withBox(box);
  });

  tearDown(() async {
    await box.clear();
    await box.close();
  });

  group('int', () {
    test('putInt/getInt round-trips', () async {
      await p.putInt('coins', 42);
      expect(p.getInt('coins'), 42);
    });

    test('getInt clamps to min/max on read', () async {
      await p.putInt('v', 500); // stored as-is (no clamp args here)
      expect(p.getInt('v', min: 0, max: 100), 100);
      await p.putInt('w', -50);
      expect(p.getInt('w', min: 0, max: 100), 0);
    });

    test('putInt clamps to min/max on write', () async {
      await p.putInt('cap', 9999, min: 0, max: 100);
      expect(p.getInt('cap'), 100);
      await p.putInt('floor', -5, min: 0, max: 100);
      expect(p.getInt('floor'), 0);
    });

    test('missing int key returns the fallback', () {
      expect(p.getInt('nope', fallback: 7), 7);
      expect(p.getInt('nope'), 0);
    });

    test('a stored num coerces to int', () async {
      await box.put('numv', 3.9);
      expect(p.getInt('numv'), 3); // toInt truncates
    });
  });

  group('bool', () {
    test('putBool/getBool round-trips', () async {
      await p.putBool('flag', true);
      expect(p.getBool('flag'), isTrue);
      await p.putBool('flag', false);
      expect(p.getBool('flag'), isFalse);
    });

    test('missing bool key returns fallback', () {
      expect(p.getBool('missing', fallback: true), isTrue);
      expect(p.getBool('missing'), isFalse);
    });

    test('type mismatch returns fallback (corruption tolerant)', () async {
      await box.put('flag', 'not a bool');
      expect(p.getBool('flag', fallback: true), isTrue);
    });
  });

  group('String', () {
    test('putString/getString round-trips', () async {
      await p.putString('name', 'Stick');
      expect(p.getString('name'), 'Stick');
    });

    test('missing string returns fallback', () {
      expect(p.getString('missing', fallback: 'x'), 'x');
      expect(p.getString('missing'), '');
    });

    test('non-string stored value returns fallback', () async {
      await box.put('name', 123);
      expect(p.getString('name', fallback: 'fb'), 'fb');
    });
  });

  group('List<String>', () {
    test('putStringList/getStringList round-trips', () async {
      await p.putStringList('owned', ['a', 'b', 'c']);
      expect(p.getStringList('owned'), ['a', 'b', 'c']);
    });

    test('non-string entries are skipped', () async {
      await box.put('mixed', <dynamic>['a', 1, 'b', true]);
      expect(p.getStringList('mixed'), ['a', 'b']);
    });

    test('a non-list stored value returns the fallback', () async {
      await box.put('owned', 'not a list');
      expect(p.getStringList('owned', fallback: ['fb']), ['fb']);
    });

    test('returns a fresh list (mutating it does not affect the box)', () async {
      await p.putStringList('owned', ['a']);
      final got = p.getStringList('owned');
      got.add('z');
      expect(p.getStringList('owned'), ['a']);
    });
  });

  group('Map<String, dynamic>', () {
    test('putMap/getMap round-trips', () async {
      await p.putMap('records', {'g1': 10, 'g2': 20});
      final got = p.getMap('records');
      expect(got['g1'], 10);
      expect(got['g2'], 20);
    });

    test('non-string keys are dropped', () async {
      await box.put('m', <dynamic, dynamic>{'ok': 1, 2: 'dropped'});
      final got = p.getMap('m');
      expect(got.containsKey('ok'), isTrue);
      expect(got.length, 1);
    });

    test('a non-map stored value returns fallback', () async {
      await box.put('records', 42);
      expect(p.getMap('records', fallback: {'fb': 1}), {'fb': 1});
    });
  });

  group('maintenance', () {
    test('remove deletes a single key', () async {
      await p.putInt('k', 5);
      await p.remove('k');
      expect(p.getInt('k', fallback: -1), -1);
    });

    test('clear empties the box', () async {
      await p.putInt('a', 1);
      await p.putString('b', 'x');
      await p.clear();
      expect(p.getInt('a', fallback: -1), -1);
      expect(p.getString('b', fallback: 'gone'), 'gone');
    });

    test('box getter exposes the backing box', () {
      expect(p.box, same(box));
    });
  });
}
