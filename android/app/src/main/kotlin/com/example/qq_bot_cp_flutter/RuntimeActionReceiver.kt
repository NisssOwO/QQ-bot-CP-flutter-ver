package com.shinycolors.officialbot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class RuntimeActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_STOP -> context.stopService(Intent(context, RuntimeService::class.java))
            ACTION_RESTART -> {
                // The notification action is a user gesture, so the foreground service
                // may start here; keep the receiver alive until both steps ran.
                val pending = goAsync()
                try {
                    context.stopService(Intent(context, RuntimeService::class.java))
                    val error = RuntimeLauncher.request(context, "notification")
                    if (error != null) RuntimeLogRecorder(context).record(RuntimeLogRecorder.Status.FAILED, "restart.begin", "无法从通知重启：$error", 0, error)
                } finally {
                    pending.finish()
                }
            }
        }
    }

    companion object {
        const val ACTION_STOP = "com.shinycolors.officialbot.action.STOP_RUNTIME"
        const val ACTION_RESTART = "com.shinycolors.officialbot.action.RESTART_RUNTIME"
    }
}