import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/remote_source.dart';
import 'native_apps.dart';

/// Talks to a remote APK source.
///
/// FTP and SMB go through the native bridge (commons-net / jcifs-ng); WebDAV is
/// implemented in Dart over HTTP(S). All listing is recursive and only returns
/// real `.apk` files (hidden/dot entries and other files are skipped).
class RemoteClient {
  RemoteClient._();

  static const int _maxDepth = 6;
  static const int _maxDirs = 500;

  static Future<Map<String, dynamic>> test(RemoteSource source) async {
    try {
      final files = await list(source);
      return {'ok': true, 'count': files.length};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  static Future<List<Map<String, dynamic>>> list(RemoteSource source) {
    if (source.isWebdav) return _webdavList(source);
    return NativeApps.remoteList(source.toChannelArgs());
  }

  /// Downloads one listed entry and returns the local file path.
  static Future<String> download(
      RemoteSource source, Map<String, dynamic> entry) async {
    final name = (entry['name'] as String?) ?? 'download.apk';
    if (source.isWebdav) {
      return _webdavDownload(source, entry, name);
    }
    return NativeApps.remoteDownload(
      source.toChannelArgs(),
      (entry['path'] as String?) ?? '',
      name,
    );
  }

  // --------------------------------------------------------------- webdav

  static Uri _rootUri(RemoteSource source) {
    final scheme = source.secure ? 'https' : 'http';
    var path = source.path.trim();
    if (path.isEmpty) path = '/';
    if (!path.startsWith('/')) path = '/$path';
    // Collections must be addressed with a trailing slash; many servers answer
    // 301/404 (instead of listing) when it is missing.
    if (!path.endsWith('/')) path = '$path/';
    return Uri(
      scheme: scheme,
      host: source.host.trim(),
      port: source.port,
      path: path,
    );
  }

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'Hamstapp/1.0'
    // LAN NAS boxes commonly present self-signed certificates.
    ..badCertificateCallback = (cert, host, port) => true;

  static void _applyAuth(HttpClientRequest req, RemoteSource source) {
    if (!source.anonymous && source.username.isNotEmpty) {
      final token =
          base64.encode(utf8.encode('${source.username}:${source.password}'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    }
  }

  static Future<List<Map<String, dynamic>>> _webdavList(
      RemoteSource source) async {
    final client = _client();
    try {
      final root = _rootUri(source);
      final rootPath = root.path;
      final rootDepth = _depthOf(rootPath);
      final out = <Map<String, dynamic>>[];
      final visited = <String>{};
      final queue = <Uri>[root];

      while (queue.isNotEmpty) {
        if (visited.length >= _maxDirs) break;
        final dir = queue.removeAt(0);
        if (!visited.add(dir.toString())) continue;

        final entries = await _propfind(client, source, dir);
        for (final e in entries) {
          final href = e['href'] as String;
          var target = dir.resolve(href);
          if (e['isDir'] == true) {
            if (!target.path.endsWith('/')) {
              target = target.replace(path: '${target.path}/');
            }
            if (_depthOf(target.path) - rootDepth <= _maxDepth) {
              queue.add(target);
            }
          } else {
            final name = e['name'] as String;
            if (name.startsWith('.') ||
                !name.toLowerCase().endsWith('.apk')) {
              continue;
            }
            final rel = Uri.decodeComponent(target.path.startsWith(rootPath)
                ? target.path.substring(rootPath.length)
                : name);
            out.add({
              'name': name,
              'rel': rel,
              'path': target.path,
              'size': e['size'] ?? 0,
              'modified': e['modified'] ?? 0,
            });
          }
        }
      }
      out.sort((a, b) => (a['rel'] as String)
          .toLowerCase()
          .compareTo((b['rel'] as String).toLowerCase()));
      return out;
    } finally {
      client.close(force: true);
    }
  }

  static int _depthOf(String path) =>
      path.split('/').where((s) => s.isNotEmpty).length;

  static Future<List<Map<String, dynamic>>> _propfind(
      HttpClient client, RemoteSource source, Uri uri) async {
    var target = uri;
    for (var attempt = 0; attempt <= 5; attempt++) {
      final req = await client.openUrl('PROPFIND', target)
        ..followRedirects = false
        ..persistentConnection = false
        ..headers.set('Depth', '1')
        ..headers.contentLength = 0;
      _applyAuth(req, source);
      final resp = await req.close();
      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
      }
      final code = resp.statusCode;
      if (code >= 300 && code < 400) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc == null || attempt == 5) {
          throw HttpException('HTTP $code（重定向但无 Location）', uri: target);
        }
        target = target.resolve(loc);
        continue;
      }
      if (code >= 400) {
        throw HttpException(
          'HTTP $code ${resp.reasonPhrase}${_hint(code)}${_snippet(bytes)}',
          uri: target,
        );
      }
      return parseWebdavEntries(utf8.decode(bytes, allowMalformed: true));
    }
    throw HttpException('重定向次数过多', uri: target);
  }

  static Future<String> _webdavDownload(
      RemoteSource source, Map<String, dynamic> entry, String name) async {
    final client = _client();
    try {
      final root = _rootUri(source);
      final path = (entry['path'] as String?) ?? '';
      final uri = path.isEmpty ? root : root.replace(path: path);

      final req = await client.getUrl(uri);
      _applyAuth(req, source);
      final resp = await req.close();
      if (resp.statusCode >= 400) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode}', uri: uri);
      }
      final dir = await _downloadDir();
      final file = File('${dir.path}/${_safeName(name)}');
      final sink = file.openWrite();
      await resp.pipe(sink);
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Directory> _downloadDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/apk_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeName(String name) {
    final s = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return s.isEmpty ? 'download.apk' : s;
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

  // --------------------------------------------------------------- parsing

  /// Last path segment of an already percent-decoded path.
  static String _basename(String path) {
    final parts = path.trim().split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  /// Parses a WebDAV `multistatus` XML body into raw entries (files and
  /// collections). Prefix-agnostic because servers use D:, d:, lp1: or none.
  static List<Map<String, dynamic>> parseWebdavEntries(String xml) {
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
      final name = _basename(decoded);
      if (name.isEmpty) continue;
      out.add({
        'href': decoded,
        'name': name,
        'isDir': decoded.endsWith('/'),
        'size': int.tryParse(lenRe.firstMatch(block)?.group(1) ?? '') ?? 0,
        'modified': _parseHttpDate(modRe.firstMatch(block)?.group(1)),
      });
    }
    return out;
  }

  /// Files-only view of [parseWebdavEntries] (kept for callers/tests).
  static List<Map<String, dynamic>> parseWebdavListing(String xml) {
    final out = <Map<String, dynamic>>[];
    for (final e in parseWebdavEntries(xml)) {
      if (e['isDir'] == true) continue;
      final name = e['name'] as String;
      if (name.startsWith('.') || !name.toLowerCase().endsWith('.apk')) {
        continue;
      }
      out.add({
        'name': name,
        'size': e['size'],
        'path': e['href'],
        'modified': e['modified'],
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
