package com.example.qq_bot_cp_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import java.util.UUID

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
            val runId = UUID.randomUUID().toString().take(8)
            RuntimeEventBus.runId = runId
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("runId", runId).remove("runtimeLastError").apply()
            update("starting", "restart.begin", "开始启动（runId=$runId）")
            try {
                update("starting", "process.stop", "确认旧 Runtime 已停止", System.currentTimeMillis() - started)
                controller?.stop()
                update("starting", "runtime.prepare", "正在准备 Node/DSH 运行文件", System.currentTimeMillis() - started)
                val root = RuntimeAssetInstaller.install(this)
                update("starting", "config.load", "读取公开配置和 Keystore 凭据（${root.name}）", System.currentTimeMillis() - started)
                val configured = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)
                if (configured) {
                    update("starting", "runtime.spawn", "正在启动 Node/DSH 子进程", System.currentTimeMillis() - started)
                    controller = RuntimeProcessController(this)
                    val credentials = CredentialStore(this)
                    val config = getSharedPreferences("public-config", MODE_PRIVATE)
                    controller?.start(mapOf(
                        "QQBOT_APPID" to credentials.read("qqbotAppId"),
                        "QQBOT_SECRET" to credentials.read("qqbotSecret"),
                        "LLM_API_KEY" to credentials.read("llmApiKey"),
                        "LLM_PROVIDER" to config.getString("protocol", "").orEmpty(),
                        "LLM_MODEL" to config.getString("model", "").orEmpty(),
                        "LLM_BASE_URL" to config.getString("baseUrl", "").orEmpty(),
                    ))
                    update("online", "ready", "Node/DSH 进程已启动，等待网关和模型就绪", System.currentTimeMillis() - started)
                } else {
                    update("online", "ready", "服务已就绪，等待在 Flutter 中填写凭据", System.currentTimeMillis() - started)
                }
                update("online", "restart.complete", "启动流程完成", System.currentTimeMillis() - started)
            } catch (error: Exception) {
                update("failed", "restart.failed", "启动失败：${error.message ?: error}", System.currentTimeMillis() - started)
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
        RuntimeEventBus.emit("info", "runtime", "$phase：$message", elapsedMs.takeIf { it > 0 })
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("$phase：$message"))
    }

    private fun notification(text: String): Notification = Notification.Builder(this, CHANNEL)
        .setContentTitle("QQ-bot-CP").setContentText(text)
        .setSmallIcon(android.R.drawable.stat_notify_sync).setOngoing(true).build()

}

