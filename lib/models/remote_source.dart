/// Configuration of a remote APK source (FTP or SMB/Samba).
class RemoteSource {
  String protocol; // 'ftp' | 'smb'
  String host;
  int port;
  String path; // FTP remote dir, or SMB share[/subdir]
  String username;
  String password;
  bool anonymous;

  RemoteSource({
    this.protocol = 'ftp',
    this.host = '',
    this.port = 21,
    this.path = '',
    this.username = '',
    this.password = '',
    this.anonymous = true,
  });

  factory RemoteSource.fromMap(Map<String, dynamic> map) => RemoteSource(
        protocol: map['protocol'] as String? ?? 'ftp',
        host: map['host'] as String? ?? '',
        port: (map['port'] as num?)?.toInt() ?? 21,
        path: map['path'] as String? ?? '',
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        anonymous: map['anonymous'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'protocol': protocol,
        'host': host,
        'port': port,
        'path': path,
        'username': username,
        'password': password,
        'anonymous': anonymous,
      };

  bool get isSmb => protocol == 'smb' || protocol == 'samba';

  bool get configured => host.trim().isNotEmpty && path.trim().isNotEmpty;

  /// Default port for the selected protocol.
  static int defaultPort(String protocol) =>
      (protocol == 'smb' || protocol == 'samba') ? 445 : 21;

  String get protocolLabel => isSmb ? 'SMB' : 'FTP';

  String get summary {
    if (!configured) return '未配置';
    final auth = anonymous ? '匿名' : username;
    return '$protocolLabel · $host:$port/$path · $auth';
  }

  /// Arguments passed to the native channel.
  Map<String, dynamic> toChannelArgs() => <String, dynamic>{
        'protocol': protocol,
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
  }) =>
      RemoteSource(
        protocol: protocol ?? this.protocol,
        host: host ?? this.host,
        port: port ?? this.port,
        path: path ?? this.path,
        username: username ?? this.username,
        password: password ?? this.password,
        anonymous: anonymous ?? this.anonymous,
      );
}
