// memorize_session.dart — الجلسة المقفلة: تشغيل/تسجيل/تكرار حتى الانتهاء.
//
// التسلسل لكل مقطع، ولكل تكرار من 1..N:
//   • (اختياري) استماع: يُشغَّل صوت المحفّظ كاملًا.
//   • (اختياري) تسميع: يبدأ التسجيل، ويُحفظ ملف لكل تكرار.
//     ينتهي التسجيل إمّا بزر «تم التسميع» أو تلقائيًا حسب الإعداد.
// أثناء ذلك الشاشة مثبّتة والإشعارات مكتومة، وزرّ الرجوع معطّل،
// مع زرّ خروج طارئ بضغطة مطوّلة.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/memo_segment.dart';
import '../services/recite_player.dart';
import '../services/session_lock.dart';

class MemorizeSessionScreen extends StatefulWidget {
  final List<MemoSegment> segments;
  final MemoConfig config;
  const MemorizeSessionScreen({
    super.key,
    required this.segments,
    required this.config,
  });

  @override
  State<MemorizeSessionScreen> createState() => _MemorizeSessionScreenState();
}

enum _Phase { preparing, listening, reciting, finished }

class _MemorizeSessionScreenState extends State<MemorizeSessionScreen> {
  final RecitePlayer _player = RecitePlayer();

  int _segIndex = 0;
  int _rep = 1;
  _Phase _phase = _Phase.preparing;
  bool _cancelled = false;

  late String _sessionDir;
  final List<String> _recordings = [];

  // إشارة «تم التسميع» اليدوية
  Completer<void>? _recitalDone;

  // مؤقّت عرض زمن التسجيل
  Timer? _ticker;
  int _recSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await SessionLock.start();

    final base = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    _sessionDir = '${base.path}/memorize_$stamp';
    await Directory(_sessionDir).create(recursive: true);

    for (var s = 0; s < widget.segments.length; s++) {
      if (_cancelled) break;
      final seg = widget.segments[s];
      await _player.load(seg.path);

      for (var r = 1; r <= widget.config.repetitions; r++) {
        if (_cancelled) break;
        if (mounted) {
          setState(() {
            _segIndex = s;
            _rep = r;
          });
        }

        // مرحلة الاستماع
        if (widget.config.listenFirst) {
          _setPhase(_Phase.listening);
          await _player.playToEnd();
          if (_cancelled) break;
        }

        // مرحلة التسميع/التسجيل
        if (widget.config.recordSelf) {
          _setPhase(_Phase.reciting);
          final path =
              '$_sessionDir/seg${s + 1}_rep$r.m4a';
          await _player.startRecording(path);
          _startTicker();

          if (widget.config.autoAdvance) {
            // سجّل بمدّة مساوية لمدّة المقطع تقريبًا (دقيقة كحدّ أقصى احتياطي)
            await Future.delayed(const Duration(seconds: 30));
          } else {
            _recitalDone = Completer<void>();
            await _recitalDone!.future; // ينتظر زرّ «تم التسميع»
          }

          _stopTicker();
          final saved = await _player.stopRecording();
          if (saved != null) _recordings.add(saved);
        } else {
          // بلا تسجيل: فاصل قصير بين التكرارات
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
    }

    await SessionLock.stop();
    if (mounted) {
      setState(() => _phase = _Phase.finished);
    }
  }

  void _setPhase(_Phase p) {
    if (mounted) setState(() => _phase = p);
  }

  void _markRecitalDone() {
    if (_recitalDone != null && !_recitalDone!.isCompleted) {
      _recitalDone!.complete();
    }
  }

  void _startTicker() {
    _recSeconds = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSeconds++);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _emergencyExit() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('إنهاء الجلسة؟'),
            content: const Text(
                'سيتم إنهاء التحفيظ المقفل قبل إكمال كل التكرارات. متأكّد؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('متابعة')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('إنهاء')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    _cancelled = true;
    _markRecitalDone(); // يحرّر الانتظار لو كان واقفًا على زر «تم»
    await _player.stopPlayback();
    await _player.stopRecording();
    _stopTicker();
    await SessionLock.stop();
    if (mounted) setState(() => _phase = _Phase.finished);
  }

  @override
  void dispose() {
    _stopTicker();
    _player.dispose();
    SessionLock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.segments.length * widget.config.repetitions;
    final done = _phase == _Phase.finished
        ? total
        : (_segIndex * widget.config.repetitions) + (_rep - 1);
    final progress = total == 0 ? 0.0 : done / total;

    return PopScope(
      canPop: _phase == _Phase.finished,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E3B30),
        body: SafeArea(
          child: _phase == _Phase.finished
              ? _finishedView()
              : _activeView(progress, total, done),
        ),
      ),
    );
  }

  Widget _activeView(double progress, int total, int done) {
    final seg = widget.segments[_segIndex];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.lock, color: Colors.white70, size: 20),
              const Text('جلسة تحفيظ مقفلة',
                  style: TextStyle(color: Colors.white70)),
              Text('$done / $total',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF66D6B5)),
            ),
          ),
          const Spacer(),
          Text(
            seg.label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'التكرار $_rep من ${widget.config.repetitions}',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 40),
          _phaseIndicator(),
          const Spacer(),
          if (_phase == _Phase.reciting && !widget.config.autoAdvance)
            FilledButton.icon(
              onPressed: _markRecitalDone,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF66D6B5),
                foregroundColor: const Color(0xFF0E3B30),
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.check),
              label: const Text('تم التسميع',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 16),
          GestureDetector(
            onLongPress: _emergencyExit,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Text('خروج طارئ — اضغط مطوّلًا',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseIndicator() {
    switch (_phase) {
      case _Phase.listening:
        return Column(
          children: const [
            Icon(Icons.volume_up_rounded, color: Color(0xFF66D6B5), size: 72),
            SizedBox(height: 12),
            Text('استمع لصوت المحفّظ…',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        );
      case _Phase.reciting:
        final m = (_recSeconds ~/ 60).toString().padLeft(2, '0');
        final s = (_recSeconds % 60).toString().padLeft(2, '0');
        return Column(
          children: [
            const Icon(Icons.mic, color: Colors.redAccent, size: 72),
            const SizedBox(height: 12),
            const Text('سمّع الآن — يُسجَّل صوتك',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 6),
            Text('$m:$s',
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
          ],
        );
      default:
        return const Column(
          children: [
            SizedBox(
                height: 48,
                width: 48,
                child: CircularProgressIndicator(color: Color(0xFF66D6B5))),
            SizedBox(height: 12),
            Text('جارٍ التجهيز…', style: TextStyle(color: Colors.white)),
          ],
        );
    }
  }

  Widget _finishedView() {
    final saved = _recordings.length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_rounded,
              color: Color(0xFF66D6B5), size: 88),
          const SizedBox(height: 16),
          Text(
            _cancelled ? 'تم إنهاء الجلسة' : 'أحسنت! اكتملت الجلسة',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (widget.config.recordSelf)
            Text('حُفظ $saved تسجيلًا لتسميعك',
                style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          if (saved > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'المجلّد: $_sessionDir',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          const SizedBox(height: 32),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF66D6B5),
              foregroundColor: const Color(0xFF0E3B30),
              minimumSize: const Size(200, 52),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}
