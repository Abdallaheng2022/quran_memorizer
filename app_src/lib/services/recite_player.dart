// recite_player.dart — تشغيل صوت المحفّظ + تسجيل صوت المتعلّم.
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

class RecitePlayer {
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  /// يحمّل ملف المقطع ويعيد مدّته (قد تكون null لو تعذّر القياس).
  Future<Duration?> load(String path) async {
    try {
      return await _player.setFilePath(path);
    } catch (_) {
      return null;
    }
  }

  /// يشغّل المقطع من بدايته حتى نهايته (ينتظر الاكتمال).
  Future<void> playToEnd() async {
    await _player.seek(Duration.zero);
    await _player.play();
    await _player.playerStateStream.firstWhere(
      (s) => s.processingState == ProcessingState.completed,
    );
    await _player.stop();
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// تيّار موضع التشغيل (لعرض شريط تقدّم أثناء الاستماع).
  Stream<Duration> get positionStream => _player.positionStream;

  Future<bool> hasMicPermission() => _recorder.hasPermission();

  Future<void> startRecording(String path) async {
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
  }

  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (_) {
      return null;
    }
  }

  Future<bool> isRecording() => _recorder.isRecording();

  /// مستوى صوت الإدخال أثناء التسجيل (للمؤشّر البصري).
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 200));

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
