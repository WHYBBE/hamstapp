import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../models/app_meta.dart';
import '../models/backup_list.dart';
import '../models/category.dart';
import '../models/snapshot.dart';
import '../services/native_apps.dart';
import '../services/storage.dart';

enum AppFilter {
  all,
  user,
  system,
  favorite,
  categorized,
  uncategorized,
  hasReason,
  uninstalled,
}

enum AppSort { name, installTime, updateTime, size }

class AppState extends ChangeNotifier {
  final Storage storage;

  AppState(this.storage);

  List<AppInfo> apps = <AppInfo>[];
  Map<String, AppMeta> meta = <String, AppMeta>{};
  List<AppCategory> categories = <AppCategory>[];
  List<Snapshot> snapshots = <Snapshot>[];
  List<BackupList> backupLists = <BackupList>[];

  /// Apps detected as uninstalled during the most recent scan and that the
  /// user has not been asked about yet this session.
  List<AppMeta> pendingUninstalls = <AppMeta>[];

  bool initialized = false;
  bool scanning = false;
  String? scanError;
  int lastScanMs = 0;
  DateTime? lastScanAt;
  bool includeSystemInScan = true;

  String query = '';
  AppFilter filter = AppFilter.all;
  AppSort sort = AppSort.name;
  String? filterCategoryId;

  final Random _rand = Random();

  /// Public wrapper so widgets can trigger a rebuild after mutating a
  /// filter/sort field directly.
  void refresh() => notifyListeners();

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 32)}';

  // ---------------------------------------------------------------- lifecycle

  Future<void> init() async {
    meta = await _loadMeta();
    categories = await _loadCategories();
    snapshots = await _loadSnapshots();
    backupLists = await _loadBackupLists();
    final cached = await storage.readJson(_kAppsCache);
    if (cached is List) {
      apps = cached
          .map((e) => AppInfo.fromMap((e as Map).cast<dynamic, dynamic>()))
          .toList();
    }
    initialized = true;
    notifyListeners();
  }

  Future<Map<String, AppMeta>> _loadMeta() async {
    final raw = await storage.readJson(_kMeta);
    if (raw is Map) {
      return raw.map((k, v) =>
          MapEntry(k as String, AppMeta.fromMap((v as Map).cast<String, dynamic>())));
    }
    return <String, AppMeta>{};
  }

  Future<List<AppCategory>> _loadCategories() async {
    final raw = await storage.readJson(_kCategories);
    if (raw is List) {
      return raw
          .map((e) => AppCategory.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return <AppCategory>[];
  }

  Future<List<Snapshot>> _loadSnapshots() async {
    final raw = await storage.readJson(_kSnapshots);
    if (raw is List) {
      return raw
          .map((e) => Snapshot.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return <Snapshot>[];
  }

  Future<List<BackupList>> _loadBackupLists() async {
    final raw = await storage.readJson(_kBackupLists);
    if (raw is List) {
      return raw
          .map((e) => BackupList.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return <BackupList>[];
  }

  // ---------------------------------------------------------------- scanning

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    scanError = null;
    pendingUninstalls = <AppMeta>[];
    notifyListeners();

    // Baseline used to detect removals: the most recent snapshot if one
    // exists ("当前 vs 上次快照"), otherwise the previous scan result.
    final baseline = _baseline();

    final sw = Stopwatch()..start();
    try {
      final result =
          await NativeApps.getInstalledApps(includeSystem: includeSystemInScan);
      result.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

      final now = DateTime.now();
      final current = <String>{};
      for (final app in result) {
        current.add(app.packageName);
        final m = meta.putIfAbsent(
          app.packageName,
          () => AppMeta(
            packageName: app.packageName,
            firstSeenAt: now.millisecondsSinceEpoch,
          ),
        );
        m.packageName = app.packageName;
        m.lastKnownName = app.appName;
        if (m.uninstalledAt != 0) {
          // App came back -> clear the previous uninstall record.
          m.uninstalledAt = 0;
          m.uninstallReason = '';
        }
      }

      // Detect apps that were present in the baseline but are gone now.
      final pending = <AppMeta>[];
      for (final entry in baseline.entries) {
        final pkg = entry.key;
        if (current.contains(pkg)) continue;
        final m = meta.putIfAbsent(
          pkg,
          () => AppMeta(
            packageName: pkg,
            firstSeenAt: now.millisecondsSinceEpoch,
          ),
        );
        if (m.lastKnownName.isEmpty) m.lastKnownName = entry.value;
        if (m.uninstalledAt == 0) {
          m.uninstalledAt = now.millisecondsSinceEpoch;
          m.uninstallReason = '';
          pending.add(m);
        }
      }
      pendingUninstalls = pending;

      apps = result;
      await storage.writeJson(
          _kAppsCache, apps.map((e) => e.toMap()).toList());
      await _persistMeta();

      sw.stop();
      lastScanMs = sw.elapsedMilliseconds;
      lastScanAt = now;
    } catch (e) {
      sw.stop();
      lastScanMs = sw.elapsedMilliseconds;
      scanError = e.toString();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Map<String, String> _baseline() {
    if (snapshots.isNotEmpty) {
      final latest = snapshots.reduce(
          (a, b) => a.createdAt >= b.createdAt ? a : b);
      if (latest.entries.isNotEmpty) {
        return {
          for (final e in latest.entries) e.packageName: e.appName,
        };
      }
    }
    return {for (final a in apps) a.packageName: a.appName};
  }

  void clearPendingUninstalls() {
    if (pendingUninstalls.isEmpty) return;
    pendingUninstalls = <AppMeta>[];
    notifyListeners();
  }

  /// All apps ever seen that are currently uninstalled, newest first.
  List<AppMeta> get uninstalledApps {
    final list = meta.values.where((m) => m.isUninstalled).toList()
      ..sort((a, b) => b.uninstalledAt.compareTo(a.uninstalledAt));
    return list;
  }

  // ---------------------------------------------------------------- meta

  AppMeta metaFor(String packageName) {
    return meta.putIfAbsent(
      packageName,
      () => AppMeta(
        packageName: packageName,
        firstSeenAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> updateMeta(
    String packageName, {
    String? reason,
    String? note,
    bool? favorite,
    bool? pinned,
    List<String>? categoryIds,
    String? uninstallReason,
  }) async {
    final m = metaFor(packageName);
    if (reason != null) m.reason = reason;
    if (note != null) m.note = note;
    if (favorite != null) m.favorite = favorite;
    if (pinned != null) m.pinned = pinned;
    if (categoryIds != null) m.categoryIds = categoryIds;
    if (uninstallReason != null) m.uninstallReason = uninstallReason;
    await _persistMeta();
    notifyListeners();
  }

  Future<void> clearMeta(String packageName) async {
    meta.remove(packageName);
    await _persistMeta();
    notifyListeners();
  }

  /// Persist in-memory metadata changes (e.g. debounced text field edits).
  Future<void> persistMeta() => _persistMeta();

  Future<void> _persistMeta() =>
      storage.writeJson(_kMeta, meta.map((k, v) => MapEntry(k, v.toMap())));

  // ---------------------------------------------------------------- categories

  Future<AppCategory> addCategory(String name,
      {int colorValue = 0xFF6C8CFF, String emoji = '📦'}) async {
    final c = AppCategory(
        id: _newId(), name: name, colorValue: colorValue, emoji: emoji);
    categories.add(c);
    await _persistCategories();
    notifyListeners();
    return c;
  }

  Future<void> updateCategory(AppCategory c,
      {String? name, int? colorValue, String? emoji}) async {
    if (name != null) c.name = name;
    if (colorValue != null) c.colorValue = colorValue;
    if (emoji != null) c.emoji = emoji;
    await _persistCategories();
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    categories.removeWhere((c) => c.id == id);
    for (final m in meta.values) {
      m.categoryIds.remove(id);
    }
    await _persistCategories();
    await _persistMeta();
    if (filterCategoryId == id) filterCategoryId = null;
    notifyListeners();
  }

  Future<void> _persistCategories() async {
    await storage
        .writeJson(_kCategories, categories.map((c) => c.toMap()).toList());
  }

  // ---------------------------------------------------------------- snapshots

  Future<Snapshot> createSnapshot(String name, {String note = ''}) async {
    final snapshot = Snapshot(
      id: _newId(),
      name: name.isEmpty
          ? '快照 ${snapshots.length + 1}'
          : name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      note: note,
      entries: apps
          .map((a) => SnapshotEntry(
                packageName: a.packageName,
                appName: a.appName,
                versionName: a.versionName,
                versionCode: a.versionCode,
                lastUpdateTime: a.lastUpdateTime,
                firstInstallTime: a.firstInstallTime,
                isSystem: a.isSystem,
                sizeBytes: a.sizeBytes,
              ))
          .toList(),
    );
    snapshots.add(snapshot);
    await _persistSnapshots();
    notifyListeners();
    return snapshot;
  }

  Future<void> deleteSnapshot(String id) async {
    snapshots.removeWhere((s) => s.id == id);
    await _persistSnapshots();
    notifyListeners();
  }

  Future<void> renameSnapshot(String id, String name) async {
    final s = snapshots.firstWhere((e) => e.id == id);
    s.name = name;
    await _persistSnapshots();
    notifyListeners();
  }

  Future<void> _persistSnapshots() async {
    await storage
        .writeJson(_kSnapshots, snapshots.map((s) => s.toMap()).toList());
  }

  // ---------------------------------------------------------------- backups

  Future<BackupList> addBackupList(String name, {String description = ''}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final b = BackupList(
      id: _newId(),
      name: name.isEmpty ? '备份列表 ${backupLists.length + 1}' : name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    backupLists.add(b);
    await _persistBackupLists();
    notifyListeners();
    return b;
  }

  Future<void> deleteBackupList(String id) async {
    backupLists.removeWhere((b) => b.id == id);
    await _persistBackupLists();
    notifyListeners();
  }

  Future<void> updateBackupList(BackupList list,
      {String? name, String? description}) async {
    if (name != null) list.name = name;
    if (description != null) list.description = description;
    list.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persistBackupLists();
    notifyListeners();
  }

  Future<void> toggleBackupMember(String listId, String packageName) async {
    final list = backupLists.firstWhere((b) => b.id == listId);
    if (list.packageNames.contains(packageName)) {
      list.packageNames.remove(packageName);
    } else {
      list.packageNames.add(packageName);
    }
    list.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persistBackupLists();
    notifyListeners();
  }

  Future<void> backupCurrentApps(String listId) async {
    final list = backupLists.firstWhere((b) => b.id == listId);
    list.packageNames = apps.map((a) => a.packageName).toList();
    list.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persistBackupLists();
    notifyListeners();
  }

  Future<void> _persistBackupLists() async {
    await storage
        .writeJson(_kBackupLists, backupLists.map((b) => b.toMap()).toList());
  }

  // ---------------------------------------------------------------- filtering

  List<AppInfo> get visibleApps {
    final q = query.trim().toLowerCase();
    var list = apps.where((app) {
      switch (filter) {
        case AppFilter.user:
          if (app.isSystem) return false;
          break;
        case AppFilter.system:
          if (!app.isSystem) return false;
          break;
        case AppFilter.favorite:
          if (!metaFor(app.packageName).favorite) return false;
          break;
        case AppFilter.categorized:
          if (metaFor(app.packageName).categoryIds.isEmpty) return false;
          break;
        case AppFilter.uncategorized:
          if (metaFor(app.packageName).categoryIds.isNotEmpty) return false;
          break;
        case AppFilter.hasReason:
          if (metaFor(app.packageName).reason.isEmpty) return false;
          break;
        case AppFilter.uninstalled:
          // Handled separately via [uninstalledApps].
          return false;
        case AppFilter.all:
          break;
      }
      if (filterCategoryId != null) {
        if (!metaFor(app.packageName).categoryIds.contains(filterCategoryId)) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        if (!app.appName.toLowerCase().contains(q) &&
            !app.packageName.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    switch (sort) {
      case AppSort.name:
        list.sort((a, b) =>
            a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
        break;
      case AppSort.installTime:
        list.sort((a, b) => b.firstInstallTime.compareTo(a.firstInstallTime));
        break;
      case AppSort.updateTime:
        list.sort((a, b) => b.lastUpdateTime.compareTo(a.lastUpdateTime));
        break;
      case AppSort.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
    }
    return list;
  }

  List<AppInfo> get favorites => apps
      .where((a) => metaFor(a.packageName).favorite)
      .toList()
    ..sort((a, b) =>
        a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

  AppInfo? appByPackage(String packageName) {
    for (final a in apps) {
      if (a.packageName == packageName) return a;
    }
    return null;
  }

  int get userAppCount => apps.where((a) => !a.isSystem).length;
  int get systemAppCount => apps.where((a) => a.isSystem).length;

  static const _kMeta = 'meta';
  static const _kCategories = 'categories';
  static const _kSnapshots = 'snapshots';
  static const _kBackupLists = 'backup_lists';
  static const _kAppsCache = 'apps_cache';
}
