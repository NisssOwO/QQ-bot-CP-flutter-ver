package com.shinycolors.officialbot

import android.app.Activity
import android.content.Context
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts

/**
 * Bridges the notification permission request into the activity's result registry.
 *
 * Kotlin resolves an older androidx.activity than the manifest merge uses, so
 * `registerForActivityResult` callbacks cannot be used directly. Registering
 * through the registry keeps the system dialog working on Android 13+.
 */
class NotificationPermissionBinding(private val activity: Activity) {
    private val registry: ActivityResultRegistry? by lazy {
        try {
            val field = activity.javaClass.superclass?.superclass?.getDeclaredField("activityResultRegistry")
            field?.isAccessible = true
            field?.get(activity) as? ActivityResultRegistry
        } catch (_: Throwable) {
            null
        }
    }

    private val registration by lazy {
        registry?.register(
            "notification_permission",
            ActivityResultContracts.RequestPermission(),
        ) { granted: Boolean -> NotificationPermission.post(activity, granted) }
    }

    /** Shows the system dialog when possible and reports the state the caller can rely on. */
    fun request(): String {
        if (!NotificationPermission.needed(activity)) return NotificationPermission.current(activity)
        val launcher = registration ?: return NotificationPermission.current(activity)
        return try {
            launcher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            "pending"
        } catch (_: Throwable) {
            NotificationPermission.current(activity)
        }
    }
}

object NotificationPermission {
    fun needed(context: Context): Boolean = android.os.Build.VERSION.SDK_INT >= 33 &&
        androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) !=
        android.content.pm.PackageManager.PERMISSION_GRANTED

    fun current(context: Context): String =
        if (!needed(context)) "granted" else if (android.os.Build.VERSION.SDK_INT >= 33) "denied" else "unavailable"

    fun post(context: Context, granted: Boolean) {
        context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean("notificationPermissionGranted", granted).apply()
        RuntimeEventBus.emit(
            "info",
            "通知",
            if (granted) "已允许通知，运行状态会显示在通知栏" else "通知权限被拒绝，Runtime 仍会启动，但无法显示常驻通知",
        )
    }
}