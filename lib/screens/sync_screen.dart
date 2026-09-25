import 'dart:io';
import 'dart:typed_data';

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

  /// Bumped when the cache is cleared so open tabs reload their cache view.
  int _cacheEpoch = 0;

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

  Future<void> _confirmClearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除下载缓存'),
        content: const Text('删除已缓存的 APK 与信息，下次安装会重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final freed = await RemoteClient.clearCache();
    if (!mounted) return;
    setState(() => _cacheEpoch++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已清除缓存（${Fmt.size(freed)}）')));
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
                switch (v) {
                  case 'edit':
                    _openEditor(active);
                  case 'delete':
                    _confirmDelete(state, active);
                  case 'clear':
                    _confirmClearCache();
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
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.cleaning_services_outlined),
                    title: Text('清除下载缓存'),
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
                  _SyncSourceTab(
                    key: ValueKey(s.id),
                    source: s,
                    reloadToken: _cacheEpoch,
                  ),
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
  const _SyncSourceTab({
    super.key,
    required this.source,
    this.reloadToken = 0,
  });
  final RemoteSource source;
  final int reloadToken;

  @override
  State<_SyncSourceTab> createState() => _SyncSourceTabState();
}

class _SyncSourceTabState extends State<_SyncSourceTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _files = [];
  Map<String, Map<String, dynamic>> _cache = {};
  int _cacheBytes = 0;
  bool _loading = true;
  String? _error;
  final Set<String> _installing = {};
  final Map<String, double?> _progress = {};
  final Map<String, Uint8List?> _icons = {};

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
        oldWidget.source.summary != widget.source.summary ||
        oldWidget.reloadToken != widget.reloadToken) {
      _icons.clear();
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
      // Drop cached copies whose remote file changed or disappeared.
      try {
        await RemoteClient.pruneCache(widget.source, files);
      } catch (_) {}
      final cache = await RemoteClient.cacheIndex(widget.source);
      if (!mounted) return;
      setState(() {
        _files = files;
        _cache = cache;
        _cacheBytes = cache.values.fold(
          0,
          (sum, e) => sum + ((e['size'] as num?)?.toInt() ?? 0),
        );
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
    setState(() {
      _installing.add(key);
      _progress[key] = 0;
    });
    try {
      final local = await RemoteClient.download(
        widget.source,
        f,
        onProgress: (received, total) {
          if (!mounted || !_installing.contains(key)) return;
          setState(() {
            _progress[key] =
                total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          });
        },
      );
      // Refresh this entry's metadata/icon from the (now populated) cache.
      await _refreshCache();
      final ok = await NativeApps.installApk(local);
      if (!ok) throw StateError('无法调起系统安装器');
      _snack('已交给系统安装器：${f['name']}');
    } catch (e) {
      _snack('安装失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _installing.remove(key);
          _progress.remove(key);
        });
      }
    }
  }

  /// Downloads and parses an APK (without installing) so its full metadata
  /// and icon become visible in the list.
  Future<void> _fetchInfo(Map<String, dynamic> f) async {
    final key = (f['path'] as String?) ?? (f['name'] as String? ?? '');
    if (_installing.contains(key)) return;
    setState(() {
      _installing.add(key);
      _progress[key] = 0;
    });
    try {
      await RemoteClient.download(
        widget.source,
        f,
        onProgress: (received, total) {
          if (!mounted || !_installing.contains(key)) return;
          setState(() {
            _progress[key] =
                total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          });
        },
      );
      await _refreshCache();
      _snack('已获取 APK 信息');
    } catch (e) {
      _snack('获取信息失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _installing.remove(key);
          _progress.remove(key);
        });
      }
    }
  }

  Future<void> _refreshCache() async {
    final cache = await RemoteClient.cacheIndex(widget.source);
    if (!mounted) return;
    setState(() {
      _cache = cache;
      _cacheBytes = cache.values.fold(
        0,
        (sum, e) => sum + ((e['size'] as num?)?.toInt() ?? 0),
      );
    });
  }

  Future<Uint8List?> _iconFor(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (_icons.containsKey(path)) return _icons[path];
    try {
      final bytes = await File(path).readAsBytes();
      _icons[path] = bytes;
      return bytes;
    } catch (_) {
      _icons[path] = null;
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final byPkg = {
      for (final a in state.apps) a.packageName: a,
    };

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
            return _SourceHeader(
              source: widget.source,
              count: _files.length,
              cacheBytes: _cacheBytes,
            );
          }
          final f = _files[i - 1];
          return _buildItem(state, byPkg, f);
        },
      ),
    );
  }

  Widget _buildItem(
    AppState state,
    Map<String, AppInfo> byPkg,
    Map<String, dynamic> f,
  ) {
    final name = f['name'] as String? ?? '';
    final rel = (f['rel'] as String?) ?? name;
    final remoteSize = (f['size'] as num?)?.toInt() ?? 0;
    final remoteModified = (f['modified'] as num?)?.toInt() ?? 0;
    final key = (f['path'] as String?) ?? name;
    final meta = _cache[key];
    final installing = _installing.contains(key);
    final progress = _progress[key];

    // Package identity: prefer parsed APK metadata, fall back to filename.
    final pkg = (meta?['packageName'] as String?)?.trim() ?? '';
    final installed = pkg.isNotEmpty
        ? byPkg[pkg]
        : _matchInstalled(state.apps, name);

    final apkName = (meta?['appName'] as String?)?.trim() ?? '';
    final apkVersion = (meta?['versionName'] as String?)?.trim() ?? '';
    final apkVersionCode = (meta?['versionCode'] as num?)?.toInt() ?? 0;
    final minSdk = (meta?['minSdk'] as num?)?.toInt() ?? 0;
    final size = (meta?['size'] as num?)?.toInt() ?? remoteSize;

    final (status, statusColor) =
        _status(state, meta, installed, apkVersionCode, pkg.isNotEmpty);

    final title = rel == name ? name : rel;
    final subtitleLines = <String>[
      if (apkName.isNotEmpty) 'APK：$apkName',
      '${Fmt.size(size)}'
          '${remoteModified > 0 ? ' · ${Fmt.relative(remoteModified)}' : ''}',
      if (pkg.isNotEmpty) '包名：$pkg',
      if (apkVersion.isNotEmpty) '版本：$apkVersion${apkVersionCode > 0 ? ' ($apkVersionCode)' : ''}',
      if (installed != null)
        '已安装：${installed.appName} v${installed.versionName}',
      if (minSdk > 0) 'minSdk $minSdk',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: _leading(f, meta, installed, apkName),
          title: Text(title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitleLines.join('\n'),
              style: const TextStyle(height: 1.4),
            ),
          ),
          isThreeLine: subtitleLines.length > 2,
          trailing: installing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: installed == null ? '安装' : '更新',
                  icon: const Icon(Icons.download_for_offline_outlined),
                  onPressed: () => _install(f),
                ),
          onTap: installing ? null : () => _install(f),
          onLongPress: installing ? null : () => _fetchInfo(f),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: 8),
                Text(
                  '已缓存',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (installing && progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
            ),
          ),
      ],
    );
  }

  Widget _leading(
    Map<String, dynamic> f,
    Map<String, dynamic>? meta,
    AppInfo? installed,
    String apkName,
  ) {
    if (installed != null) {
      return AppIcon(packageName: installed.packageName, label: installed.appName);
    }
    final iconPath = meta?['iconPath'] as String?;
    if (iconPath != null && iconPath.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: _iconFor(iconPath),
        builder: (context, snap) => AppIcon(
          packageName: (meta?['packageName'] as String?) ?? '',
          label: apkName,
          bytes: snap.data,
        ),
      );
    }
    return const CircleAvatar(child: Icon(Icons.android));
  }

  /// Returns (label, color) describing the action for this APK.
  (String, Color) _status(
    AppState state,
    Map<String, dynamic>? meta,
    AppInfo? installed,
    int apkVersionCode,
    bool identityKnown,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (installed == null) {
      // Without parsed metadata we cannot tell whether it is a new app or a
      // package we simply could not match, so don't claim "新安装".
      if (!identityKnown) {
        return ('未获取信息（长按解析）', scheme.onSurfaceVariant);
      }
      return ('新安装', scheme.primary);
    }
    if (!identityKnown || apkVersionCode <= 0) {
      return ('更新（版本未知）', Colors.orange);
    }
    final currentCode = installed.versionCode;
    if (apkVersionCode > currentCode) {
      return ('可更新 v${installed.versionName} → $apkVersionCode', Colors.green);
    }
    if (apkVersionCode == currentCode) {
      return ('已是最新 (${installed.versionName})', scheme.onSurfaceVariant);
    }
    return ('已安装更高版本 (${installed.versionName})', Colors.redAccent);
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
  const _SourceHeader({
    required this.source,
    required this.count,
    required this.cacheBytes,
  });
  final RemoteSource source;
  final int count;
  final int cacheBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现 $count 个 APK'
            '${cacheBytes > 0 ? ' · 缓存 ${Fmt.size(cacheBytes)}' : ''}',
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
          const SizedBox(height: 4),
          Text(
            '点击安装，长按可先下载解析 APK 信息（名称/版本/包名）',
            style: TextStyle(
              fontSize: 11,
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
