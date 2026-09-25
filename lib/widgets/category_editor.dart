import 'package:flutter/material.dart';

import '../models/category.dart';
import '../state/app_state.dart';

const List<int> kCategoryPalette = [
  0xFF6C8CFF,
  0xFFF0A030,
  0xFF4CAF50,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF795548,
];

const List<String> kCategoryEmojiChoices = [
  '📦',
  '🎮',
  '🛠️',
  '💰',
  '📷',
  '🎵',
  '📚',
  '🛒',
  '💬',
  '🏦',
  '🚀',
  '❤️',
];

/// Create or edit a category. Pass null [existing] to create a new one.
Future<void> showCategoryEditor(
  BuildContext context,
  AppState state,
  AppCategory? existing,
) async {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final emojiController = TextEditingController(
    text: existing?.emoji ?? kCategoryEmojiChoices.first,
  );
  var color = existing?.colorValue ?? kCategoryPalette.first;
  var emoji = existing?.emoji ?? kCategoryEmojiChoices.first;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(existing == null ? '新建分类' : '编辑分类'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: kCategoryPalette.map((p) {
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(color).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: emojiController,
                      decoration: const InputDecoration(
                        labelText: '自定义 Emoji',
                        hintText: '粘贴或输入一个 Emoji',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final chars = v.trim().characters;
                        if (chars.isEmpty) return;
                        setLocal(() => emoji = chars.first);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCategoryEmojiChoices.map((e) {
                  final selected = e == emoji;
                  return GestureDetector(
                    onTap: () {
                      emojiController.text = e;
                      setLocal(() => emoji = e);
                    },
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              if (existing == null) {
                await state.addCategory(name, colorValue: color, emoji: emoji);
              } else {
                await state.updateCategory(
                  existing,
                  name: name,
                  colorValue: color,
                  emoji: emoji,
                );
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

Future<void> confirmDeleteCategory(
  BuildContext context,
  AppState state,
  AppCategory c,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除分类'),
      content: Text('删除「${c.name}」后，应用上的该分类也会移除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok == true) await state.deleteCategory(c.id);
}
