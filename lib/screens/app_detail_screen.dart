import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/category.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_tile.dart';

class AppDetailScreen extends StatefulWidget {
  const AppDetailScreen({super.key, required this.packageName});

  final String packageName;

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  late final TextEditingController _reason;
  late final TextEditingController _note;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final meta = state.metaFor(widget.packageName);
    _reason = TextEditingController(text: meta.reason);
    _note = TextEditingController(text: meta.note);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    context.read<AppState>().persistMeta();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  String _currentPageName(AppState state) {
    final pages = state.tilePages;
    if (pages.isEmpty) return '无磁贴页';
    final i = state.currentTilePageIndex.clamp(0, pages.length - 1);
    return pages[i].name;
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) context.read<AppState>().persistMeta();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final meta = state.metaFor(widget.packageName);
    final app = state.appByPackage(widget.packageName);
    final name = app?.appName ?? widget.packageName;
    final pinLocations = state.pinLocationsFor(widget.packageName);
    final currentPinCount = state.pinCountOnCurrentPage(widget.packageName);

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          if (app != null)
            IconButton(
              tooltip: '应用信息',
              icon: const Icon(Icons.info_outline),
              onPressed: () => openAppInfo(context, widget.packageName),
            ),
          if (app != null && !app.isSystem)
            IconButton(
              tooltip: '卸载',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => uninstallApp(context, widget.packageName, name),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(app: app, packageName: widget.packageName, name: name),
          const SizedBox(height: 16),
          if (app != null)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => launchApp(context, widget.packageName),
                    icon: const Icon(Icons.rocket_launch),
                    label: const Text('启动'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        state.updateMeta(widget.packageName, favorite: !meta.favorite),
                    icon: Icon(meta.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded),
                    label: Text(meta.favorite ? '已收藏' : '收藏'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          _SectionTitle('固定到磁贴'),
          if (pinLocations.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text('尚未固定到任何磁贴页', style: TextStyle(fontSize: 13)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (page, count) in pinLocations)
                    InputChip(
                      avatar: const Icon(Icons.push_pin, size: 16),
                      label: Text(
                        count > 1 ? '${page.name} ×$count' : page.name,
                      ),
                      onDeleted: () =>
                          state.removeTilesOnPage(widget.packageName, page.id),
                    ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: currentPinCount > 0,
            onChanged: (v) => v
                ? state.addTile(widget.packageName,
                    pageId: state.currentTilePageId)
                : state.removeTilesOnCurrentPage(widget.packageName),
            title: Text('固定到当前页「${_currentPageName(state)}」'),
            subtitle: currentPinCount > 1
                ? Text('当前页已有 $currentPinCount 份（可多份）')
                : const Text('在当前磁贴页显示'),
          ),
          const SizedBox(height: 12),
          _SectionTitle('安装原因'),
          TextField(
            controller: _reason,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: '为什么安装它？例如：薅羊毛、工作需要、朋友推荐…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              state.metaFor(widget.packageName).reason = v;
              _schedulePersist();
            },
          ),
          const SizedBox(height: 20),
          _SectionTitle('备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: '其它想记录的信息',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              state.metaFor(widget.packageName).note = v;
              _schedulePersist();
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SectionTitle('分类'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _createCategory(context, state),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建分类'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.categories.map((c) {
              final selected = meta.categoryIds.contains(c.id);
              return FilterChip(
                label: Text('${c.emoji} ${c.name}'),
                selected: selected,
                onSelected: (v) {
                  final ids = List<String>.from(meta.categoryIds);
                  if (v) {
                    ids.add(c.id);
                  } else {
                    ids.remove(c.id);
                  }
                  state.updateMeta(widget.packageName, categoryIds: ids);
                },
              );
            }).toList(),
          ),
          if (state.categories.isEmpty)
            Text('还没有分类，点击「新建分类」创建一个吧',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 24),
          if (app != null) _InfoTable(app: app),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await state.clearMeta(widget.packageName);
              if (!context.mounted) return;
              _reason.clear();
              _note.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除该应用的自定义信息')),
              );
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('清除该应用的自定义信息'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _createCategory(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分类名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      final c = await state.addCategory(name.trim());
      final meta = state.metaFor(widget.packageName);
      final ids = List<String>.from(meta.categoryIds)..add(c.id);
      await state.updateMeta(widget.packageName, categoryIds: ids);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.packageName, required this.name});

  final AppInfo? app;
  final String packageName;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(packageName: packageName, label: name, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(packageName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (app != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (app!.versionName.isNotEmpty)
                      CategoryChip(
                        category: AppCategory(
                            id: '_v', name: 'v${app!.versionName}', emoji: '🏷️'),
                      ),
                    if (app!.isSystem)
                      CategoryChip(
                        category:
                            AppCategory(id: '_s', name: '系统应用', emoji: '⚙️'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.app});
  final AppInfo app;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('安装时间', Fmt.dateTime(app.firstInstallTime)),
      ('更新时间', Fmt.dateTime(app.lastUpdateTime)),
      ('大小', Fmt.size(app.sizeBytes)),
      ('版本号', '${app.versionName} (${app.versionCode})'),
      ('targetSdk', '${app.targetSdk}'),
      ('minSdk', '${app.minSdk}'),
      ('UID', '${app.uid}'),
      ('APK 路径', app.apkPath),
    ];
    return Card(
      elevation: 0,
      color: Colors.grey.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: rows
              .map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(r.$1,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13)),
                        ),
                        Expanded(
                          child: SelectableText(r.$2,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
