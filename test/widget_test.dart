import 'package:flutter_test/flutter_test.dart';

import 'package:hamstapp/models/app_meta.dart';
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
}
