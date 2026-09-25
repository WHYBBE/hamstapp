import 'dart:convert';
import 'dart:io';

import '../models/remote_source.dart';
import 'native_apps.dart';

/// Talks to a remote APK source.
///
/// FTP and SMB go through the native bridge (commons-net / jcifs-ng); WebDAV is
/// implemented in Dart over HTTP(S).
class RemoteClient {
  RemoteClient._();

  static Future<Map<String, dynamic>> test(RemoteSource source) async {
    try {
      if (source.isWebdav) {
        final files = await _webdavList(source);
        return {'ok': true, 'count': files.length};
      }
      return await NativeApps.remoteTest(source.toChannelArgs());
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  static Future<List<Map<String, dynamic>>> list(RemoteSource source) {
    if (source.isWebdav) return _webdavList(source);
    return NativeApps.remoteList(source.toChannelArgs());
  }

  static Future<List<Map<String, dynamic>>> _webdavList(
      RemoteSource source) async {
    final scheme = source.secure ? 'https' : 'http';
    var path = source.path.trim();
    if (path.isEmpty) path = '/';
    if (!path.startsWith('/')) path = '/$path';
    // Collections must be addressed with a trailing slash; many servers answer
    // 301/404 (instead of listing) when it is missing.
    if (!path.endsWith('/')) path = '$path/';
    var uri = Uri(
      scheme: scheme,
      host: source.host.trim(),
      port: source.port,
      path: path,
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'Hamstapp/1.0'
      // LAN NAS boxes commonly present self-signed certificates.
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      for (var attempt = 0; attempt <= 5; attempt++) {
        final req = await client.openUrl('PROPFIND', uri)
          ..followRedirects = false
          ..persistentConnection = false
          ..headers.set('Depth', '1')
          ..headers.contentLength = 0;
        if (!source.anonymous && source.username.isNotEmpty) {
          final token = base64
              .encode(utf8.encode('${source.username}:${source.password}'));
          req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
        }
        final resp = await req.close();
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        final code = resp.statusCode;
        if (code >= 300 && code < 400) {
          final loc = resp.headers.value(HttpHeaders.locationHeader);
          if (loc == null || attempt == 5) {
            throw HttpException('HTTP $code（重定向但无 Location）', uri: uri);
          }
          uri = uri.resolve(loc);
          continue;
        }
        if (code >= 400) {
          final reason = resp.reasonPhrase;
          throw HttpException(
            'HTTP $code $reason${_hint(code)}${_snippet(bytes)}',
            uri: uri,
          );
        }
        return parseWebdavListing(utf8.decode(bytes, allowMalformed: true));
      }
      throw HttpException('重定向次数过多', uri: uri);
    } finally {
      client.close(force: true);
    }
  }

  static String _hint(int code) {
    switch (code) {
      case 401:
        return '（需要登录，请关闭“匿名登录”并填写账号密码）';
      case 403:
        return '（无权限，账号可能不允许该目录）';
      case 404:
        return '（路径不存在，注意大小写并确认 WebDAV 根目录）';
      case 405:
        return '（该地址不是 WebDAV 服务，或不允许 PROPFIND）';
      default:
        return '';
    }
  }

  static String _snippet(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return '';
    final short = text.length > 200 ? '${text.substring(0, 200)}…' : text;
    return ' · $short';
  }

  /// Parses a WebDAV `multistatus` XML body into `.apk` file entries.
  ///
  /// Namespace prefixes vary between servers (D:, d:, lp1:, none), so the
  /// matching is prefix-agnostic.
  static List<Map<String, dynamic>> parseWebdavListing(String xml) {
    final out = <Map<String, dynamic>>[];
    final blocks = xml.split(
        RegExp(r'</[a-zA-Z0-9]*:?response\s*>', caseSensitive: false));
    final hrefRe = RegExp(r'<[a-zA-Z0-9]*:?href[^>]*>(.*?)</[a-zA-Z0-9]*:?href>',
        caseSensitive: false, dotAll: true);
    final lenRe = RegExp(r'<[a-zA-Z0-9]*:?getcontentlength[^>]*>\s*(\d+)',
        caseSensitive: false);
    final modRe = RegExp(
        r'<[a-zA-Z0-9]*:?getlastmodified[^>]*>(.*?)</',
        caseSensitive: false,
        dotAll: true);

    for (final block in blocks) {
      final href = hrefRe.firstMatch(block)?.group(1);
      if (href == null) continue;
      final decoded = Uri.decodeComponent(href.trim());
      if (decoded.endsWith('/')) continue; // collection
      final name = decoded.split('/').where((s) => s.isNotEmpty).last;
      if (name.isEmpty || !name.toLowerCase().endsWith('.apk')) continue;
      final size = int.tryParse(lenRe.firstMatch(block)?.group(1) ?? '') ?? 0;
      final modified = _parseHttpDate(modRe.firstMatch(block)?.group(1));
      out.add({
        'name': name,
        'size': size,
        'path': decoded,
        'modified': modified,
      });
    }
    out.sort((a, b) => (a['name'] as String)
        .toLowerCase()
        .compareTo((b['name'] as String).toLowerCase()));
    return out;
  }

  static int _parseHttpDate(String? raw) {
    if (raw == null) return 0;
    try {
      return HttpDate.parse(raw.trim()).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }
}
