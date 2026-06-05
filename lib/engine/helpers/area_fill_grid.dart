import 'dart:ui';

/// Player id stored in a cell that nobody has painted yet.
const int kEmptyCell = -1;

/// A coarse grid of cells, each owned by a single player id, used for
/// territory-control / coverage scoring.
///
/// Coordinates handed to [paintCircle] are **normalized**: `(0,0)` is the
/// top-left of the grid and `(1,1)` is the bottom-right, independent of the
/// pixel size of the arena. The grid maps those onto `cols x rows` cells, so
/// the same painting logic works at any resolution. Later paints overwrite
/// earlier ones (last writer wins), which is exactly the "splash over a rival"
/// feel.
///
/// Used by Paint Splash.
class AreaFillGrid {
  /// Number of columns (cells across).
  final int cols;

  /// Number of rows (cells down).
  final int rows;

  /// Row-major ownership: `_cells[row * cols + col]`. [kEmptyCell] == unpainted.
  final List<int> _cells;

  /// Creates an all-empty grid.
  ///
  /// Throws [ArgumentError] when [cols] or [rows] is < 1.
  AreaFillGrid({required this.cols, required this.rows})
      : _cells = List<int>.filled(
          _validatedArea(cols, rows),
          kEmptyCell,
        );

  static int _validatedArea(int cols, int rows) {
    if (cols < 1) throw ArgumentError.value(cols, 'cols', 'must be >= 1');
    if (rows < 1) throw ArgumentError.value(rows, 'rows', 'must be >= 1');
    return cols * rows;
  }

  /// Total number of cells (`cols * rows`).
  int get totalCells => _cells.length;

  /// Owner id at ([col], [row]).
  ///
  /// Throws [RangeError] when the coordinate is outside the grid.
  int ownerAt(int col, int row) {
    _checkCoord(col, row);
    return _cells[row * cols + col];
  }

  void _checkCoord(int col, int row) {
    if (col < 0 || col >= cols) {
      throw RangeError.range(col, 0, cols - 1, 'col');
    }
    if (row < 0 || row >= rows) {
      throw RangeError.range(row, 0, rows - 1, 'row');
    }
  }

  /// Paint every cell whose center lies within [normRadius] of [normCenter]
  /// (both in normalized 0..1 grid space) with [playerId].
  ///
  /// The circle is measured in normalized space so it stays round regardless of
  /// the grid's aspect ratio. Cells fully outside the grid are skipped; a paint
  /// entirely off-grid simply does nothing. Throws [ArgumentError] for a
  /// negative or non-finite radius, or a non-finite center.
  void paintCircle(int playerId, Offset normCenter, double normRadius) {
    if (!normRadius.isFinite || normRadius < 0) {
      throw ArgumentError.value(
          normRadius, 'normRadius', 'must be >= 0 and finite');
    }
    if (!normCenter.dx.isFinite || !normCenter.dy.isFinite) {
      throw ArgumentError.value(normCenter, 'normCenter', 'must be finite');
    }
    if (normRadius == 0) return;

    final r2 = normRadius * normRadius;
    for (var row = 0; row < rows; row++) {
      // Cell centers sit at (i + 0.5) / count so they tile [0,1] evenly.
      final cy = (row + 0.5) / rows;
      final dy = cy - normCenter.dy;
      final dy2 = dy * dy;
      if (dy2 > r2) continue; // whole row is out of vertical reach
      for (var col = 0; col < cols; col++) {
        final cx = (col + 0.5) / cols;
        final dx = cx - normCenter.dx;
        if (dx * dx + dy2 <= r2) {
          _cells[row * cols + col] = playerId;
        }
      }
    }
  }

  /// Number of cells currently owned by [playerId].
  int coverageOf(int playerId) {
    var n = 0;
    for (final owner in _cells) {
      if (owner == playerId) n++;
    }
    return n;
  }

  /// Fraction of the whole grid owned by [playerId], in `[0, 1]`.
  double fractionOf(int playerId) =>
      totalCells == 0 ? 0 : coverageOf(playerId) / totalCells;

  /// Iterate every cell in row-major order, invoking [fn] with its column, row
  /// and current owner ([kEmptyCell] for unpainted). Intended for rendering.
  void forEachCell(void Function(int col, int row, int owner) fn) {
    for (var row = 0; row < rows; row++) {
      final base = row * cols;
      for (var col = 0; col < cols; col++) {
        fn(col, row, _cells[base + col]);
      }
    }
  }

  /// Reset every cell to empty for a fresh round.
  void clear() {
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = kEmptyCell;
    }
  }
}
