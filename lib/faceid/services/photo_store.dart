import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStore {
  PhotoStore._();

  static Directory? _baseDir;

  static Future<Directory> baseDir() async {
    final existing = _baseDir;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'faceid'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _baseDir = dir;
    return dir;
  }

  static Future<Directory> _subDir(String name) async {
    final base = await baseDir();
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> knownFacesDir() => _subDir('known_faces');

  static Future<Directory> capturedDir() => _subDir('captured');

  static Future<Directory> tempDir() => _subDir('tmp');

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}_'
        '${three(time.millisecond)}';
  }

  static Future<String> saveKnownFace(
    int personId,
    Uint8List jpeg, {
    DateTime? time,
  }) async {
    final dir = await knownFacesDir();
    final stamp = _stamp(time ?? DateTime.now());
    final path = p.join(dir.path, '${personId}_$stamp.jpg');
    await File(path).writeAsBytes(jpeg, flush: true);
    return path;
  }

  static Future<String> saveScanPhoto(
    int personId,
    String action,
    Uint8List jpeg, {
    DateTime? time,
  }) async {
    final dir = await capturedDir();
    final stamp = _stamp(time ?? DateTime.now());
    final path = p.join(dir.path, '${personId}_${action}_$stamp.jpg');
    await File(path).writeAsBytes(jpeg, flush: true);
    return path;
  }

  static Future<String> writeTemp(Uint8List bytes, String name) async {
    final dir = await tempDir();
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<void> deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // E'tiborsiz qoldiriladi.
    }
  }

  static Future<void> cleanupTemp() async {
    try {
      final dir = await tempDir();
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // E'tiborsiz qoldiriladi.
          }
        }
      }
    } catch (_) {
      // E'tiborsiz qoldiriladi.
    }
  }
}
