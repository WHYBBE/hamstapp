import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'apps_screen.dart';
import 'backup_lists_screen.dart';
import 'categories_screen.dart';
import 'quick_launch_screen.dart';
import 'snapshots_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['囤囤', '快速启动', '快照对比', '备份列表', '分类'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // First launch: nothing scanned yet -> kick off a scan automatically.
    if (state.initialized && state.apps.isEmpty && !state.scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && state.apps.isEmpty && !state.scanning) state.scan();
      });
    }

    final screens = const [
      AppsScreen(),
      QuickLaunchScreen(),
      SnapshotsScreen(),
      BackupListsScreen(),
      CategoriesScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index],
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: '应用'),
          NavigationDestination(
              icon: Icon(Icons.rocket_launch_outlined),
              selectedIcon: Icon(Icons.rocket_launch),
              label: '快启'),
          NavigationDestination(
              icon: Icon(Icons.compare_arrows_outlined),
              selectedIcon: Icon(Icons.compare_arrows),
              label: '快照'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: '备份'),
          NavigationDestination(
              icon: Icon(Icons.category_outlined),
              selectedIcon: Icon(Icons.category),
              label: '分类'),
        ],
      ),
    );
  }
}
