package com.example.qq_bot_cp_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import android.provider.Settings
import android.net.Uri

class MainActivity : FlutterActivity() {
    private val methodChannel = "qq_bot_cp/runtime"
    private val eventChannel = "qq_bot_cp/runtime_events"
    private val apkPickerRequest = 1901

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
                "testQqConnection" -> testQqConnection(result)
                "getAppInfo" -> result.success(appInfo())
                "pickAndInstallApk" -> pickAndInstallApk(result)
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

    private fun testQqConnection(result: MethodChannel.Result) {
        Thread {
            val credentials = CredentialStore(this)
            val configured = credentials.has("qqbotAppId") && credentials.has("qqbotSecret")
            if (!configured) {
                runOnUiThread { result.success(mapOf("configured" to false, "stage" to "config", "message" to "AppID 或 AppSecret 未配置")) }
                return@Thread
            }
            try {
                val started = System.currentTimeMillis()
                val connection = (URL("https://api.sgroup.qq.com").openConnection() as HttpURLConnection).apply {
                    requestMethod = "HEAD"
                    connectTimeout = 5000
                    readTimeout = 5000
                }
                val status = connection.responseCode
                connection.disconnect()
                runOnUiThread { result.success(mapOf("configured" to true, "stage" to "network", "message" to "官方网关可达（未执行登录）", "statusCode" to status, "elapsedMs" to (System.currentTimeMillis() - started))) }
            } catch (error: Exception) {
                runOnUiThread { result.success(mapOf("configured" to true, "stage" to "network", "message" to "官方网关不可达：${error.message ?: error}")) }
            }
        }.start()
    }

    private fun appInfo(): Map<String, String> {
        val info = packageManager.getPackageInfo(packageName, 0)
        return mapOf("versionName" to (info.versionName ?: "未知"), "versionCode" to info.longVersionCode.toString(), "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "未知"))
    }

    private fun pickAndInstallApk(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            result.success(mapOf("status" to "permission_required"))
            return
        }
        pendingInstallResult = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/vnd.android.package-archive"
        }, apkPickerRequest)
    }

    private var pendingInstallResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != apkPickerRequest) return
        val result = pendingInstallResult
        pendingInstallResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result?.success(mapOf("status" to "cancelled"))
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result?.success(mapOf("status" to "installer_opened"))
        } catch (error: Exception) {
            result?.error("INSTALLER_ERROR", error.message, null)
        }
    }
}
