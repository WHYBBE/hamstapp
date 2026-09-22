import 'package:flutter_test/flutter_test.dart';

import 'package:hamstapp/models/app_meta.dart';
import 'package:hamstapp/models/category.dart';
import 'package:hamstapp/models/snapshot.dart';
import 'package:hamstapp/models/snapshot_diff.dart';

SnapshotEntry _e(String pkg, String ver, int code) => SnapshotEntry(
      packageName: pkg,
      appName: pkg,
      versionName: ver,
      versionCode: code,
      lastUpdateTime: 0,
      firstInstallTime: 0,
      isSystem: false,
      sizeBytes: 0,
    );

void main() {
  test('snapshot diff detects added, removed and updated apps', () {
    final older = Snapshot(
      id: 'a',
      name: 'older',
      createdAt: 0,
      entries: [_e('com.a', '1.0', 1), _e('com.b', '1.0', 1), _e('com.c', '1.0', 1)],
    );
    final newer = Snapshot(
      id: 'b',
      name: 'newer',
      createdAt: 1,
      entries: [_e('com.a', '1.0', 1), _e('com.b', '2.0', 2), _e('com.d', '1.0', 1)],
    );

    final diff = SnapshotDiff.between(older, newer);

    expect(diff.added.map((e) => e.packageName), contains('com.d'));
    expect(diff.removed.map((e) => e.packageName), contains('com.c'));
    expect(diff.updated.map((e) => e.packageName), contains('com.b'));
    expect(diff.unchanged.map((e) => e.packageName), contains('com.a'));
    expect(diff.changedCount, 3);
  });

  test('AppMeta round-trips uninstall fields', () {
    final meta = AppMeta(
      packageName: 'com.example',
      lastKnownName: '示例',
      uninstallReason: '太占空间',
      uninstalledAt: 123456789,
    );
    final restored = AppMeta.fromMap(meta.toMap());
    expect(restored.isUninstalled, isTrue);
    expect(restored.lastKnownName, '示例');
    expect(restored.uninstallReason, '太占空间');
    expect(restored.uninstalledAt, 123456789);
    expect(restored.hasUserData, isTrue);
  });

  test('snapshot round-trips full annotation data', () {
    final snapshot = Snapshot(
      id: 's1',
      name: '完整快照',
      createdAt: 1000,
      categories: [AppCategory(id: 'c1', name: '工具', emoji: '🛠️')],
      entries: [
        const SnapshotEntry(
          packageName: 'com.a',
          appName: 'A',
          versionName: '1.0',
          versionCode: 1,
          lastUpdateTime: 0,
          firstInstallTime: 0,
          isSystem: false,
          sizeBytes: 0,
          reason: '薅羊毛',
          note: '备注内容',
          categoryIds: ['c1'],
          favorite: true,
          pinned: true,
        ),
        const SnapshotEntry(
          packageName: 'com.gone',
          appName: 'Gone',
          versionName: '',
          versionCode: 0,
          lastUpdateTime: 0,
          firstInstallTime: 0,
          isSystem: false,
          sizeBytes: 0,
          uninstallReason: '不好用',
          uninstalledAt: 2000,
        ),
      ],
    );

    final restored = Snapshot.fromMap(snapshot.toMap());
    final a = restored.entries.firstWhere((e) => e.packageName == 'com.a');
    expect(a.reason, '薅羊毛');
    expect(a.note, '备注内容');
    expect(a.categoryIds, ['c1']);
    expect(a.favorite, isTrue);
    expect(a.isInstalled, isTrue);

    final gone =
        restored.entries.firstWhere((e) => e.packageName == 'com.gone');
    expect(gone.uninstallReason, '不好用');
    expect(gone.isInstalled, isFalse);
    expect(restored.installedCount, 1);
    expect(restored.uninstalledCount, 1);
    expect(restored.categories.single.name, '工具');
  });

  test('uninstalled snapshot entries are not treated as removed again', () {
    final older = Snapshot(
      id: 'a',
      name: 'older',
      createdAt: 0,
      entries: [_e('com.a', '1.0', 1)],
    );
    // com.a is now recorded as uninstalled in the newer snapshot.
    final newer = Snapshot(
      id: 'b',
      name: 'newer',
      createdAt: 1,
      entries: [
        const SnapshotEntry(
          packageName: 'com.a',
          appName: 'A',
          versionName: '1.0',
          versionCode: 1,
          lastUpdateTime: 0,
          firstInstallTime: 0,
          isSystem: false,
          sizeBytes: 0,
          uninstallReason: '不好用',
          uninstalledAt: 5,
        ),
      ],
    );

    final diff = SnapshotDiff.between(older, newer);
    expect(diff.removed.map((e) => e.packageName), contains('com.a'));
    expect(diff.added, isEmpty);
  });
}
