import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/remote_source.dart';
import '../services/native_apps.dart';
import '../services/remote_client.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_icon.dart';
import 'remote_source_screen.dart';

/// Remote APK sync: one tab per configured source (FTP / Samba / WebDAV),
/// recursive listing with one-tap install.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with TickerProviderStateMixin {
  TabController? _tabs;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  TabController _controllerFor(AppState state, List<RemoteSource> sources) {
    final activeIndex = () {
      final i = sources.indexWhere((s) => s.id == state.activeSyncSourceId);
      return i < 0 ? 0 : i;
    }();
    if (_tabs == null || _tabs!.length != sources.length) {
      _tabs?.dispose();
      _tabs = TabController(
        length: sources.length,
        vsync: this,
        initialIndex: activeIndex,
      );
      _tabs!.addListener(() {
        if (!mounted || _tabs == null || _tabs!.indexIsChanging) return;
        final st = context.read<AppState>();
        final list = st.syncSources;
        final i = _tabs!.index;
        if (i >= 0 && i < list.length && st.activeSyncSourceId != list[i].id) {
          st.setActiveSyncSource(list[i].id);
        }
      });
    }
    return _tabs!;
  }

  Future<void> _openEditor(RemoteSource? source) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SyncSourceEditScreen(source: source)),
    );
  }

  Future<void> _confirmDelete(AppState state, RemoteSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除同步源'),
        content: Text('确定删除「${source.displayName}」吗？'),
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
    if (ok == true) await state.removeSyncSource(source.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = state.syncSources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('同步', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: '新建同步源',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(null),
          ),
          if (sources.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) {
                final active = state.remoteSource;
                if (v == 'edit') {
                  _openEditor(active);
                } else if (v == 'delete') {
                  _confirmDelete(state, active);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('编辑当前源'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除当前源'),
                  ),
                ),
              ],
            ),
        ],
        bottom: sources.isEmpty
            ? null
            : TabBar(
                controller: _controllerFor(state, sources),
                isScrollable: true,
                tabs: [for (final s in sources) Tab(text: s.displayName)],
              ),
      ),
      body: sources.isEmpty
          ? _EmptySync(onAdd: () => _openEditor(null))
          : TabBarView(
              controller: _controllerFor(state, sources),
              children: [
                for (final s in sources)
                  _SyncSourceTab(key: ValueKey(s.id), source: s),
              ],
            ),
    );
  }
}

class _EmptySync extends StatelessWidget {
  const _EmptySync({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_sync_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('还没有同步源', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              '添加局域网 / NAS 上的 FTP、Samba 或 WebDAV 目录，\n自动递归查找其中的 APK 并一键安装。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新建同步源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncSourceTab extends StatefulWidget {
  const _SyncSourceTab({super.key, required this.source});
  final RemoteSource source;

  @override
  State<_SyncSourceTab> createState() => _SyncSourceTabState();
}

class _SyncSourceTabState extends State<_SyncSourceTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  String? _error;
  final Set<String> _installing = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SyncSourceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id ||
        oldWidget.source.summary != widget.source.summary) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await RemoteClient.list(widget.source);
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _install(Map<String, dynamic> f) async {
    final key = (f['path'] as String?) ?? (f['name'] as String? ?? '');
    setState(() => _installing.add(key));
    try {
      final local = await RemoteClient.download(widget.source, f);
      final ok = await NativeApps.installApk(local);
      if (!ok) throw StateError('无法调起系统安装器');
      _snack('已交给系统安装器：${f['name']}');
    } catch (e) {
      _snack('安装失败：$e');
    } finally {
      if (mounted) setState(() => _installing.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();

    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        text: '加载失败\n$_error',
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_files.isEmpty) {
      return _Message(
        icon: Icons.folder_open,
        text: '没有找到 APK\n${widget.source.summary}',
        actionLabel: '刷新',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _files.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _SourceHeader(source: widget.source, count: _files.length);
          }
          final f = _files[i - 1];
          final name = f['name'] as String? ?? '';
          final rel = (f['rel'] as String?) ?? name;
          final size = (f['size'] as num?)?.toInt() ?? 0;
          final hit = _matchInstalled(state.apps, name);
          final key = (f['path'] as String?) ?? name;
          final installing = _installing.contains(key);
          return ListTile(
            leading: hit != null
                ? AppIcon(packageName: hit.packageName, label: hit.appName)
                : const CircleAvatar(child: Icon(Icons.android)),
            title: Text(rel == name ? name : rel),
            subtitle: Text([
              Fmt.size(size),
              if (hit != null)
                '已安装：${hit.appName}'
                    '${hit.versionName.isEmpty ? '' : ' v${hit.versionName}'}',
            ].join(' · ')),
            trailing: installing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: hit == null ? '安装' : '更新',
                    icon: const Icon(Icons.download_for_offline_outlined),
                    onPressed: () => _install(f),
                  ),
            onTap: installing ? null : () => _install(f),
          );
        },
      ),
    );
  }

  static AppInfo? _matchInstalled(List<AppInfo> apps, String fileName) {
    final lower = fileName.toLowerCase();
    for (final a in apps) {
      final pkg = a.packageName.toLowerCase();
      if (pkg.isNotEmpty && lower.contains(pkg)) return a;
    }
    return null;
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({required this.source, required this.count});
  final RemoteSource source;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现 $count 个 APK',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            source.summary,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String text;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
