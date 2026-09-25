import 'package:flutter/material.dart';

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
          child: Text('还没有分类。\n点击右上角新建一个，再到应用详情里给应用归类。',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.categories.length,
      itemBuilder: (context, i) {
        final c = state.categories[i];
        final count = state.apps
            .where((a) => state.metaFor(a.packageName).categoryIds.contains(c.id))
            .length;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(c.colorValue).withValues(alpha: 0.18),
            child: Text(c.emoji),
          ),
          title:
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
          onTap: () => showCategoryApps(context, state, c),
        );
      },
    );
  }
}

void showCategoryApps(BuildContext context, AppState state, AppCategory c) {
  final apps = state.apps
      .where((a) => state.metaFor(a.packageName).categoryIds.contains(c.id))
      .toList()
    ..sort(
        (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${c.emoji} ${c.name}')),
        body: apps.isEmpty
            ? const Center(child: Text('该分类下还没有应用'))
            : ListView.builder(
                itemCount: apps.length,
                itemBuilder: (context, i) {
                  final app = apps[i];
                  return ListTile(
                    leading: AppIcon(
                        packageName: app.packageName, label: app.appName),
                    title: Text(app.appName),
                    subtitle: Text(app.packageName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing:
                        const Icon(Icons.rocket_launch_outlined, size: 20),
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
      ),
    ),
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
          final pageIndex =
              pages.isEmpty ? -1 : state.currentTilePageIndex.clamp(0, pages.length - 1);
          final pageName = pageIndex < 0 ? '（无磁贴页）' : pages[pageIndex].name;

          void snack(String text) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(
              content: Text(text),
              duration: const Duration(milliseconds: 900),
            ));
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
                        const Text('固定到磁贴',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
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
                      final count =
                          state.pinCountOnCurrentPage(app.packageName);
                      final pinned = count > 0;
                      return ListTile(
                        leading: AppIcon(
                            packageName: app.packageName, label: app.appName),
                        title: Text(app.appName),
                        subtitle: Text(app.packageName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: pinned
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.push_pin,
                                      color: Colors.orange, size: 18),
                                  if (count > 1) ...[
                                    const SizedBox(width: 4),
                                    Text('×$count'),
                                  ],
                                ],
                              )
                            : const Icon(Icons.add_circle_outline,
                                color: Colors.grey),
                        onTap: () {
                          if (pinned) {
                            state.removeOneTileOnCurrentPage(app.packageName);
                            setLocal(() {});
                            snack('已取消固定');
                          } else {
                            state.addTile(app.packageName,
                                pageId: state.currentTilePageId);
                            setLocal(() {});
                            snack('已固定到「$pageName」');
                          }
                        },
                        onLongPress: () {
                          state.addTile(app.packageName,
                              pageId: state.currentTilePageId);
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
