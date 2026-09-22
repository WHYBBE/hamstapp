import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_tile.dart';
import '../widgets/uninstall_reason.dart';
import 'app_detail_screen.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showUninstalled = state.filter == AppFilter.uninstalled;
    final apps = state.visibleApps;

    return Column(
      children: [
        _SearchBar(state: state),
        _FilterRow(state: state),
        _StatsBar(state: state, shown: showUninstalled ? state.uninstalledApps.length : apps.length),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.scan,
            child: showUninstalled
                ? _UninstalledList(state: state)
                : apps.isEmpty
                    ? _EmptyView(state: state)
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: apps.length,
                        itemBuilder: (context, i) {
                          final app = apps[i];
                          return AppListTile(
                            app: app,
                            state: state,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AppDetailScreen(
                                      packageName: app.packageName),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _UninstalledList extends StatelessWidget {
  const _UninstalledList({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.uninstalledApps;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Center(child: Text('还没有卸载记录')),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length,
      itemBuilder: (context, i) =>
          UninstalledTile(meta: items[i], state: state),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.state});
  final AppState state;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.state.query);
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => _focusNode.unfocus(),
              onSubmitted: (_) => _focusNode.unfocus(),
              onChanged: (v) {
                widget.state.query = v;
                widget.state.refresh();
              },
              decoration: InputDecoration(
                hintText: '搜索应用名 / 包名',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          widget.state.query = '';
                          widget.state.refresh();
                        },
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SortMenu(state: widget.state),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppSort>(
      icon: const Icon(Icons.sort),
      tooltip: '排序',
      initialValue: state.sort,
      onSelected: (v) {
        state.sort = v;
        state.refresh();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: AppSort.name, child: Text('按名称')),
        PopupMenuItem(value: AppSort.installTime, child: Text('按安装时间')),
        PopupMenuItem(value: AppSort.updateTime, child: Text('按更新时间')),
        PopupMenuItem(value: AppSort.size, child: Text('按大小')),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state});
  final AppState state;

  static const _labels = {
    AppFilter.all: '全部',
    AppFilter.user: '用户',
    AppFilter.system: '系统',
    AppFilter.favorite: '⭐收藏',
    AppFilter.categorized: '已分类',
    AppFilter.uncategorized: '未分类',
    AppFilter.hasReason: '有原因',
    AppFilter.unorganized: '🫥未整理',
    AppFilter.uninstalled: '🗑️已卸载',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          ..._labels.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(e.value),
                  selected: state.filter == e.key,
                  onSelected: (_) {
                    state.filter = e.key;
                    state.refresh();
                  },
                ),
              )),
          if (state.categories.isNotEmpty) ...[
            const VerticalDivider(width: 12),
            ...state.categories.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text('${c.emoji} ${c.name}'),
                    selected: state.filterCategoryId == c.id,
                    onSelected: (_) {
                      state.filterCategoryId =
                          state.filterCategoryId == c.id ? null : c.id;
                      state.refresh();
                    },
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.state, required this.shown});
  final AppState state;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final last = state.lastScanAt;
    final text = state.scanning
        ? '正在扫描…'
        : last == null
            ? '尚未扫描，下拉刷新'
            : state.filter == AppFilter.uninstalled
                ? '卸载记录 $shown 条 · 上次扫描 ${Fmt.relative(last.millisecondsSinceEpoch)}'
                : '共 ${state.apps.length} 个应用（用户 ${state.userAppCount} / 系统 ${state.systemAppCount}）'
                    ' · 显示 $shown · 用时 ${state.lastScanMs} ms · ${Fmt.relative(last.millisecondsSinceEpoch)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (state.scanning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            state.scanError != null
                ? '扫描失败：${state.scanError}'
                : state.scanning
                    ? '正在扫描已安装应用…'
                    : '没有匹配的应用',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
