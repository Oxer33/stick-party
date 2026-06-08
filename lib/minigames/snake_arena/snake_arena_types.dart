// Small grid value types for [SnakeArena], split into their own file (same game
// folder) so the gameplay module stays under the file-size budget. These are
// leaf data types with no dependency on the game logic.
import 'dart:ui';

import '../../engine/bots.dart';

/// Four cardinal headings on the grid, ordered clockwise so a right turn is
/// `(index + 1) % 4` and a left turn is `(index + 3) % 4`.
enum Heading { up, right, down, left }

/// Unit step (in cells) for each heading.
const Map<Heading, Cell> kStep = {
  Heading.up: Cell(0, -1),
  Heading.right: Cell(1, 0),
  Heading.down: Cell(0, 1),
  Heading.left: Cell(-1, 0),
};

/// Immutable integer grid coordinate.
class Cell {
  final int col;
  final int row;
  const Cell(this.col, this.row);

  Cell plus(Cell o) => Cell(col + o.col, row + o.row);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.col == col && other.row == row;

  @override
  int get hashCode => col * 31337 + row;
}

/// One player's snake: an ordered body (head first) on the shared grid.
/// Mutable round-scoped state (allowed for the duration of one round).
class Snake {
  final int playerId;
  final Color color;
  final List<Cell> body; // index 0 == head
  Heading heading;
  bool alive = true;
  int pendingGrowth = 0; // segments still to grow (skips tail removal)
  int score = 0; // pellets eaten (HUD readout)

  // Bot steering only.
  final ReactionClock? clock;

  Snake({
    required this.playerId,
    required this.color,
    required Cell head,
    required this.heading,
    this.clock,
  }) : body = [head];

  Cell get head => body.first;
  int get length => body.length;
}
