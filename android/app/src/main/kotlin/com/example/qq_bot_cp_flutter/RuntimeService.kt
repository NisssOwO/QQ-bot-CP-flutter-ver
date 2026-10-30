package com.shinycolors.officialbot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.ConnectivityManager
import android.net.Network
import java.util.UUID
import android.app.PendingIntent

class RuntimeService : Service() {
    companion object {
        const val PREFS = "runtime"
        private const val CHANNEL = "runtime"
        private const val NOTIFICATION_ID = 1001
    }
    private var controller: RuntimeProcessController? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val reconnectHandler = Handler(Looper.getMainLooper())
    private var reconnectAttempt = 0

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "QQ-bot-CP Runtime", NotificationManager.IMPORTANCE_LOW))
        startForeground(NOTIFICATION_ID, notification("正在启动 Runtime"))
        update("starting", "准备启动", "正在初始化 Android Runtime")
        registerNetworkCallback()
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
                    controller?.start(runtimeEnvironment())
                    reconnectAttempt = 0
                    update("online", "ready", "Node/DSH 进程已启动，等待网关和模型就绪", System.currentTimeMillis() - started)
                } else {
                    update("online", "ready", "服务已就绪，等待在 Flutter 中填写凭据", System.currentTimeMillis() - started)
                }
                update("online", "restart.complete", "启动流程完成", System.currentTimeMillis() - started)
            } catch (error: Exception) {
                update("failed", "restart.failed", "启动失败：${error.message ?: error}", System.currentTimeMillis() - started, "runtime_start_failed")
            }
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("服务已就绪"))
        }, "runtime-bootstrap").start()
        return START_STICKY
    }

    override fun onDestroy() {
        reconnectHandler.removeCallbacksAndMessages(null)
        networkCallback?.let { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) }
        networkCallback = null
        controller?.stop()
        update("stopped", "已停止", "Runtime Service 已停止")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun update(status: String, phase: String, message: String, elapsedMs: Long = 0, errorCode: String? = null) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString("status", status).putString("phase", phase)
            .putString("message", message).putLong("elapsedMs", elapsedMs).apply()
        RuntimeEventBus.emit(if (status == "failed") "error" else "info", "runtime", "$phase：$message", elapsedMs.takeIf { it > 0 }, errorCode)
        RuntimeWidgetProvider.updateAll(this)
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("$phase：$message"))
    }

    private fun notification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(this, 1002, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stopIntent = PendingIntent.getBroadcast(this, 1003, Intent(this, RuntimeActionReceiver::class.java).setAction(RuntimeActionReceiver.ACTION_STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("QQ-bot-CP").setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync).setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(Notification.Action.Builder(null, "停止 Runtime", stopIntent).build())
            .build()
    }

    private fun runtimeEnvironment(): Map<String, String> {
        val credentials = CredentialStore(this)
        val config = getSharedPreferences("public-config", MODE_PRIVATE)
        return mapOf(
            "QQBOT_APPID" to credentials.read("qqbotAppId"),
            "QQBOT_SECRET" to credentials.read("qqbotSecret"),
            "LLM_API_KEY" to credentials.read("llmApiKey"),
            "LLM_PROVIDER" to config.getString("protocol", "").orEmpty(),
            "LLM_MODEL" to config.getString("model", "").orEmpty(),
            "LLM_BASE_URL" to config.getString("baseUrl", "").orEmpty(),
        )
    }

    private fun scheduleReconnect() {
        if (!getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)) return
        if (controller?.isAlive() == true) {
            reconnectAttempt = 0
            return
        }
        val delay = minOf(60_000L, 1_000L shl minOf(reconnectAttempt, 6))
        reconnectAttempt++
        update("reconnecting", "network.retry", "第 $reconnectAttempt 次重连，${delay / 1000} 秒后检查", delay)
        reconnectHandler.postDelayed({
            try {
                if (controller?.isAlive() != true) {
                    controller = RuntimeProcessController(this)
                    controller?.start(runtimeEnvironment())
                    update("online", "network.recovered", "Runtime 进程已恢复")
                    reconnectAttempt = 0
                }
            } catch (error: Exception) {
                RuntimeEventBus.emit("error", "network", "重连失败：${error.message ?: error}", errorCode = "runtime_reconnect_failed")
                if (reconnectAttempt < 7) scheduleReconnect() else update("failed", "network.cooldown", "连续重连失败，进入冷却", errorCode = "runtime_reconnect_cooldown")
            }
        }, delay)
    }

    private fun registerNetworkCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            RuntimeEventBus.emit("warn", "network", "当前 Android 版本不支持默认网络回调", errorCode = "network_callback_unsupported")
            return
        }
        val manager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                RuntimeEventBus.emit("info", "network", "网络已恢复，准备检查 Runtime 连接", errorCode = "network_available")
                val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                if (prefs.getString("status", "") == "reconnecting") {
                    scheduleReconnect()
                }
            }
            override fun onLost(network: Network) {
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("status", "reconnecting").putString("phase", "network.lost").putString("message", "网络断开，等待恢复").apply()
                RuntimeEventBus.emit("warn", "network", "网络已断开，Runtime 将等待恢复", errorCode = "network_lost")
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("网络断开，等待恢复"))
            }
        }
        manager.registerDefaultNetworkCallback(callback)
        networkCallback = callback
    }

}

