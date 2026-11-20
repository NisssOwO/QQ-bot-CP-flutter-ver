package com.shinycolors.officialbot

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
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
        /** 网关看门狗的检查周期。 */
        const val GATEWAY_WATCHDOG_INTERVAL_MS = 60_000L
        /** 网络刚恢复时先给 SDK 一点时间自己连，再判断是否需要自愈。 */
        const val NETWORK_PROBE_DELAY_MS = 20_000L
        /** Guards every persisted stage so state, log, widget and notification agree. */
        val STAGE_LOCK = Any()
    }

    private var coordinator: RuntimeCoordinator? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var started = false
    private val watchdog = Handler(Looper.getMainLooper())

    /**
     * 周期检查 QQ 网关是否真的活着。Node 进程和前台服务都正常也不代表网关通，
     * 夜间被省电断网后 SDK 会卡在永不返回的 await 上（见 RuntimeCoordinator.checkGatewayHealth）。
     */
    private val watchdogTask = object : Runnable {
        override fun run() {
            coordinator?.checkGatewayHealth("watchdog")
            watchdog.postDelayed(this, GATEWAY_WATCHDOG_INTERVAL_MS)
        }
    }

    private val networkProbe = Runnable { coordinator?.checkGatewayHealth("network_available") }

    override fun onCreate() {
        super.onCreate()
        serviceAlive = true
        RuntimeEventBus.setContext(this)
        RuntimeLogRecorder(this).migrateHistoryIfNeeded()
        RuntimeLogTailer.ensureStarted(this)
        coordinator = RuntimeCoordinator(this) { RuntimeProcessController(this) }
        val notifier = RuntimeNotifier(this)
        startAsForeground(notifier.build("正在启动 Runtime"))
        registerNetworkCallback()
        watchdog.postDelayed(watchdogTask, GATEWAY_WATCHDOG_INTERVAL_MS)
    }

    /**
     * 前台服务类型决定系统给的运行时长配额。
     *
     * `dataSync` 从 Android 14 起有累计配额（24 小时内 6 小时）。用光之后系统会调
     * `onTimeout()`，如果应用不主动停就抛 `ForegroundServiceDidNotStopInTimeException`
     * 直接把进程崩掉 —— 设备上那两次 APP CRASH 正是这个：
     * `A foreground service of type dataSync did not stop within its timeout`。
     *
     * 这台机器人的实质是"常驻接收消息"，用 Android 14 新增的 `remoteMessaging`
     * 才对：它没有累计时长限制。API 34 以下没有这个类型，仍用 `dataSync`
     * （那些版本本来也不限制 dataSync）。
     */
    private fun startAsForeground(notification: Notification) {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                startForeground(
                    RuntimeNotifier.ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
                )

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                startForeground(
                    RuntimeNotifier.ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )

            else -> startForeground(RuntimeNotifier.ID, notification)
        }
    }

    /** API 34：系统判定前台服务超时（配额耗尽）。 */
    override fun onTimeout(startId: Int, fgsType: Int) {
        handleForegroundTimeout("fgsType=$fgsType")
    }

    /** API 35+：单参版本，部分机型只回调这一个。 */
    override fun onTimeout(startId: Int) {
        handleForegroundTimeout("startId=$startId")
    }

    /**
     * 走到这里说明配额已经用光。继续赖着只会让系统抛异常崩进程，
     * 所以主动停掉服务并留下记录，让用户或下次启动恢复。
     */
    private fun handleForegroundTimeout(reason: String) {
        RuntimeLogRecorder(this).record(
            RuntimeLogRecorder.Status.STOPPED,
            "foreground.timeout",
            "系统判定前台服务超时（$reason），主动停止以避免进程崩溃",
            0,
        )
        RuntimeEventBus.emit(
            "error",
            "service",
            "系统判定前台服务超时，Runtime 已停止",
            errorCode = "foreground_timeout",
        )
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
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
        watchdog.removeCallbacksAndMessages(null)
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
            val baseUrl = config.getString("baseUrl", "").orEmpty()
            // DeepSeek 官方端点固定走 /chat/completions：只有这条请求路径验证过服务端
            // 联网搜索（deepseek_web_search）与 thinking:{type} 格式；Responses 协议下
            // 思考字段与工具声明都需要另行适配，留给后续。
            val api = when {
                baseUrl.contains("deepseek.com", ignoreCase = true) -> "openai-completions"
                protocol == "openai-responses" -> "openai-responses"
                protocol == "anthropic-messages" -> "anthropic-messages"
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
                // DeepSeek 服务端联网搜索：pi-ai 只会在 DeepSeek 官方端点上真正注入
                // deepseek_web_search，换第三方聚合站时该开关自动失效，不会因未知字段被拒。
                // 同一个变量也让 web-tools 插件让位，避免 Bing 兜底抢走本该走服务端深度搜索的问题。
                "DEEPSEEK_WEB_SEARCH" to
                    if (config.getBoolean("webSearch", true) && baseUrl.contains("deepseek.com", ignoreCase = true)) "1" else "0",
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
                    // 断网期间 SDK 可能已经卡死，给 20 秒自连机会后再兜底检查一次。
                    watchdog.removeCallbacks(networkProbe)
                    watchdog.postDelayed(networkProbe, NETWORK_PROBE_DELAY_MS)
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
