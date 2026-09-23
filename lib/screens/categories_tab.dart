import 'package:flutter/material.dart';

import '../models/category.dart';
import '../state/app_state.dart';
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
                itemBuilder: (context, i) => ListTile(
                  leading: AppIcon(
                      packageName: apps[i].packageName, label: apps[i].appName),
                  title: Text(apps[i].appName),
                  subtitle: Text(apps[i].packageName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AppDetailScreen(packageName: apps[i].packageName),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

/// Bottom sheet to add pinned (tile) apps.
void showPinSheet(BuildContext context, AppState state) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final apps = state.apps
              .where((a) =>
                  query.isEmpty ||
                  a.appName.toLowerCase().contains(query.toLowerCase()) ||
                  a.packageName.toLowerCase().contains(query.toLowerCase()))
              .take(150)
              .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (ctx, scrollController) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('选择要置顶到磁贴的应用',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
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
                      final pinned = state.metaFor(app.packageName).pinned;
                      return ListTile(
                        leading: AppIcon(
                            packageName: app.packageName, label: app.appName),
                        title: Text(app.appName),
                        subtitle: Text(app.packageName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Icon(
                          pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          color: pinned ? Colors.orange : Colors.grey,
                        ),
                        onTap: () {
                          state.togglePinned(app.packageName);
                          setLocal(() {});
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
