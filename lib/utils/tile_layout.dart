/// Number of grid columns per row on the tile board (one row = 6 cells).
const int kTileCols = 6;

/// Allowed tile size range (1..kTileCols wide, 1..kTileMaxH tall).
const int kTileMaxH = 6;

/// Desired placement of a tile. col/row < 0 means "auto place".
class TileSpec {
  final String id;
  final int w;
  final int h;
  final int col;
  final int row;

  const TileSpec({
    required this.id,
    this.w = 1,
    this.h = 1,
    this.col = -1,
    this.row = -1,
  });
}

class TilePlacement {
  final String id;
  final int col;
  final int row;
  final int w;
  final int h;

  const TilePlacement(this.id, this.col, this.row, this.w, this.h);
}

class TileLayoutResult {
  final Map<String, TilePlacement> placements;
  final int rows;

  const TileLayoutResult(this.placements, this.rows);
}

/// Resolve a collision-free layout for [specs].
///
/// Stored positions that fit are honoured first; the rest are packed into the
/// first free cells in the given order. When [ignoreStored] is true every tile
/// is packed sequentially (used by the sort/reflow actions).
TileLayoutResult resolveTileLayout(
  List<TileSpec> specs, {
  int cols = kTileCols,
  bool ignoreStored = false,
}) {
  final occupied = <int>{};
  int key(int c, int r) => r * cols + c;

  bool fits(int c, int r, int w, int h) {
    if (c < 0 || r < 0 || c + w > cols) return false;
    for (var x = c; x < c + w; x++) {
      for (var y = r; y < r + h; y++) {
        if (occupied.contains(key(x, y))) return false;
      }
    }
    return true;
  }

  void occupy(int c, int r, int w, int h) {
    for (var x = c; x < c + w; x++) {
      for (var y = r; y < r + h; y++) {
        occupied.add(key(x, y));
      }
    }
  }

  final result = <String, TilePlacement>{};

  if (!ignoreStored) {
    for (final s in specs) {
      if (s.col >= 0 && s.row >= 0 && fits(s.col, s.row, s.w, s.h)) {
        occupy(s.col, s.row, s.w, s.h);
        result[s.id] = TilePlacement(s.id, s.col, s.row, s.w, s.h);
      }
    }
  }

  for (final s in specs) {
    if (result.containsKey(s.id)) continue;
    final w = s.w.clamp(1, cols);
    final h = s.h.clamp(1, kTileMaxH);
    var placed = false;
    for (var r = 0; !placed; r++) {
      for (var c = 0; c + w <= cols; c++) {
        if (fits(c, r, w, h)) {
          occupy(c, r, w, h);
          result[s.id] = TilePlacement(s.id, c, r, w, h);
          placed = true;
          break;
        }
      }
    }
  }

  var rows = 0;
  for (final p in result.values) {
    if (p.row + p.h > rows) rows = p.row + p.h;
  }
  return TileLayoutResult(result, rows);
}

/// Find a free spot for a tile of [w]x[h] as close as possible to
/// ([wantCol], [wantRow]), treating [others] as already placed.
TilePlacement resolveMove(
  List<TileSpec> others,
  String id,
  int wantCol,
  int wantRow,
  int w,
  int h, {
  int cols = kTileCols,
}) {
  final occupied = <int>{};
  int key(int c, int r) => r * cols + c;
  final base = resolveTileLayout(others, cols: cols);
  for (final p in base.placements.values) {
    for (var x = p.col; x < p.col + p.w; x++) {
      for (var y = p.row; y < p.row + p.h; y++) {
        occupied.add(key(x, y));
      }
    }
  }

  bool fits(int c, int r) {
    if (c < 0 || r < 0 || c + w > cols) return false;
    for (var x = c; x < c + w; x++) {
      for (var y = r; y < r + h; y++) {
        if (occupied.contains(key(x, y))) return false;
      }
    }
    return true;
  }

  final cc = wantCol.clamp(0, cols - w);
  final rr = wantRow < 0 ? 0 : wantRow;
  if (fits(cc, rr)) return TilePlacement(id, cc, rr, w, h);

  // scan forwards from the requested row for the first free spot
  for (var r = rr; r < rr + 200; r++) {
    for (var c = 0; c + w <= cols; c++) {
      if (fits(c, r)) return TilePlacement(id, c, r, w, h);
    }
  }
  return TilePlacement(id, 0, 0, w, h);
}
