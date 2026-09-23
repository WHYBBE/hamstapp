import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
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

class _TilesTab extends StatelessWidget {
  const _TilesTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final apps = state.pinnedApps;
    if (apps.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '还没有磁贴\n点击右上角 ➕ 选择要置顶的应用',
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
      itemBuilder: (context, i) => _Tile(app: apps[i], state: state),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.app, required this.state});
  final AppInfo app;
  final AppState state;

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
