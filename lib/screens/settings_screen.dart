import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/native_apps.dart';
import '../state/app_state.dart';
import '../utils/backup_actions.dart';
import 'sync_screen.dart';

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
          const _SectionHeader('高级'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('同步（FTP / Samba / WebDAV）'),
            subtitle: Text(state.remoteSource.summary),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncScreen()),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('数据备份'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('导出数据包'),
            subtitle: const Text('把快照、磁贴、分组、备份列表等全部数据打包为单个文件'),
            onTap: () => exportData(context, state),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导入数据包'),
            subtitle: const Text('先清空当前数据，再完整导入（不支持部分导入）'),
            onTap: () => importData(context, state),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('清空数据'),
            subtitle: const Text('删除全部本地数据，无法恢复'),
            onTap: () => clearData(context, state),
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
              '磁贴：在「启动 → 磁贴」点击右上角 ✏️ 进入编辑模式，'
              '长按磁贴拖动移动、拖动右下角缩放；完成后点击右上角「完成」退出。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
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
