package com.shinycolors.officialbot

import android.content.Context
import android.os.Handler
import org.json.JSONArray
import org.json.JSONObject

/**
 * Writes one runtime stage: persisted state, live event, widget and notification.
 *
 * The shared [RuntimeService.STAGE_LOCK] keeps these four views at the same revision
 * even when several threads report changes at once.
 */
class RuntimeLogRecorder(private val context: Context) {
    enum class Status(val key: String) {
        STOPPED("stopped"), STARTING("starting"), ONLINE("online"), RECONNECTING("reconnecting"), FAILED("failed");
    }

    fun credentialsConfigured(): Boolean = prefs().getBoolean("credentialsConfigured", false)

    /**
     * 丢掉旧版本写下的日志历史。
     *
     * 0.2.32 之前的 [RuntimeLogTailer] 会从文件开头重读一遍，把昨天的行记成"刚刚发生"，
     * 于是历史里同一批错误的时刻全被改写，事后根本无法分辨新旧。这些条目的时间已经
     * 不可信，留着只会误导排查，所以在格式修正后一次性清掉。
     */
    fun migrateHistoryIfNeeded() {
        if (prefs().getInt(KEY_HISTORY_VERSION, 0) >= HISTORY_VERSION) return
        prefs().edit()
            .remove("logHistory")
            .putInt(KEY_HISTORY_VERSION, HISTORY_VERSION)
            .commit()
    }

    /**
     * Starts a new run.
     *
     * 旧实现会直接 `remove("runtimeLastError")`，于是“上次为什么失败”在重启那一刻
     * 就被抹掉，事后只能看到一次成功启动。现在改成先归档到 [KEY_ERROR_HISTORY]
     * 再清空当前错误，历史留得住，当前状态也不会被旧错误污染。
     */
    fun markRun(runId: String) {
        synchronized(RuntimeService.STAGE_LOCK) {
            val previousRun = prefs().getString("runId", null)
            val previousError = prefs().getString("runtimeLastError", null)
            archiveError(previousRun, previousError)
            prefs().edit().putString("runId", runId).remove("runtimeLastError").commit()
            RuntimeEventBus.runId = runId
        }
    }

    fun record(status: Status, phase: String, message: String, elapsedMs: Long, errorCode: String? = null) {
        synchronized(RuntimeService.STAGE_LOCK) {
            prefs().edit()
                .putString("status", status.key)
                .putString("phase", phase)
                .putString("message", message)
                .putLong("elapsedMs", elapsedMs)
                .putString("errorCode", errorCode.orEmpty())
                // Wall-clock stamp of this stage, so a UI watchdog can tell a stalled
                // start from a slow start that keeps reporting progress.
                .putLong("stageAt", System.currentTimeMillis())
                .commit()
        }
        RuntimeEventBus.emit(if (status == Status.FAILED) "error" else "info", "runtime", "$phase：$message", elapsedMs.takeIf { it > 0 }, errorCode)
        // Widget and notification views run on the main thread; a start that emits many
        // stages must not queue them behind the log reader threads.
        onMain {
            RuntimeWidgetProvider.updateAll(context)
            RuntimeNotifier(context).show("$phase：$message")
        }
    }

    /** Appends one parsed process line and its per-module counters under the same lock. */
    fun stream(
        level: String,
        module: String,
        message: String,
        qq: String?,
        ai: String?,
        network: String?,
        errorCode: String?,
        at: Long? = null,
    ) {
        synchronized(RuntimeService.STAGE_LOCK) {
            val editor = prefs().edit()
            qq?.let { editor.putString("qqStatus", it) }
            ai?.let { editor.putString("aiStatus", it) }
            network?.let { editor.putString("networkStatus", it) }
            appendHistory(editor, level, module, message, errorCode, at)
            editor.commit()
        }
        RuntimeEventBus.emit(level, module, message, errorCode = errorCode, timeMs = at)
    }

    private fun appendHistory(
        editor: android.content.SharedPreferences.Editor,
        level: String,
        module: String,
        message: String,
        errorCode: String?,
        at: Long?,
    ) {
        val array = try {
            JSONArray(prefs().getString("logHistory", "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val entry = JSONObject()
            // 有文件时间戳就用它：读到的时刻会把旧日志伪造成刚刚发生的事故。
            // 存数字而不是字符串，Dart 侧才能直接按毫秒还原。
            .put("time", at ?: System.currentTimeMillis())
            .put("level", level)
            .put("module", module)
            .put("message", message)
        RuntimeEventBus.runId?.let { entry.put("runId", it) }
        errorCode?.let { entry.put("errorCode", it) }
        array.put(entry)
        // 只保留最近 HISTORY_LIMIT 条。早期是 500 条，一次重连风暴就能把“最初的
        // 断开原因”挤出窗口，于是事后看到的永远是最后一轮失败。
        if (array.length() <= HISTORY_LIMIT) {
            editor.putString("logHistory", array.toString())
            return
        }
        val trimmed = JSONArray()
        for (index in array.length() - HISTORY_LIMIT until array.length()) trimmed.put(array.opt(index))
        editor.putString("logHistory", trimmed.toString())
    }

    /** 归档一条启动失败原因，最多保留 [ERROR_HISTORY_LIMIT] 条。调用方必须已持有 STAGE_LOCK。 */
    private fun archiveError(runId: String?, message: String?) {
        if (message.isNullOrBlank()) return
        val array = try {
            JSONArray(prefs().getString(KEY_ERROR_HISTORY, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val entry = JSONObject()
            .put("at", System.currentTimeMillis())
            .put("runId", runId.orEmpty())
            .put("message", message)
        array.put(entry)
        val trimmed = JSONArray()
        for (index in maxOf(0, array.length() - ERROR_HISTORY_LIMIT) until array.length()) trimmed.put(array.opt(index))
        prefs().edit().putString(KEY_ERROR_HISTORY, trimmed.toString()).commit()
    }

    private fun prefs() = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)

    private fun onMain(block: () -> Unit) {
        if (android.os.Looper.myLooper() === android.os.Looper.getMainLooper()) {
            block()
            return
        }
        MAIN.post(block)
    }

    companion object {
        /** 日志页可见的历史条数。 */
        const val HISTORY_LIMIT = 2000

        /** 跨重启保留的启动失败记录条数。 */
        const val ERROR_HISTORY_LIMIT = 20

        /** SharedPreferences 里归档启动失败原因的 key。 */
        const val KEY_ERROR_HISTORY = "runtimeErrorHistory"

        /**
         * 日志历史的格式版本。
         *
         * 1 = 时间戳取自 runtime.log 里的 ISO 前缀（之前是读取时刻）。
         * 版本不一致时清空历史：旧条目的时间不可信，留着会误导排查。
         */
        const val HISTORY_VERSION = 1
        private const val KEY_HISTORY_VERSION = "logHistoryVersion"

        private val MAIN = Handler(android.os.Looper.getMainLooper())
    }
}
