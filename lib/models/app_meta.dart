/// User generated metadata for an installed package.
class AppMeta {
  String packageName;
  String reason;
  String note;
  bool favorite;
  bool pinned;
  List<String> categoryIds;
  int firstSeenAt;

  AppMeta({
    required this.packageName,
    this.reason = '',
    this.note = '',
    this.favorite = false,
    this.pinned = false,
    List<String>? categoryIds,
    int? firstSeenAt,
  })  : categoryIds = categoryIds ?? <String>[],
        firstSeenAt =
            firstSeenAt ?? DateTime.now().millisecondsSinceEpoch;

  factory AppMeta.fromMap(Map<String, dynamic> map) => AppMeta(
        packageName: map['packageName'] as String,
        reason: map['reason'] as String? ?? '',
        note: map['note'] as String? ?? '',
        favorite: map['favorite'] as bool? ?? false,
        pinned: map['pinned'] as bool? ?? false,
        categoryIds: (map['categoryIds'] as List?)?.cast<String>() ?? [],
        firstSeenAt: map['firstSeenAt'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'reason': reason,
        'note': note,
        'favorite': favorite,
        'pinned': pinned,
        'categoryIds': categoryIds,
        'firstSeenAt': firstSeenAt,
      };

  bool get hasUserData =>
      reason.isNotEmpty ||
      note.isNotEmpty ||
      favorite ||
      pinned ||
      categoryIds.isNotEmpty;
}
