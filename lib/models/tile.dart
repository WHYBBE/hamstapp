/// A single tile on the quick-launch board.
///
/// Tiles are independent entities keyed by [id], so the same app can appear
/// multiple times on the same page (and across pages) without restriction.
class Tile {
  final String id;
  String packageName;

  /// Which [TilePage] this tile lives on.
  String pageId;

  /// Grid position/size on the 6-column board. col/row of -1 means auto.
  int col;
  int row;
  int w;
  int h;

  /// Whether the app name is shown under the icon. When false the tile is
  /// icon-only (1x1 tiles already hide the label regardless of this).
  bool showLabel;

  Tile({
    required this.id,
    required this.packageName,
    required this.pageId,
    this.col = -1,
    this.row = -1,
    this.w = 1,
    this.h = 1,
    this.showLabel = true,
  });

  factory Tile.fromMap(Map<String, dynamic> map) => Tile(
        id: map['id'] as String,
        packageName: map['packageName'] as String? ?? '',
        pageId: map['pageId'] as String? ?? '',
        col: map['col'] as int? ?? -1,
        row: map['row'] as int? ?? -1,
        w: map['w'] as int? ?? 1,
        h: map['h'] as int? ?? 1,
        showLabel: map['showLabel'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'packageName': packageName,
        'pageId': pageId,
        'col': col,
        'row': row,
        'w': w,
        'h': h,
        'showLabel': showLabel,
      };
}
