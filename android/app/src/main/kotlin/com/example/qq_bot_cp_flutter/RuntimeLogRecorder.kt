package com.shinycolors.officialbot

import android.content.Context
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

    fun markRun(runId: String) {
        synchronized(RuntimeService.STAGE_LOCK) {
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
                .commit()
            RuntimeEventBus.emit(if (status == Status.FAILED) "error" else "info", "runtime", "$phase：$message", elapsedMs.takeIf { it > 0 }, errorCode)
            RuntimeWidgetProvider.updateAll(context)
            RuntimeNotifier(context).show("$phase：$message")
        }
    }

    /** Appends one parsed process line and its per-module counters under the same lock. */
    fun stream(level: String, module: String, message: String, qq: String?, ai: String?, network: String?, errorCode: String?) {
        synchronized(RuntimeService.STAGE_LOCK) {
            val editor = prefs().edit()
            qq?.let { editor.putString("qqStatus", it) }
            ai?.let { editor.putString("aiStatus", it) }
            network?.let { editor.putString("networkStatus", it) }
            appendHistory(editor, level, module, message, errorCode)
            editor.commit()
            RuntimeEventBus.emit(level, module, message, errorCode = errorCode)
        }
    }

    private fun appendHistory(editor: android.content.SharedPreferences.Editor, level: String, module: String, message: String, errorCode: String?) {
        val array = try {
            JSONArray(prefs().getString("logHistory", "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val entry = JSONObject()
            .put("time", System.currentTimeMillis().toString())
            .put("level", level)
            .put("module", module)
            .put("message", message)
        RuntimeEventBus.runId?.let { entry.put("runId", it) }
        errorCode?.let { entry.put("errorCode", it) }
        array.put(entry)
        val keep = maxOf(0, array.length() - 500)
        val trimmed = JSONArray()
        for (index in keep until array.length()) trimmed.put(array.opt(index))
        editor.putString("logHistory", trimmed.toString())
    }

    private fun prefs() = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
}