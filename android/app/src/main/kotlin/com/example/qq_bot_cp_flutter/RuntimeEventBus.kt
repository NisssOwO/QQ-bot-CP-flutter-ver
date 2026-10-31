package com.shinycolors.officialbot

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray

/** Forwards runtime events to Flutter; history is persisted by [RuntimeLogRecorder]. */
object RuntimeEventBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var context: Context? = null
    @Volatile var runId: String? = null

    fun setContext(value: Context) {
        context = value.applicationContext
    }

    fun attach(value: EventChannel.EventSink?) {
        sink = value
    }

    fun attach(value: Context, events: EventChannel.EventSink?) {
        setContext(value)
        sink = events
    }

    fun emit(level: String, module: String, message: String, elapsedMs: Long? = null, errorCode: String? = null) {
        val event = mutableMapOf<String, Any>(
            "time" to System.currentTimeMillis().toString(),
            "level" to level,
            "module" to module,
            "message" to message,
        )
        runId?.let { event["runId"] = it }
        elapsedMs?.let { event["elapsedMs"] = it }
        errorCode?.let { event["errorCode"] = it }
        // Flutter engine calls must happen on the main thread.
        mainHandler.post { sink?.success(event) }
    }

    fun recentLogs(): List<Map<String, Any?>> {
        val app = context ?: return emptyList()
        return try {
            val array = JSONArray(app.getSharedPreferences("runtime", Context.MODE_PRIVATE).getString("logHistory", "[]") ?: "[]")
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                item.keys().asSequence().associateWith { key -> item.get(key) }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}