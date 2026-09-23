import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/tile_page.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
import '../utils/tile_layout.dart';
import '../widgets/app_icon.dart';
import '../widgets/category_editor.dart';
import 'app_detail_screen.dart';
import 'categories_tab.dart';

class QuickLaunchScreen extends StatefulWidget {
  const QuickLaunchScreen({super.key});

  @override
  State<QuickLaunchScreen> createState() => _QuickLaunchScreenState();
}

class _QuickLaunchScreenState extends State<QuickLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('快速启动', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: _actions(context, state),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: '磁贴'),
            Tab(icon: Icon(Icons.category_outlined, size: 20), text: '分类'),
            Tab(icon: Icon(Icons.star_outline, size: 20), text: '收藏'),
            Tab(icon: Icon(Icons.history, size: 20), text: '最近'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TilesTab(state: state),
          CategoriesTab(state: state),
          _FavoritesTab(state: state),
          _RecentTab(state: state),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppState state) {
    switch (_tabs.index) {
      case 0:
        return [
          PopupMenuButton<String>(
            tooltip: '排序磁贴',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              final pages = state.tilePages;
              if (pages.isEmpty) return;
              final idx =
                  state.currentTilePageIndex.clamp(0, pages.length - 1);
              final pageId = pages[idx].id;
              if (v == 'reset') {
                state.resetTileLayout(pageId);
              } else {
                state.applyTileSort(pageId, _tileSortFrom(v));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'name', child: Text('按名称')),
              PopupMenuItem(value: 'recent', child: Text('按最近使用')),
              PopupMenuItem(value: 'install', child: Text('按安装时间')),
              PopupMenuItem(value: 'update', child: Text('按更新时间')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'reset', child: Text('重置布局')),
            ],
          ),
          IconButton(
            tooltip: '置顶应用到磁贴',
            icon: const Icon(Icons.add),
            onPressed: () => showPinSheet(context, state),
          ),
        ];
      case 1:
        return [
          IconButton(
            tooltip: '新建分类',
            icon: const Icon(Icons.add),
            onPressed: () => showCategoryEditor(context, state, null),
          ),
        ];
      default:
        return const [];
    }
  }
}

TileSort _tileSortFrom(String v) {
  switch (v) {
    case 'recent':
      return TileSort.recent;
    case 'install':
      return TileSort.installTime;
    case 'update':
      return TileSort.updateTime;
    default:
      return TileSort.name;
  }
}

// ---------------------------------------------------------------- 磁贴

class _TilesTab extends StatefulWidget {
  const _TilesTab({required this.state});
  final AppState state;

  @override
  State<_TilesTab> createState() => _TilesTabState();
}

class _TilesTabState extends State<_TilesTab> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.state.currentTilePageIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setIndex(int i) {
    setState(() => _index = i);
    widget.state.setCurrentTilePage(i);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pages = state.tilePages;
    if (pages.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '还没有磁贴页',
      );
    }
    if (_index >= pages.length) _index = pages.length - 1;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: _setIndex,
            itemBuilder: (context, i) =>
                _TileBoard(state: state, page: pages[i]),
          ),
        ),
        _PageBar(
          state: state,
          currentIndex: _index,
          onSelect: (i) {
            _setIndex(i);
            _controller.animateToPage(
              i,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
            );
          },
          onAdd: () async {
            final page = await _promptAddPage(context, state);
            if (page == null) return;
            final idx = state.tilePages.indexWhere((p) => p.id == page.id);
            if (idx < 0) return;
            _setIndex(idx);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_controller.hasClients) _controller.jumpToPage(idx);
            });
          },
          onChanged: () {
            setState(() {
              if (_index >= state.tilePages.length) {
                _index = state.tilePages.length - 1;
              }
            });
            widget.state.setCurrentTilePage(_index);
            final target = _index;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_controller.hasClients &&
                  (_controller.page?.round() ?? 0) != target) {
                _controller.jumpToPage(target);
              }
            });
          },
        ),
      ],
    );
  }
}

/// A scrollable 6-column board. Tiles can be freely positioned and sized
/// (1x1 up to 6x6); long-press to drag, tap the corner button for options.
class _TileBoard extends StatefulWidget {
  const _TileBoard({required this.state, required this.page});
  final AppState state;
  final TilePage page;

  @override
  State<_TileBoard> createState() => _TileBoardState();
}

class _TileBoardState extends State<_TileBoard> {
  final GlobalKey _boardKey = GlobalKey();
  static const double _gap = 8;
  static const double _pad = 12;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final page = widget.page;
    final pins = state.pinsOnPage(page);
    if (pins.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '「${page.name}」还没有磁贴\n点击右上角 ➕ 选择要置顶的应用',
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final cellW =
          (constraints.maxWidth - _pad * 2 - _gap * (kTileCols - 1)) / kTileCols;
      final specs = pins.map((a) {
        final m = state.metaFor(a.packageName);
        return TileSpec(
            id: a.packageName, w: m.tileW, h: m.tileH, col: m.tileCol, row: m.tileRow);
      }).toList();
      final layout = resolveTileLayout(specs);
      final rows = layout.rows;
      final boardHeight =
          _pad * 2 + rows * cellW + (rows > 1 ? (rows - 1) * _gap : 0.0);

      double x(int col) => _pad + col * (cellW + _gap);
      double y(int row) => _pad + row * (cellW + _gap);
      double w(int n) => n * cellW + (n - 1) * _gap;
      double h(int n) => n * cellW + (n - 1) * _gap;

      return SingleChildScrollView(
        child: SizedBox(
          key: _boardKey,
          height: boardHeight,
          width: double.infinity,
          child: Stack(
            children: [
              for (final app in pins)
                Builder(builder: (context) {
                  final p = layout.placements[app.packageName]!;
                  return Positioned(
                    left: x(p.col),
                    top: y(p.row),
                    width: w(p.w),
                    height: h(p.h),
                    child: _Tile(
                      app: app,
                      state: state,
                      page: page,
                      boardKey: _boardKey,
                      cellW: cellW,
                      gap: _gap,
                      pad: _pad,
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    });
  }
}

/// Bottom page switcher (put at the very bottom, like a tab bar).
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.state,
    required this.currentIndex,
    required this.onSelect,
    required this.onChanged,
    required this.onAdd,
  });

  final AppState state;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = state.tilePages;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final page = pages[i];
                final selected = i == currentIndex;
                final count = state.pinCountOnPage(page);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    onLongPress: () => _pageMenu(context, state, page, onChanged),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            page.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              color: (selected
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant)
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '新建磁贴页',
            icon: const Icon(Icons.add),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

Future<TilePage?> _promptAddPage(BuildContext context, AppState state) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建磁贴页'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '页面名称'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建')),
      ],
    ),
  );
  if (name == null) return null;
  return state.addTilePage(name);
}

void _pageMenu(
  BuildContext context,
  AppState state,
  TilePage page,
  VoidCallback onChanged,
) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('重命名页面'),
            onTap: () async {
              Navigator.pop(ctx);
              final controller = TextEditingController(text: page.name);
              final name = await showDialog<String>(
                context: context,
                builder: (dctx) => AlertDialog(
                  title: const Text('重命名页面'),
                  content:
                      TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dctx),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(dctx, controller.text.trim()),
                        child: const Text('保存')),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) {
                await state.renameTilePage(page.id, name);
                onChanged();
              }
            },
          ),
          if (state.tilePages.length > 1)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除页面'),
              subtitle: const Text('页面上的磁贴会移回第一个页面'),
              onTap: () async {
                Navigator.pop(ctx);
                await state.deleteTilePage(page.id);
                onChanged();
              },
            ),
        ],
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.app,
    required this.state,
    required this.page,
    required this.boardKey,
    required this.cellW,
    required this.gap,
    required this.pad,
  });

  final AppInfo app;
  final AppState state;
  final TilePage page;
  final GlobalKey boardKey;
  final double cellW;
  final double gap;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final meta = state.metaFor(app.packageName);
    final width = meta.tileW * cellW + (meta.tileW - 1) * gap;
    final height = meta.tileH * cellW + (meta.tileH - 1) * gap;
    final shortest = width < height ? width : height;
    final iconSize = (shortest * 0.42).clamp(24.0, 96.0);
    final fontScale = (shortest / 56).clamp(0.85, 1.9);

    final content = _content(context, iconSize, fontScale);

    return LongPressDraggable<String>(
      data: app.packageName,
      feedback: _feedback(width, height, content),
      childWhenDragging: Opacity(opacity: 0.25, child: content),
      onDragEnd: (details) => _onDrop(details),
      child: content,
    );
  }

  Widget _content(BuildContext context, double iconSize, double fontScale) {
    final color = _tileColor(app.appName);
    final tappable = Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchApp(context, app.packageName),
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 10,
              right: 26,
              child: AppIcon(
                packageName: app.packageName,
                label: app.appName,
                size: iconSize,
              ),
            ),
            Positioned(
              left: 10,
              right: 8,
              bottom: 8,
              child: Text(
                app.appName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (12 * fontScale).clamp(11.0, 20.0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: tappable),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: () => _showTileMenu(context),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.more_vert,
                  size: 16, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _feedback(double width, double height, Widget child) {
    return SizedBox(
      width: width,
      height: height,
      child: Opacity(opacity: 0.85, child: child),
    );
  }

  void _onDrop(DraggableDetails details) {
    final box = boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final col = ((local.dx - pad) / (cellW + gap)).round();
    final row = ((local.dy - pad) / (cellW + gap)).round();
    state.moveTile(app.packageName, col, row);
  }

  void _showTileMenu(BuildContext context) {
    final meta = state.metaFor(app.packageName);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.rocket_launch_outlined),
                title: const Text('启动'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchApp(context, app.packageName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio),
                title: const Text('调整尺寸'),
                subtitle: Text('当前 ${meta.tileW} × ${meta.tileH}（一行 $kTileCols 格）'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSizePicker(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('应用详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AppDetailScreen(packageName: app.packageName),
                    ),
                  );
                },
              ),
              if (state.tilePages.length > 1)
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('移动到页面…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveToPage(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('取消置顶'),
                onTap: () {
                  state.togglePinned(app.packageName);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSizePicker(BuildContext context) async {
    final meta = state.metaFor(app.packageName);
    var w = meta.tileW;
    var h = meta.tileH;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('调整磁贴尺寸'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepper(
                label: '宽',
                value: w,
                min: 1,
                max: kTileCols,
                onChanged: (v) => setLocal(() => w = v),
              ),
              const SizedBox(height: 8),
              _stepper(
                label: '高',
                value: h,
                min: 1,
                max: kTileMaxH,
                onChanged: (v) => setLocal(() => h = v),
              ),
              const SizedBox(height: 12),
              Text('1 行 = $kTileCols 格，例如 2×2、1×3、4×4',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                state.setTileSize(app.packageName, w, h);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 32, child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Future<void> _moveToPage(BuildContext context) async {
    final others =
        state.tilePages.where((p) => p.id != page.id).toList();
    final target = await showModalBottomSheet<TilePage>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('移动到',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...others.map((p) => ListTile(
                  leading: const Icon(Icons.grid_view_rounded),
                  title: Text(p.name),
                  trailing: Text('${state.pinCountOnPage(p)}'),
                  onTap: () => Navigator.pop(ctx, p),
                )),
          ],
        ),
      ),
    );
    if (target != null) {
      await state.assignPinToPage(app.packageName, target.id);
    }
  }

  Color _tileColor(String label) {
    final hash = label.codeUnits.fold<int>(0, (p, c) => p * 31 + c);
    final hue = (hash % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.42).toColor();
  }
}

// ---------------------------------------------------------------- 收藏

class _FavoritesTab extends StatefulWidget {
  const _FavoritesTab({required this.state});
  final AppState state;

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final favorites = state.favorites;

    final results = _query.trim().isEmpty
        ? <AppInfo>[]
        : state.apps
            .where((a) =>
                a.appName.toLowerCase().contains(_query.toLowerCase()) ||
                a.packageName.toLowerCase().contains(_query.toLowerCase()))
            .take(12)
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: '搜索任意应用并立即启动',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_query.trim().isNotEmpty)
          Expanded(child: _resultList(state, results))
        else
          Expanded(child: _favoritesGrid(state, favorites)),
      ],
    );
  }

  Widget _resultList(AppState state, List<AppInfo> results) {
    if (results.isEmpty) {
      return const Center(child: Text('没有找到匹配的应用'));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final app = results[i];
        return ListTile(
          leading: AppIcon(packageName: app.packageName, label: app.appName),
          title: Text(app.appName),
          subtitle:
              Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.rocket_launch_outlined),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            launchApp(context, app.packageName);
          },
        );
      },
    );
  }

  Widget _favoritesGrid(AppState state, List<AppInfo> favorites) {
    if (favorites.isEmpty) {
      return _hint(
        context,
        icon: Icons.star_outline,
        text: '还没有收藏的应用\n在应用列表点击 ⭐ 收藏，即可在这里一键启动',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, i) {
        final app = favorites[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => launchApp(context, app.packageName),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailScreen(packageName: app.packageName),
            ),
          ),
          child: Column(
            children: [
              AppIcon(packageName: app.packageName, label: app.appName, size: 56),
              const SizedBox(height: 8),
              Text(
                app.appName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 最近

class _RecentTab extends StatelessWidget {
  const _RecentTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final apps = state.recentApps;
    if (apps.isEmpty) {
      return _hint(
        context,
        icon: Icons.history,
        text: '还没有启动记录\n从囤囤里启动应用后会出现在这里',
      );
    }
    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        final meta = state.metaFor(app.packageName);
        return ListTile(
          leading: AppIcon(packageName: app.packageName, label: app.appName),
          title: Text(app.appName),
          subtitle: Text('上次启动 ${Fmt.relative(meta.lastLaunchedAt)}'),
          trailing: const Icon(Icons.rocket_launch_outlined, size: 20),
          onTap: () => launchApp(context, app.packageName),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailScreen(packageName: app.packageName),
            ),
          ),
        );
      },
    );
  }
}

Widget _hint(BuildContext context,
    {required IconData icon, required String text}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    ),
  );
}
