import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Exposes the "no navigation bar" mode to the top-level screens.
///
/// When [active] is true, each screen shows a fixed menu button as its AppBar
/// leading. Tapping it calls [onOpen], which is handled by [HomeScreen] to
/// reveal the floating navigation panel. The button lives in the AppBar so the
/// closed state never covers page content (unlike a floating button).
class FloatingNavScope extends InheritedWidget {
  const FloatingNavScope({
    super.key,
    required this.active,
    required this.onOpen,
    required super.child,
  });

  final bool active;
  final VoidCallback onOpen;

  static FloatingNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingNavScope>();

  static bool activeOf(BuildContext context) =>
      maybeOf(context)?.active ?? false;

  @override
  bool updateShouldNotify(FloatingNavScope oldWidget) =>
      active != oldWidget.active || onOpen != oldWidget.onOpen;
}

/// Fixed top-left navigation button shown while [FloatingNavScope.active].
class FloatingNavButton extends StatelessWidget {
  const FloatingNavButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = FloatingNavScope.maybeOf(context);
    if (scope == null || !scope.active) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: context.strings.t('导航'),
      onPressed: scope.onOpen,
    );
  }
}
