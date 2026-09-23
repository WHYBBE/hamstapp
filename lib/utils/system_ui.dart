import 'package:flutter/services.dart';

/// Show or hide the system status bar.
///
/// When hidden, Android draws it only as a transient overlay (revealed by
/// swiping from the top) so it never reserves layout space. The bottom
/// navigation bar is always kept visible.
Future<void> applyStatusBarVisibility(bool show) async {
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: show
        ? const [SystemUiOverlay.top, SystemUiOverlay.bottom]
        : const [SystemUiOverlay.bottom],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
}
