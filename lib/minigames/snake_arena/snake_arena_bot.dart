// Bot steering AI for [SnakeArena], split into its own file (same game folder)
// so the gameplay module stays under the file-size budget. Pure logic: it reads
// the shared snake/food snapshots and two collision predicates the game owns,
// and mutates only the steered bot's heading. No rendering, no state of its own.
import 'dart:math' as math;

import '../../core/rng.dart';
import '../../engine/bots.dart';
import 'snake_arena_types.dart';

/// Drives one bot snake's turn decision. Constructed per tick with live
/// snapshots + the game's wall/body collision tests, so the AI stays in sync
/// with SUDDEN DEATH and growth without duplicating that logic.
class SnakeBot {
  final List<Snake> snakes;
  final List<Cell> food;
  final int cols;
  final int rows;
  final BotProfile profile;
  final SeededRng rng;

  /// Outside-the-(possibly-shrunk)-arena test (owned by the game).
  final bool Function(Cell) hitsWall;

  /// Body-collision test, ignoring [mover]'s about-to-move tail (owned by game).
  final bool Function(Cell cell, Snake mover) hitsBody;

  // Scoring weights (mirror the game's previous inline tuning).
  final double foodBias;
  final int lookahead;
  final int floodCap;
  final double spaceWeight;
  final double headOnPenalty;

  /// How hard this bot tries to CUT A RIVAL OFF: a bonus for a (safe) move that
  /// drops the bot's head onto a cell the rival is about to enter — a deliberate
  /// intercept. Scaled by [BotProfile.accuracy] at the call site, so hard bots
  /// set up cut-offs while easy bots barely bother (and just wander/self-crash).
  final double interceptWeight;

  SnakeBot({
    required this.snakes,
    required this.food,
    required this.cols,
    required this.rows,
    required this.profile,
    required this.rng,
    required this.hitsWall,
    required this.hitsBody,
    required this.foodBias,
    required this.lookahead,
    required this.floodCap,
    required this.spaceWeight,
    required this.headOnPenalty,
    this.interceptWeight = 0,
  });

  /// Choose [s]'s heading from straight + both turns (reverse is illegal): the
  /// highest-scoring legal one, or a random legal one on an error roll (a
  /// misjudgment, not suicide). Unchanged only when fully boxed in.
  void steer(Snake s) {
    final options = <Heading>[];
    var best = s.heading;
    var bestScore = -double.infinity;
    final target = _nearestFood(s.head);

    for (final i in const [0, 1, 3]) {
      // 0 = straight, 1 = clockwise, 3 = counter-clockwise (2 = reverse, skip).
      final h = Heading.values[(s.heading.index + i) % 4];
      if (_isBlocked(s, h)) continue;
      options.add(h);
      final score = _headingScore(s, h, target);
      if (score > bestScore) {
        bestScore = score;
        best = h;
      }
    }

    if (options.isEmpty) return; // boxed in — it will crash (correct).
    if (options.length > 1 && rng.chance(profile.errorRate)) {
      s.heading = rng.pick(options); // believable misjudgment
      return;
    }
    s.heading = best;
  }

  /// Higher is better: reachable open space after the step (dominant, so it
  /// avoids self-traps), plus a pull toward [target] when food bias fires, plus a
  /// CUT-OFF bonus for sliding the head across a rival's near path (a deliberate
  /// intercept), minus a penalty for a cell a rival head could also enter (a
  /// fatal head-on). The cut-off only fires when the move is itself safe, so a
  /// strong bot blocks rivals without throwing itself away.
  double _headingScore(Snake s, Heading h, Cell? target) {
    final next = s.head.plus(kStep[h]!);
    final space = _reachableSpace(next, s);
    var score = space.toDouble() * spaceWeight;
    if (target != null && rng.chance(foodBias)) {
      score += (cols + rows) - _manhattan(next, target);
    }
    // Only chase an intercept from a move that keeps real room to live — a strong
    // cut-off, not a suicide. (Boxed-in moves never earn the cut-off bonus.)
    if (interceptWeight > 0 && space > lookahead) {
      score += interceptWeight * _interceptBonus(next, s);
    }
    if (_rivalCanEnter(next, s)) score -= headOnPenalty;
    return score;
  }

  /// Cut-off signal for moving to [self]'s candidate cell [next]: 1.0 if [next]
  /// sits ON a rival's near-future LINE (the cell 2 ahead along the rival's
  /// heading — i.e. just in front of where it is about to be), so [self] lays a
  /// fresh body segment across the rival's path and the rival drives into it.
  /// Excludes the rival's IMMEDIATE next cell (that is a mutual head-on, handled
  /// by the head-on penalty), so this rewards a clean intercept, not a trade. 0
  /// when no rival's line passes through [next].
  double _interceptBonus(Cell next, Snake self) {
    var best = 0.0;
    for (final o in snakes) {
      if (!o.alive || identical(o, self)) continue;
      final oneAhead = o.head.plus(kStep[o.heading]!);
      final twoAhead = oneAhead.plus(kStep[o.heading]!);
      if (next == oneAhead) continue; // head-on trade, not a cut-off
      if (next == twoAhead) {
        // Closer rivals are juicier (the cut lands sooner) — scale by proximity.
        final d = _manhattan(self.head, o.head);
        final prox = (6 - d).clamp(0, 6) / 6.0;
        best = math.max(best, 0.5 + 0.5 * prox);
      }
    }
    return best;
  }

  /// True if some OTHER living snake's head is one cell from [cell] (it could
  /// move in on the same tick, killing both) — lets bots dodge head-on trades.
  bool _rivalCanEnter(Cell cell, Snake self) {
    for (final o in snakes) {
      if (!o.alive || identical(o, self)) continue;
      if (_manhattan(o.head, cell) == 1) return true;
    }
    return false;
  }

  /// Capped flood-fill: free cells reachable from [from] (bodies — except
  /// [mover]'s about-to-move tail — and walls are solid). Counts at most
  /// [floodCap], [lookahead] rings deep; 0 if [from] itself is solid.
  int _reachableSpace(Cell from, Snake mover) {
    if (hitsWall(from) || hitsBody(from, mover)) return 0;
    final seen = <Cell>{from};
    var frontier = <Cell>[from];
    var count = 1;
    for (var depth = 0; depth < lookahead && count < floodCap; depth++) {
      final next = <Cell>[];
      for (final cell in frontier) {
        for (final step in kStep.values) {
          final n = cell.plus(step);
          if (seen.contains(n)) continue;
          if (hitsWall(n) || hitsBody(n, mover)) continue;
          seen.add(n);
          next.add(n);
          if (++count >= floodCap) break;
        }
        if (count >= floodCap) break;
      }
      if (next.isEmpty) break;
      frontier = next;
    }
    return count;
  }

  Cell? _nearestFood(Cell from) {
    Cell? best;
    var bestDist = 1 << 30;
    for (final f in food) {
      final d = _manhattan(from, f);
      if (d < bestDist) {
        bestDist = d;
        best = f;
      }
    }
    return best;
  }

  bool _isBlocked(Snake s, Heading h) {
    final next = s.head.plus(kStep[h]!);
    return hitsWall(next) || hitsBody(next, s);
  }

  static int _manhattan(Cell a, Cell b) =>
      (a.col - b.col).abs() + (a.row - b.row).abs();
}
