import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/native_apps.dart';
import '../state/app_state.dart';

Future<void> launchApp(BuildContext context, String packageName) async {
  final state = context.read<AppState>();
  final ok = await NativeApps.launchApp(packageName);
  if (ok) {
    await state.markLaunched(packageName);
  }
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.strings.t('无法启动该应用（可能已禁用或没有启动入口）'),
        ),
      ),
    );
  }
}

Future<void> openAppInfo(BuildContext context, String packageName) async {
  final ok = await NativeApps.openAppInfo(packageName);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.t('无法打开应用信息页'))),
    );
  }
}

Future<void> uninstallApp(
  BuildContext context,
  String packageName,
  String name,
) async {
  final strings = context.strings;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(strings.t('卸载应用')),
      content: Text(strings.t('确定要卸载「{name}」吗？', {'name': name})),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(strings.t('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(strings.t('卸载')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  await NativeApps.uninstallApp(packageName);
}
