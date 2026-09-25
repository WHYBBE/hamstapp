import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/app_state.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Export the full data package to a user-chosen file.
Future<void> exportData(BuildContext context, AppState state) async {
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
      dialogTitle: AppStrings.current.t('导出囤囤数据'),
    );
    if (uri == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppStrings.current.t('已导出数据包'))),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.current.t('导出失败：{error}', {'error': e}),
          ),
        ),
      );
  }
}

/// Import a data package. Clears ALL existing data first (no partial import).
Future<void> importData(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: AppStrings.current.t('选择囤囤数据包'),
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw FormatException(
        AppStrings.current.t('文件内容不是有效的数据包'),
      );
    }
    final pkg = decoded.cast<String, dynamic>();
    if (pkg['app'] != 'hamstapp') {
      throw FormatException(
        AppStrings.current.t('这不是囤囤导出的数据包'),
      );
    }
    final counts = state.packageCounts(pkg);
    final summary =
        counts.entries.map((e) => '${e.key} ${e.value}').join(' · ');
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.current.t('导入数据')),
        content: Text(
          AppStrings.current.t(
                '导入会先清空当前全部数据，再写入数据包内容，不会进行部分导入。\n\n',
              ) +
              AppStrings.current.t(
                '数据包内容：{summary}\n\n确定继续吗？',
                {'summary': summary},
              ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.current.t('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppStrings.current.t('清空并导入'))),
        ],
      ),
    );
    if (ok != true) return;
    await state.importPackage(pkg);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppStrings.current.t('导入完成'))),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.current.t(
              '导入失败：{error}（本地数据未改动）',
              {'error': e},
            ),
          ),
        ),
      );
  }
}

/// Wipe all local data after a confirmation.
Future<void> clearData(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppStrings.current.t('清空数据')),
      content: Text(
        AppStrings.current.t('将删除全部应用记录、分组、快照、备份列表、磁贴与设置，且无法恢复。确定吗？'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.current.t('取消'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(AppStrings.current.t('清空')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await state.clearAllData();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(AppStrings.current.t('已清空数据'))));
}
