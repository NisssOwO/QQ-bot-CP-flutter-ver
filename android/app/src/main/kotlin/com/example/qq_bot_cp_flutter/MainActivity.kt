package com.example.qq_bot_cp_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build

class MainActivity : FlutterActivity() {
    private val methodChannel = "qq_bot_cp/runtime"
    private val eventChannel = "qq_bot_cp/runtime_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRuntime" -> { startRuntimeService(); result.success(null) }
                "stopRuntime" -> { stopService(Intent(this, RuntimeService::class.java)); result.success(null) }
                "restartRuntime" -> { stopService(Intent(this, RuntimeService::class.java)); startRuntimeService(); result.success(null) }
                "getRuntimeState" -> result.success(runtimeState())
                "getPublicConfig" -> result.success(mapOf("protocol" to "", "model" to "", "baseUrl" to "", "appId" to "", "qqConfigured" to false, "llmConfigured" to false))
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}
            override fun onCancel(arguments: Any?) {}
        })
    }

    private fun runtimeState(): Map<String, Any?> {
        val prefs = getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE)
        return mapOf(
            "status" to prefs.getString("status", "stopped"),
            "phase" to prefs.getString("phase", "未启动"),
            "message" to prefs.getString("message", ""),
            "elapsedMs" to prefs.getLong("elapsedMs", 0L),
            "exitCode" to null,
        )
    }

    private fun startRuntimeService() {
        val intent = Intent(this, RuntimeService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }
}
