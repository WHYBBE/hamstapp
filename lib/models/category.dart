class AppCategory {
  final String id;
  String name;
  int colorValue;
  String emoji;

  AppCategory({
    required this.id,
    required this.name,
    this.colorValue = 0xFF6C8CFF,
    this.emoji = '📦',
  });

  factory AppCategory.fromMap(Map<String, dynamic> map) => AppCategory(
        id: map['id'] as String,
        name: map['name'] as String? ?? '未命名',
        colorValue: map['colorValue'] as int? ?? 0xFF6C8CFF,
        emoji: map['emoji'] as String? ?? '📦',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'emoji': emoji,
      };
}
