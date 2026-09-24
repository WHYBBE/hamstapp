import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/uninstall_reason.dart';
import 'apps_screen.dart';
import 'quick_launch_screen.dart';
import 'settings_screen.dart';
import 'snapshots_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _uninstallSheetVisible = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // First launch: nothing scanned yet -> kick off a scan automatically.
    if (state.initialized && state.apps.isEmpty && !state.scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && state.apps.isEmpty && !state.scanning) state.scan();
      });
    }

    // After a scan detects uninstalls (current vs last snapshot) ask for reasons.
    if (state.pendingUninstalls.isNotEmpty && !_uninstallSheetVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || state.pendingUninstalls.isEmpty) return;
        _uninstallSheetVisible = true;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => UninstallReasonSheet(state: state),
        ).whenComplete(() => _uninstallSheetVisible = false);
      });
    }

    const screens = [
      QuickLaunchScreen(),
      AppsScreen(),
      SnapshotsScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (state.tileEditMode) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('请先点击右上角「完成」结束磁贴编辑')),
              );
            return;
          }
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: '应用',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined),
            selectedIcon: Icon(Icons.compare_arrows),
            label: '快照',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
