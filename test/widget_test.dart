import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hamstapp/models/app_info.dart';
import 'package:hamstapp/models/app_meta.dart';
import 'package:hamstapp/models/remote_source.dart';
import 'package:hamstapp/models/category.dart';
import 'package:hamstapp/models/snapshot.dart';
import 'package:hamstapp/models/snapshot_diff.dart';
import 'package:hamstapp/models/tile.dart';
import 'package:hamstapp/models/tile_page.dart';
import 'package:hamstapp/services/remote_client.dart';
import 'package:hamstapp/services/storage.dart';
import 'package:hamstapp/state/app_state.dart';
import 'package:hamstapp/utils/search.dart';
import 'package:hamstapp/utils/tile_layout.dart';

class _MemStorage implements Storage {
  final Map<String, dynamic> _data = <String, dynamic>{};

  @override
  Future<dynamic> readJson(String name) async => _data[name];

  @override
  Future<void> writeJson(String name, dynamic data) async {
    _data[name] = data;
  }
}

AppInfo _ai(String pkg, String name) => AppInfo(
      packageName: pkg,
      appName: name,
      versionName: '1',
      versionCode: 1,
      firstInstallTime: 0,
      lastUpdateTime: 0,
      isSystem: false,
      enabled: true,
      apkPath: '',
      sizeBytes: 0,
      targetSdk: 33,
      minSdk: 21,
      uid: 0,
    );

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
      lastLaunchedAt: 999,
      tilePageId: 'page-1',
    );
    final restored = AppMeta.fromMap(meta.toMap());
    expect(restored.isUninstalled, isTrue);
    expect(restored.lastKnownName, '示例');
    expect(restored.uninstallReason, '太占空间');
    expect(restored.uninstalledAt, 123456789);
    expect(restored.lastLaunchedAt, 999);
    expect(restored.tilePageId, 'page-1');
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

  test('tile layout packs six per row', () {
    final specs = List.generate(7, (i) => TileSpec(id: 'a$i'));
    final res = resolveTileLayout(specs);
    expect(res.rows, 2);
    expect(res.placements['a0']!.col, 0);
    expect(res.placements['a5']!.col, 5);
    expect(res.placements['a6']!.row, 1);
    expect(res.placements['a6']!.col, 0);
  });

  test('tile layout honours stored positions', () {
    final res = resolveTileLayout([
      const TileSpec(id: 'x', col: 3, row: 2, w: 2, h: 2),
      const TileSpec(id: 'y'),
    ]);
    expect(res.placements['x']!.col, 3);
    expect(res.placements['x']!.row, 2);
    expect(res.rows, 4);
    expect(res.placements['y']!.col, 0);
    expect(res.placements['y']!.row, 0);
  });

  test('tile layout supports 4x4 and 1x3 sizes', () {
    final res = resolveTileLayout([
      const TileSpec(id: 'big', w: 4, h: 4),
      const TileSpec(id: 'tall', w: 1, h: 3),
    ]);
    expect(res.placements['big']!.w, 4);
    expect(res.placements['big']!.h, 4);
    expect(res.rows, 4);
    expect(res.placements['tall']!.col, 4);
    expect(res.placements['tall']!.row, 0);
  });

  test('resolveMove finds nearest free spot on collision', () {
    final others = [const TileSpec(id: 'o', col: 0, row: 0, w: 2, h: 2)];
    final p = resolveMove(others, 'n', 0, 0, 2, 2);
    expect(p.col, 2);
    expect(p.row, 0);
  });

  test('addTile pins to the current page and allows duplicates', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [
      TilePage(id: 'p1', name: 'P1', createdAt: 0),
      TilePage(id: 'p2', name: 'P2', createdAt: 0),
    ];
    state.apps = [_ai('com.x', 'X')];
    state.currentTilePageIndex = 1;

    final t1 = await state.addTile('com.x');
    final t2 = await state.addTile('com.x');

    expect(t1.pageId, 'p2');
    expect(t2.pageId, 'p2');
    expect(t1.id, isNot(t2.id));
    expect(state.metaFor('com.x').pinned, isTrue);
    expect(state.pinCountOnPage(state.tilePages[0]), 0);
    expect(state.pinCountOnPage(state.tilePages[1]), 2);
  });

  test('new tiles default to 2x2 and follow the setting', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)];
    state.apps = [_ai('com.x', 'X')];

    final t = await state.addTile('com.x');
    expect(t.w, 2);
    expect(t.h, 2);

    await state.setTileDefaultSize(3);
    final t2 = await state.addTile('com.x');
    expect(t2.w, 3);
    expect(t2.h, 3);
  });

  test('removing one duplicate keeps the others', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)];
    state.apps = [_ai('com.x', 'X')];

    final t1 = await state.addTile('com.x');
    await state.addTile('com.x');
    await state.removeTile(t1.id);

    expect(state.tiles.length, 1);
    expect(state.metaFor('com.x').pinned, isTrue);
  });

  test('reordering a page keeps its tiles with it', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [
      TilePage(id: 'p1', name: 'P1', createdAt: 0),
      TilePage(id: 'p2', name: 'P2', createdAt: 0),
    ];
    state.apps = [_ai('com.a', 'A'), _ai('com.b', 'B')];
    state.tiles = [
      Tile(id: 't1', packageName: 'com.a', pageId: 'p1'),
      Tile(id: 't2', packageName: 'com.b', pageId: 'p2'),
    ];

    // Move P2 to the front; its tile must follow to index 0.
    await state.moveTilePage(1, -1);

    expect(state.tilePages.first.id, 'p2');
    expect(state.currentTilePageIndex, 0);
    final onFirst =
        state.tilesOnPage(state.tilePages[0]).map((t) => t.packageName);
    expect(onFirst, contains('com.b'));
    expect(onFirst, isNot(contains('com.a')));
  });

  test('search matches pinyin initials and full pinyin', () {
    expect(AppSearch.score('com.tencent.mm', '微信', 'wx'), isNotNull);
    expect(AppSearch.score('com.tencent.mm', '微信', 'weixin'), isNotNull);
    expect(AppSearch.score('com.tencent.mm', '微信', 'w'), isNotNull);
    expect(AppSearch.score('com.tencent.mm', '微信', 'zzz'), isNull);
  });

  test('search falls back to fuzzy subsequence', () {
    // "gmap" should fuzzily match "Google Maps".
    expect(AppSearch.score('com.google.maps', 'Google Maps', 'gmap'), isNotNull);
    // Contiguous prefix should outrank a scattered subsequence.
    final prefix = AppSearch.score('a', 'Maps', 'map')!;
    final fuzzy = AppSearch.score('a', 'Maps', 'mps')!;
    expect(prefix, greaterThan(fuzzy));
  });

  test('search supports multi-token queries and empty query', () {
    expect(AppSearch.score('com.a', 'Google Maps', 'google maps'), isNotNull);
    expect(AppSearch.score('com.a', 'Google Maps', 'maps google'), isNotNull);
    expect(AppSearch.score('com.a', 'Google Maps', 'google zzz'), isNull);
    expect(AppSearch.score('com.a', '任意', ''), 0);
  });

  test('rank orders the best match first', () {
    final apps = [
      _ai('com.x', '支付宝'),
      _ai('com.y', '微信'),
      _ai('com.z', 'Wechat'),
    ];
    final ranked = AppSearch.rank(apps, 'wx');
    expect(ranked.first.packageName, 'com.y');
  });

  test('export/import round-trips all data', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)];
    state.apps = [_ai('com.x', 'X')];
    state.metaFor('com.x')
      ..reason = 'because'
      ..favorite = true;
    state.categories = [AppCategory(id: 'c1', name: '工具', emoji: '🛠️')];
    state.tiles = [
      Tile(id: 't1', packageName: 'com.x', pageId: 'p1', w: 2, h: 2),
    ];
    state.settings['tile_default_size'] = 3;

    // Must be JSON-serialisable and re-parse cleanly.
    final pkg = jsonDecode(jsonEncode(state.exportPackage()))
        as Map<String, dynamic>;

    await state.clearAllData();
    expect(state.tiles, isEmpty);
    expect(state.categories, isEmpty);
    expect(state.meta, isEmpty);

    await state.importPackage(pkg);
    expect(state.categories.single.name, '工具');
    expect(state.tiles.single.packageName, 'com.x');
    expect(state.tiles.single.w, 2);
    expect(state.metaFor('com.x').reason, 'because');
    expect(state.metaFor('com.x').pinned, isTrue);
    expect(state.tileDefaultSize, 3);
  });

  test('remote source config round-trips through settings', () async {
    final state = AppState(_MemStorage());
    expect(state.remoteSource.configured, isFalse);
    expect(state.remoteSource.anonymous, isTrue);

    await state.setRemoteSource(RemoteSource(
      protocol: 'smb',
      host: 'nas.local',
      port: 445,
      path: 'share/apks',
      username: 'u',
      password: 'p',
      anonymous: false,
    ));

    final s = state.remoteSource;
    expect(s.isSmb, isTrue);
    expect(s.host, 'nas.local');
    expect(s.path, 'share/apks');
    expect(s.username, 'u');
    expect(s.configured, isTrue);

    // Survives an export/import cycle too.
    final pkg = state.exportPackage();
    final fresh = AppState(_MemStorage());
    await fresh.importPackage(pkg);
    expect(fresh.remoteSource.path, 'share/apks');
    expect(fresh.remoteSource.anonymous, isFalse);
  });

  test('webdav listing parses apk entries', () {
    const xml = '''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/apks/</D:href>
    <D:propstat><D:prop>
      <D:resourcetype><D:collection/></D:resourcetype>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/apks/com.example.app-1.2.3.apk</D:href>
    <D:propstat><D:prop>
      <D:getcontentlength>123456</D:getcontentlength>
      <D:getlastmodified>Wed, 21 Oct 2015 07:28:00 GMT</D:getlastmodified>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/apks/notes.txt</D:href>
    <D:propstat><D:prop>
      <D:getcontentlength>10</D:getcontentlength>
    </D:prop></D:propstat>
  </D:response>
</D:multistatus>
''';
    final list = RemoteClient.parseWebdavListing(xml);
    expect(list.length, 1);
    expect(list.single['name'], 'com.example.app-1.2.3.apk');
    expect(list.single['size'], 123456);
    expect(list.single['modified'], isNot(0));
  });

  test('webdav listing handles namespace-less hrefs', () {
    const xml = '<multistatus><response>'
        '<href>/dav/%E5%BA%94%E7%94%A8.apk</href>'
        '<getcontentlength>5</getcontentlength>'
        '</response></multistatus>';
    final list = RemoteClient.parseWebdavListing(xml);
    expect(list.single['name'], '应用.apk');
    expect(list.single['size'], 5);
  });

  test('RemoteSource.fromMap defaults are sane', () {
    final s = RemoteSource.fromMap(<String, dynamic>{});
    expect(s.protocol, 'ftp');
    expect(s.port, 21);
    expect(s.anonymous, isTrue);
    expect(RemoteSource.defaultPort('smb'), 445);
    expect(RemoteSource.defaultPort('ftp'), 21);
  });

  test('import rejects a malformed package without touching data', () async {
    final state = AppState(_MemStorage());
    state.tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)];
    state.categories = [AppCategory(id: 'c1', name: 'keep', emoji: 'x')];

    await expectLater(
      state.importPackage(<String, dynamic>{'app': 'other'}),
      throwsA(isA<FormatException>()),
    );
    expect(state.categories.single.name, 'keep');
  });

  test('legacy pinned meta migrates into a tile on load', () async {
    final storage = _MemStorage();
    storage._data['tile_pages'] = [
      TilePage(id: 'p1', name: 'P1', createdAt: 0).toMap(),
      TilePage(id: 'p2', name: 'P2', createdAt: 0).toMap(),
    ];
    storage._data['meta'] = {
      'com.legacy': AppMeta(
        packageName: 'com.legacy',
        pinned: true,
        tilePageId: 'p2',
      ).toMap(),
    };

    final state = AppState(storage);
    await state.init();

    expect(state.tiles.length, 1);
    expect(state.tiles.single.packageName, 'com.legacy');
    expect(state.tiles.single.pageId, 'p2');

    state.apps = [_ai('com.legacy', 'L')];
    expect(state.pinCountOnPage(state.tilePages[1]), 1);
  });
}
