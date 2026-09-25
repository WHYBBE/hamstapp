import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hamstapp/models/app_info.dart';
import 'package:hamstapp/models/category.dart';
import 'package:hamstapp/models/tile.dart';
import 'package:hamstapp/models/tile_page.dart';
import 'package:hamstapp/screens/categories_tab.dart';
import 'package:hamstapp/screens/quick_launch_screen.dart';
import 'package:hamstapp/services/storage.dart';
import 'package:hamstapp/state/app_state.dart';
import 'package:hamstapp/widgets/category_editor.dart';

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

void main() {
  testWidgets('dragging a tile moves it to a new cell', (tester) async {
    final state = AppState(_MemStorage())
      ..initialized = true
      ..apps = [_ai('com.a', 'A')]
      ..tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)]
      ..tiles = [
        Tile(
          id: 't1',
          packageName: 'com.a',
          pageId: 'p1',
          col: 0,
          row: 0,
          w: 2,
          h: 2,
        ),
      ]
      ..currentTilePageIndex = 0
      ..tileEditMode = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: QuickLaunchScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final tile = find.byKey(const ValueKey('t1'));
    expect(tile, findsOneWidget);

    final start = tester.getCenter(tile);
    final gesture = await tester.startGesture(start);
    // Hold past the 180ms long-press delay to start the move drag.
    await tester.pump(const Duration(milliseconds: 300));
    // Drag right by more than one cell (~122px at the default 800px width).
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      state.tileById('t1')!.col,
      greaterThan(0),
      reason: 'tile should have moved right',
    );
  });

  testWidgets('empty tile page can enter edit mode and pin an app', (
    tester,
  ) async {
    final state = AppState(_MemStorage())
      ..initialized = true
      ..apps = [_ai('com.a', 'A')]
      ..tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)]
      ..tiles = []
      ..currentTilePageIndex = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: QuickLaunchScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Browsing an empty page shows the hint, not a board.
    expect(find.textContaining('还没有磁贴'), findsOneWidget);

    // Tap the edit button in the AppBar.
    final editBtn = find.byIcon(Icons.edit_outlined);
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pump();

    expect(state.tileEditMode, isTrue);
    // Editing an empty page must render the board/grid (hint replaced) and
    // expose the pin action.
    expect(find.textContaining('还没有磁贴'), findsNothing);
    expect(find.byTooltip('置顶应用到磁贴'), findsOneWidget);

    // Pinning from the edit action actually adds a tile to the empty page.
    await tester.tap(find.byTooltip('置顶应用到磁贴'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ListTile, 'A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.tiles.length, 1);
    expect(state.tiles.first.pageId, 'p1');
  });

  testWidgets('wide board keeps a far-right tile instead of re-packing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState(_MemStorage())
      ..initialized = true
      ..apps = [_ai('com.a', 'A')]
      ..tilePages = [TilePage(id: 'p1', name: 'P1', createdAt: 0)]
      ..tiles = [
        Tile(
          id: 't1',
          packageName: 'com.a',
          pageId: 'p1',
          col: 10,
          row: 0,
          w: 2,
          h: 2,
        ),
      ]
      ..currentTilePageIndex = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: QuickLaunchScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Column 10 only fits because the wide screen exposes more than 6 columns;
    // on a phone it would have been re-packed to the left.
    final tile = find.byKey(const ValueKey('t1'));
    expect(tile, findsOneWidget);
    expect(tester.getRect(tile).left, greaterThan(400));
  });

  testWidgets('category screen can add an app to the category', (tester) async {
    final cat = AppCategory(id: 'c1', name: '工具', emoji: '🛠');
    final state = AppState(_MemStorage())
      ..initialized = true
      ..apps = [_ai('com.a', 'A')]
      ..categories = [cat];

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: CategoryAppsScreen(state: state, category: cat),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('该分类下还没有应用'), findsOneWidget);

    await tester.tap(find.byTooltip('添加应用到该分类'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(ListTile, 'A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.metaFor('com.a').categoryIds, contains('c1'));
    expect(find.byTooltip('移出分类'), findsOneWidget);
  });

  testWidgets('category editor accepts a custom emoji', (tester) async {
    final state = AppState(_MemStorage())..initialized = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCategoryEditor(context, state, null),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2)); // name + custom emoji
    await tester.enterText(fields.first, '测试');
    await tester.enterText(fields.at(1), '🦄');
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.categories.single.name, '测试');
    expect(state.categories.single.emoji, '🦄');
  });
}
