import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/engine/player_manager.dart';

void main() {
  group('PlayerSlot', () {
    test('defaults assigns palette color and human/bot name', () {
      final human = PlayerSlot.defaults(0);
      expect(human.id, 0);
      expect(human.isBot, isFalse);
      expect(human.name, 'P1');

      final bot = PlayerSlot.defaults(2, isBot: true);
      expect(bot.isBot, isTrue);
      expect(bot.name, 'CPU 3');
      expect(bot.colorArgb, isNot(human.colorArgb));
    });

    test('copyWith returns a changed copy, original untouched', () {
      final a = PlayerSlot.defaults(0);
      final b = a.copyWith(name: 'Zoe', team: Team.a, skinId: 'neon');
      expect(b.name, 'Zoe');
      expect(b.team, Team.a);
      expect(b.skinId, 'neon');
      expect(a.name, 'P1'); // immutable
      expect(a.team, Team.none);
    });

    test('value equality and hashCode', () {
      final a = PlayerSlot.defaults(1);
      final b = PlayerSlot.defaults(1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(a.copyWith(isBot: true))));
    });
  });

  group('PlayerManager', () {
    test('rejects empty and >4 rosters', () {
      expect(() => PlayerManager(const []), throwsArgumentError);
      expect(
        () => PlayerManager([for (var i = 0; i < 5; i++) PlayerSlot.defaults(i)]),
        throwsArgumentError,
      );
    });

    test('quickDefault is one human + one bot', () {
      final pm = PlayerManager.quickDefault();
      expect(pm.count, 2);
      expect(pm.humanCount, 1);
      expect(pm.botCount, 1);
      expect(pm.mode, GameMode.ffa);
    });

    test('addSlot / removeLast clamp to 1..4 and stay immutable', () {
      var pm = PlayerManager([PlayerSlot.defaults(0)]);
      pm = pm.addSlot(isBot: true).addSlot().addSlot();
      expect(pm.count, 4);
      final capped = pm.addSlot(); // already 4
      expect(capped.count, 4);

      final shrunk = pm.removeLast().removeLast().removeLast();
      expect(shrunk.count, 1);
      expect(shrunk.removeLast().count, 1); // floor at 1
    });

    test('byId throws for unknown id', () {
      final pm = PlayerManager.quickDefault();
      expect(pm.byId(0).id, 0);
      expect(() => pm.byId(9), throwsArgumentError);
    });

    test('withMode and teamMembers', () {
      final pm = PlayerManager([
        PlayerSlot.defaults(0).copyWith(team: Team.a),
        PlayerSlot.defaults(1).copyWith(team: Team.b),
        PlayerSlot.defaults(2).copyWith(team: Team.a),
      ]).withMode(GameMode.team2v2);
      expect(pm.mode, GameMode.team2v2);
      expect(pm.teamMembers(Team.a).length, 2);
      expect(pm.teamMembers(Team.b).length, 1);
    });

    test('replace swaps one slot, out-of-range is a no-op', () {
      final pm = PlayerManager.quickDefault();
      final replaced = pm.replace(1, pm.slots[1].copyWith(name: 'Bot9'));
      expect(replaced.slots[1].name, 'Bot9');
      expect(pm.replace(9, pm.slots[0]).slots[1].name, isNot('Bot9'));
    });
  });
}
