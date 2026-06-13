// session_lock.dart — التحكّم في «القفل الصارم» للجلسة.
//
// يجمع بين:
//   • تثبيت الشاشة (Lock Task / Screen Pinning) عبر قناة أصلية للأندرويد.
//     - بدون Device Owner: تثبيت شاشة يمنع الخروج العادي (يُخرَج بضغط مطوّل
//       على «رجوع + المهام» ويُظهر تنبيهًا) — وهو أقوى قفل متاح لتطبيق عادي.
//     - مع Device Owner: قفل كامل غير قابل للهروب (Kiosk حقيقي).
//   • كتم الإشعارات كليًّا (Do Not Disturb = None).
//   • إبقاء الشاشة مضاءة + وضع غامر يخفي أشرطة النظام.
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SessionLock {
  static const MethodChannel _ch = MethodChannel('quran.lock/session');

  /// هل التطبيق مفعّل كـ Device Owner (قفل كامل ممكن)؟
  static Future<bool> isDeviceOwner() async {
    try {
      return await _ch.invokeMethod<bool>('isDeviceOwner') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// هل مُنح إذن «عدم الإزعاج»؟
  static Future<bool> isDndGranted() async {
    try {
      return await _ch.invokeMethod<bool>('isDndGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يفتح شاشة إعدادات منح إذن «عدم الإزعاج».
  static Future<void> openDndSettings() async {
    try {
      await _ch.invokeMethod('openDndSettings');
    } catch (_) {}
  }

  /// يفتح شاشة تفعيل مدير الجهاز (لازم لمحاولة القفل الأقوى/الـ Kiosk).
  static Future<void> requestAdmin() async {
    try {
      await _ch.invokeMethod('requestAdmin');
    } catch (_) {}
  }

  /// يبدأ القفل الصارم.
  static Future<void> start() async {
    await WakelockPlus.enable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await _ch.invokeMethod('startLock'); // كتم الإشعارات + تثبيت الشاشة
    } catch (_) {}
  }

  /// ينهي القفل ويعيد كل شيء لطبيعته.
  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stopLock');
    } catch (_) {}
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await WakelockPlus.disable();
  }
}
