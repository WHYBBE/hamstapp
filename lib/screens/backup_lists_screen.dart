import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/backup_list.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_tile.dart';
import '../widgets/uninstall_reason.dart';

class BackupListsScreen extends StatelessWidget {
  const BackupListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final lists = [...state.backupLists]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, state),
        icon: const Icon(Icons.playlist_add),
        label: const Text('新建备份列表'),
      ),
      body: lists.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('还没有备份列表。\n把重要 / 想长期跟踪的应用放进列表，\n随时知道它们是否还在设备上。',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: lists.length,
              itemBuilder: (context, i) {
                final b = lists[i];
                final installed = b.packageNames
                    .where((p) => state.appByPackage(p) != null)
                    .length;
                final missing = b.packageNames.length - installed;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                  title: Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${b.packageNames.length} 个应用 · 已安装 $installed'
                    '${missing > 0 ? ' · 缺失 $missing' : ''}\n'
                    '更新于 ${Fmt.dateTime(b.updatedAt)}'
                    '${b.description.isNotEmpty ? ' · ${b.description}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _onAction(context, state, b, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('打开')),
                      PopupMenuItem(value: 'backup', child: Text('备份当前全部应用')),
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                  onTap: () => _openDetail(context, state, b),
                );
              },
            ),
    );
  }

  Future<void> _create(BuildContext context, AppState state) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建备份列表'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: '名称', hintText: '例如：常用工具、必装应用'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '描述（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (created != true) return;
    final b = await state.addBackupList(nameController.text.trim(),
        description: descController.text.trim());
    if (!context.mounted) return;
    _openDetail(context, state, b);
  }

  Future<void> _onAction(
      BuildContext context, AppState state, BackupList b, String action) async {
    switch (action) {
      case 'open':
        _openDetail(context, state, b);
        break;
      case 'backup':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('备份当前全部应用'),
            content: Text(
                '将把当前扫描到的 ${state.apps.length} 个应用全部加入「${b.name}」，'
                '并替换原有内容。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确定')),
            ],
          ),
        );
        if (ok == true) await state.backupCurrentApps(b.id);
        break;
      case 'rename':
        final controller = TextEditingController(text: b.name);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('重命名'),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('保存')),
            ],
          ),
        );
        if (name != null && name.isNotEmpty) {
          await state.updateBackupList(b, name: name);
        }
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除备份列表'),
            content: Text('确定删除「${b.name}」吗？'),
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
        if (ok == true) await state.deleteBackupList(b.id);
        break;
    }
  }

  void _openDetail(BuildContext context, AppState state, BackupList b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BackupListDetailScreen(listId: b.id)),
    );
  }
}

class BackupListDetailScreen extends StatelessWidget {
  const BackupListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = state.backupLists.firstWhere((b) => b.id == listId);
    final members = list.packageNames
        .map((p) => state.appByPackage(p))
        .whereType<AppInfo>()
        .toList();

    final missing = list.packageNames
        .where((p) => state.appByPackage(p) == null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(list.name),
        actions: [
          IconButton(
            tooltip: '添加应用',
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSheet(context, state, list),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '共 ${list.packageNames.length} 个 · 已安装 ${members.length} · 缺失 ${missing.length}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          if (list.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(list.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
          const Divider(),
          ...members.map((app) => AppListTile(
                app: app,
                state: state,
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '移出列表',
                  onPressed: () =>
                      state.toggleBackupMember(list.id, app.packageName),
                ),
              )),
          if (missing.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('未安装 / 已卸载 (${missing.length})',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700)),
            ),
            ...missing.map((p) {
              final meta = state.metaFor(p);
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22FF0000),
                  child: Icon(Icons.help_outline, color: Colors.redAccent),
                ),
                title: Text(
                  meta.lastKnownName.isEmpty ? p : meta.lastKnownName,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  meta.uninstallReason.isNotEmpty
                      ? '🗑️ ${meta.uninstallReason}\n$p'
                      : (meta.reason.isNotEmpty
                          ? '安装原因：${meta.reason}\n$p'
                          : '$p\n该应用当前不在设备上，点击记录卸载原因'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => showUninstallReasonDialog(
                  context,
                  state,
                  p,
                  meta.lastKnownName.isEmpty ? p : meta.lastKnownName,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => state.toggleBackupMember(list.id, p),
                ),
              );
            }),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, AppState state, BackupList list) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final apps = state.apps
                .where((a) =>
                    !list.packageNames.contains(a.packageName) &&
                    (query.isEmpty ||
                        a.appName.toLowerCase().contains(query.toLowerCase()) ||
                        a.packageName
                            .toLowerCase()
                            .contains(query.toLowerCase())))
                .take(100)
                .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              builder: (ctx, scrollController) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: InputDecoration(
                        hintText: '搜索要加入的应用',
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
                        return ListTile(
                          leading: AppIcon(
                              packageName: app.packageName, label: app.appName),
                          title: Text(app.appName),
                          subtitle: Text(app.packageName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () {
                            state.toggleBackupMember(
                                list.id, app.packageName);
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
}
