package com.shinycolors.officialbot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannel = "qq_bot_cp/runtime"
    private val eventChannel = "qq_bot_cp/runtime_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRuntime", "stopRuntime", "restartRuntime" -> result.success(null)
                "getRuntimeState" -> result.success(mapOf("status" to "stopped", "phase" to "未启动", "elapsedMs" to 0))
                "getPublicConfig" -> result.success(mapOf("protocol" to "", "model" to "", "baseUrl" to "", "appId" to "", "qqConfigured" to false, "llmConfigured" to false))
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}
            override fun onCancel(arguments: Any?) {}
        })
    }
}
