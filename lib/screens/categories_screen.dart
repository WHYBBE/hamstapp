import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../state/app_state.dart';
import '../widgets/app_icon.dart';

const _palette = [
  0xFF6C8CFF,
  0xFFF0A030,
  0xFF4CAF50,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF795548,
];

const _emojiChoices = ['📦', '🎮', '🛠️', '💰', '📷', '🎵', '📚', '🛒', '💬', '🏦', '🚀', '❤️'];

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCategory(context, state, null),
        icon: const Icon(Icons.add),
        label: const Text('新建分类'),
      ),
      body: state.categories.isEmpty
          ? _empty()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.categories.length,
              itemBuilder: (context, i) {
                final c = state.categories[i];
                final count = state.apps
                    .where((a) =>
                        state.metaFor(a.packageName).categoryIds.contains(c.id))
                    .length;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(c.colorValue).withValues(alpha: 0.18),
                    child: Text(c.emoji),
                  ),
                  title: Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$count 个应用'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editCategory(context, state, c);
                      if (v == 'delete') _deleteCategory(context, state, c);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                  onTap: () => _showCategoryApps(context, state, c),
                );
              },
            ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('还没有分类，点击右下角新建一个，\n然后在应用详情里给应用归类。',
            textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _editCategory(
      BuildContext context, AppState state, AppCategory? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var color = existing?.colorValue ?? _palette.first;
    var emoji = existing?.emoji ?? _emojiChoices.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? '新建分类' : '编辑分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: '名称', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _palette.map((p) {
                  final selected = p == color;
                  return GestureDetector(
                    onTap: () => setLocal(() => color = p),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(p),
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: Colors.black54, width: 3)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('图标'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emojiChoices.map((e) {
                  final selected = e == emoji;
                  return GestureDetector(
                    onTap: () => setLocal(() => emoji = e),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: selected
                            ? Color(color).withValues(alpha: 0.2)
                            : Colors.transparent,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                if (existing == null) {
                  await state.addCategory(name, colorValue: color, emoji: emoji);
                } else {
                  await state.updateCategory(existing,
                      name: name, colorValue: color, emoji: emoji);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(
      BuildContext context, AppState state, AppCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('删除「${c.name}」后，应用上的该分类也会移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await state.deleteCategory(c.id);
  }

  void _showCategoryApps(BuildContext context, AppState state, AppCategory c) {
    final apps = state.apps
        .where((a) => state.metaFor(a.packageName).categoryIds.contains(c.id))
        .toList()
      ..sort((a, b) =>
          a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
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
                        packageName: apps[i].packageName,
                        label: apps[i].appName),
                    title: Text(apps[i].appName),
                    subtitle: Text(apps[i].packageName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
        ),
      ),
    );
  }
}
