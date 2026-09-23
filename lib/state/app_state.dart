import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../models/app_meta.dart';
import '../models/backup_list.dart';
import '../models/category.dart';
import '../models/snapshot.dart';
import '../models/tile_page.dart';
import '../services/native_apps.dart';
import '../services/storage.dart';
import '../utils/format.dart';
import '../utils/tile_layout.dart';

/// Which apps are in scope by type. Kept separate from [AppFilter] so it does
/// not take part in the annotation filter radio group.
enum AppScope { all, user, system }

enum AppFilter {
  all,
  favorite,
  categorized,
  uncategorized,
  hasReason,
  unorganized,
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
  List<TilePage> tilePages = <TilePage>[];

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
  AppScope scope = AppScope.all;
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
    tilePages = await _loadTilePages();
    if (tilePages.isEmpty) {
      tilePages.add(TilePage(
        id: _newId(),
        name: '页面 1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      await _persistTilePages();
    }
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <SnapshotEntry>[];
    final seen = <String>{};

    // Currently installed apps, together with their annotations.
    for (final a in apps) {
      final m = metaFor(a.packageName);
      seen.add(a.packageName);
      entries.add(SnapshotEntry(
        packageName: a.packageName,
        appName: a.appName,
        versionName: a.versionName,
        versionCode: a.versionCode,
        lastUpdateTime: a.lastUpdateTime,
        firstInstallTime: a.firstInstallTime,
        isSystem: a.isSystem,
        sizeBytes: a.sizeBytes,
        reason: m.reason,
        note: m.note,
        categoryIds: List<String>.from(m.categoryIds),
        favorite: m.favorite,
        pinned: m.pinned,
      ));
    }

    // Apps we've seen before that are currently uninstalled: keep their
    // uninstall record (including the reason) so the next snapshot can
    // restore it.
    for (final m in meta.values) {
      if (!m.isUninstalled || seen.contains(m.packageName)) continue;
      entries.add(SnapshotEntry(
        packageName: m.packageName,
        appName: m.lastKnownName.isEmpty ? m.packageName : m.lastKnownName,
        versionName: '',
        versionCode: 0,
        lastUpdateTime: 0,
        firstInstallTime: 0,
        isSystem: false,
        sizeBytes: 0,
        reason: m.reason,
        note: m.note,
        categoryIds: List<String>.from(m.categoryIds),
        favorite: m.favorite,
        pinned: m.pinned,
        uninstallReason: m.uninstallReason,
        uninstalledAt: m.uninstalledAt,
      ));
    }

    final snapshot = Snapshot(
      id: _newId(),
      name: name.isEmpty ? '快照 ${snapshots.length + 1}' : name,
      createdAt: now,
      note: note,
      entries: entries,
      categories: categories
          .map((c) => AppCategory(
                id: c.id,
                name: c.name,
                colorValue: c.colorValue,
                emoji: c.emoji,
              ))
          .toList(),
    );
    snapshots.add(snapshot);
    await _persistSnapshots();
    notifyListeners();
    return snapshot;
  }

  /// Restore the app annotations (reason, note, categories, favorite) and
  /// uninstall records stored in [snapshot]. Categories referenced by the
  /// snapshot are recreated if missing. Returns the number of apps updated.
  Future<int> restoreSnapshot(String snapshotId) async {
    final snapshot = snapshots.firstWhere((s) => s.id == snapshotId);

    // Recreate categories that no longer exist.
    final existingCatIds = categories.map((c) => c.id).toSet();
    for (final c in snapshot.categories) {
      if (existingCatIds.contains(c.id)) continue;
      categories.add(AppCategory(
        id: c.id,
        name: c.name,
        colorValue: c.colorValue,
        emoji: c.emoji,
      ));
      existingCatIds.add(c.id);
    }

    final installed = {for (final a in apps) a.packageName};

    for (final e in snapshot.entries) {
      final m = metaFor(e.packageName);
      m.reason = e.reason;
      m.note = e.note;
      m.favorite = e.favorite;
      m.pinned = e.pinned;
      m.categoryIds =
          e.categoryIds.where(existingCatIds.contains).toList(growable: true);
      if (e.appName.isNotEmpty) m.lastKnownName = e.appName;

      if (e.uninstalledAt != 0 && !installed.contains(e.packageName)) {
        // Keep it as an uninstall record with its reason.
        m.uninstallReason = e.uninstallReason;
        m.uninstalledAt = e.uninstalledAt;
      } else {
        // Installed (or reinstalled) now -> clear the uninstall record.
        m.uninstallReason = '';
        m.uninstalledAt = 0;
      }
    }

    await _persistCategories();
    await _persistMeta();
    notifyListeners();
    return snapshot.entries.length;
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

  // ---------------------------------------------------------------- tile pages

  Future<List<TilePage>> _loadTilePages() async {
    final raw = await storage.readJson(_kTilePages);
    if (raw is List) {
      return raw
          .map((e) => TilePage.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return <TilePage>[];
  }

  Future<void> _persistTilePages() async {
    await storage
        .writeJson(_kTilePages, tilePages.map((p) => p.toMap()).toList());
  }

  /// Pinned apps shown on [page]. Pins with an unknown/empty page id fall back
  /// to the first page so they are never lost.
  List<AppInfo> pinsOnPage(TilePage page) {
    if (tilePages.isEmpty) return pinnedApps;
    final first = tilePages.first;
    final validIds = tilePages.map((p) => p.id).toSet();
    return apps.where((a) {
      if (!metaFor(a.packageName).pinned) return false;
      final pid = metaFor(a.packageName).tilePageId;
      if (page.id == first.id) {
        return pid.isEmpty || !validIds.contains(pid) || pid == page.id;
      }
      return pid == page.id;
    }).toList()
      ..sort((a, b) =>
          a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  }

  int pinCountOnPage(TilePage page) => pinsOnPage(page).length;

  Future<TilePage> addTilePage(String name) async {
    final page = TilePage(
      id: _newId(),
      name: name.isEmpty ? '页面 ${tilePages.length + 1}' : name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    tilePages.add(page);
    await _persistTilePages();
    notifyListeners();
    return page;
  }

  Future<void> renameTilePage(String id, String name) async {
    final page = tilePages.firstWhere((p) => p.id == id);
    page.name = name;
    await _persistTilePages();
    notifyListeners();
  }

  Future<void> deleteTilePage(String id) async {
    if (tilePages.length <= 1) return;
    tilePages.removeWhere((p) => p.id == id);
    final firstId = tilePages.first.id;
    for (final m in meta.values) {
      if (m.pinned && m.tilePageId == id) m.tilePageId = firstId;
    }
    if (currentTilePageIndex >= tilePages.length) {
      currentTilePageIndex = tilePages.length - 1;
    }
    await _persistTilePages();
    await _persistMeta();
    notifyListeners();
  }

  Future<void> assignPinToPage(String packageName, String pageId) async {
    final m = metaFor(packageName);
    m.tilePageId = pageId;
    await _persistMeta();
    notifyListeners();
  }

  /// Currently visible tile page (transient, not persisted).
  int currentTilePageIndex = 0;

  void setCurrentTilePage(int i) {
    if (i == currentTilePageIndex) return;
    currentTilePageIndex = i;
    notifyListeners();
  }

  TilePage _pageForPin(String packageName) {
    if (tilePages.isEmpty) {
      return TilePage(id: '', name: '页面 1', createdAt: 0);
    }
    final pid = metaFor(packageName).tilePageId;
    return tilePages.firstWhere(
      (p) => p.id == pid,
      orElse: () => tilePages.first,
    );
  }

  List<TileSpec> _specsForPage(TilePage page, {String? exclude}) {
    final specs = <TileSpec>[];
    for (final a in pinsOnPage(page)) {
      if (a.packageName == exclude) continue;
      final m = metaFor(a.packageName);
      specs.add(TileSpec(
        id: a.packageName,
        w: m.tileW,
        h: m.tileH,
        col: m.tileCol,
        row: m.tileRow,
      ));
    }
    return specs;
  }

  /// Move a tile to the given grid cell (finds the nearest free spot on
  /// collision).
  Future<void> moveTile(String packageName, int col, int row) async {
    final m = metaFor(packageName);
    final page = _pageForPin(packageName);
    final others = _specsForPage(page, exclude: packageName);
    final p = resolveMove(
        others, packageName, col, row, m.tileW, m.tileH);
    m.tileCol = p.col;
    m.tileRow = p.row;
    await _persistMeta();
    notifyListeners();
  }

  /// Change a tile's size (width 1..6, height 1..6), relocating if needed.
  Future<void> setTileSize(String packageName, int w, int h) async {
    final cw = w.clamp(1, kTileCols);
    final ch = h.clamp(1, kTileMaxH);
    final m = metaFor(packageName);
    final page = _pageForPin(packageName);
    final others = _specsForPage(page, exclude: packageName);
    final p = resolveMove(
      others,
      packageName,
      m.tileCol < 0 ? 0 : m.tileCol,
      m.tileRow < 0 ? 0 : m.tileRow,
      cw,
      ch,
    );
    m.tileW = cw;
    m.tileH = ch;
    m.tileCol = p.col;
    m.tileRow = p.row;
    await _persistMeta();
    notifyListeners();
  }

  /// Lock/unlock a tile page. A locked page cannot be rearranged.
  Future<void> setTilePageLocked(String id, bool locked) async {
    final page = tilePages.firstWhere((p) => p.id == id);
    page.locked = locked;
    await _persistTilePages();
    notifyListeners();
  }

  /// Manually move a tile page (sub-tab) left/right by [delta].
  Future<void> moveTilePage(int index, int delta) async {
    final target = index + delta;
    if (index < 0 || index >= tilePages.length) return;
    if (target < 0 || target >= tilePages.length) return;
    final page = tilePages.removeAt(index);
    tilePages.insert(target, page);
    currentTilePageIndex = target;
    await _persistTilePages();
    notifyListeners();
  }

  // ---------------------------------------------------------------- filtering

  List<AppInfo> get visibleApps {
    final q = query.trim().toLowerCase();
    var list = apps.where((app) {
      switch (scope) {
        case AppScope.user:
          if (app.isSystem) return false;
          break;
        case AppScope.system:
          if (!app.isSystem) return false;
          break;
        case AppScope.all:
          break;
      }
      switch (filter) {
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
        case AppFilter.unorganized:
          final m = metaFor(app.packageName);
          if (m.categoryIds.isNotEmpty ||
              m.reason.isNotEmpty ||
              m.note.isNotEmpty) {
            return false;
          }
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

  /// Apps manually pinned to the tile board, ordered by name.
  List<AppInfo> get pinnedApps => apps
      .where((a) => metaFor(a.packageName).pinned)
      .toList()
    ..sort((a, b) =>
        a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

  /// Apps launched from this app, most recent first.
  List<AppInfo> get recentApps {
    final list = apps
        .where((a) => metaFor(a.packageName).lastLaunchedAt > 0)
        .toList()
      ..sort((a, b) => metaFor(b.packageName)
          .lastLaunchedAt
          .compareTo(metaFor(a.packageName).lastLaunchedAt));
    return list;
  }

  Future<void> markLaunched(String packageName) async {
    final m = metaFor(packageName);
    m.lastLaunchedAt = DateTime.now().millisecondsSinceEpoch;
    await _persistMeta();
    notifyListeners();
  }

  Future<void> togglePinned(String packageName) async {
    final m = metaFor(packageName);
    m.pinned = !m.pinned;
    await _persistMeta();
    notifyListeners();
  }

  AppInfo? appByPackage(String packageName) {
    for (final a in apps) {
      if (a.packageName == packageName) return a;
    }
    return null;
  }

  int get userAppCount => apps.where((a) => !a.isSystem).length;
  int get systemAppCount => apps.where((a) => a.isSystem).length;

  /// Human readable summary shown as a hint in the app bar (long-press).
  String get appsStatsText {
    if (scanning) return '正在扫描…';
    final last = lastScanAt;
    if (last == null) return '尚未扫描，点击右上角刷新';
    final ago = Fmt.relative(last.millisecondsSinceEpoch);
    if (filter == AppFilter.uninstalled) {
      return '卸载记录 ${uninstalledApps.length} 条 · 上次扫描 $ago';
    }
    return '共 ${apps.length} 个应用（用户 $userAppCount / 系统 $systemAppCount）'
        ' · 显示 ${visibleApps.length} · 用时 $lastScanMs ms · $ago';
  }

  static const _kMeta = 'meta';
  static const _kCategories = 'categories';
  static const _kSnapshots = 'snapshots';
  static const _kBackupLists = 'backup_lists';
  static const _kAppsCache = 'apps_cache';
  static const _kTilePages = 'tile_pages';
}
