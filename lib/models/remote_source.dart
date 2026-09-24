/// Configuration of a remote APK source (FTP, SMB/Samba or WebDAV).
class RemoteSource {
  String protocol; // 'ftp' | 'smb' | 'webdav'
  String host;
  int port;
  String path; // FTP/WebDAV remote dir, or SMB share[/subdir]
  String username;
  String password;
  bool anonymous;

  /// Use HTTPS/TLS (WebDAV only).
  bool secure;

  RemoteSource({
    this.protocol = 'ftp',
    this.host = '',
    this.port = 21,
    this.path = '',
    this.username = '',
    this.password = '',
    this.anonymous = true,
    this.secure = false,
  });

  factory RemoteSource.fromMap(Map<String, dynamic> map) {
    final protocol = map['protocol'] as String? ?? 'ftp';
    return RemoteSource(
      protocol: protocol,
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? defaultPort(protocol),
      path: map['path'] as String? ?? '',
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      anonymous: map['anonymous'] as bool? ?? true,
      secure: map['secure'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'protocol': protocol,
        'host': host,
        'port': port,
        'path': path,
        'username': username,
        'password': password,
        'anonymous': anonymous,
        'secure': secure,
      };

  bool get isSmb => protocol == 'smb' || protocol == 'samba';
  bool get isWebdav => protocol == 'webdav';
  bool get isFtp => !isSmb && !isWebdav;

  bool get configured => host.trim().isNotEmpty && path.trim().isNotEmpty;

  /// Default port for the selected protocol.
  static int defaultPort(String protocol, {bool secure = false}) {
    switch (protocol) {
      case 'smb':
      case 'samba':
        return 445;
      case 'webdav':
        return secure ? 443 : 80;
      default:
        return 21;
    }
  }

  String get protocolLabel {
    if (isSmb) return 'SMB';
    if (isWebdav) return secure ? 'WebDAV(HTTPS)' : 'WebDAV';
    return 'FTP';
  }

  String get summary {
    if (!configured) return '未配置';
    final auth = anonymous ? '匿名' : username;
    return '$protocolLabel · $host:$port/$path · $auth';
  }

  /// Arguments passed to the native channel (FTP/SMB only).
  Map<String, dynamic> toChannelArgs() => <String, dynamic>{
        'protocol': isSmb ? 'smb' : 'ftp',
        'host': host.trim(),
        'port': port,
        'path': path.trim(),
        'username': username,
        'password': password,
        'anonymous': anonymous,
      };

  RemoteSource copyWith({
    String? protocol,
    String? host,
    int? port,
    String? path,
    String? username,
    String? password,
    bool? anonymous,
    bool? secure,
  }) =>
      RemoteSource(
        protocol: protocol ?? this.protocol,
        host: host ?? this.host,
        port: port ?? this.port,
        path: path ?? this.path,
        username: username ?? this.username,
        password: password ?? this.password,
        anonymous: anonymous ?? this.anonymous,
        secure: secure ?? this.secure,
      );
}
