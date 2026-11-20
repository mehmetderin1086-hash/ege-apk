import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persistent on-disk cache for synthesized speech (like the Windows JARVIS
/// `synthesize_tts_cached`): repeated phrases play instantly and offline.
class TtsDiskCache {
  static bool enabled = true;
  static const int maxFiles = 400;

  static Future<Directory?>? _opening;
  static final Map<String, String> _index = {};

  static Future<Directory?> _ensure() => _opening ??= _open();

  static Future<Directory?> _open() async {
    try {
      final base = await getApplicationCacheDirectory();
      final d = Directory('${base.path}${Platform.pathSeparator}jarvis_tts');
      await d.create(recursive: true);
      for (final f in d.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        final hash = name.split('__').first;
        _index[hash] = name;
      }
      return d;
    } catch (_) {
      enabled = false;
      return null;
    }
  }

  /// FNV-1a 64-bit hash + length; plenty for a phrase cache.
  static String hashKey(String key) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(key)) {
      h ^= b;
      h = h * 0x100000001b3;
    }
    return '${h.toUnsigned(64).toRadixString(16)}${key.length.toRadixString(36)}';
  }

  static Future<({Uint8List bytes, String ext, String providerId})?> get(
    String key,
  ) async {
    if (!enabled) return null;
    final dir = await _ensure();
    if (dir == null) return null;
    final name = _index[hashKey(key)];
    if (name == null) return null;
    try {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      final bytes = await f.readAsBytes();
      if (bytes.length < 200) return null;
      await f.setLastModified(DateTime.now());
      final parts = name.split('__');
      final rest = parts.length > 1 ? parts[1] : 'cache.mp3';
      final dot = rest.lastIndexOf('.');
      return (
        bytes: bytes,
        ext: dot < 0 ? 'mp3' : rest.substring(dot + 1),
        providerId: dot < 0 ? rest : rest.substring(0, dot),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> put(
    String key,
    Uint8List bytes,
    String ext,
    String providerId,
  ) async {
    if (!enabled || bytes.length < 200) return;
    final dir = await _ensure();
    if (dir == null) return;
    final hash = hashKey(key);
    final safeProvider = providerId.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final name = '${hash}__$safeProvider.$ext';
    try {
      await File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
      _index[hash] = name;
      if (_index.length > maxFiles) await _trim(dir);
    } catch (_) {}
  }

  static Future<void> _trim(Directory dir) async {
    try {
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files.take(files.length - maxFiles + 60)) {
        final name = f.uri.pathSegments.last;
        _index.remove(name.split('__').first);
        await f.delete();
      }
    } catch (_) {}
  }

  static Future<({int files, int bytes})> stats() async {
    final dir = await _ensure();
    if (dir == null) return (files: 0, bytes: 0);
    var total = 0;
    var count = 0;
    for (final f in dir.listSync().whereType<File>()) {
      count++;
      total += f.lengthSync();
    }
    return (files: count, bytes: total);
  }

  static Future<int> clear() async {
    final dir = await _ensure();
    if (dir == null) return 0;
    var n = 0;
    for (final f in dir.listSync().whereType<File>()) {
      try {
        await f.delete();
        n++;
      } catch (_) {}
    }
    _index.clear();
    return n;
  }
}
