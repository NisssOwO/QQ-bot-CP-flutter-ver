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
    private var reconnectScheduled = false
    @Volatile private var bootstrapGeneration = 0L

    override fun onCreate() {
        super.onCreate()
        RuntimeEventBus.setContext(this)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "QQ-bot-CP Runtime", NotificationManager.IMPORTANCE_LOW))
        startForeground(NOTIFICATION_ID, notification("正在启动 Runtime"))
        update("starting", "准备启动", "正在初始化 Android Runtime")
        registerNetworkCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        reconnectHandler.removeCallbacksAndMessages(null)
        reconnectScheduled = false
        val generation = ++bootstrapGeneration
        Thread({
            val started = System.currentTimeMillis()
            val runId = UUID.randomUUID().toString().take(8)
            RuntimeEventBus.runId = runId
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("runId", runId).remove("runtimeLastError").apply()
            if (!isCurrentGeneration(generation)) return@Thread
            update("starting", "restart.begin", "开始启动（runId=$runId）")
            try {
                if (!isCurrentGeneration(generation)) return@Thread
                update("starting", "process.stop", "确认旧 Runtime 已停止", System.currentTimeMillis() - started)
                controller?.stop()
                if (!isCurrentGeneration(generation)) return@Thread
                update("starting", "runtime.prepare", "正在准备 Node/DSH 运行文件", System.currentTimeMillis() - started)
                val root = RuntimeAssetInstaller.install(this)
                if (!isCurrentGeneration(generation)) return@Thread
                update("starting", "config.load", "读取公开配置和 Keystore 凭据（${root.name}）", System.currentTimeMillis() - started)
                update("starting", "plugin.load", "正在加载 DSH profile 和 QQ/角色插件", System.currentTimeMillis() - started)
                val configured = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)
                if (configured) {
                    if (!isCurrentGeneration(generation)) return@Thread
                    val network = getSystemService(ConnectivityManager::class.java).activeNetwork
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("networkStatus", if (network == null) "离线" else "在线").apply()
                    update("starting", "network.check", if (network == null) "当前没有可用网络，Runtime 将等待重连" else "检测到可用网络，准备连接网关", System.currentTimeMillis() - started, if (network == null) "network_unavailable" else null)
                    update("starting", "runtime.spawn", "正在启动 Node/DSH 子进程", System.currentTimeMillis() - started)
                    if (!isCurrentGeneration(generation)) return@Thread
                    controller = RuntimeProcessController(this)
                    controller?.start(runtimeEnvironment())
                    if (!isCurrentGeneration(generation)) {
                        controller?.stop()
                        return@Thread
                    }
                    reconnectAttempt = 0
                    update("starting", "qq.connect", "已启动 QQ Bot 连接流程，等待 WebSocket 握手", System.currentTimeMillis() - started)
                    update("starting", "session.restore", "正在准备会话目录（不会把会话内容写入日志）", System.currentTimeMillis() - started)
                    update("online", "ready", "Node/DSH 进程已启动，等待网关和模型就绪", System.currentTimeMillis() - started)
                } else {
                    update("online", "ready", "服务已就绪，等待在 Flutter 中填写凭据", System.currentTimeMillis() - started)
                }
                if (isCurrentGeneration(generation)) update("online", "restart.complete", "启动流程完成", System.currentTimeMillis() - started)
            } catch (error: Exception) {
                if (isCurrentGeneration(generation)) update("failed", "restart.failed", "启动失败：${error.message ?: error}", System.currentTimeMillis() - started, "runtime_start_failed")
            }
            if (isCurrentGeneration(generation)) getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("服务已就绪"))
        }, "runtime-bootstrap").start()
        return START_STICKY
    }

    override fun onDestroy() {
        bootstrapGeneration++
        reconnectHandler.removeCallbacksAndMessages(null)
        reconnectScheduled = false
        networkCallback?.let { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) }
        networkCallback = null
        controller?.stop()
        update("stopped", "已停止", "Runtime Service 已停止")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun isCurrentGeneration(generation: Long): Boolean = generation == bootstrapGeneration

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
        val protocol = config.getString("protocol", "").orEmpty()
        val api = when (protocol) {
            "openai-responses" -> "openai-responses"
            "anthropic-messages" -> "anthropic-messages"
            else -> "openai-completions"
        }
        return mapOf(
            "QQBOT_APPID" to credentials.read("qqbotAppId"),
            "QQBOT_SECRET" to credentials.read("qqbotSecret"),
            "LLM_API_KEY" to credentials.read("llmApiKey"),
            // dsh-llm-pi-ai owns one configured route named relay; the wire
            // protocol is selected independently so provider lookup remains stable.
            "LLM_PROVIDER" to "relay",
            "LLM_API" to api,
            "LLM_MODEL" to config.getString("model", "").orEmpty(),
            "LLM_BASE_URL" to config.getString("baseUrl", "").orEmpty(),
            "LLM_THINKING_LEVEL" to config.getString("thinkingLevel", "medium").orEmpty(),
        )
    }

    private fun scheduleReconnect(immediate: Boolean = false) {
        if (!getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)) return
        if (controller?.isAlive() == true) {
            reconnectAttempt = 0
            return
        }
        if (reconnectScheduled) return
        reconnectScheduled = true
        val delay = if (immediate) 0L else minOf(60_000L, 1_000L shl minOf(reconnectAttempt, 6))
        reconnectAttempt++
        update("reconnecting", "network.retry", "第 $reconnectAttempt 次重连，${delay / 1000} 秒后检查", delay)
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putInt("reconnectAttempts", reconnectAttempt).putLong("nextRetryMs", delay).apply()
        reconnectHandler.postDelayed({
            reconnectScheduled = false
            try {
                if (controller?.isAlive() != true) {
                    controller = RuntimeProcessController(this)
                    controller?.start(runtimeEnvironment())
                    update("online", "network.recovered", "Runtime 进程已恢复")
                    reconnectAttempt = 0
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putInt("reconnectAttempts", 0).putLong("nextRetryMs", 0L).apply()
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
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("networkStatus", "在线").apply()
                val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                if (prefs.getString("status", "") == "reconnecting") {
                    scheduleReconnect(immediate = true)
                }
            }
            override fun onLost(network: Network) {
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("status", "reconnecting").putString("phase", "network.lost").putString("message", "网络断开，等待恢复").apply()
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("networkStatus", "离线").apply()
                RuntimeEventBus.emit("warn", "network", "网络已断开，Runtime 将等待恢复", errorCode = "network_lost")
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("网络断开，等待恢复"))
            }
        }
        manager.registerDefaultNetworkCallback(callback)
        networkCallback = callback
    }

}

