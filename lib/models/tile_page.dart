import '../l10n/app_strings.dart';

/// A named page on the tile board (like a Win8 start screen page).
class TilePage {
  final String id;
  String name;
  final int createdAt;

  TilePage({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory TilePage.fromMap(Map<String, dynamic> map) => TilePage(
        id: map['id'] as String,
        name: map['name'] as String? ?? AppStrings.current.t('页面'),
        createdAt: map['createdAt'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
      };
}
