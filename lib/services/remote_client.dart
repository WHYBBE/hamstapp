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
    if (!path.startsWith('/')) path = '/$path';
    final uri = Uri.parse('$scheme://${source.host.trim()}:${source.port}$path');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl('PROPFIND', uri);
      req.headers.set('Depth', '1');
      req.headers.contentLength = 0;
      if (!source.anonymous && source.username.isNotEmpty) {
        final token =
            base64.encode(utf8.encode('${source.username}:${source.password}'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
      }
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 400) {
        throw HttpException('HTTP ${resp.statusCode}', uri: uri);
      }
      return parseWebdavListing(body);
    } finally {
      client.close(force: true);
    }
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
