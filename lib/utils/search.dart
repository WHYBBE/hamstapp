import 'package:lpinyin/lpinyin.dart';

import '../models/app_info.dart';

/// Precomputed, cached search keys for an app.
class SearchFields {
  const SearchFields({
    required this.name,
    required this.pkg,
    required this.full,
    required this.initials,
  });

  /// Lowercased display name.
  final String name;

  /// Lowercased package name.
  final String pkg;

  /// Full pinyin (no tones/spaces) plus latin characters, lowercased.
  final String full;

  /// Pinyin initials plus latin characters, lowercased. e.g. 微信 -> wx.
  final String initials;
}

/// Fuzzy search over app names/packages with pinyin support.
///
/// Matches, in order of preference: exact name, name prefix/substring,
/// package, pinyin initials (e.g. `wx` -> 微信), full pinyin (`weixin`), then
/// character subsequence (e.g. `gmap` -> Google Maps). Queries are split on
/// whitespace and every token must match.
class AppSearch {
  AppSearch._();

  static final Map<String, SearchFields> _cache = <String, SearchFields>{};

  static SearchFields fieldsFor(String packageName, String appName) {
    final lowerName = appName.toLowerCase();
    final cached = _cache[packageName];
    if (cached != null && cached.name == lowerName) return cached;
    final f = SearchFields(
      name: lowerName,
      pkg: packageName.toLowerCase(),
      full: _safePinyin(appName).toLowerCase(),
      initials: _safeShortPinyin(appName).toLowerCase(),
    );
    _cache[packageName] = f;
    return f;
  }

  static void clearCache() => _cache.clear();

  /// Lowercased full pinyin (latin characters preserved) for sorting names.
  static String pinyinKey(String s) => _safePinyin(s).toLowerCase();

  static String _safePinyin(String s) {
    try {
      return PinyinHelper.getPinyinE(s, separator: '');
    } catch (_) {
      return s;
    }
  }

  static String _safeShortPinyin(String s) {
    try {
      return PinyinHelper.getShortPinyin(s);
    } catch (_) {
      return s;
    }
  }

  static bool matches(String packageName, String appName, String query) =>
      score(packageName, appName, query) != null;

  /// Relevance score (higher is better) or null when [query] does not match.
  /// An empty query scores 0 and matches everything.
  static int? score(String packageName, String appName, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0;
    final f = fieldsFor(packageName, appName);
    var total = 0;
    for (final token in q.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final s = _tokenScore(f, token);
      if (s == null) return null;
      total += s;
    }
    return total;
  }

  /// Filters and ranks [apps] by relevance to [query].
  static List<AppInfo> rank(List<AppInfo> apps, String query, {int? limit}) {
    final q = query.trim();
    List<AppInfo> list;
    if (q.isEmpty) {
      list = List<AppInfo>.from(apps)
        ..sort(
          (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
        );
    } else {
      final scored = <MapEntry<AppInfo, int>>[];
      for (final a in apps) {
        final s = score(a.packageName, a.appName, q);
        if (s != null) scored.add(MapEntry(a, s));
      }
      scored.sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.appName.toLowerCase().compareTo(
          b.key.appName.toLowerCase(),
        );
      });
      list = scored.map((e) => e.key).toList();
    }
    return limit == null ? list : list.take(limit).toList();
  }

  static int? _tokenScore(SearchFields f, String t) {
    if (f.name == t) return 1000;
    if (f.name.startsWith(t)) return 920 - t.length.clamp(0, 40);
    final ni = f.name.indexOf(t);
    if (ni >= 0) return 860 - ni.clamp(0, 40);
    if (f.pkg == t) return 840;
    if (f.pkg.contains(t)) return 800;
    if (f.initials == t) return 780;
    if (f.initials.startsWith(t)) return 760 - t.length.clamp(0, 30);
    if (f.initials.contains(t)) return 720;
    if (f.full.startsWith(t)) return 700 - t.length.clamp(0, 30);
    if (f.full.contains(t)) return 660;

    final fs = _subsequence(t, f.initials);
    if (fs != null) return 480 + fs;
    final ff = _subsequence(t, f.full);
    if (ff != null) return 440 + ff;
    final fn = _subsequence(t, f.name);
    if (fn != null) return 400 + fn;
    return null;
  }

  /// Fuzzy match: every character of [q] appears in [s] in order. Rewards
  /// contiguous and leading matches. Returns null when unmatched.
  static int? _subsequence(String q, String s) {
    if (q.isEmpty || s.isEmpty) return null;
    var si = 0;
    var score = 0;
    var last = -2;
    for (var qi = 0; qi < q.length; qi++) {
      final c = q.codeUnitAt(qi);
      var found = -1;
      for (var j = si; j < s.length; j++) {
        if (s.codeUnitAt(j) == c) {
          found = j;
          break;
        }
      }
      if (found < 0) return null;
      score += found == last + 1 ? 3 : 1;
      if (found == 0) score += 1;
      last = found;
      si = found + 1;
    }
    return score;
  }
}
