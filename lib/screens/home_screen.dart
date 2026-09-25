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

  static const List<_NavItem> _destinations = [
    _NavItem(Icons.rocket_launch_outlined, Icons.rocket_launch, '启动'),
    _NavItem(Icons.apps_outlined, Icons.apps, '应用'),
    _NavItem(Icons.compare_arrows_outlined, Icons.compare_arrows, '快照'),
    _NavItem(Icons.settings_outlined, Icons.settings, '设置'),
  ];

  void _select(AppState state, int i) {
    if (state.tileEditMode) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('请先点击右上角「完成」结束磁贴编辑')),
        );
      return;
    }
    setState(() => _index = i);
  }

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
    final body = IndexedStack(index: _index, children: screens);

    final mq = MediaQuery.of(context);
    final mode = state.resolvedNavMode(mq.size.width, mq.size.height);

    switch (mode) {
      case NavMode.rail:
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => _select(state, i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      case NavMode.floating:
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: body),
              _FloatingNav(
                index: _index,
                destinations: _destinations,
                onSelect: (i) => _select(state, i),
              ),
            ],
          ),
        );
      case NavMode.auto:
      case NavMode.bottom:
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => _select(state, i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
    }
  }
}

/// A single top-level destination, shared by all navigation presentations.
class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Bottom-right floating button that reveals a compact vertical navigation.
class _FloatingNav extends StatefulWidget {
  const _FloatingNav({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });

  final int index;
  final List<_NavItem> destinations;
  final ValueChanged<int> onSelect;

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      right: 16,
      bottom: 24,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _open
                  ? Container(
                      key: const ValueKey('nav-panel'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < widget.destinations.length; i++)
                            _item(context, i, scheme),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('nav-closed')),
            ),
            FloatingActionButton(
              onPressed: () => setState(() => _open = !_open),
              tooltip: _open ? '收起导航' : '导航',
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: AnimatedRotation(
                turns: _open ? 0.125 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(_open ? Icons.close : Icons.menu),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, ColorScheme scheme) {
    final selected = i == widget.index;
    final d = widget.destinations[i];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _open = false);
        widget.onSelect(i);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? d.selectedIcon : d.icon,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(
              d.label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
