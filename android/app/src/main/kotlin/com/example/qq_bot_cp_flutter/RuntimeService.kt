package com.example.qq_bot_cp_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder

class RuntimeService : Service() {
    companion object {
        const val PREFS = "runtime"
        private const val CHANNEL = "runtime"
        private const val NOTIFICATION_ID = 1001
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "QQ-bot-CP Runtime", NotificationManager.IMPORTANCE_LOW))
        startForeground(NOTIFICATION_ID, notification("正在启动 Runtime"))
        update("starting", "准备启动", "正在初始化 Android Runtime")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Thread({
            val started = System.currentTimeMillis()
            update("starting", "检查运行环境", "Runtime Service 已启动")
            Thread.sleep(150)
            update("starting", "等待 Node/DSH 接入", "原生服务已就绪，Node Runtime 尚未接入")
            update("online", "服务已就绪", "等待 Runtime 进程接入", System.currentTimeMillis() - started)
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("服务已就绪，Runtime 待接入"))
        }, "runtime-bootstrap").start()
        return START_STICKY
    }

    override fun onDestroy() {
        update("stopped", "已停止", "Runtime Service 已停止")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun update(status: String, phase: String, message: String, elapsedMs: Long = 0) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString("status", status).putString("phase", phase)
            .putString("message", message).putLong("elapsedMs", elapsedMs).apply()
    }

    private fun notification(text: String): Notification = Notification.Builder(this, CHANNEL)
        .setContentTitle("QQ-bot-CP").setContentText(text)
        .setSmallIcon(android.R.drawable.stat_notify_sync).setOngoing(true).build()

}
