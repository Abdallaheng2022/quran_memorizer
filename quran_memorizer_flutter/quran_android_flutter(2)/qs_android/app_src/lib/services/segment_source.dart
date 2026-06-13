// segment_source.dart — تجهيز قائمة المقاطع من مصادر مختلفة.
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/memo_segment.dart';

class SegmentSource {
  /// يفكّ ضغط ملف الـ zip القادم من السيرفر ويكتب المقاطع على القرص،
  /// ثم يعيد قائمتها مرتّبة باسم الملف.
  static Future<List<MemoSegment>> fromZipBytes(Uint8List zipBytes) async {
    final base = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outDir = Directory('${base.path}/segments_$stamp');
    await outDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final paths = <String>[];
    for (final entry in archive) {
      if (entry.isFile && _isAudio(entry.name)) {
        final f = File('${outDir.path}/${_safeName(entry.name)}');
        await f.create(recursive: true);
        await f.writeAsBytes(entry.content as List<int>);
        paths.add(f.path);
      }
    }
    paths.sort();
    return _toSegments(paths);
  }

  /// يبني المقاطع من مسارات ملفات اختارها المستخدم مباشرةً.
  static List<MemoSegment> fromPaths(List<String> paths) {
    final clean = paths.where((p) => _isAudio(p)).toList()..sort();
    return _toSegments(clean);
  }

  static List<MemoSegment> _toSegments(List<String> paths) {
    final out = <MemoSegment>[];
    for (var i = 0; i < paths.length; i++) {
      final name = paths[i].split('/').last;
      out.add(MemoSegment(index: i, label: 'مقطع ${i + 1} · $name', path: paths[i]));
    }
    return out;
  }

  static bool _isAudio(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp3') ||
        n.endsWith('.m4a') ||
        n.endsWith('.wav') ||
        n.endsWith('.ogg') ||
        n.endsWith('.aac') ||
        n.endsWith('.opus');
  }

  static String _safeName(String name) =>
      name.split('/').last.replaceAll(RegExp(r'[^\w.\-]'), '_');
}
