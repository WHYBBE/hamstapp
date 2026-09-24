import 'package:flutter/services.dart';

import '../models/app_info.dart';

/// Thin wrapper over the native `hamstapp/apps` MethodChannel.
class NativeApps {
  static const MethodChannel _channel = MethodChannel('hamstapp/apps');

  NativeApps._();

  static Future<List<AppInfo>> getInstalledApps({bool includeSystem = true}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'getInstalledApps',
      {'includeSystem': includeSystem},
    );
    if (raw == null) return <AppInfo>[];
    return raw
        .map((e) => AppInfo.fromMap((e as Map).cast<dynamic, dynamic>()))
        .toList(growable: false);
  }

  static Future<Uint8List?> getAppIcon(String packageName, {int size = 144}) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'getAppIcon',
      {'packageName': packageName, 'size': size},
    );
    return bytes;
  }

  static Future<bool> launchApp(String packageName) async {
    final ok = await _channel.invokeMethod<bool>(
      'launchApp',
      {'packageName': packageName},
    );
    return ok ?? false;
  }

  static Future<bool> openAppInfo(String packageName) async {
    final ok = await _channel.invokeMethod<bool>(
      'openAppInfo',
      {'packageName': packageName},
    );
    return ok ?? false;
  }

  static Future<bool> uninstallApp(String packageName) async {
    final ok = await _channel.invokeMethod<bool>(
      'uninstallApp',
      {'packageName': packageName},
    );
    return ok ?? false;
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final info = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
    return (info ?? {}).cast<String, dynamic>();
  }

  /// Tests a remote APK source. Returns `{ok: bool, count: int, error: String?}`.
  static Future<Map<String, dynamic>> remoteTest(
      Map<String, dynamic> config) async {
    final r = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('remoteTest', config);
    return (r ?? {}).cast<String, dynamic>();
  }

  /// Lists `.apk` files on a remote source. Each item has name/size/path.
  static Future<List<Map<String, dynamic>>> remoteList(
      Map<String, dynamic> config) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('remoteList', config);
    if (raw == null) return <Map<String, dynamic>>[];
    return raw
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }
}
