import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/native_apps.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const _SectionHeader('系统'),
          SwitchListTile(
            value: state.showSystemStatusBar,
            onChanged: (v) => state.setShowSystemStatusBar(v),
            title: const Text('显示系统状态栏'),
            subtitle: const Text('关闭后隐藏系统状态栏，内容更沉浸；向下滑动可临时唤出'),
            secondary: Icon(
              state.showSystemStatusBar
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('磁贴'),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: const Text('新增磁贴默认大小'),
            subtitle: Text(
              '当前 ${state.tileDefaultSize}×${state.tileDefaultSize}，'
              '置顶新应用时使用',
            ),
            trailing: DropdownButton<int>(
              value: state.tileDefaultSize,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) state.setTileDefaultSize(v);
              },
              items: const [
                DropdownMenuItem(value: 1, child: Text('1×1')),
                DropdownMenuItem(value: 2, child: Text('2×2')),
                DropdownMenuItem(value: 3, child: Text('3×3')),
                DropdownMenuItem(value: 4, child: Text('4×4')),
              ],
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('数据备份'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('导出数据包'),
            subtitle: const Text('把快照、磁贴、分组、备份列表等全部数据打包为单个文件'),
            onTap: () => _exportData(context, state),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导入数据包'),
            subtitle: const Text('先清空当前数据，再完整导入（不支持部分导入）'),
            onTap: () => _importData(context, state),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error),
            title: const Text('清空数据'),
            subtitle: const Text('删除全部本地数据，无法恢复'),
            onTap: () => _clearData(context, state),
          ),
          const Divider(height: 1),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.pets),
            title: Text('囤囤 · Hamstapp'),
            subtitle: Text('Android 应用管理器'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),
          const _DeviceInfoTile(),
          const Divider(height: 1),
          const _SectionHeader('提示'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Text(
              '磁贴：在「快速启动 → 磁贴」点击右上角 ✏️ 进入编辑模式，'
              '长按磁贴拖动移动、拖动右下角缩放；完成后点击右上角「完成」退出。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

Future<void> _exportData(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final pkg = state.exportPackage();
    final json = const JsonEncoder.withIndent('  ').convert(pkg);
    final now = DateTime.now();
    final name = 'hamstapp_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}.json';
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      dialogTitle: '导出囤囤数据',
    );
    if (uri == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已导出数据包')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('导出失败：$e')));
  }
}

Future<void> _importData(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择囤囤数据包',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('文件内容不是有效的数据包');
    }
    final pkg = decoded.cast<String, dynamic>();
    if (pkg['app'] != 'hamstapp') {
      throw const FormatException('这不是囤囤导出的数据包');
    }
    final counts = state.packageCounts(pkg);
    final summary = counts.entries
        .map((e) => '${e.key} ${e.value}')
        .join(' · ');
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: Text(
          '导入会先清空当前全部数据，再写入数据包内容，'
          '不会进行部分导入。\n\n数据包内容：$summary\n\n确定继续吗？',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空并导入')),
        ],
      ),
    );
    if (ok != true) return;
    await state.importPackage(pkg);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('导入完成')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text('导入失败：$e（本地数据未改动）')));
  }
}

Future<void> _clearData(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清空数据'),
      content: const Text(
          '将删除全部应用记录、分组、快照、备份列表、磁贴与设置，且无法恢复。确定吗？'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('清空'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await state.clearAllData();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('已清空数据')));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
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

class _DeviceInfoTile extends StatelessWidget {
  const _DeviceInfoTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: NativeApps.getDeviceInfo(),
      builder: (context, snap) {
        final info = snap.data;
        final text = info == null
            ? '读取中…'
            : '${info['manufacturer']} ${info['model']} · Android ${info['androidVersion']} (API ${info['sdkInt']})';
        return ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('设备'),
          subtitle: Text(text),
        );
      },
    );
  }
}
