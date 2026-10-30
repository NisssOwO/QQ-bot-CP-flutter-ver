package com.example.qq_bot_cp_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    private val methodChannel = "qq_bot_cp/runtime"
    private val eventChannel = "qq_bot_cp/runtime_events"
    private val apkPickerRequest = 1901
    private val backupExportRequest = 2001
    private val backupImportRequest = 2002

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
                "getUpdateCachePath" -> result.success(File(cacheDir, "online-update.apk").absolutePath)
                "verifyAndInstallUpdate" -> verifyAndInstallUpdate(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                "getThemeSettings" -> result.success(themeSettings())
                "saveThemeSettings" -> { saveThemeSettings(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "exportBackup" -> exportBackup(result)
                "importBackup" -> importBackup(result)
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
        if (requestCode != apkPickerRequest) return
        val result = pendingInstallResult
        pendingInstallResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result?.success(mapOf("status" to "cancelled"))
            return
        }
        try {
            val cached = File(cacheDir, "pending-update.apk")
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(cached).use { output -> input.copyTo(output) } } ?: throw IllegalArgumentException("无法读取 APK 文件")
            val validation = validateApk(cached)
            if (validation["ok"] != "true") {
                result?.success(mapOf("status" to "rejected", "reason" to (validation["reason"] ?: "APK 校验失败"), "sha256" to (validation["sha256"] ?: "")))
                return
            }
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result?.success(mapOf("status" to "installer_opened"))
        } catch (error: Exception) {
            result?.error("INSTALLER_ERROR", error.message, null)
        }
    }

    private fun exportBackup(result: MethodChannel.Result) {
        pendingBackupResult = result
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { type = "application/json"; putExtra(Intent.EXTRA_TITLE, "qq-bot-cp-backup.json") }, backupExportRequest)
    }

    private fun importBackup(result: MethodChannel.Result) {
        pendingBackupResult = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "application/json" }, backupImportRequest)
    }

    private fun backupJson(): JSONObject {
        val config = getSharedPreferences("public-config", MODE_PRIVATE)
        val theme = getSharedPreferences("theme", MODE_PRIVATE)
        return JSONObject().put("schemaVersion", 1).put("appVersion", appInfo()["versionName"]).put("publicConfig", JSONObject().put("protocol", config.getString("protocol", "")).put("model", config.getString("model", "")).put("baseUrl", config.getString("baseUrl", ""))).put("theme", JSONObject().put("mode", theme.getString("mode", "dark")).put("seedColor", theme.getInt("seedColor", 0xff8290ff.toInt())).put("cardRadius", theme.getFloat("cardRadius", 16f)).put("cardOpacity", theme.getFloat("cardOpacity", 1f)).put("tintedBackground", theme.getBoolean("tintedBackground", false)))
    }

    private fun restoreBackup(json: JSONObject) {
        require(json.optInt("schemaVersion", 0) == 1) { "不支持的备份版本" }
        val config = json.optJSONObject("publicConfig") ?: JSONObject()
        getSharedPreferences("public-config", MODE_PRIVATE).edit().putString("protocol", config.optString("protocol")).putString("model", config.optString("model")).putString("baseUrl", config.optString("baseUrl")).apply()
        val theme = json.optJSONObject("theme") ?: JSONObject()
        getSharedPreferences("theme", MODE_PRIVATE).edit().putString("mode", theme.optString("mode", "dark")).putInt("seedColor", theme.optInt("seedColor", 0xff8290ff.toInt())).putFloat("cardRadius", theme.optDouble("cardRadius", 16.0).toFloat()).putFloat("cardOpacity", theme.optDouble("cardOpacity", 1.0).toFloat()).putBoolean("tintedBackground", theme.optBoolean("tintedBackground", false)).apply()
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
        if (!file.isFile) { result.success(mapOf("status" to "rejected", "reason" to "下载文件不存在")); return }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(8192); var count = input.read(buffer); while (count > 0) { digest.update(buffer, 0, count); count = input.read(buffer) } }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (expected.isNotEmpty() && actual != expected) { result.success(mapOf("status" to "rejected", "reason" to "SHA-256 校验失败", "sha256" to actual)); return }
        val validation = validateApk(file)
        if (validation["ok"] != "true") { result.success(mapOf("status" to "rejected", "reason" to (validation["reason"] ?: "APK 校验失败"), "sha256" to actual)); return }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, "application/vnd.android.package-archive"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) })
        result.success(mapOf("status" to "installer_opened", "sha256" to actual))
    }
}
