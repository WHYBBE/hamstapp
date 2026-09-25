import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import '../widgets/app_tile.dart';
import '../widgets/floating_nav.dart';
import '../widgets/uninstall_reason.dart';
import 'app_detail_screen.dart';
import 'sync_screen.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showUninstalled = state.filter == AppFilter.uninstalled;
    final apps = state.visibleApps;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: FloatingNavScope.activeOf(context)
            ? const FloatingNavButton()
            : null,
        title: Text(
          context.strings.t('应用'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: context.strings.t('同步远程 APK'),
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncScreen()),
            ),
          ),
          IconButton(
            tooltip: state.appsStatsText,
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.appsStatsText),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
            },
          ),
          state.scanning
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: context.strings.t('刷新应用列表'),
                  icon: const Icon(Icons.refresh),
                  onPressed: state.scan,
                ),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(state: state),
          _FilterRow(state: state),
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
                                  packageName: app.packageName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
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
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Center(child: Text(context.strings.t('还没有卸载记录'))),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.query,
  );
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
                hintText: context.strings.t('搜索应用名 / 包名 / 拼音首字母'),
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
    final s = context.strings;
    return PopupMenuButton<AppSort>(
      icon: const Icon(Icons.sort),
      tooltip: s.t('排序'),
      initialValue: state.sort,
      onSelected: (v) {
        state.sort = v;
        state.refresh();
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: AppSort.name, child: Text(s.t('按名称'))),
        PopupMenuItem(value: AppSort.installTime, child: Text(s.t('按安装时间'))),
        PopupMenuItem(value: AppSort.updateTime, child: Text(s.t('按更新时间'))),
        PopupMenuItem(value: AppSort.size, child: Text(s.t('按大小'))),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final labels = {
      AppFilter.all: s.t('全部'),
      AppFilter.favorite: '⭐${s.t('收藏')}',
      AppFilter.categorized: s.t('已分类'),
      AppFilter.uncategorized: s.t('未分类'),
      AppFilter.hasReason: s.t('有原因'),
      AppFilter.unorganized: '🫥${s.t('未整理')}',
      AppFilter.uninstalled: '🗑️${s.t('已卸载')}',
    };
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 12),
          _ScopeDropdown(state: state),
          const SizedBox(width: 4),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                ...labels.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: e.key == AppFilter.unorganized
                          ? s.t('未分组、无原因/备注，且未收藏、未固定到磁贴')
                          : '',
                      child: FilterChip(
                        label: Text(e.value),
                        selected: state.filter == e.key,
                        onSelected: (_) {
                          state.filter = e.key;
                          state.refresh();
                        },
                      ),
                    ),
                  ),
                ),
                if (state.categories.isNotEmpty) ...[
                  const VerticalDivider(width: 12),
                  ...state.categories.map(
                    (c) => Padding(
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
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed combo box for the app-type scope (全部/用户/系统). Independent of
/// the annotation filter radio group.
class _ScopeDropdown extends StatelessWidget {
  const _ScopeDropdown({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.strings;
    final (label, icon) = switch (state.scope) {
      AppScope.all => (s.t('全部'), Icons.apps),
      AppScope.user => (s.t('用户'), Icons.person_outline),
      AppScope.system => (s.t('系统'), Icons.settings_outlined),
    };
    final active = state.scope != AppScope.all;
    return PopupMenuButton<AppScope>(
      tooltip: s.t('应用类型'),
      initialValue: state.scope,
      onSelected: (v) {
        state.scope = v;
        state.refresh();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: AppScope.all,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.apps),
            title: Text(s.t('全部')),
          ),
        ),
        PopupMenuItem(
          value: AppScope.user,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(s.t('用户')),
          ),
        ),
        PopupMenuItem(
          value: AppScope.system,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text(s.t('系统')),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
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
                ? context.strings.t('扫描失败：{error}', {
                    'error': state.scanError,
                  })
                : state.scanning
                ? context.strings.t('正在扫描已安装应用…')
                : context.strings.t('没有匹配的应用'),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
