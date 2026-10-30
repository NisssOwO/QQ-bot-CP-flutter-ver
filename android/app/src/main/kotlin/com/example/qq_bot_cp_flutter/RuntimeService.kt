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
    private var controller: RuntimeProcessController? = null

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
            update("starting", "安装 Runtime Bundle", "正在准备 Node/DSH 运行文件")
            val root = RuntimeAssetInstaller.install(this)
            update("starting", "检查凭据", "Runtime 文件已准备：${root.name}")
            val configured = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)
            if (configured) {
                update("starting", "启动 Node/DSH", "正在启动后台进程")
                controller = RuntimeProcessController(this)
                controller?.start(emptyMap())
                update("online", "Runtime 已启动", "Node/DSH 进程运行中", System.currentTimeMillis() - started)
            } else {
                update("online", "服务已就绪", "等待在 Flutter 中填写凭据", System.currentTimeMillis() - started)
            }
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("服务已就绪"))
        }, "runtime-bootstrap").start()
        return START_STICKY
    }

    override fun onDestroy() {
        controller?.stop()
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
