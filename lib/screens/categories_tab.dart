import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../utils/search.dart';
import '../widgets/app_icon.dart';
import '../widgets/category_editor.dart';
import 'app_detail_screen.dart';

class CategoriesTab extends StatelessWidget {
  const CategoriesTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.categories.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '还没有分类。\n点击右上角新建一个，再到应用详情里给应用归类。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.categories.length,
      itemBuilder: (context, i) {
        final c = state.categories[i];
        final count = state.apps
            .where(
              (a) => state.metaFor(a.packageName).categoryIds.contains(c.id),
            )
            .length;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(c.colorValue).withValues(alpha: 0.18),
            child: Text(c.emoji),
          ),
          title: Text(
            c.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('$count 个应用'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') showCategoryEditor(context, state, c);
              if (v == 'delete') confirmDeleteCategory(context, state, c);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryAppsScreen(state: state, category: c),
            ),
          ),
        );
      },
    );
  }
}

/// Apps inside a single category. Tap launches, long-press opens details, and
/// the AppBar "+" opens a searchable picker to add more apps to the category.
class CategoryAppsScreen extends StatelessWidget {
  const CategoryAppsScreen({
    super.key,
    required this.state,
    required this.category,
  });

  final AppState state;
  final AppCategory category;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final apps =
        s.apps
            .where(
              (a) => s.metaFor(a.packageName).categoryIds.contains(category.id),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('${category.emoji} ${category.name}'),
        actions: [
          IconButton(
            tooltip: '添加应用到该分类',
            icon: const Icon(Icons.add),
            onPressed: () => showCategoryPicker(context, s, category),
          ),
        ],
      ),
      body: apps.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '该分类下还没有应用\n点击右上角 ➕ 添加',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          : ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, i) {
                final app = apps[i];
                return ListTile(
                  leading: AppIcon(
                    packageName: app.packageName,
                    label: app.appName,
                  ),
                  title: Text(app.appName),
                  subtitle: Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '移出分类',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      final ids = List<String>.from(
                        s.metaFor(app.packageName).categoryIds,
                      )..remove(category.id);
                      s.updateMeta(app.packageName, categoryIds: ids);
                    },
                  ),
                  onTap: () => launchApp(context, app.packageName),
                  onLongPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AppDetailScreen(packageName: app.packageName),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Searchable sheet for toggling category membership. Tap a row to add or
/// remove the app from [category].
void showCategoryPicker(
  BuildContext context,
  AppState state,
  AppCategory category,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final apps = AppSearch.rank(state.apps, query, limit: 300);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (ctx, scrollController) {
              final memberCount = state.apps
                  .where(
                    (a) => state
                        .metaFor(a.packageName)
                        .categoryIds
                        .contains(category.id),
                  )
                  .length;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '添加到「${category.emoji} ${category.name}」',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '已添加 $memberCount 个应用 · 点击行切换',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: InputDecoration(
                        hintText: '搜索应用',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: apps.length,
                      itemBuilder: (context, i) {
                        final app = apps[i];
                        final inCat = state
                            .metaFor(app.packageName)
                            .categoryIds
                            .contains(category.id);
                        return ListTile(
                          leading: AppIcon(
                            packageName: app.packageName,
                            label: app.appName,
                          ),
                          title: Text(app.appName),
                          subtitle: Text(
                            app.packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: inCat
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.grey,
                                ),
                          onTap: () {
                            final ids = List<String>.from(
                              state.metaFor(app.packageName).categoryIds,
                            );
                            if (inCat) {
                              ids.remove(category.id);
                            } else {
                              ids.add(category.id);
                            }
                            state.updateMeta(app.packageName, categoryIds: ids);
                            setLocal(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

/// Bottom sheet to pin/unpin apps on the currently visible tile page.
///
/// Tap: pin when not pinned on this page, otherwise unpin (remove one).
/// Long-press: add another copy of the same app to this page.
void showPinSheet(BuildContext context, AppState state) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final apps = AppSearch.rank(state.apps, query, limit: 150);
          final pages = state.tilePages;
          final pageIndex = pages.isEmpty
              ? -1
              : state.currentTilePageIndex.clamp(0, pages.length - 1);
          final pageName = pageIndex < 0 ? '（无磁贴页）' : pages[pageIndex].name;

          void snack(String text) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(text),
                duration: const Duration(milliseconds: 900),
              ),
            );
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (ctx, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '固定到磁贴',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '当前页：$pageName · 点击固定/取消，长按再添加一个',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setLocal(() => query = v),
                    decoration: InputDecoration(
                      hintText: '搜索应用',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: apps.length,
                    itemBuilder: (context, i) {
                      final app = apps[i];
                      final count = state.pinCountOnCurrentPage(
                        app.packageName,
                      );
                      final pinned = count > 0;
                      return ListTile(
                        leading: AppIcon(
                          packageName: app.packageName,
                          label: app.appName,
                        ),
                        title: Text(app.appName),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: pinned
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.push_pin,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  if (count > 1) ...[
                                    const SizedBox(width: 4),
                                    Text('×$count'),
                                  ],
                                ],
                              )
                            : const Icon(
                                Icons.add_circle_outline,
                                color: Colors.grey,
                              ),
                        onTap: () {
                          if (pinned) {
                            state.removeOneTileOnCurrentPage(app.packageName);
                            setLocal(() {});
                            snack('已取消固定');
                          } else {
                            state.addTile(
                              app.packageName,
                              pageId: state.currentTilePageId,
                            );
                            setLocal(() {});
                            snack('已固定到「$pageName」');
                          }
                        },
                        onLongPress: () {
                          state.addTile(
                            app.packageName,
                            pageId: state.currentTilePageId,
                          );
                          setLocal(() {});
                          snack('已再添加一个到「$pageName」');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
