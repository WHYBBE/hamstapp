import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/remote_source.dart';
import '../services/remote_client.dart';
import '../state/app_state.dart';

/// Create or edit one sync source (FTP / Samba / WebDAV).
class SyncSourceEditScreen extends StatefulWidget {
  const SyncSourceEditScreen({super.key, this.source});

  /// `null` means "create a new source".
  final RemoteSource? source;

  @override
  State<SyncSourceEditScreen> createState() => _SyncSourceEditScreenState();
}

class _SyncSourceEditScreenState extends State<SyncSourceEditScreen> {
  late String _protocol;
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _path;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _domain;
  late bool _anonymous;
  late bool _secure;
  bool _busy = false;

  bool get _isNew => widget.source == null;

  @override
  void initState() {
    super.initState();
    final s = widget.source ?? RemoteSource();
    // Normalise legacy/unknown protocol values so the segmented control is valid.
    _protocol = s.isSmb ? 'smb' : (s.isWebdav ? 'webdav' : 'ftp');
    _name = TextEditingController(text: s.name);
    _host = TextEditingController(text: s.host);
    _port = TextEditingController(text: s.port.toString());
    _path = TextEditingController(text: s.path);
    _username = TextEditingController(text: s.username);
    _password = TextEditingController(text: s.password);
    _domain = TextEditingController(text: s.domain);
    _anonymous = s.anonymous;
    _secure = s.secure;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _path.dispose();
    _username.dispose();
    _password.dispose();
    _domain.dispose();
    super.dispose();
  }

  RemoteSource _build() => RemoteSource(
        id: widget.source?.id ?? '',
        name: _name.text.trim(),
        protocol: _protocol,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ??
            RemoteSource.defaultPort(_protocol, secure: _secure),
        path: _path.text.trim(),
        username: _username.text,
        password: _password.text,
        anonymous: _anonymous,
        domain: _domain.text,
        secure: _secure,
      );

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onProtocolChanged(String p) {
    setState(() {
      if (_port.text.trim() ==
          RemoteSource.defaultPort(_protocol, secure: _secure).toString()) {
        _port.text = RemoteSource.defaultPort(p, secure: _secure).toString();
      }
      _protocol = p;
    });
  }

  void _onSecureChanged(bool v) {
    setState(() {
      if (_port.text.trim() ==
          RemoteSource.defaultPort(_protocol, secure: _secure).toString()) {
        _port.text = RemoteSource.defaultPort(_protocol, secure: v).toString();
      }
      _secure = v;
    });
  }

  Future<void> _save() async {
    final cfg = _build();
    if (cfg.host.trim().isEmpty || cfg.path.trim().isEmpty) {
      _snack('请至少填写主机和路径');
      return;
    }
    final state = context.read<AppState>();
    if (_isNew) {
      await state.addSyncSource(cfg);
    } else {
      await state.updateSyncSource(cfg);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _test() async {
    final cfg = _build();
    if (!cfg.configured) {
      _snack('请先填写主机和路径');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await RemoteClient.test(cfg);
      final ok = r['ok'] == true;
      _snack(ok ? '连接成功，发现 ${r['count']} 个 APK' : '连接失败：${r['error'] ?? '未知错误'}');
    } catch (e) {
      _snack('连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建同步源' : '编辑同步源',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _test,
            child: const Text('测试连接'),
          ),
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.check),
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
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如 NAS / 路由器共享',
              helperText: '显示在同步界面的标签页上，留空则用协议名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ftp', label: Text('FTP')),
              ButtonSegment(value: 'smb', label: Text('Samba')),
              ButtonSegment(value: 'webdav', label: Text('WebDAV')),
            ],
            selected: {_protocol},
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
              helperText:
                  '默认 ${RemoteSource.defaultPort(_protocol, secure: _secure)}',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _path,
            decoration: InputDecoration(
              labelText: _protocol == 'smb' ? '共享路径' : '远程目录',
              hintText: _protocol == 'smb' ? 'share/apks' : '/apks',
              helperText: '支持多层目录，会自动递归查找其中的 APK',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_protocol == 'webdav')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _secure,
              onChanged: _onSecureChanged,
              title: const Text('使用 HTTPS'),
              subtitle: const Text('WebDAV over TLS'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('匿名登录'),
            subtitle: const Text('FTP anonymous / SMB 来宾 / WebDAV 无鉴权'),
          ),
          if (!_anonymous) ...[
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                helperText: 'SMB 可用 域\\用户名（如 WORKGROUP\\why）',
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
            if (_protocol == 'smb') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _domain,
                decoration: const InputDecoration(
                  labelText: '域 / 工作组（可选）',
                  hintText: 'WORKGROUP',
                  helperText: 'Windows 本地账户或域常需填写，Samba 一般留空',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
