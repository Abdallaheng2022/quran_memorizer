// memo_segment.dart — نموذج المقطع الواحد في جلسة التحفيظ.
class MemoSegment {
  final int index; // ترتيب المقطع (يبدأ من صفر)
  final String label; // اسم ظاهر للمستخدم (مثل «مقطع 1» أو رقم الآية)
  final String path; // مسار ملف صوت المحفّظ لهذا المقطع على الجهاز

  const MemoSegment({
    required this.index,
    required this.label,
    required this.path,
  });
}

/// إعدادات الجلسة التي يحدّدها المستخدم قبل بدء التحفيظ المقفل.
class MemoConfig {
  final int repetitions; // عدد مرات تكرار كل مقطع
  final bool listenFirst; // يسمع صوت المحفّظ قبل التسميع
  final bool recordSelf; // يسجّل صوته في كل تكرار
  final bool autoAdvance; // ينتقل تلقائيًا بعد انتهاء التلاوة (بدل زر «تم»)

  const MemoConfig({
    this.repetitions = 3,
    this.listenFirst = true,
    this.recordSelf = true,
    this.autoAdvance = false,
  });
}
