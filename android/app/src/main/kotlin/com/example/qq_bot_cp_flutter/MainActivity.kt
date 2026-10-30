package com.example.qq_bot_cp_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import org.json.JSONObject

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
                "getPublicConfig" -> result.success(publicConfig())
                "saveConfig" -> { saveConfig(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "getConfigHistory" -> result.success(configHistory())
                "deleteConfigHistory" -> { getSharedPreferences("public-config-history", MODE_PRIVATE).edit().remove("items").apply(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { RuntimeEventBus.attach(events) }
            override fun onCancel(arguments: Any?) { RuntimeEventBus.attach(null) }
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

    private fun publicConfig(): Map<String, Any?> {
        val config = getSharedPreferences("public-config", MODE_PRIVATE)
        val credentials = CredentialStore(this)
        return mapOf(
            "protocol" to config.getString("protocol", ""),
            "model" to config.getString("model", ""),
            "baseUrl" to config.getString("baseUrl", ""),
            "appId" to if (credentials.has("qqbotAppId")) credentials.read("qqbotAppId") else "",
            "qqConfigured" to (credentials.has("qqbotAppId") && credentials.has("qqbotSecret")),
            "llmConfigured" to credentials.has("llmApiKey"),
        )
    }

    private fun saveConfig(values: Map<*, *>) {
        val credentials = CredentialStore(this)
        val appId = values["appId"] as? String ?: ""
        val secret = values["secret"] as? String ?: ""
        val apiKey = values["apiKey"] as? String ?: ""
        if (appId.isNotBlank()) credentials.save("qqbotAppId", appId.trim())
        if (secret.isNotBlank()) credentials.save("qqbotSecret", secret)
        if (apiKey.isNotBlank()) credentials.save("llmApiKey", apiKey)
        getSharedPreferences("public-config", MODE_PRIVATE).edit()
            .putString("protocol", values["protocol"] as? String ?: "")
            .putString("model", values["model"] as? String ?: "")
            .putString("baseUrl", values["baseUrl"] as? String ?: "")
            .apply()
        val configured = credentials.has("qqbotAppId") && credentials.has("qqbotSecret") && credentials.has("llmApiKey")
        getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("credentialsConfigured", configured).apply()
        saveConfigHistory(
            values["protocol"] as? String ?: "",
            values["model"] as? String ?: "",
            values["baseUrl"] as? String ?: "",
        )
    }

    private fun saveConfigHistory(protocol: String, model: String, baseUrl: String) {
        if (protocol.isBlank() && model.isBlank() && baseUrl.isBlank()) return
        val prefs = getSharedPreferences("public-config-history", MODE_PRIVATE)
        val items = try { org.json.JSONArray(prefs.getString("items", "[]")) } catch (_: Exception) { org.json.JSONArray() }
        val next = org.json.JSONArray()
        next.put(org.json.JSONObject().put("protocol", protocol.trim()).put("model", model.trim()).put("baseUrl", baseUrl.trim()))
        for (index in 0 until minOf(items.length(), 9)) {
            val item = items.optJSONObject(index) ?: continue
            if (item.optString("protocol") == protocol.trim() && item.optString("model") == model.trim() && item.optString("baseUrl") == baseUrl.trim()) continue
            next.put(item)
        }
        prefs.edit().putString("items", next.toString()).apply()
    }

    private fun configHistory(): List<Map<String, String>> {
        val prefs = getSharedPreferences("public-config-history", MODE_PRIVATE)
        val items = try { org.json.JSONArray(prefs.getString("items", "[]")) } catch (_: Exception) { org.json.JSONArray() }
        return (0 until items.length()).mapNotNull { index ->
            val item = items.optJSONObject(index) ?: return@mapNotNull null
            mapOf("protocol" to item.optString("protocol"), "model" to item.optString("model"), "baseUrl" to item.optString("baseUrl"))
        }
    }
}
