import 'package:intl/intl.dart';

class Fmt {
  static final DateFormat _date = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _day = DateFormat('yyyy-MM-dd');

  static String dateTime(int millis) =>
      millis <= 0 ? '未知' : _date.format(DateTime.fromMillisecondsSinceEpoch(millis));

  static String day(int millis) =>
      millis <= 0 ? '未知' : _day.format(DateTime.fromMillisecondsSinceEpoch(millis));

  static String size(int bytes) {
    if (bytes <= 0) return '未知';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  static String relative(int millis) {
    if (millis <= 0) return '未知';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()} 年前';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()} 个月前';
    if (diff.inDays >= 1) return '${diff.inDays} 天前';
    if (diff.inHours >= 1) return '${diff.inHours} 小时前';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} 分钟前';
    return '刚刚';
  }
}
