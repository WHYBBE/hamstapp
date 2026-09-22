class AppInfo {
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final int firstInstallTime;
  final int lastUpdateTime;
  final bool isSystem;
  final bool enabled;
  final String apkPath;
  final int sizeBytes;
  final int targetSdk;
  final int minSdk;
  final int uid;

  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.firstInstallTime,
    required this.lastUpdateTime,
    required this.isSystem,
    required this.enabled,
    required this.apkPath,
    required this.sizeBytes,
    required this.targetSdk,
    required this.minSdk,
    required this.uid,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      versionName: map['versionName'] as String? ?? '',
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      firstInstallTime: (map['firstInstallTime'] as num?)?.toInt() ?? 0,
      lastUpdateTime: (map['lastUpdateTime'] as num?)?.toInt() ?? 0,
      isSystem: map['isSystem'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? true,
      apkPath: map['apkPath'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      targetSdk: (map['targetSdk'] as num?)?.toInt() ?? 0,
      minSdk: (map['minSdk'] as num?)?.toInt() ?? 0,
      uid: (map['uid'] as num?)?.toInt() ?? 0,
    );
  }

  DateTime get firstInstallDate =>
      DateTime.fromMillisecondsSinceEpoch(firstInstallTime);
  DateTime get lastUpdateDate =>
      DateTime.fromMillisecondsSinceEpoch(lastUpdateTime);

  String get initial =>
      appName.trim().isEmpty ? '?' : appName.trim()[0].toUpperCase();

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'versionName': versionName,
        'versionCode': versionCode,
        'firstInstallTime': firstInstallTime,
        'lastUpdateTime': lastUpdateTime,
        'isSystem': isSystem,
        'enabled': enabled,
        'apkPath': apkPath,
        'sizeBytes': sizeBytes,
        'targetSdk': targetSdk,
        'minSdk': minSdk,
        'uid': uid,
      };
}
