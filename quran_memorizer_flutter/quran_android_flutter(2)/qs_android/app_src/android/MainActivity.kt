package PLACEHOLDER_PACKAGE

import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "quran.lock/session"

    private val dpm: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val adminComponent: ComponentName
        get() = ComponentName(this, QuranAdminReceiver::class.java)

    private val notifManager: NotificationManager
        get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceOwner" -> result.success(isDeviceOwner())
                    "isDndGranted" -> result.success(notifManager.isNotificationPolicyAccessGranted)
                    "openDndSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    "requestAdmin" -> {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "لتمكين القفل الكامل أثناء جلسات التحفيظ."
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "startLock" -> {
                        startLock()
                        result.success(true)
                    }
                    "stopLock" -> {
                        stopLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isDeviceOwner(): Boolean {
        return try {
            dpm.isDeviceOwnerApp(packageName)
        } catch (e: Exception) {
            false
        }
    }

    private fun startLock() {
        // 1) كتم الإشعارات كليًّا إن مُنح الإذن
        try {
            if (notifManager.isNotificationPolicyAccessGranted) {
                notifManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
            }
        } catch (_: Exception) {}

        // 2) لو التطبيق Device Owner: اسمح بقفل المهام لحزمتنا (Kiosk حقيقي)
        try {
            if (isDeviceOwner()) {
                dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
            }
        } catch (_: Exception) {}

        // 3) ابدأ قفل المهام / تثبيت الشاشة
        try {
            startLockTask()
        } catch (_: Exception) {}
    }

    private fun stopLock() {
        try {
            stopLockTask()
        } catch (_: Exception) {}
        try {
            if (notifManager.isNotificationPolicyAccessGranted) {
                notifManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
            }
        } catch (_: Exception) {}
    }
}
