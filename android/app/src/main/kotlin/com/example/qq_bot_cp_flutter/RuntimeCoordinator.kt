package com.shinycolors.officialbot

import android.app.ActivityManager
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import com.shinycolors.officialbot.RuntimeLogRecorder.Status
import java.util.UUID

/** Single entry point for starting [RuntimeService] so callers report identical failure codes. */
object RuntimeLauncher {
    const val CODE_RESTRICTED = "foreground_service_restricted"
    const val CODE_FAILED = "runtime_launch_failed"

    fun request(context: Context, source: String): String? {
        val intent = Intent(context, RuntimeService::class.java)
            .setAction(RuntimeService.ACTION_START)
            .putExtra(RuntimeService.EXTRA_SOURCE, source)
        return start(context, intent)
    }

    /**
     * Restarts a run that is already alive without stopping the service, because a
     * stop/start pair would be delivered to the same instance and ignored as a duplicate.
     */
    fun restart(context: Context, source: String): String? {
        val intent = Intent(context, RuntimeService::class.java)
            .setAction(RuntimeService.ACTION_RESTART)
            .putExtra(RuntimeService.EXTRA_SOURCE, source)
        return start(context, intent)
    }

    private fun start(context: Context, intent: Intent): String? {
        return try {
            context.startForegroundService(intent)
            null
        } catch (error: Exception) {
            val restricted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                error is ForegroundServiceStartNotAllowedException
            if (restricted && backgroundRestricted(context)) CODE_RESTRICTED else CODE_FAILED
        }
    }

    fun backgroundRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val manager = context.getSystemService(ActivityManager::class.java) ?: return false
        return manager.isBackgroundRestricted
    }
}

/** Maps a failed executable launch onto a code the UI can explain. */
object NativeExec {
    const val CODE_UNAVAILABLE = "native_exec_unavailable"
    const val CODE_EXEC_UNSUPPORTED = "native_exec_unsupported"
    const val CODE_BUNDLE_INCOMPLETE = "runtime_bundle_incomplete"

    fun codeFor(error: Throwable): String {
        if (error is RuntimeAssetInstaller.IncompleteBundleException) return CODE_BUNDLE_INCOMPLETE
        val text = (error.message ?: error.toString()).lowercase()
        return when {
            text.contains("incomplete") || text.contains("no such file") || text.contains("enoent") -> CODE_BUNDLE_INCOMPLETE
            text.contains("error=13") || text.contains("permission denied") -> CODE_EXEC_UNSUPPORTED
            else -> RuntimeService.CODE_START_FAILED
        }
    }
}

/**
 * Owns everything written while a runtime restart is in flight.
 *
 * Writes go through one serial queue so the stored state, widget and notification
 * always describe the same stage, and stages posted by an outdated restart are dropped.
 */
class RuntimeCoordinator(
    private val service: RuntimeService,
    private val controllerFactory: () -> RuntimeProcessController,
) {
    private val queueThread = HandlerThread("runtime-stages").apply { start() }
    private val queue = Handler(queueThread.looper)
    private var controller: RuntimeProcessController? = null
    private var token = 0L
    private var active = false
    private var startedAt = 0L
    private var lastPhase = ""
    private var reconnectAttempts = 0
    private var lastExtensionAt = 0L
    private var lastExtensionReport = 0L

    fun start(source: String) {
        val mine = synchronized(this) {
            token++
            active = true
            startedAt = System.currentTimeMillis()
            lastPhase = ""
            reconnectAttempts = 0
            token
        }
        RuntimeNotifier(service).update("正在启动 Runtime")
        queue.post { bootstrap(mine, source) }
    }

    fun stop(message: String) {
        synchronized(this) {
            token++
            active = false
            lastPhase = "process.stop"
        }
        queue.post {
            controller?.stop()
            controller = null
            record(Status.STOPPED, "process.stop", message, 0, force = true)
        }
    }

    fun shutdown() {
        synchronized(this) {
            token++
            active = false
        }
        controller?.stop()
        controller = null
        queue.removeCallbacksAndMessages(null)
        queueThread.quitSafely()
    }

    fun onNetworkLost() {
        synchronized(this) {
            if (!active) return
            lastPhase = "network.lost"
        }
        queue.post { record(Status.RECONNECTING, "network.lost", "网络断开，等待恢复", 0, errorCode = "network_lost") }
    }

    fun onNetworkAvailable() {
        val reconnect = synchronized(this) {
            active && lastPhase == "network.lost" && controller?.isAlive() != true
        }
        if (reconnect) scheduleReconnect(immediate = true)
    }

    private fun bootstrap(mine: Long, source: String) {
        if (!isCurrent(mine)) return
        val runtime = service.current()
        val runId = UUID.randomUUID().toString().take(8)
        manage().markRun(runId)
        record(Status.STARTING, "restart.begin", "开始启动（runId=$runId，来源=$source）", errorCode = null, mine = mine)
        try {
            controller?.stop()
            controller = null
            record(Status.STARTING, "runtime.prepare", "正在准备 Node/DSH 运行文件", mine = mine)
            val startedAt = System.currentTimeMillis()
            val root = RuntimeAssetInstaller.install(service) { copied ->
                lastExtensionAt = System.currentTimeMillis()
                if (lastExtensionAt - lastExtensionReport < 1000) return@install
                lastExtensionReport = lastExtensionAt
                record(Status.STARTING, "runtime.prepare", "正在准备 Node/DSH 运行文件（已解包 $copied 个文件）", mine = mine)
            }
            val seconds = (System.currentTimeMillis() - startedAt) / 1000
            record(Status.STARTING, "runtime.prepare", "运行文件就绪（解包 ${root.name}，耗时 ${seconds} 秒）", mine = mine)
            record(Status.STARTING, "config.load", "读取公开配置和 Keystore 凭据（${root.name}）", mine = mine)
            record(Status.STARTING, "plugin.load", "正在加载 DSH profile 和 QQ/角色插件", mine = mine)
            if (!runtime.credentialsConfigured()) {
                record(Status.ONLINE, "ready", "服务已就绪，等待在 Flutter 中填写凭据", mine = mine)
                record(Status.ONLINE, "restart.complete", "启动流程完成", mine = mine)
                return
            }
            val online = runtime.networkAvailable()
            record(Status.STARTING, "network.check", if (online) "检测到可用网络，准备连接网关" else "当前没有可用网络，Runtime 将等待重连", mine = mine, errorCode = if (online) null else "network_unavailable")
            if (!isCurrent(mine)) return
            record(Status.STARTING, "runtime.spawn", "正在启动 Node/DSH 子进程", mine = mine)
            val process = controllerFactory()
            controller = process
            try {
                process.start(runtime.runtimeEnvironment())
            } catch (error: Exception) {
                record(Status.FAILED, "runtime.spawn", "启动失败：${error.message ?: error}", mine = mine, errorCode = NativeExec.codeFor(error))
                return
            }
            if (!isCurrent(mine)) {
                process.stop()
                return
            }
            record(Status.STARTING, "qq.connect", "已启动 QQ Bot 连接流程，等待 WebSocket 握手", mine = mine)
            record(Status.STARTING, "session.restore", "正在准备会话目录（不会把会话内容写入日志）", mine = mine)
            when (process.boot()) {
                RuntimeProcessController.Boot.BOOTED -> {
                    record(Status.ONLINE, "runtime.spawn", "Node 进程已启动", mine = mine)
                    record(Status.ONLINE, "ready", "Runtime 已启动，等待 QQ 网关握手", mine = mine)
                    record(Status.ONLINE, "restart.complete", "启动流程完成", mine = mine)
                }
                RuntimeProcessController.Boot.SILENT -> {
                    record(Status.ONLINE, "ready", "Runtime 进程运行中，但 ${RuntimeProcessController.BOOT_TIMEOUT_MS / 1000} 秒内没有收到启动信号，请查看日志", mine = mine)
                    record(Status.ONLINE, "restart.complete", "启动流程完成", mine = mine)
                }
                RuntimeProcessController.Boot.EXITED -> record(Status.FAILED, "runtime.early_exit", "Node 进程在启动阶段退出，退出码=${process.exitCode()}", mine = mine, errorCode = "runtime_early_exit")
                RuntimeProcessController.Boot.NOT_STARTED -> record(Status.FAILED, "runtime.early_exit", "Node 进程没有启动", mine = mine, errorCode = "runtime_early_exit")
            }
        } catch (error: Exception) {
            if (isCurrent(mine)) record(Status.FAILED, "restart.failed", "启动失败：${error.message ?: error}", mine = mine, errorCode = RuntimeService.CODE_START_FAILED)
        }
    }

    private fun scheduleReconnect(immediate: Boolean) {
        val attempt = synchronized(this) {
            if (!active) return
            if (controller?.isAlive() == true) {
                reconnectAttempts = 0
                return
            }
            ++reconnectAttempts
        }
        val delay = if (immediate) 0L else minOf(60_000L, 1_000L shl minOf(attempt - 1, 6))
        record(Status.RECONNECTING, "network.retry", "第 $attempt 次重连，${delay / 1000} 秒后检查", errorCode = null, mine = token)
        queue.postDelayed({
            val mine = synchronized(this) { token }
            if (!active || controller?.isAlive() == true) return@postDelayed
            try {
                val process = controllerFactory()
                controller = process
                process.start(service.current().runtimeEnvironment())
                synchronized(this) { reconnectAttempts = 0 }
                record(Status.ONLINE, "network.recovered", "Runtime 进程已恢复", mine = mine)
            } catch (error: Exception) {
                val code = NativeExec.codeFor(error)
                if (code == NativeExec.CODE_UNAVAILABLE || code == NativeExec.CODE_EXEC_UNSUPPORTED) {
                    record(Status.FAILED, "runtime.spawn", "重连失败：${error.message ?: error}", mine = mine, errorCode = code)
                } else if (synchronized(this) { reconnectAttempts } < 7) {
                    record(Status.RECONNECTING, "network.retry", "重连失败，稍后重试：${error.message ?: error}", mine = mine, errorCode = "runtime_reconnect_failed")
                    scheduleReconnect(immediate = false)
                } else {
                    record(Status.FAILED, "network.cooldown", "连续重连失败，进入冷却", mine = mine, errorCode = "runtime_reconnect_cooldown")
                }
            }
        }, delay)
    }

    private fun isCurrent(mine: Long): Boolean = synchronized(this) { active && mine == token }

    private fun manage() = RuntimeLogRecorder(service)

    private fun record(status: Status, phase: String, message: String, mine: Long, errorCode: String? = null, force: Boolean = false) {
        if (!force && !isCurrent(mine)) return
        synchronized(this) { lastPhase = phase }
        manage().record(status, phase, message, (System.currentTimeMillis() - startedAt).coerceAtLeast(0), errorCode)
    }
}