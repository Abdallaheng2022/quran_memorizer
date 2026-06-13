// memorize_setup.dart — تجهيز جلسة التحفيظ المقفلة.
//
// يختار المستخدم:
//   1) مصدر المقاطع: تقطيع تلقائي عبر السيرفر (صفحة/آيات/أرباع…)،
//      أو ملفات مقاطع جاهزة، أو ملف واحد كامل.
//   2) عدد مرات التكرار.
//   3) خيارات: الاستماع أولًا، تسجيل الصوت، الانتقال التلقائي.
// ثم يتأكّد من الأذونات (الميكروفون + عدم الإزعاج) ويبدأ الجلسة المقفلة.
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models/memo_segment.dart';
import '../services/recite_player.dart';
import '../services/segment_source.dart';
import '../services/session_lock.dart';
import 'memorize_session.dart';

enum _Source { server, files, single }

class MemorizeSetupScreen extends StatefulWidget {
  final Api api;
  const MemorizeSetupScreen({super.key, required this.api});

  @override
  State<MemorizeSetupScreen> createState() => _MemorizeSetupScreenState();
}

class _MemorizeSetupScreenState extends State<MemorizeSetupScreen> {
  _Source _source = _Source.server;

  // مصدر السيرفر
  final _range = TextEditingController(text: 'surah:112');
  String _level = 'page';
  Uint8List? _audioBytes;
  String? _audioName;

  // مصدر الملفات
  List<String> _pickedPaths = [];

  // إعدادات الجلسة
  int _reps = 3;
  bool _listenFirst = true;
  bool _recordSelf = true;
  bool _autoAdvance = false;

  bool _busy = false;
  String? _status;

  final _levels = const {
    'page': 'صفحات',
    'ayah': 'آيات',
    'rub': 'أرباع',
    'hizb': 'أحزاب',
    'juz': 'أجزاء',
  };

  Future<void> _pickServerAudio() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'],
      withData: true,
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() {
        _audioName = res.files.first.name;
        _audioBytes = res.files.first.bytes;
        _status = null;
      });
    }
  }

  Future<void> _pickSegmentFiles({required bool single}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'],
      allowMultiple: !single,
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() {
        _pickedPaths = res.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();
        _status = null;
      });
    }
  }

  /// يبني قائمة المقاطع حسب المصدر المختار.
  Future<List<MemoSegment>?> _buildSegments() async {
    if (_source == _Source.server) {
      if (_audioBytes == null) {
        setState(() => _status = 'اختر ملف صوت المحفّظ أولًا.');
        return null;
      }
      setState(() => _status = 'جارٍ التحليل والتقطيع عبر السيرفر…');
      final analyze = await widget.api.analyze(
        audio: _audioBytes!,
        name: _audioName ?? 'audio.mp3',
        range: _range.text.trim().isEmpty ? 'all' : _range.text.trim(),
        level: _level,
      );
      if (!analyze.ok) {
        setState(() => _status = analyze.data['error']?.toString() ??
            'تعذّر التحليل (${analyze.status}).');
        return null;
      }
      final token = analyze.data['token']?.toString();
      final bounds = analyze.data['bounds'] as List?;
      if (token == null || bounds == null) {
        setState(() => _status = 'ردّ غير متوقّع من السيرفر.');
        return null;
      }
      setState(() => _status = 'جارٍ تجهيز المقاطع…');
      final save = await widget.api.save(token, bounds);
      if (!save.ok || save.bytes == null) {
        setState(() => _status = save.data['error']?.toString() ??
            'تعذّر تجهيز الملف (${save.status}).');
        return null;
      }
      return SegmentSource.fromZipBytes(save.bytes!);
    } else {
      if (_pickedPaths.isEmpty) {
        setState(() => _status = 'اختر ملف/ملفات المقاطع أولًا.');
        return null;
      }
      return SegmentSource.fromPaths(_pickedPaths);
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _status = null;
    });

    // 1) تجهيز المقاطع
    final segments = await _buildSegments();
    if (segments == null || segments.isEmpty) {
      setState(() {
        _busy = false;
        _status ??= 'لم يتم العثور على مقاطع.';
      });
      return;
    }

    // 2) إذن الميكروفون (لو التسجيل مفعّل)
    if (_recordSelf) {
      final player = RecitePlayer();
      final ok = await player.hasMicPermission();
      await player.dispose();
      if (!ok) {
        setState(() {
          _busy = false;
          _status = 'يلزم إذن الميكروفون لتسجيل التسميع.';
        });
        return;
      }
    }

    // 3) إذن «عدم الإزعاج» لكتم الإشعارات (اختياري لكن موصى به)
    final dnd = await SessionLock.isDndGranted();
    if (!dnd && mounted) {
      final go = await _askDnd();
      if (go) {
        await SessionLock.openDndSettings();
        setState(() {
          _busy = false;
          _status = 'فعّل الإذن ثم اضغط «ابدأ» مرّة أخرى.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    final config = MemoConfig(
      repetitions: _reps,
      listenFirst: _listenFirst,
      recordSelf: _recordSelf,
      autoAdvance: _autoAdvance,
    );

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemorizeSessionScreen(segments: segments, config: config),
    ));
  }

  Future<bool> _askDnd() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('كتم الإشعارات'),
            content: const Text(
                'لكتمٍ تامّ للإشعارات أثناء التحفيظ، امنح التطبيق إذن «عدم الإزعاج». '
                'تقدر تتخطّى وتكمل بدونه.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('تخطّي'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('فتح الإعدادات'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('وضع التحفيظ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sourceSelector(),
          const SizedBox(height: 16),
          if (_source == _Source.server) ..._serverFields(),
          if (_source == _Source.files) _filesField(single: false),
          if (_source == _Source.single) _filesField(single: true),
          const Divider(height: 32),
          _repsField(),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _listenFirst,
            onChanged: (v) => setState(() => _listenFirst = v),
            title: const Text('استمع لصوت المحفّظ قبل التسميع'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _recordSelf,
            onChanged: (v) => setState(() => _recordSelf = v),
            title: const Text('سجّل صوتي في كل تكرار'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _autoAdvance,
            onChanged: _recordSelf
                ? (v) => setState(() => _autoAdvance = v)
                : null,
            title: const Text('انتقال تلقائي بعد التلاوة'),
            subtitle: const Text('بدل الضغط على «تم التسميع» يدويًا'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFFFF4E5),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'أثناء الجلسة سيُثبَّت التطبيق على الشاشة وتُكتَم الإشعارات، ولن تتمكّن '
                'من فتح تطبيقات أخرى حتى تُنهي كل التكرارات. يوجد زرّ خروج طارئ بضغطة '
                'مطوّلة عند الحاجة.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_clock),
            label: Text(_busy ? 'جارٍ التجهيز…' : 'ابدأ الجلسة المقفلة'),
          ),
        ],
      ),
    );
  }

  Widget _sourceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('مصدر المقاطع',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<_Source>(
          segments: const [
            ButtonSegment(value: _Source.server, label: Text('تقطيع تلقائي')),
            ButtonSegment(value: _Source.files, label: Text('مقاطع جاهزة')),
            ButtonSegment(value: _Source.single, label: Text('ملف واحد')),
          ],
          selected: {_source},
          onSelectionChanged: (s) => setState(() {
            _source = s.first;
            _status = null;
          }),
        ),
      ],
    );
  }

  List<Widget> _serverFields() {
    return [
      OutlinedButton.icon(
        onPressed: _busy ? null : _pickServerAudio,
        icon: const Icon(Icons.audiotrack),
        label: Text(_audioName ?? 'اختر ملف صوت المحفّظ'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _range,
        decoration: const InputDecoration(
          labelText: 'المدى (مثل surah:112 أو juz:30 أو all)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _level,
        decoration: const InputDecoration(
            labelText: 'مستوى التقطيع', border: OutlineInputBorder()),
        items: _levels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) => setState(() => _level = v ?? 'page'),
      ),
    ];
  }

  Widget _filesField({required bool single}) {
    final count = _pickedPaths.length;
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _pickSegmentFiles(single: single),
      icon: const Icon(Icons.library_music),
      label: Text(count == 0
          ? (single ? 'اختر ملف الصوت' : 'اختر ملفات المقاطع')
          : (single ? 'ملف مختار: ${_pickedPaths.first.split('/').last}' : 'تم اختيار $count مقطع')),
    );
  }

  Widget _repsField() {
    return Row(
      children: [
        const Text('عدد مرات التكرار',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton.filledTonal(
          onPressed: _reps > 1 ? () => setState(() => _reps--) : null,
          icon: const Icon(Icons.remove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('$_reps',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        IconButton.filledTonal(
          onPressed: _reps < 50 ? () => setState(() => _reps++) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
