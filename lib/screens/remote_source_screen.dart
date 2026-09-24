import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/remote_source.dart';
import '../services/native_apps.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_icon.dart';

/// Configure and sync a remote APK source (FTP / SMB).
class RemoteSourceScreen extends StatefulWidget {
  const RemoteSourceScreen({super.key});

  @override
  State<RemoteSourceScreen> createState() => _RemoteSourceScreenState();
}

class _RemoteSourceScreenState extends State<RemoteSourceScreen> {
  late String _protocol;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _path;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late bool _anonymous;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().remoteSource;
    _protocol = s.protocol;
    _host = TextEditingController(text: s.host);
    _port = TextEditingController(text: s.port.toString());
    _path = TextEditingController(text: s.path);
    _username = TextEditingController(text: s.username);
    _password = TextEditingController(text: s.password);
    _anonymous = s.anonymous;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _path.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  RemoteSource _build() => RemoteSource(
        protocol: _protocol,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ??
            RemoteSource.defaultPort(_protocol),
        path: _path.text.trim(),
        username: _username.text,
        password: _password.text,
        anonymous: _anonymous,
      );

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onProtocolChanged(String p) {
    setState(() {
      if (_port.text.trim() ==
          RemoteSource.defaultPort(_protocol).toString()) {
        _port.text = RemoteSource.defaultPort(p).toString();
      }
      _protocol = p;
    });
  }

  Future<void> _save() async {
    await context.read<AppState>().setRemoteSource(_build());
    if (!mounted) return;
    _snack('已保存');
  }

  Future<void> _test() async {
    final cfg = _build();
    if (!cfg.configured) {
      _snack('请先填写主机和路径');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await NativeApps.remoteTest(cfg.toChannelArgs());
      final ok = r['ok'] == true;
      _snack(ok ? '连接成功，发现 ${r['count']} 个 APK' : '连接失败：${r['error'] ?? '未知错误'}');
    } catch (e) {
      _snack('连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    final state = context.read<AppState>();
    final cfg = _build();
    if (!cfg.configured) {
      _snack('请先填写主机和路径');
      return;
    }
    setState(() => _busy = true);
    try {
      final files = await NativeApps.remoteList(cfg.toChannelArgs());
      await state.setRemoteSource(cfg);
      if (!mounted) return;
      if (files.isEmpty) {
        _snack('该目录下没有找到 APK');
        return;
      }
      _showResult(state, files);
    } catch (e) {
      _snack('同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResult(AppState state, List<Map<String, dynamic>> files) {
    final matches = <MapEntry<AppInfo, Map<String, dynamic>>>[];
    final others = <Map<String, dynamic>>[];
    for (final f in files) {
      final name = (f['name'] as String? ?? '').toLowerCase();
      AppInfo? hit;
      for (final a in state.apps) {
        if (name.contains(a.packageName.toLowerCase())) {
          hit = a;
          break;
        }
      }
      if (hit != null) {
        matches.add(MapEntry(hit, f));
      } else {
        others.add(f);
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '可更新 ${matches.length} · 其它 ${others.length}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  if (matches.isNotEmpty)
                    const _SectionLabel('匹配到本机应用（可用于更新）'),
                  ...matches.map((e) => ListTile(
                        leading: AppIcon(
                            packageName: e.key.packageName,
                            label: e.key.appName),
                        title: Text(e.key.appName),
                        subtitle: Text(
                            '${e.value['name']} · ${Fmt.size((e.value['size'] as num?)?.toInt() ?? 0)}'),
                        trailing: const Icon(Icons.system_update_alt),
                      )),
                  if (others.isNotEmpty)
                    const _SectionLabel('其它 APK'),
                  ...others.map((f) => ListTile(
                        leading: const Icon(Icons.android),
                        title: Text(f['name'] as String? ?? ''),
                        subtitle: Text(
                            Fmt.size((f['size'] as num?)?.toInt() ?? 0)),
                      )),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程 APK 源',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _test,
            child: const Text('测试连接'),
          ),
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
            onPressed: _busy ? null : _save,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('连接局域网 / NAS 上的 FTP 或 Samba 共享，'
              '读取其中的 APK 列表用于更新软件。配置会被记住。'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ftp', label: Text('FTP')),
              ButtonSegment(value: 'smb', label: Text('Samba (SMB)')),
            ],
            selected: {_protocol == 'smb' ? 'smb' : 'ftp'},
            onSelectionChanged: (v) => _onProtocolChanged(v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '主机',
              hintText: '192.168.1.10 或 nas.local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '端口',
              helperText: _protocol == 'smb' ? '默认 445' : '默认 21',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _path,
            decoration: InputDecoration(
              labelText: _protocol == 'smb' ? '共享路径' : '远程目录',
              hintText:
                  _protocol == 'smb' ? 'share/apks' : '/apks',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('匿名登录'),
            subtitle: const Text('无需账号密码（FTP anonymous / SMB 来宾）'),
          ),
          if (!_anonymous) ...[
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync),
            label: const Text('同步 APK 列表'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
