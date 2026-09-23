import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/tile_page.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
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
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) =>
                _PageGrid(state: state, page: pages[i]),
          ),
        ),
        _PageBar(
          state: state,
          currentIndex: _index,
          onSelect: (i) {
            setState(() => _index = i);
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
            setState(() => _index = idx);
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

class _PageGrid extends StatelessWidget {
  const _PageGrid({required this.state, required this.page});
  final AppState state;
  final TilePage page;

  @override
  Widget build(BuildContext context) {
    final apps = state.pinsOnPage(page);
    if (apps.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '「${page.name}」还没有磁贴\n点击右上角 ➕ 选择要置顶的应用',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) =>
          _Tile(app: apps[i], state: state, page: page),
    );
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
  const _Tile({required this.app, required this.state, required this.page});
  final AppInfo app;
  final AppState state;
  final TilePage page;

  @override
  Widget build(BuildContext context) {
    final color = _tileColor(app.appName);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchApp(context, app.packageName),
        onLongPress: () => _showTileMenu(context),
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 10,
              child: AppIcon(
                packageName: app.packageName,
                label: app.appName,
                size: 44,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                app.appName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
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
              leading: const Icon(Icons.info_outline),
              title: const Text('应用详情'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppDetailScreen(packageName: app.packageName),
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
