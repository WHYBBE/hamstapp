import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/snapshot.dart';
import '../models/snapshot_diff.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_icon.dart';
import '../widgets/uninstall_reason.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    required this.olderLabel,
    required this.newerLabel,
    required this.older,
    required this.newer,
  });

  final String olderLabel;
  final String newerLabel;
  final List<SnapshotEntry> older;
  final List<SnapshotEntry> newer;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late final SnapshotDiff _diff = SnapshotDiff.between(
    Snapshot(id: 'a', name: widget.olderLabel, createdAt: 0, entries: widget.older),
    Snapshot(id: 'b', name: widget.newerLabel, createdAt: 0, entries: widget.newer),
  );

  bool _showUnchanged = false;

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      Tab(text: '新增 ${_diff.added.length}'),
      Tab(text: '卸载 ${_diff.removed.length}'),
      Tab(text: '更新 ${_diff.updated.length}'),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('列表差异'),
          bottom: TabBar(
            tabs: tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
          ),
          actions: [
            IconButton(
              tooltip: _showUnchanged ? '隐藏未变化' : '显示未变化',
              icon: Icon(_showUnchanged ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _showUnchanged = !_showUnchanged),
            ),
          ],
        ),
        body: Column(
          children: [
            _CompareHeader(
              olderLabel: widget.olderLabel,
              newerLabel: widget.newerLabel,
              diff: _diff,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DiffList(items: _diff.added, emptyText: '没有新增应用', unchanged: _showUnchanged ? _diff.unchanged : null),
                  _DiffList(
                    items: _diff.removed,
                    emptyText: '没有卸载应用',
                    allowUninstallReason: true,
                  ),
                  _DiffList(items: _diff.updated, emptyText: '没有应用更新', showVersion: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader({
    required this.olderLabel,
    required this.newerLabel,
    required this.diff,
  });

  final String olderLabel;
  final String newerLabel;
  final SnapshotDiff diff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('基准：$olderLabel',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.arrow_forward, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('对比：$newerLabel',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '共 ${diff.changedCount} 处变化 · 新增 ${diff.added.length} · 卸载 ${diff.removed.length} · 更新 ${diff.updated.length}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _DiffList extends StatelessWidget {
  const _DiffList({
    required this.items,
    required this.emptyText,
    this.showVersion = false,
    this.unchanged,
    this.allowUninstallReason = false,
  });

  final List<DiffItem> items;
  final String emptyText;
  final bool showVersion;
  final List<DiffItem>? unchanged;
  final bool allowUninstallReason;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && (unchanged == null || unchanged!.isEmpty)) {
      return Center(child: Text(emptyText));
    }
    final state = allowUninstallReason ? context.watch<AppState>() : null;
    return ListView(
      children: [
        ...items.map((e) {
          final reason = allowUninstallReason
              ? state!.metaFor(e.packageName).uninstallReason
              : '';
          return _DiffTile(
            item: e,
            showVersion: showVersion,
            uninstallReason: reason,
            onEditReason: allowUninstallReason
                ? () => showUninstallReasonDialog(
                      context,
                      state!,
                      e.packageName,
                      e.appName,
                    )
                : null,
          );
        }),
        if (unchanged != null && unchanged!.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('未变化 (${unchanged!.length})',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
          ...unchanged!.map((e) => _DiffTile(item: e, showVersion: false)),
        ],
      ],
    );
  }
}

class _DiffTile extends StatelessWidget {
  const _DiffTile({
    required this.item,
    required this.showVersion,
    this.uninstallReason = '',
    this.onEditReason,
  });

  final DiffItem item;
  final bool showVersion;
  final String uninstallReason;
  final VoidCallback? onEditReason;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      DiffType.added => (Icons.add_circle, Colors.green),
      DiffType.removed => (Icons.remove_circle, Colors.red),
      DiffType.updated => (Icons.upgrade, Colors.blue),
      DiffType.unchanged => (Icons.check_circle_outline, Colors.grey),
    };

    final base = showVersion && item.fromVersion.isNotEmpty
        ? '${item.fromVersion}  →  ${item.toVersion}'
        : '${item.packageName}${item.sizeBytes > 0 ? ' · ${Fmt.size(item.sizeBytes)}' : ''}';

    return ListTile(
      leading: AppIcon(packageName: item.packageName, label: item.appName, size: 40),
      title: Text(item.appName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        uninstallReason.isNotEmpty ? '🗑️ $uninstallReason\n$base' : base,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: uninstallReason.isNotEmpty,
      trailing: onEditReason != null
          ? IconButton(
              tooltip: uninstallReason.isEmpty ? '添加卸载原因' : '编辑卸载原因',
              icon: Icon(
                uninstallReason.isEmpty ? Icons.edit_outlined : Icons.check_circle,
                color: uninstallReason.isEmpty ? Colors.grey : Colors.green,
              ),
              onPressed: onEditReason,
            )
          : Icon(icon, color: color),
    );
  }
}
