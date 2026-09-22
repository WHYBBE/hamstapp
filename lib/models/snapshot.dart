/// A single app recorded inside a snapshot.
class SnapshotEntry {
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final int lastUpdateTime;
  final int firstInstallTime;
  final bool isSystem;
  final int sizeBytes;

  const SnapshotEntry({
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.lastUpdateTime,
    required this.firstInstallTime,
    required this.isSystem,
    required this.sizeBytes,
  });

  factory SnapshotEntry.fromMap(Map<String, dynamic> map) => SnapshotEntry(
        packageName: map['packageName'] as String,
        appName: map['appName'] as String? ?? '',
        versionName: map['versionName'] as String? ?? '',
        versionCode: map['versionCode'] as int? ?? 0,
        lastUpdateTime: map['lastUpdateTime'] as int? ?? 0,
        firstInstallTime: map['firstInstallTime'] as int? ?? 0,
        isSystem: map['isSystem'] as bool? ?? false,
        sizeBytes: map['sizeBytes'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'versionName': versionName,
        'versionCode': versionCode,
        'lastUpdateTime': lastUpdateTime,
        'firstInstallTime': firstInstallTime,
        'isSystem': isSystem,
        'sizeBytes': sizeBytes,
      };
}

/// A point-in-time capture of the installed app list.
class Snapshot {
  final String id;
  String name;
  final int createdAt;
  final List<SnapshotEntry> entries;
  final String note;

  Snapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.entries,
    this.note = '',
  });

  DateTime get createdDate => DateTime.fromMillisecondsSinceEpoch(createdAt);

  factory Snapshot.fromMap(Map<String, dynamic> map) => Snapshot(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        createdAt: map['createdAt'] as int? ?? 0,
        note: map['note'] as String? ?? '',
        entries: (map['entries'] as List?)
                ?.map((e) => SnapshotEntry.fromMap(
                    (e as Map).cast<String, dynamic>()))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'note': note,
        'entries': entries.map((e) => e.toMap()).toList(),
      };
}
