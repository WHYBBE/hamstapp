import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Simple JSON-file backed persistence inside the app documents directory.
class Storage {
  Storage._(this._dir);

  final Directory _dir;

  static Storage? _instance;

  static Future<Storage> instance() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/hamstapp');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _instance = Storage._(dir);
    return _instance!;
  }

  File _file(String name) => File('${_dir.path}/$name.json');

  Future<dynamic> readJson(String name) async {
    try {
      final f = _file(name);
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      if (content.trim().isEmpty) return null;
      return jsonDecode(content);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String name, dynamic data) async {
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }
}
