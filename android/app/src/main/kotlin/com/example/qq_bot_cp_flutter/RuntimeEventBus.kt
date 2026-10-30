package com.shinycolors.officialbot

import io.flutter.plugin.common.EventChannel

object RuntimeEventBus {
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile var runId: String? = null
    fun attach(value: EventChannel.EventSink?) { sink = value }
    fun emit(level: String, module: String, message: String, elapsedMs: Long? = null, errorCode: String? = null) {
        val event = mutableMapOf<String, Any>("time" to System.currentTimeMillis().toString(), "level" to level, "module" to module, "message" to message)
        runId?.let { event["runId"] = it }
        if (elapsedMs != null) event["elapsedMs"] = elapsedMs
        if (errorCode != null) event["errorCode"] = errorCode
        sink?.success(event)
    }
}
