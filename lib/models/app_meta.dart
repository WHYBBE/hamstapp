/// User generated metadata for an installed package.
class AppMeta {
  String packageName;
  String reason;
  String note;
  bool favorite;
  bool pinned;
  List<String> categoryIds;
  int firstSeenAt;

  /// Last known display name, kept even after the app is uninstalled.
  String lastKnownName;

  /// Why the user removed the app.
  String uninstallReason;

  /// Timestamp when the uninstall was detected; 0 means still installed.
  int uninstalledAt;

  /// Last time the app was launched from this app; 0 means never.
  int lastLaunchedAt;

  /// Which tile page this pinned app lives on ('' = default/first page).
  String tilePageId;

  AppMeta({
    required this.packageName,
    this.reason = '',
    this.note = '',
    this.favorite = false,
    this.pinned = false,
    List<String>? categoryIds,
    int? firstSeenAt,
    this.lastKnownName = '',
    this.uninstallReason = '',
    this.uninstalledAt = 0,
    this.lastLaunchedAt = 0,
    this.tilePageId = '',
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
        lastKnownName: map['lastKnownName'] as String? ?? '',
        uninstallReason: map['uninstallReason'] as String? ?? '',
        uninstalledAt: map['uninstalledAt'] as int? ?? 0,
        lastLaunchedAt: map['lastLaunchedAt'] as int? ?? 0,
        tilePageId: map['tilePageId'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'reason': reason,
        'note': note,
        'favorite': favorite,
        'pinned': pinned,
        'categoryIds': categoryIds,
        'firstSeenAt': firstSeenAt,
        'lastKnownName': lastKnownName,
        'uninstallReason': uninstallReason,
        'uninstalledAt': uninstalledAt,
        'lastLaunchedAt': lastLaunchedAt,
        'tilePageId': tilePageId,
      };

  bool get isUninstalled => uninstalledAt != 0;

  bool get hasUserData =>
      reason.isNotEmpty ||
      note.isNotEmpty ||
      favorite ||
      pinned ||
      categoryIds.isNotEmpty ||
      uninstallReason.isNotEmpty;
}
