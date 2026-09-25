import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/native_apps.dart';

/// Loads an app icon from the native side and caches it in memory.
class AppIcon extends StatefulWidget {
  const AppIcon({
    super.key,
    required this.packageName,
    required this.label,
    this.size = 44,
    this.bytes,
  });

  final String packageName;
  final String label;
  final double size;

  /// Pre-decoded icon bytes (e.g. read from a downloaded APK). When set the
  /// icon is not fetched from the native side.
  final Uint8List? bytes;

  static final Map<String, Uint8List?> _cache = {};

  static void evictAll() => _cache.clear();

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName ||
        oldWidget.bytes != widget.bytes) {
      _bytes = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.bytes != null) {
      setState(() {
        _bytes = widget.bytes;
        _loading = false;
      });
      return;
    }
    final cached = AppIcon._cache[widget.packageName];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _bytes = cached;
        _loading = false;
      });
      return;
    }
    try {
      final bytes = await NativeApps.getAppIcon(
        widget.packageName,
        size: (widget.size * 3).round(),
      );
      AppIcon._cache[widget.packageName] = bytes;
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      AppIcon._cache[widget.packageName] = null;
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.size * 0.26);
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      );
    }
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: _colorFor(widget.label),
      ),
      child: _loading
          ? SizedBox(
              width: widget.size * 0.4,
              height: widget.size * 0.4,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              widget.label.isEmpty ? '?' : widget.label.characters.first,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: widget.size * 0.45,
              ),
            ),
    );
  }

  Color _colorFor(String label) {
    final hash = label.codeUnits.fold<int>(0, (p, c) => p * 31 + c);
    final hue = (hash % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
  }
}
