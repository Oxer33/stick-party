import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/meta/daily.dart';

void main() {
  group('DailyService.generateForDay', () {
    test('produces exactly kDailyMissionCount (3) missions', () {
      final missions = DailyService.generateForDay('2026-06-05');
      expect(missions.length, kDailyMissionCount);
      expect(kDailyMissionCount, 3);
    });

    test('is deterministic: same ISO yields identical missions', () {
      final a = DailyService.generateForDay('2026-06-05');
      final b = DailyService.generateForDay('2026-06-05');
      expect(a, b);
    });

    test('different days generally yield different mission sets', () {
      final a = DailyService.generateForDay('2026-06-05');
      final b = DailyService.generateForDay('2026-12-25');
      // At least the ids differ (they embed the ISO date).
      expect(a.map((m) => m.id).toList(),
          isNot(equals(b.map((m) => m.id).toList())));
    });

    test('fresh missions start at zero progress and uncompleted', () {
      final missions = DailyService.generateForDay('2026-06-05');
      for (final m in missions) {
        expect(m.progress, 0);
        expect(m.completed, isFalse);
        expect(m.claimed, isFalse);
        expect(m.target, greaterThan(0));
        expect(m.id, startsWith('2026-06-05#'));
      }
    });

    test('generated mission types are distinct (shuffled from the pool)', () {
      final missions = DailyService.generateForDay('2026-06-05');
      final types = missions.map((m) => m.type).toSet();
      expect(types.length, missions.length);
    });
  });

  group('DailyService.applyEvent', () {
    test('advances matching missions and flags completion at target', () {
      // Build a known mission of a specific type.
      final missions = DailyService.generateForDay('2026-06-05');
      final target = missions.first;
      // Advance that type to exactly its target.
      final updated =
          DailyService.applyEvent(missions, target.type, target.target);
      final after = updated.firstWhere((m) => m.id == target.id);
      expect(after.progress, target.target);
      expect(after.completed, isTrue);
    });

    test('partial progress does not complete and clamps at target', () {
      final missions = [
        const DailyMission(
          id: 'm1',
          type: DailyMissionType.playRounds,
          target: 5,
          progress: 0,
          rewardCoins: 10,
          completed: false,
          claimed: false,
        ),
      ];
      final step1 =
          DailyService.applyEvent(missions, DailyMissionType.playRounds, 2);
      expect(step1.first.progress, 2);
      expect(step1.first.completed, isFalse);
      // Overshoot is clamped to the target.
      final step2 =
          DailyService.applyEvent(step1, DailyMissionType.playRounds, 99);
      expect(step2.first.progress, 5);
      expect(step2.first.completed, isTrue);
    });

    test('returns a new list (immutable) and leaves the original alone', () {
      final missions = [
        const DailyMission(
          id: 'm1',
          type: DailyMissionType.winRounds,
          target: 3,
          progress: 0,
          rewardCoins: 20,
          completed: false,
          claimed: false,
        ),
      ];
      final updated =
          DailyService.applyEvent(missions, DailyMissionType.winRounds, 1);
      expect(identical(missions, updated), isFalse);
      expect(missions.first.progress, 0); // original unchanged
      expect(updated.first.progress, 1);
    });

    test('does not touch missions of other types', () {
      final missions = [
        const DailyMission(
          id: 'm1',
          type: DailyMissionType.winCup,
          target: 1,
          progress: 0,
          rewardCoins: 50,
          completed: false,
          claimed: false,
        ),
      ];
      final updated =
          DailyService.applyEvent(missions, DailyMissionType.playRounds, 5);
      expect(updated.first.progress, 0);
    });

    test('non-positive increment is a no-op (returns input)', () {
      final missions = DailyService.generateForDay('2026-06-05');
      expect(
          DailyService.applyEvent(missions, missions.first.type, 0), missions);
      expect(
          DailyService.applyEvent(missions, missions.first.type, -3), missions);
    });

    test('an already-completed mission is not advanced further', () {
      final missions = [
        const DailyMission(
          id: 'm1',
          type: DailyMissionType.playRounds,
          target: 2,
          progress: 2,
          rewardCoins: 10,
          completed: true,
          claimed: false,
        ),
      ];
      final updated =
          DailyService.applyEvent(missions, DailyMissionType.playRounds, 5);
      expect(updated.first.progress, 2);
    });
  });

  group('DailyService.computeLoginBonus', () {
    test('cycles over a 7-day window', () {
      expect(kLoginBonusCycleDays, 7);
      expect(DailyService.loginCycle.length, 7);
      // dayIndex == streakIndex % 7
      for (var i = 0; i < 14; i++) {
        final res = DailyService.computeLoginBonus(
          '', // never claimed
          i,
          todayIso: '2026-06-05',
        );
        expect(res.dayIndex, i % 7);
        expect(res.reward, DailyService.loginCycle[i % 7]);
      }
    });

    test('flags alreadyClaimedToday when last day == today', () {
      final claimed = DailyService.computeLoginBonus(
        '2026-06-05',
        2,
        todayIso: '2026-06-05',
      );
      expect(claimed.alreadyClaimedToday, isTrue);

      final fresh = DailyService.computeLoginBonus(
        '2026-06-04',
        2,
        todayIso: '2026-06-05',
      );
      expect(fresh.alreadyClaimedToday, isFalse);
    });

    test('negative streak index is treated as day 0', () {
      final res = DailyService.computeLoginBonus('', -5, todayIso: '2026-06-05');
      expect(res.dayIndex, 0);
      expect(res.reward, DailyService.loginCycle[0]);
    });

    test('cycle has cosmetic-token days and coin days', () {
      final kinds = DailyService.loginCycle.map((r) => r.kind).toSet();
      expect(kinds, contains(LoginRewardKind.coins));
      expect(kinds, contains(LoginRewardKind.cosmeticToken));
    });
  });

  group('DailyService.isoForDate', () {
    test('formats as zero-padded YYYY-MM-DD', () {
      expect(DailyService.isoForDate(DateTime(2026, 1, 3)), '2026-01-03');
      expect(DailyService.isoForDate(DateTime(2026, 12, 25)), '2026-12-25');
    });
  });

  group('DailyMission value type', () {
    const base = DailyMission(
      id: 'm1',
      type: DailyMissionType.playRounds,
      target: 5,
      progress: 2,
      rewardCoins: 10,
      completed: false,
      claimed: false,
    );

    test('progressFraction is progress/target clamped to [0,1]', () {
      expect(base.progressFraction, closeTo(0.4, 1e-9));
      expect(base.copyWith(progress: 99).progressFraction, 1.0);
    });

    test('copyWith overrides only the given fields', () {
      final c = base.copyWith(progress: 4, completed: true, claimed: true);
      expect(c.progress, 4);
      expect(c.completed, isTrue);
      expect(c.claimed, isTrue);
      // Untouched fields preserved.
      expect(c.id, 'm1');
      expect(c.target, 5);
      expect(c.rewardCoins, 10);
    });

    test('toMap / fromMap round-trips', () {
      final map = base.toMap();
      expect(map['id'], 'm1');
      expect(map['type'], 'playRounds');
      final back = DailyMission.fromMap(map);
      expect(back, base);
    });

    test('fromMap clamps corrupt values to safe ranges', () {
      // Numeric fields are clamped; missing bools/type fall back. (The store
      // only coerces nums and tolerates missing keys, per daily.dart.)
      final back = DailyMission.fromMap(<dynamic, dynamic>{
        'id': 'x',
        'type': 'not_a_type', // -> playRounds fallback
        'target': -3, // -> 1
        'progress': 99, // -> clamped to target (1)
        'rewardCoins': -5, // -> 0
        // 'completed' and 'claimed' omitted -> false
      });
      expect(back.target, 1);
      expect(back.progress, 1);
      expect(back.rewardCoins, 0);
      expect(back.type, DailyMissionType.playRounds); // fallback
      expect(back.completed, isFalse);
      expect(back.claimed, isFalse);
    });

    test('fromMap defaults a fully-empty map', () {
      final back = DailyMission.fromMap(const <dynamic, dynamic>{});
      expect(back.id, '');
      expect(back.target, 1);
      expect(back.progress, 0);
      expect(back.rewardCoins, 0);
      expect(back.type, DailyMissionType.playRounds);
      expect(back.completed, isFalse);
      expect(back.claimed, isFalse);
    });

    test('equality and hashCode compare all fields', () {
      final same = base.copyWith();
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(base == base.copyWith(progress: 3), isFalse);
    });
  });

  group('LoginReward / LoginBonusResult value types', () {
    test('LoginReward equality, hashCode, toString', () {
      const a = LoginReward(kind: LoginRewardKind.coins, amount: 10);
      const b = LoginReward(kind: LoginRewardKind.coins, amount: 10);
      const c = LoginReward(kind: LoginRewardKind.cosmeticToken, amount: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('coins'));
    });

    test('LoginBonusResult equality and hashCode', () {
      const reward = LoginReward(kind: LoginRewardKind.coins, amount: 10);
      const a = LoginBonusResult(
          dayIndex: 0, reward: reward, alreadyClaimedToday: false);
      const b = LoginBonusResult(
          dayIndex: 0, reward: reward, alreadyClaimedToday: false);
      const c = LoginBonusResult(
          dayIndex: 1, reward: reward, alreadyClaimedToday: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
