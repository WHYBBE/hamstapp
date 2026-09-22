import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../widgets/app_icon.dart';
import 'app_detail_screen.dart';

class QuickLaunchScreen extends StatefulWidget {
  const QuickLaunchScreen({super.key});

  @override
  State<QuickLaunchScreen> createState() => _QuickLaunchScreenState();
}

class _QuickLaunchScreenState extends State<QuickLaunchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final favorites = state.favorites;

    final results = _query.trim().isEmpty
        ? <AppInfo>[]
        : state.visibleApps
            .where((a) =>
                a.appName.toLowerCase().contains(_query.toLowerCase()) ||
                a.packageName.toLowerCase().contains(_query.toLowerCase()))
            .take(12)
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '搜索任意应用并立即启动',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_query.trim().isNotEmpty)
          Expanded(child: _resultList(state, results))
        else
          Expanded(child: _favoritesGrid(state, favorites)),
      ],
    );
  }

  Widget _resultList(AppState state, List<AppInfo> results) {
    if (results.isEmpty) {
      return const Center(child: Text('没有找到匹配的应用'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final app = results[i];
        return ListTile(
          leading: AppIcon(packageName: app.packageName, label: app.appName),
          title: Text(app.appName),
          subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.rocket_launch_outlined),
          onTap: () => launchApp(context, app.packageName),
        );
      },
    );
  }

  Widget _favoritesGrid(AppState state, List<AppInfo> favorites) {
    if (favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rocket_launch_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                '还没有收藏的应用\n在应用列表点击 ⭐ 收藏，即可在这里一键启动',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, i) {
        final app = favorites[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => launchApp(context, app.packageName),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailScreen(packageName: app.packageName),
            ),
          ),
          child: Column(
            children: [
              AppIcon(packageName: app.packageName, label: app.appName, size: 56),
              const SizedBox(height: 8),
              Text(
                app.appName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
