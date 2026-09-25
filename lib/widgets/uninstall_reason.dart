import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/app_meta.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'app_icon.dart';

const List<String> kUninstallReasonPresets = [
  '不好用',
  '太占空间',
  '找到替代品',
  '广告太多',
  '不再需要',
  '闪退/故障',
  '隐私担忧',
  '已换设备',
];

/// Dialog to record why an app was uninstalled.
Future<void> showUninstallReasonDialog(
  BuildContext context,
  AppState state,
  String packageName,
  String appName,
) async {
  final meta = state.metaFor(packageName);
  final controller = TextEditingController(text: meta.uninstallReason);
  final s = context.strings;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(s.t('卸载原因 · {name}', {'name': appName}),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: s.t('为什么卸载它？'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kUninstallReasonPresets.map((r) {
                  return ActionChip(
                    label: Text(s.t(r), style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      controller.text = s.t(r);
                      setLocal(() {});
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(s.t('清除原因')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(s.t('保存')),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  await state.updateMeta(packageName, uninstallReason: result);
}

/// Bottom sheet shown after a scan detects uninstalls, letting the user
/// annotate each removed app with a reason.
class UninstallReasonSheet extends StatelessWidget {
  const UninstallReasonSheet({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _build(context, state.pendingUninstalls),
    );
  }

  Widget _build(BuildContext context, List<AppMeta> items) {
    final s = context.strings;
    if (items.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(s.t('已全部处理'))),
        ),
      );
    }
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.t('检测到 {n} 个应用被卸载', {'n': items.length}),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.t('对比上次快照后发现以下应用已不在设备上，可以为它们记录卸载原因。'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final m = items[i];
                return ListTile(
                  leading: AppIcon(
                    packageName: m.packageName,
                    label: m.lastKnownName.isEmpty
                        ? m.packageName
                        : m.lastKnownName,
                    size: 40,
                  ),
                  title: Text(
                    m.lastKnownName.isEmpty ? m.packageName : m.lastKnownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    m.uninstallReason.isEmpty
                        ? s.t('{pkg}\n点击添加卸载原因', {'pkg': m.packageName})
                        : s.t('原因：{reason}', {'reason': m.uninstallReason}),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.uninstallReason.isEmpty
                          ? Colors.grey.shade600
                          : Colors.grey.shade800,
                    ),
                  ),
                  isThreeLine: m.uninstallReason.isEmpty,
                  trailing: Icon(
                    m.uninstallReason.isEmpty
                        ? Icons.edit_outlined
                        : Icons.check_circle,
                    color: m.uninstallReason.isEmpty
                        ? Colors.grey
                        : Colors.green,
                  ),
                  onTap: () => showUninstallReasonDialog(
                    context,
                    state,
                    m.packageName,
                    m.lastKnownName.isEmpty ? m.packageName : m.lastKnownName,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  state.clearPendingUninstalls();
                  Navigator.pop(context);
                },
                child: Text(s.t('完成')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tile for the "已卸载" list.
class UninstalledTile extends StatelessWidget {
  const UninstalledTile({super.key, required this.meta, required this.state});

  final AppMeta meta;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final name = meta.lastKnownName.isEmpty ? meta.packageName : meta.lastKnownName;
    return ListTile(
      leading: AppIcon(packageName: meta.packageName, label: name, size: 44),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.current.t('卸载于 {date}', {
              'date': Fmt.dateTime(meta.uninstalledAt),
            }),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (meta.uninstallReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('🗑️ ${meta.uninstallReason}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
            ),
        ],
      ),
      trailing: Icon(
        meta.uninstallReason.isEmpty ? Icons.edit_outlined : Icons.edit,
        color: Colors.grey,
      ),
      onTap: () => showUninstallReasonDialog(
          context, state, meta.packageName, name),
    );
  }
}
