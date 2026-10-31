package com.shinycolors.officialbot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val methodChannel = "qq_bot_cp/runtime"
    private val eventChannel = "qq_bot_cp/runtime_events"
    private val apkPickerRequest = 1901
    private val backupExportRequest = 2001
    private val backupImportRequest = 2002
    private val roleExportRequest = 2101
    private val roleImportRequest = 2102
    private var pendingStartResult: MethodChannel.Result? = null

    private val notificationPermission by lazy { NotificationPermissionBinding(this) }


    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRuntime" -> { startRuntimeService(); result.success(null) }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "stopRuntime" -> { markRuntimeStopping("用户请求停止 Runtime"); getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("userStopped", true).apply(); stopService(Intent(this, RuntimeService::class.java)); result.success(null) }
                "restartRuntime" -> { markRuntimeStopping("准备重启 Runtime"); getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("userStopped", false).apply(); stopService(Intent(this, RuntimeService::class.java)); launchRuntime("user"); result.success(null) }
                "getRuntimeState" -> result.success(runtimeState())
                "getRecentLogs" -> result.success(RuntimeEventBus.recentLogs())
                "getPublicConfig" -> result.success(publicConfig())
                "saveConfig" -> { saveConfig(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "fetchModels" -> fetchModels(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "testLlmConnection" -> testLlmConnection(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "testLlmRequest" -> testLlmRequest(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "getConfigHistory" -> result.success(configHistory())
                "deleteConfigHistory" -> { getSharedPreferences("public-config-history", MODE_PRIVATE).edit().remove("items").apply(); result.success(null) }
                "testQqConnection" -> testQqConnection(result)
                "getAppInfo" -> result.success(appInfo())
                "pickAndInstallApk" -> pickAndInstallApk(result)
                "getUpdateCachePath" -> result.success(File(cacheDir, "online-update.apk").absolutePath)
                "getUpdateEndpoint" -> result.success(getSharedPreferences("public-config", MODE_PRIVATE).getString("updateUrl", "").orEmpty())
                "saveUpdateEndpoint" -> { getSharedPreferences("public-config", MODE_PRIVATE).edit().putString("updateUrl", (call.arguments as? String ?: "").trim()).apply(); result.success(null) }
                "verifyAndInstallUpdate" -> verifyAndInstallUpdate(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "getThemeSettings" -> result.success(themeSettings())
                "saveThemeSettings" -> { saveThemeSettings(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "exportBackup" -> exportBackup(result)
                "importBackup" -> importBackup(result)
                "getBackups" -> result.success(listBackups())
                "restoreBackupFile" -> restoreBackupFile(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "getDefaultRole" -> result.success(defaultRole())
                "saveDefaultRole" -> { saveDefaultRole(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "getRoles" -> result.success(roleCards())
                "saveRoleCard" -> { saveRoleCard(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "deleteRoleCard" -> { deleteRoleCard(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "exportRoleCard" -> exportRoleCard(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "importRoleCard" -> importRoleCard(result)
                "clearData" -> { clearData(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "openBatteryOptimizationSettings" -> { openBatteryOptimizationSettings(); result.success(null) }
                "openNotificationSettings" -> { openNotificationSettings(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { RuntimeEventBus.attach(this@MainActivity, events) }
            override fun onCancel(arguments: Any?) { RuntimeEventBus.attach(null) }
        })
    }

    private fun runtimeState(): Map<String, Any?> {
        val prefs = getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE)
        val processAlive = prefs.getBoolean("runtimeProcessAlive", false) && RuntimeService.serviceAlive
        val persistedStatus = prefs.getString("status", "stopped") ?: "stopped"
        val status = if (!processAlive && persistedStatus == "online") "stopped" else persistedStatus
        return mapOf(
            "status" to status,
            "phase" to prefs.getString("phase", "未启动"),
            "message" to if (!processAlive && persistedStatus == "online") "Runtime 进程未运行" else prefs.getString("message", ""),
            "elapsedMs" to prefs.getLong("elapsedMs", 0L),
            "exitCode" to null,
            "errorCode" to prefs.getString("errorCode", "").orEmpty().ifBlank { null },
            "qqStatus" to prefs.getString("qqStatus", "未知"),
            "aiStatus" to prefs.getString("aiStatus", "未知"),
            "networkStatus" to prefs.getString("networkStatus", "未知"),
            "reconnectAttempts" to prefs.getInt("reconnectAttempts", 0),
            "nextRetryMs" to prefs.getLong("nextRetryMs", 0L),
            "qqFailureCount" to prefs.getInt("qqFailureCount", 0),
            "aiFailureCount" to prefs.getInt("aiFailureCount", 0),
            "processAlive" to processAlive,
            "userStopped" to prefs.getBoolean("userStopped", false),
        )
    }

    private fun startRuntimeService() {
        getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("userStopped", false).apply()
        val restricted = RuntimeLauncher.backgroundRestricted(this)
        getSharedPreferences("runtime", MODE_PRIVATE).edit()
            .putBoolean("notificationPermissionGranted", hasNotificationPermission())
            .putBoolean("batteryOptimizationIgnored", batteryOptimizationIgnored())
            .putBoolean("backgroundRestricted", restricted)
            .apply()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && batteryOptimizationIgnored().not()) {
            RuntimeEventBus.emit("warn", "后台", "尚未关闭电池优化，HyperOS 可能在锁屏后结束 Runtime", errorCode = "battery_optimization_enabled")
        }
        launchRuntime("foreground")
    }

    /** Starting from the background is refused by Android 12+, so only the foreground path exists. */
    private fun runtimeForeground(): Boolean = true

    /**
     * Starts the runtime, asking for notification permission first so the ongoing
     * notification is visible from the first second.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        pendingStartResult?.let { previous -> previous.success("superseded") }
        pendingStartResult = null
        result.success(notificationPermission.request())
    }

    private fun hasNotificationPermission(): Boolean = !NotificationPermission.needed(this)

    private fun batteryOptimizationIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val manager = getSystemService(PowerManager::class.java) ?: return false
        return manager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun launchRuntime(source: String) {
        val error = RuntimeLauncher.request(this, source) ?: return
        val message = when (error) {
            RuntimeLauncher.CODE_RESTRICTED -> "系统禁止后台启动前台服务，请在设置中允许本应用后台运行，再从应用内启动"
            else -> "无法启动 Runtime：$error"
        }
        RuntimeLogRecorder(this).record(RuntimeLogRecorder.Status.FAILED, "runtime.launch", message, 0, error)
    }

    private fun markRuntimeStopping(message: String) {
        RuntimeLogRecorder(this).record(RuntimeLogRecorder.Status.STOPPED, "process.stop", message, 0)
    }

    private fun openBatteryOptimizationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_SETTINGS)
        }
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    private fun publicConfig(): Map<String, Any?> {
        val config = getSharedPreferences("public-config", MODE_PRIVATE)
        val credentials = CredentialStore(this)
        return mapOf(
            "protocol" to config.getString("protocol", ""),
            "model" to config.getString("model", ""),
            "baseUrl" to config.getString("baseUrl", ""),
            "thinkingLevel" to config.getString("thinkingLevel", "medium"),
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
            .putString("thinkingLevel", values["thinkingLevel"] as? String ?: "medium")
            .apply()
        val configured = credentials.has("qqbotAppId") && credentials.has("qqbotSecret") && credentials.has("llmApiKey")
        getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("credentialsConfigured", configured).apply()
        saveConfigHistory(
            values["protocol"] as? String ?: "",
            values["model"] as? String ?: "",
            values["baseUrl"] as? String ?: "",
        )
    }

    private fun fetchModels(values: Map<*, *>, result: MethodChannel.Result) {
        val baseUrl = (values["baseUrl"] as? String ?: "").trim().trimEnd('/')
        if (baseUrl.isBlank()) { result.error("MODEL_LIST_CONFIG", "请先填写 Base URL", null); return }
        Thread {
            try {
                val endpoint = if (baseUrl.endsWith("/models")) baseUrl else "$baseUrl/models"
                val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 8000
                    readTimeout = 12000
                    setRequestProperty("Accept", "application/json")
                    val suppliedKey = (values["apiKey"] as? String ?: "").trim()
                    val key = suppliedKey.ifBlank { CredentialStore(this@MainActivity).read("llmApiKey") }
                    if (key.isNotBlank()) setRequestProperty("Authorization", "Bearer $key")
                }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                connection.disconnect()
                if (status !in 200..299) throw IllegalStateException("模型接口返回 HTTP $status${modelErrorDetail(body)}")
                val models = parseModelIds(body)
                runOnUiThread { result.success(models) }
            } catch (error: Exception) {
                runOnUiThread { result.error("MODEL_LIST_ERROR", error.message ?: "无法获取模型列表", null) }
            }
        }.start()
    }

    private fun parseModelIds(body: String): List<String> {
        val text = body.trim()
        if (text.isEmpty()) return emptyList()
        val values = mutableListOf<String>()
        fun collect(array: org.json.JSONArray?) {
            if (array == null) return
            for (index in 0 until array.length()) {
                val item = array.opt(index)
                val id = when (item) {
                    is org.json.JSONObject -> listOf("id", "name", "model").firstNotNullOfOrNull { key -> item.optString(key).trim().takeIf { it.isNotEmpty() } }
                    is String -> item.trim().takeIf { it.isNotEmpty() }
                    else -> null
                }
                if (id != null) values += id
            }
        }
        try {
            if (text.startsWith("[")) {
                collect(org.json.JSONArray(text))
            } else {
                val json = org.json.JSONObject(text)
                collect(json.optJSONArray("data"))
                if (values.isEmpty()) collect(json.optJSONArray("models"))
            }
        } catch (_: Exception) {
            return emptyList()
        }
        return values.distinct().sorted()
    }

    private fun modelErrorDetail(body: String): String {
        return try {
            val json = org.json.JSONObject(body)
            val error = json.optJSONObject("error")
            val message = error?.optString("message")?.takeIf { it.isNotBlank() }
                ?: json.optString("message").takeIf { it.isNotBlank() }
            if (message == null) "" else "：$message"
        } catch (_: Exception) {
            ""
        }
    }

    private fun testLlmConnection(values: Map<*, *>, result: MethodChannel.Result) {
        val baseUrl = (values["baseUrl"] as? String ?: "").trim().trimEnd('/')
        if (baseUrl.isBlank()) { result.error("LLM_TEST_CONFIG", "请先填写 Base URL", null); return }
        Thread {
            val started = System.currentTimeMillis()
            try {
                val endpoint = if (baseUrl.endsWith("/models")) baseUrl else "$baseUrl/models"
                val suppliedKey = (values["apiKey"] as? String ?: "").trim()
                val key = suppliedKey.ifBlank { CredentialStore(this@MainActivity).read("llmApiKey") }
                val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 8000
                    readTimeout = 12000
                    setRequestProperty("Accept", "application/json")
                    if (key.isNotBlank()) setRequestProperty("Authorization", "Bearer $key")
                }
                val status = connection.responseCode
                connection.disconnect()
                val message = when {
                    status in 200..299 -> "模型接口可用，认证通过"
                    status == 401 -> "模型接口拒绝认证：API Key 无效、未保存或不适用于此接口"
                    status == 404 -> "接口不提供 /models，请检查 Base URL"
                    else -> "模型接口返回 HTTP $status"
                }
                runOnUiThread { result.success(mapOf("ok" to (status in 200..299), "stage" to "模型接口", "message" to message, "statusCode" to status, "elapsedMs" to (System.currentTimeMillis() - started))) }
            } catch (error: Exception) {
                runOnUiThread { result.success(mapOf("ok" to false, "stage" to "DNS/TLS/网络", "message" to (error.message ?: "无法连接模型接口"), "elapsedMs" to (System.currentTimeMillis() - started))) }
            }
        }.start()
    }

    private fun testLlmRequest(values: Map<*, *>, result: MethodChannel.Result) {
        val baseUrl = (values["baseUrl"] as? String ?: "").trim().trimEnd('/')
        val protocol = (values["protocol"] as? String ?: "").trim()
        val model = (values["model"] as? String ?: "").trim()
        if (baseUrl.isBlank() || model.isBlank()) { result.error("LLM_REQUEST_CONFIG", "请先填写 Base URL 和模型名称", null); return }
        Thread {
            val started = System.currentTimeMillis()
            try {
                val suffix = when (protocol) {
                    "anthropic-messages" -> "/messages"
                    "openai-responses" -> "/responses"
                    else -> "/chat/completions"
                }
                val endpoint = if (baseUrl.endsWith(suffix)) baseUrl else "$baseUrl$suffix"
                val suppliedKey = (values["apiKey"] as? String ?: "").trim()
                val key = suppliedKey.ifBlank { CredentialStore(this@MainActivity).read("llmApiKey") }
                val body = when (protocol) {
                    "anthropic-messages" -> org.json.JSONObject()
                        .put("model", model).put("max_tokens", 1)
                        .put("messages", org.json.JSONArray().put(org.json.JSONObject().put("role", "user").put("content", "ping")))
                    "openai-responses" -> org.json.JSONObject().put("model", model).put("input", "ping").put("max_output_tokens", 1)
                    else -> org.json.JSONObject().put("model", model).put("messages", org.json.JSONArray().put(org.json.JSONObject().put("role", "user").put("content", "ping"))).put("max_tokens", 1).put("stream", false)
                }
                val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 8000
                    readTimeout = 20000
                    doOutput = true
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("Content-Type", "application/json")
                    if (key.isNotBlank()) setRequestProperty("Authorization", "Bearer $key")
                }
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val status = connection.responseCode
                connection.disconnect()
                val message = when {
                    status in 200..299 -> "测试请求成功，模型已返回响应"
                    status == 401 -> "测试请求拒绝认证：请检查 API Key"
                    status == 404 -> "测试请求地址不存在：请检查 Base URL 与接口类型"
                    status == 400 -> "测试请求参数被拒绝：请检查模型名称或接口协议"
                    else -> "测试请求返回 HTTP $status"
                }
                runOnUiThread { result.success(mapOf("ok" to (status in 200..299), "stage" to "模型请求", "message" to message, "statusCode" to status, "elapsedMs" to (System.currentTimeMillis() - started))) }
            } catch (error: Exception) {
                runOnUiThread { result.success(mapOf("ok" to false, "stage" to "DNS/TLS/网络", "message" to (error.message ?: "无法连接模型请求接口"), "elapsedMs" to (System.currentTimeMillis() - started))) }
            }
        }.start()
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

    private fun themeSettings(): Map<String, Any?> {
        val prefs = getSharedPreferences("theme", MODE_PRIVATE)
        return mapOf("mode" to prefs.getString("mode", "dark"), "seedColor" to prefs.getInt("seedColor", 0xff8290ff.toInt()), "cardRadius" to prefs.getFloat("cardRadius", 16f), "cardOpacity" to prefs.getFloat("cardOpacity", 1f), "tintedBackground" to prefs.getBoolean("tintedBackground", false))
    }

    private fun saveThemeSettings(values: Map<*, *>) {
        getSharedPreferences("theme", MODE_PRIVATE).edit()
            .putString("mode", values["mode"] as? String ?: "dark")
            .putInt("seedColor", (values["seedColor"] as? Number)?.toInt() ?: 0xff8290ff.toInt())
            .putFloat("cardRadius", (values["cardRadius"] as? Number)?.toFloat() ?: 16f)
            .putFloat("cardOpacity", (values["cardOpacity"] as? Number)?.toFloat() ?: 1f)
            .putBoolean("tintedBackground", values["tintedBackground"] == true)
            .apply()
    }

    private fun defaultRole(): Map<String, String> {
        val prefs = getSharedPreferences("default-role", MODE_PRIVATE)
        return mapOf("id" to prefs.getString("id", "").orEmpty(), "name" to prefs.getString("name", "").orEmpty(), "prompt" to prefs.getString("prompt", "").orEmpty())
    }

    private fun saveDefaultRole(values: Map<*, *>) {
        getSharedPreferences("default-role", MODE_PRIVATE).edit().putString("id", values["id"] as? String ?: "").putString("name", values["name"] as? String ?: "").putString("prompt", values["prompt"] as? String ?: "").apply()
    }

    private fun roleCards(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val seenIds = mutableSetOf<String>()
        val presets = File(filesDir, "runtime/presets")
        presets.listFiles()?.filter { it.name.startsWith("preset.") && it.name.endsWith(".json") }?.forEach { file ->
            try {
                val metadata = org.json.JSONObject(file.readText())
                val id = metadata.optString("id", file.name.removePrefix("preset.").removeSuffix(".json"))
                val promptFile = File(presets, file.name.removeSuffix(".json") + ".md")
                val promptText = if (promptFile.isFile) promptFile.readText() else ""
                val body = if (promptText.startsWith("---")) promptText.substringAfter("---\n", "").substringAfter("---\n", "") else promptText
                result += mapOf("id" to id, "displayName" to metadata.optString("displayName", metadata.optString("name", id)), "prompt" to body.trim(), "builtin" to metadata.optBoolean("builtin", !id.startsWith("custom.")))
                seenIds += id
            } catch (_: Exception) { }
        }
        val array = try { org.json.JSONArray(getSharedPreferences("role-cards", MODE_PRIVATE).getString("items", "[]") ?: "[]") } catch (_: Exception) { org.json.JSONArray() }
        result += (0 until array.length()).mapNotNull { index -> val item = array.optJSONObject(index) ?: return@mapNotNull null; val id = item.optString("id"); if (id.isBlank() || seenIds.contains(id)) return@mapNotNull null; mapOf("id" to id, "displayName" to item.optString("displayName"), "prompt" to item.optString("prompt"), "builtin" to false) }
        return result
    }

    private fun saveRoleCard(values: Map<*, *>) {
        val id = (values["id"] as? String ?: "").trim()
        val name = (values["displayName"] as? String ?: "").trim()
        val prompt = values["prompt"] as? String ?: ""
        val existingPreset = findPresetFiles(id)
        require(Regex("custom\\.[a-z0-9][a-z0-9._-]{0,48}").matches(id) || existingPreset != null) { "角色 ID 必须是 custom.xxx 或已有内置角色 ID" }
        require(prompt.trim().isNotEmpty()) { "角色提示词不能为空" }
        val displayName = name.ifBlank { id }
        if (existingPreset != null) {
            existingPreset.first.writeText(prompt)
            val metadata = try { org.json.JSONObject(existingPreset.second.readText()) } catch (_: Exception) { org.json.JSONObject() }
            metadata.put("id", id).put("displayName", displayName)
            existingPreset.second.writeText(metadata.toString())
        } else {
            writeRuntimePreset(id, displayName, prompt)
        }
        val old = try { org.json.JSONArray(getSharedPreferences("role-cards", MODE_PRIVATE).getString("items", "[]") ?: "[]") } catch (_: Exception) { org.json.JSONArray() }
        val next = org.json.JSONArray(); var replaced = false
        for (index in 0 until old.length()) { val item = old.optJSONObject(index) ?: continue; if (item.optString("id") == id) { next.put(org.json.JSONObject().put("id", id).put("displayName", displayName).put("prompt", prompt)); replaced = true } else next.put(item) }
        if (!replaced) next.put(org.json.JSONObject().put("id", id).put("displayName", displayName).put("prompt", prompt))
        getSharedPreferences("role-cards", MODE_PRIVATE).edit().putString("items", next.toString()).apply()
    }

    private fun deleteRoleCard(values: Map<*, *>) {
        val id = values["id"] as? String ?: return
        val preset = findPresetFiles(id)
        if (preset != null) { preset.first.delete(); preset.second.delete() }
        val old = try { org.json.JSONArray(getSharedPreferences("role-cards", MODE_PRIVATE).getString("items", "[]") ?: "[]") } catch (_: Exception) { org.json.JSONArray() }
        val next = org.json.JSONArray()
        for (index in 0 until old.length()) { val item = old.optJSONObject(index) ?: continue; if (item.optString("id") != id) next.put(item) }
        getSharedPreferences("role-cards", MODE_PRIVATE).edit().putString("items", next.toString()).apply()
        if (getSharedPreferences("default-role", MODE_PRIVATE).getString("id", "") == id) getSharedPreferences("default-role", MODE_PRIVATE).edit().clear().apply()
    }

    private fun writeRuntimePreset(id: String, name: String, prompt: String) {
        val directory = File(filesDir, "runtime/presets").apply { mkdirs() }
        File(directory, "preset.$id.md").writeText(prompt)
        File(directory, "preset.$id.json").writeText(org.json.JSONObject().put("id", id).put("displayName", name).put("builtin", false).toString())
    }

    private fun findPresetFiles(id: String): Pair<File, File>? {
        val directory = File(filesDir, "runtime/presets")
        val metadataFiles = directory.listFiles()?.filter { it.name.startsWith("preset.") && it.name.endsWith(".json") } ?: return null
        metadataFiles.forEach { metadataFile -> try { if (org.json.JSONObject(metadataFile.readText()).optString("id") == id) return Pair(File(directory, metadataFile.name.removeSuffix(".json") + ".md"), metadataFile) } catch (_: Exception) { } }
        return null
    }

    private fun clearData(values: Map<*, *>) {
        when (values["kind"] as? String) {
            "logs" -> getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().remove("runtimeLastOutput").remove("runtimeLastError").apply()
            "sessions" -> File(filesDir, "runtime/dsh-home/sessions").deleteRecursively()
            "all" -> {
                CredentialStore(this).clear()
                getSharedPreferences("public-config", MODE_PRIVATE).edit().clear().apply()
                getSharedPreferences("theme", MODE_PRIVATE).edit().clear().apply()
                getSharedPreferences("default-role", MODE_PRIVATE).edit().clear().apply()
                getSharedPreferences("public-config-history", MODE_PRIVATE).edit().clear().apply()
                getSharedPreferences(RuntimeService.PREFS, MODE_PRIVATE).edit().putBoolean("credentialsConfigured", false).remove("runtimeLastOutput").remove("runtimeLastError").apply()
                removeCustomRuntimePresets()
            }
        }
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
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingRoleResult: MethodChannel.Result? = null
    private var roleExportJson: String = ""

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == backupExportRequest) {
            val result = pendingBackupResult; pendingBackupResult = null
            if (resultCode != RESULT_OK || data?.data == null) { result?.success(mapOf("status" to "cancelled")); return }
            try { contentResolver.openOutputStream(data.data!!)?.use { it.write(backupJson().toString().toByteArray(Charsets.UTF_8)) }; result?.success(mapOf("status" to "exported")) } catch (error: Exception) { result?.error("BACKUP_EXPORT_ERROR", error.message, null) }
            return
        }
        if (requestCode == backupImportRequest) {
            val result = pendingBackupResult; pendingBackupResult = null
            if (resultCode != RESULT_OK || data?.data == null) { result?.success(mapOf("status" to "cancelled")); return }
            try { val json = contentResolver.openInputStream(data.data!!)?.bufferedReader()?.use { it.readText() } ?: throw IllegalArgumentException("无法读取备份"); restoreBackup(JSONObject(json)); result?.success(mapOf("status" to "imported")) } catch (error: Exception) { result?.success(mapOf("status" to "rejected", "reason" to (error.message ?: "备份格式错误"))) }
            return
        }
        if (requestCode == roleExportRequest) {
            val result = pendingRoleResult; pendingRoleResult = null
            if (resultCode != RESULT_OK || data?.data == null) { result?.success(mapOf("status" to "cancelled")); return }
            try { contentResolver.openOutputStream(data.data!!)?.use { it.write(roleExportJson.toByteArray(Charsets.UTF_8)) }; result?.success(mapOf("status" to "exported")) } catch (error: Exception) { result?.error("ROLE_EXPORT_ERROR", error.message, null) }
            return
        }
        if (requestCode == roleImportRequest) {
            val result = pendingRoleResult; pendingRoleResult = null
            if (resultCode != RESULT_OK || data?.data == null) { result?.success(null); return }
            try { val text = contentResolver.openInputStream(data.data!!)?.bufferedReader()?.use { it.readText() } ?: throw IllegalArgumentException("无法读取角色卡"); result?.success(text) } catch (error: Exception) { result?.error("ROLE_IMPORT_ERROR", error.message, null) }
            return
        }
        if (requestCode != apkPickerRequest) return
        val result = pendingInstallResult
        pendingInstallResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result?.success(mapOf("status" to "cancelled"))
            return
        }
        ioExecutor.execute {
            try {
                val cached = File(cacheDir, "pending-update.apk")
                contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(cached).use { output -> input.copyTo(output) } } ?: throw IllegalArgumentException("无法读取 APK 文件")
                val validation = validateApk(cached)
                runOnUiThread {
                    if (validation["ok"] != "true") {
                        result?.success(mapOf("status" to "rejected", "reason" to (validation["reason"] ?: "APK 校验失败"), "sha256" to (validation["sha256"] ?: "")))
                        return@runOnUiThread
                    }
                    val cachedUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", cached)
                    startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(cachedUri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result?.success(mapOf("status" to "installer_opened"))
                }
            } catch (error: Exception) {
                runOnUiThread { result?.error("INSTALLER_ERROR", error.message, null) }
            }
        }
    }

    private fun exportBackup(result: MethodChannel.Result) {
        pendingBackupResult = result
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { type = "application/json"; putExtra(Intent.EXTRA_TITLE, "qq-bot-cp-backup.json") }, backupExportRequest)
    }

    private fun importBackup(result: MethodChannel.Result) {
        createAutoBackup()
        pendingBackupResult = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "application/json" }, backupImportRequest)
    }

    private fun listBackups(): List<Map<String, Any>> {
        val directory = File(filesDir, "backups")
        return directory.listFiles()?.filter { it.isFile && it.extension == "json" }?.sortedByDescending { it.lastModified() }?.map {
            mapOf("path" to it.absolutePath, "name" to it.name, "size" to it.length(), "modified" to it.lastModified())
        } ?: emptyList()
    }

    private fun restoreBackupFile(values: Map<*, *>, result: MethodChannel.Result) {
        try {
            val directory = File(filesDir, "backups").canonicalFile
            val file = File(values["path"] as? String ?: "").canonicalFile
            require(file.parentFile == directory && file.isFile) { "备份文件路径无效" }
            createAutoBackup()
            restoreBackup(JSONObject(file.readText(Charsets.UTF_8)))
            result.success(mapOf("status" to "restored"))
        } catch (error: Exception) {
            result.success(mapOf("status" to "rejected", "reason" to (error.message ?: "备份恢复失败")))
        }
    }

    private fun exportRoleCard(values: Map<*, *>, result: MethodChannel.Result) {
        roleExportJson = values["json"] as? String ?: ""
        pendingRoleResult = result
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { type = "application/json"; putExtra(Intent.EXTRA_TITLE, "role-card.json") }, roleExportRequest)
    }

    private fun importRoleCard(result: MethodChannel.Result) {
        pendingRoleResult = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "application/json" }, roleImportRequest)
    }

    private fun createAutoBackup() {
        val directory = File(filesDir, "backups")
        directory.mkdirs()
        val name = "auto-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date()) + ".json"
        File(directory, name).writeText(backupJson().toString(), Charsets.UTF_8)
        directory.listFiles()?.sortedByDescending { it.lastModified() }?.drop(5)?.forEach { it.delete() }
    }

    private fun backupJson(): JSONObject {
        val config = getSharedPreferences("public-config", MODE_PRIVATE)
        val theme = getSharedPreferences("theme", MODE_PRIVATE)
        val role = getSharedPreferences("default-role", MODE_PRIVATE)
        val cards = try { org.json.JSONArray(getSharedPreferences("role-cards", MODE_PRIVATE).getString("items", "[]") ?: "[]") } catch (_: Exception) { org.json.JSONArray() }
        return JSONObject().put("schemaVersion", 1).put("appVersion", appInfo()["versionName"]).put("publicConfig", JSONObject().put("protocol", config.getString("protocol", "")).put("model", config.getString("model", "")).put("baseUrl", config.getString("baseUrl", "")).put("thinkingLevel", config.getString("thinkingLevel", "medium")).put("updateUrl", config.getString("updateUrl", ""))).put("theme", JSONObject().put("mode", theme.getString("mode", "dark")).put("seedColor", theme.getInt("seedColor", 0xff8290ff.toInt())).put("cardRadius", theme.getFloat("cardRadius", 16f)).put("cardOpacity", theme.getFloat("cardOpacity", 1f)).put("tintedBackground", theme.getBoolean("tintedBackground", false))).put("defaultRole", JSONObject().put("id", role.getString("id", "")).put("name", role.getString("name", "")).put("prompt", role.getString("prompt", ""))).put("roleCards", cards)
    }

    private fun restoreBackup(json: JSONObject) {
        val schema = json.optInt("schemaVersion", 0)
        if (schema == 1) {
            val config = json.optJSONObject("publicConfig") ?: JSONObject()
            getSharedPreferences("public-config", MODE_PRIVATE).edit().putString("protocol", config.optString("protocol")).putString("model", config.optString("model")).putString("baseUrl", config.optString("baseUrl")).putString("thinkingLevel", config.optString("thinkingLevel", "medium")).putString("updateUrl", config.optString("updateUrl")).apply()
        } else if (json.optInt("version", 0) == 1) {
            // Legacy WebView export: migrate public AI fields and role cards only.
            // AppID, AppSecret and API keys are intentionally ignored.
            val legacy = json.optJSONObject("config") ?: JSONObject()
            val provider = legacy.optString("provider", "")
            val protocol = when (provider) {
                "relay", "openai-compatible", "" -> "openai-compatible"
                else -> provider
            }
            getSharedPreferences("public-config", MODE_PRIVATE).edit()
                .putString("protocol", protocol)
                .putString("model", legacy.optString("model", ""))
                .putString("baseUrl", legacy.optString("baseUrl", "")).apply()
            val legacyRoles = json.optJSONArray("roles") ?: org.json.JSONArray()
            val migrated = org.json.JSONArray()
            for (index in 0 until legacyRoles.length()) {
                val role = legacyRoles.optJSONObject(index) ?: continue
                val id = role.optString("id", "")
                val prompt = role.optString("prompt", "")
                if (id.startsWith("custom.") && prompt.isNotBlank()) migrated.put(JSONObject().put("id", id).put("displayName", role.optString("displayName", id)).put("prompt", prompt))
            }
            getSharedPreferences("role-cards", MODE_PRIVATE).edit().putString("items", migrated.toString()).apply()
            syncCustomRuntimePresets(migrated)
            getSharedPreferences("default-role", MODE_PRIVATE).edit().clear().apply()
            return
        } else {
            throw IllegalArgumentException("不支持的备份版本")
        }
        val theme = json.optJSONObject("theme") ?: JSONObject()
        getSharedPreferences("theme", MODE_PRIVATE).edit().putString("mode", theme.optString("mode", "dark")).putInt("seedColor", theme.optInt("seedColor", 0xff8290ff.toInt())).putFloat("cardRadius", theme.optDouble("cardRadius", 16.0).toFloat()).putFloat("cardOpacity", theme.optDouble("cardOpacity", 1.0).toFloat()).putBoolean("tintedBackground", theme.optBoolean("tintedBackground", false)).apply()
        val role = json.optJSONObject("defaultRole") ?: JSONObject()
        getSharedPreferences("default-role", MODE_PRIVATE).edit().putString("id", role.optString("id", "")).putString("name", role.optString("name", "")).putString("prompt", role.optString("prompt", "")).apply()
        val cards = json.optJSONArray("roleCards") ?: org.json.JSONArray()
        getSharedPreferences("role-cards", MODE_PRIVATE).edit().putString("items", cards.toString()).apply()
        syncCustomRuntimePresets(cards)
    }

    private fun syncCustomRuntimePresets(cards: org.json.JSONArray) {
        val directory = File(filesDir, "runtime/presets").apply { mkdirs() }
        removeCustomRuntimePresets()
        for (index in 0 until cards.length()) {
            val card = cards.optJSONObject(index) ?: continue
            val id = card.optString("id", "")
            val prompt = card.optString("prompt", "")
            if (!Regex("custom\\.[a-z0-9][a-z0-9._-]{0,48}").matches(id) || prompt.isBlank()) continue
            File(directory, "preset.$id.md").writeText(prompt, Charsets.UTF_8)
            File(directory, "preset.$id.json").writeText(JSONObject().put("id", id).put("displayName", card.optString("displayName", id)).put("builtin", false).toString(), Charsets.UTF_8)
        }
    }

    private fun removeCustomRuntimePresets() {
        val directory = File(filesDir, "runtime/presets")
        directory.listFiles()?.forEach { file ->
            if (!file.name.startsWith("preset.") || !file.name.endsWith(".json")) return@forEach
            try {
                val id = JSONObject(file.readText()).optString("id", "")
                if (id.startsWith("custom.")) {
                    file.delete()
                    File(directory, file.name.removeSuffix(".json") + ".md").delete()
                }
            } catch (_: Exception) { }
        }
    }

    private fun validateApk(file: File): Map<String, String> {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: return mapOf("ok" to "false", "reason" to "无法解析 APK 元数据")
        if (archive.packageName != packageName) return mapOf("ok" to "false", "reason" to "包名不匹配：${archive.packageName}")
        val current = packageManager.getPackageInfo(packageName, flags)
        val currentVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) current.longVersionCode else @Suppress("DEPRECATION") current.versionCode.toLong()
        val archiveVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive.longVersionCode else @Suppress("DEPRECATION") archive.versionCode.toLong()
        if (archiveVersion <= currentVersion) return mapOf("ok" to "false", "reason" to "版本号必须高于当前版本")
        val archiveSignatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") archive.signatures
        val currentSignatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) current.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") current.signatures
        if (archiveSignatures.isNullOrEmpty() || currentSignatures.isNullOrEmpty() || !archiveSignatures.first().toCharsString().equals(currentSignatures.first().toCharsString(), ignoreCase = false)) return mapOf("ok" to "false", "reason" to "签名不匹配")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(8192); var count = input.read(buffer); while (count > 0) { digest.update(buffer, 0, count); count = input.read(buffer) } }
        val sha256 = digest.digest().joinToString("") { "%02x".format(it) }
        return mapOf("ok" to "true", "sha256" to sha256, "versionCode" to archiveVersion.toString())
    }

    private fun verifyAndInstallUpdate(values: Map<*, *>, result: MethodChannel.Result) {
        val file = File(values["path"] as? String ?: "")
        val expected = (values["sha256"] as? String ?: "").trim().lowercase()
        ioExecutor.execute {
            try {
                if (!file.isFile) {
                    runOnUiThread { result.success(mapOf("status" to "rejected", "reason" to "下载文件不存在")) }
                    return@execute
                }
                val actual = sha256(file)
                if (expected.isNotEmpty() && actual != expected) {
                    runOnUiThread { result.success(mapOf("status" to "rejected", "reason" to "SHA-256 校验失败", "sha256" to actual)) }
                    return@execute
                }
                val validation = validateApk(file)
                if (validation["ok"] != "true") {
                    runOnUiThread { result.success(mapOf("status" to "rejected", "reason" to (validation["reason"] ?: "APK 校验失败"), "sha256" to actual)) }
                    return@execute
                }
                runOnUiThread {
                    val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                    startActivity(Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, "application/vnd.android.package-archive"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) })
                    result.success(mapOf("status" to "installer_opened", "sha256" to actual))
                }
            } catch (error: Exception) {
                runOnUiThread { result.error("UPDATE_VERIFY_ERROR", error.message, null) }
            }
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var count = input.read(buffer)
            while (count > 0) { digest.update(buffer, 0, count); count = input.read(buffer) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
