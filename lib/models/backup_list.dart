/// A curated set of packages the user considers "backed up" / to keep track of.
class BackupList {
  final String id;
  String name;
  String description;
  final int createdAt;
  int updatedAt;
  List<String> packageNames;

  BackupList({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
    List<String>? packageNames,
  }) : packageNames = packageNames ?? <String>[];

  factory BackupList.fromMap(Map<String, dynamic> map) => BackupList(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        createdAt: map['createdAt'] as int? ?? 0,
        updatedAt: map['updatedAt'] as int? ?? 0,
        packageNames:
            (map['packageNames'] as List?)?.cast<String>() ?? <String>[],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'packageNames': packageNames,
      };
}
