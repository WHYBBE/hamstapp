/// A named page on the tile board (like a Win8 start screen page).
class TilePage {
  final String id;
  String name;
  final int createdAt;

  /// When true the page layout is locked and cannot be rearranged.
  bool locked;

  TilePage({
    required this.id,
    required this.name,
    required this.createdAt,
    this.locked = false,
  });

  factory TilePage.fromMap(Map<String, dynamic> map) => TilePage(
        id: map['id'] as String,
        name: map['name'] as String? ?? '页面',
        createdAt: map['createdAt'] as int? ?? 0,
        locked: map['locked'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'locked': locked,
      };
}
