import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/app_state.dart';

/// Dedicated screen to tune the haptic feedback used when switching tabs and
/// tile pages: master switch, per-trigger switches, effect and strength.
class HapticsSettingsScreen extends StatelessWidget {
  const HapticsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = context.strings;
    final enabled = state.hapticsEnabled;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.t('触感反馈'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: state.setHapticsEnabled,
            secondary: const Icon(Icons.vibration),
            title: Text(s.t('启用触感反馈')),
            subtitle: Text(s.t('切换标签或磁贴页时给出轻微震动')),
          ),
          const Divider(height: 1),
          _SectionHeader(s.t('触发场景')),
          SwitchListTile(
            value: enabled && state.hapticsMainTabs,
            onChanged: enabled ? state.setHapticsMainTabs : null,
            title: Text(s.t('主标签切换')),
            subtitle: Text(s.t('启动 / 应用 / 快照 / 设置')),
          ),
          SwitchListTile(
            value: enabled && state.hapticsLaunchTabs,
            onChanged: enabled ? state.setHapticsLaunchTabs : null,
            title: Text(s.t('启动子标签切换')),
            subtitle: Text(s.t('磁贴 / 分类 / 收藏 / 最近')),
          ),
          SwitchListTile(
            value: enabled && state.hapticsTilePages,
            onChanged: enabled ? state.setHapticsTilePages : null,
            title: Text(s.t('磁贴子页切换')),
            subtitle: Text(s.t('磁贴页之间左右滑动')),
          ),
          const Divider(height: 1),
          _SectionHeader(s.t('效果')),
          ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: Text(s.t('震动效果')),
            subtitle: Text(_effectDescription(s, state.hapticEffect)),
            trailing: DropdownButton<HapticEffect>(
              value: state.hapticEffect,
              underline: const SizedBox.shrink(),
              onChanged: enabled
                  ? (v) {
                      if (v != null) state.setHapticEffect(v);
                    }
                  : null,
              items: [
                DropdownMenuItem(
                  value: HapticEffect.selection,
                  child: Text(s.t('轻触')),
                ),
                DropdownMenuItem(
                  value: HapticEffect.impact,
                  child: Text(s.t('冲击')),
                ),
                DropdownMenuItem(
                  value: HapticEffect.vibrate,
                  child: Text(s.t('振动')),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(s.t('震动等级')),
            subtitle: Text(
              state.hapticEffect == HapticEffect.impact
                  ? s.t('用于「冲击」效果')
                  : s.t('仅「冲击」效果生效'),
            ),
            trailing: DropdownButton<HapticLevel>(
              value: state.hapticLevel,
              underline: const SizedBox.shrink(),
              onChanged: enabled && state.hapticEffect == HapticEffect.impact
                  ? (v) {
                      if (v != null) state.setHapticLevel(v);
                    }
                  : null,
              items: [
                DropdownMenuItem(
                  value: HapticLevel.light,
                  child: Text(s.t('轻')),
                ),
                DropdownMenuItem(
                  value: HapticLevel.medium,
                  child: Text(s.t('中')),
                ),
                DropdownMenuItem(
                  value: HapticLevel.heavy,
                  child: Text(s.t('重')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              onPressed: enabled ? state.previewHaptic : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(s.t('测试一下')),
            ),
          ),
        ],
      ),
    );
  }
}

String _effectDescription(AppStrings s, HapticEffect effect) {
  switch (effect) {
    case HapticEffect.selection:
      return s.t('轻触：切换标签的细微反馈');
    case HapticEffect.impact:
      return s.t('冲击：按等级产生的敲击感');
    case HapticEffect.vibrate:
      return s.t('振动：较长的持续震动');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
