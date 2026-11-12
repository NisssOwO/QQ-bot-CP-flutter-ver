package com.shinycolors.officialbot

import android.app.Service
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class RuntimeService : Service() {
    companion object {
        const val PREFS = "runtime"
        @Volatile var serviceAlive: Boolean = false
        const val ACTION_START = "com.shinycolors.officialbot.action.START_RUNTIME"
        /** Restarts the run inside the live service instead of tearing the service down. */
        const val ACTION_RESTART = "com.shinycolors.officialbot.action.RESTART_RUNTIME"
        const val EXTRA_SOURCE = "source"
        const val CODE_START_FAILED = "runtime_start_failed"
        /** Guards every persisted stage so state, log, widget and notification agree. */
        val STAGE_LOCK = Any()
    }

    private var coordinator: RuntimeCoordinator? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var started = false

    override fun onCreate() {
        super.onCreate()
        serviceAlive = true
        RuntimeEventBus.setContext(this)
        RuntimeLogTailer.ensureStarted(this)
        coordinator = RuntimeCoordinator(this) { RuntimeProcessController(this) }
        val notifier = RuntimeNotifier(this)
        startForeground(RuntimeNotifier.ID, notifier.build("正在启动 Runtime"))
        registerNetworkCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val source = intent?.getStringExtra(EXTRA_SOURCE) ?: "system"
        // Restart must reach the live coordinator: stopping the service and starting it again
        // would land on this same instance, look like a duplicate start and be ignored.
        val restart = intent?.action == ACTION_RESTART
        val firstCommand = !started
        started = true
        if (restart || firstCommand) coordinator?.start(source)
        return START_STICKY
    }

    override fun onDestroy() {
        serviceAlive = false
        networkCallback?.let { callback ->
            try {
                getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
        networkCallback = null
        coordinator?.shutdown()
        coordinator = null
        RuntimeLogTailer.stopShared()
        stopForeground(STOP_FOREGROUND_REMOVE)
        RuntimeLogRecorder(this).record(RuntimeLogRecorder.Status.STOPPED, "process.stop", "Runtime Service 已停止", 0)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun current(): Current = Current()

    inner class Current {
        fun credentialsConfigured(): Boolean = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("credentialsConfigured", false)

        fun networkAvailable(): Boolean = getSystemService(ConnectivityManager::class.java)?.activeNetwork != null

        fun runtimeEnvironment(): Map<String, String> {
            val credentials = CredentialStore(this@RuntimeService)
            val config = getSharedPreferences("public-config", MODE_PRIVATE)
            val defaultRole = getSharedPreferences("default-role", MODE_PRIVATE).getString("id", "").orEmpty()
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
                "LLM_PRESET" to defaultRole,
                // Node 子进程默认按 UTC 计时；主动回复的安静时段和每日计数需要设备时区。
                "TZ" to java.util.TimeZone.getDefault().id,
            )
        }
    }

    private fun registerNetworkCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            RuntimeEventBus.emit("warn", "network", "当前 Android 版本不支持默认网络回调", errorCode = "network_callback_unsupported")
            return
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            private val main = Handler(Looper.getMainLooper())
            override fun onAvailable(network: Network) {
                main.post {
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("networkStatus", "在线").apply()
                    RuntimeEventBus.emit("info", "network", "网络已恢复，准备检查 Runtime 连接", errorCode = "network_available")
                    coordinator?.onNetworkAvailable()
                }
            }

            override fun onLost(network: Network) {
                main.post {
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("networkStatus", "离线").apply()
                    RuntimeEventBus.emit("warn", "network", "网络已断开，Runtime 将等待恢复", errorCode = "network_lost")
                    coordinator?.onNetworkLost()
                }
            }
        }
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(callback)
        networkCallback = callback
    }
}
