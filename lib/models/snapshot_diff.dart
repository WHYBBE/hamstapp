import 'snapshot.dart';

enum DiffType { added, removed, updated, unchanged }

class DiffItem {
  final DiffType type;
  final String packageName;
  final String appName;
  final String fromVersion;
  final String toVersion;
  final bool isSystem;
  final int sizeBytes;

  const DiffItem({
    required this.type,
    required this.packageName,
    required this.appName,
    this.fromVersion = '',
    this.toVersion = '',
    this.isSystem = false,
    this.sizeBytes = 0,
  });
}

class SnapshotDiff {
  final List<DiffItem> added;
  final List<DiffItem> removed;
  final List<DiffItem> updated;
  final List<DiffItem> unchanged;

  const SnapshotDiff({
    required this.added,
    required this.removed,
    required this.updated,
    required this.unchanged,
  });

  int get changedCount => added.length + removed.length + updated.length;

  static SnapshotDiff between(Snapshot older, Snapshot newer) {
    final oldMap = {for (final e in older.entries) e.packageName: e};
    final newMap = {for (final e in newer.entries) e.packageName: e};

    final added = <DiffItem>[];
    final removed = <DiffItem>[];
    final updated = <DiffItem>[];
    final unchanged = <DiffItem>[];

    for (final entry in newMap.values) {
      final prev = oldMap[entry.packageName];
      if (prev == null) {
        added.add(DiffItem(
          type: DiffType.added,
          packageName: entry.packageName,
          appName: entry.appName,
          toVersion: entry.versionName,
          isSystem: entry.isSystem,
          sizeBytes: entry.sizeBytes,
        ));
      } else if (prev.versionCode != entry.versionCode ||
          prev.versionName != entry.versionName) {
        updated.add(DiffItem(
          type: DiffType.updated,
          packageName: entry.packageName,
          appName: entry.appName,
          fromVersion: prev.versionName,
          toVersion: entry.versionName,
          isSystem: entry.isSystem,
          sizeBytes: entry.sizeBytes,
        ));
      } else {
        unchanged.add(DiffItem(
          type: DiffType.unchanged,
          packageName: entry.packageName,
          appName: entry.appName,
          toVersion: entry.versionName,
          isSystem: entry.isSystem,
          sizeBytes: entry.sizeBytes,
        ));
      }
    }

    for (final entry in oldMap.values) {
      if (!newMap.containsKey(entry.packageName)) {
        removed.add(DiffItem(
          type: DiffType.removed,
          packageName: entry.packageName,
          appName: entry.appName,
          fromVersion: entry.versionName,
          isSystem: entry.isSystem,
          sizeBytes: entry.sizeBytes,
        ));
      }
    }

    added.sort((a, b) => a.appName.compareTo(b.appName));
    removed.sort((a, b) => a.appName.compareTo(b.appName));
    updated.sort((a, b) => a.appName.compareTo(b.appName));
    return SnapshotDiff(
      added: added,
      removed: removed,
      updated: updated,
      unchanged: unchanged,
    );
  }
}
