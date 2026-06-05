import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';

void main() {
  group('BotProfile.forDifficulty tiers', () {
    final easy = BotProfile.forDifficulty(BotDifficulty.easy);
    final medium = BotProfile.forDifficulty(BotDifficulty.medium);
    final hard = BotProfile.forDifficulty(BotDifficulty.hard);

    test('reaction gets faster from easy to hard', () {
      // Easy is slower (larger delay) than medium, which is slower than hard.
      expect(easy.reactionSec, greaterThan(medium.reactionSec));
      expect(medium.reactionSec, greaterThan(hard.reactionSec));
    });

    test('error rate drops from easy to hard', () {
      expect(easy.errorRate, greaterThan(medium.errorRate));
      expect(medium.errorRate, greaterThan(hard.errorRate));
    });

    test('accuracy rises from easy to hard', () {
      expect(easy.accuracy, lessThan(medium.accuracy));
      expect(medium.accuracy, lessThan(hard.accuracy));
    });

    test('all tier fields stay within sane bounds', () {
      for (final p in [easy, medium, hard]) {
        expect(p.reactionSec, greaterThan(0));
        expect(p.errorRate, inInclusiveRange(0.0, 1.0));
        expect(p.accuracy, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('jitteredReaction', () {
    test('stays within +-25% of base for many draws (medium)', () {
      // Arrange
      final profile = BotProfile.forDifficulty(BotDifficulty.medium);
      final rng = SeededRng(123);
      final base = profile.reactionSec;
      final lo = base * 0.75;
      final hi = base * 1.25;

      // Act + Assert across many samples.
      var sawLow = false;
      var sawHigh = false;
      for (var i = 0; i < 500; i++) {
        final v = profile.jitteredReaction(rng);
        expect(v, inInclusiveRange(lo, hi));
        if (v < base) sawLow = true;
        if (v > base) sawHigh = true;
      }
      // Jitter is symmetric -> we should see both sides.
      expect(sawLow, isTrue);
      expect(sawHigh, isTrue);
    });

    test('clamps the result into [0.05, 2.0]', () {
      // Hard's base is small; even with max negative jitter we never go below
      // the 0.05 floor, and no tier exceeds the 2.0 ceiling.
      for (final d in BotDifficulty.values) {
        final profile = BotProfile.forDifficulty(d);
        final rng = SeededRng(d.index + 1);
        for (var i = 0; i < 300; i++) {
          final v = profile.jitteredReaction(rng);
          expect(v, inInclusiveRange(0.05, 2.0));
        }
      }
    });

    test('is deterministic for a fixed seed', () {
      final profile = BotProfile.forDifficulty(BotDifficulty.easy);
      final a = profile.jitteredReaction(SeededRng(9));
      final b = profile.jitteredReaction(SeededRng(9));
      expect(a, b);
    });
  });

  group('ReactionClock', () {
    test('is not ready before the delay elapses', () {
      final profile = BotProfile.forDifficulty(BotDifficulty.easy);
      final clock = ReactionClock(profile, SeededRng(3));
      expect(clock.ready, isFalse);
      // One tiny tick should not be enough (easy base ~0.55s).
      expect(clock.tick(0.001), isFalse);
      expect(clock.ready, isFalse);
    });

    test('fires exactly once after the delay, then stays fired', () {
      final profile = BotProfile.forDifficulty(BotDifficulty.medium);
      final clock = ReactionClock(profile, SeededRng(5));

      var fireCount = 0;
      // Drive 3 simulated seconds at 60fps; well past any clamped delay (<=2s).
      for (var i = 0; i < 180; i++) {
        if (clock.tick(1 / 60)) fireCount++;
      }
      expect(fireCount, 1);
      expect(clock.ready, isTrue);
    });

    test('arm re-arms for another single fire', () {
      final profile = BotProfile.forDifficulty(BotDifficulty.hard);
      final rng = SeededRng(11);
      final clock = ReactionClock(profile, rng);

      // First reaction.
      while (!clock.tick(1 / 60)) {}
      expect(clock.ready, isTrue);

      // Re-arm and confirm it fires again exactly once.
      clock.arm(profile, rng);
      expect(clock.ready, isFalse);

      var fireCount = 0;
      for (var i = 0; i < 180; i++) {
        if (clock.tick(1 / 60)) fireCount++;
      }
      expect(fireCount, 1);
      expect(clock.ready, isTrue);
    });

    test('tick returns false once already fired', () {
      final profile = BotProfile.forDifficulty(BotDifficulty.hard);
      final clock = ReactionClock(profile, SeededRng(2));
      // Big single tick guarantees it fires now.
      expect(clock.tick(5.0), isTrue);
      // Subsequent ticks do not re-fire.
      expect(clock.tick(5.0), isFalse);
      expect(clock.tick(5.0), isFalse);
    });
  });
}
