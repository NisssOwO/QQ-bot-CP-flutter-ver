package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.FileOutputStream

class RuntimeProcessController(private val context: Context) {
    private var process: Process? = null

    @Synchronized fun isAlive(): Boolean = process?.isAlive == true

    @Synchronized fun start(environment: Map<String, String>) {
        if (process?.isAlive == true) return
        val root = File(context.filesDir, "runtime")
        val bundledNode = File(root, "bin/node")
        val entry = File(root, "runtime-entry.mjs")
        require(bundledNode.isFile && entry.isFile) { "Runtime bundle is incomplete" }
        val nativeNode = File(context.applicationInfo.nativeLibraryDir, "libnode.so")
        val node = if (nativeNode.isFile) nativeNode else stageExecutable(bundledNode)
        val env = HashMap(System.getenv())
        env.putAll(environment)
        env["SHINY_RUNTIME_ROOT"] = root.absolutePath
        env["SHINY_NODE_BIN"] = node.absolutePath
        env["LD_LIBRARY_PATH"] = "${File(root, "bin").absolutePath}:${context.applicationInfo.nativeLibraryDir}"
        val child = ProcessBuilder(node.absolutePath, entry.absolutePath)
            .directory(root).redirectErrorStream(false).apply { environment().putAll(env) }.start()
        process = child
        val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
        prefs.edit().putBoolean("runtimeProcessAlive", true).putString("status", "online").apply()
        Thread { readStream(child.inputStream, "runtimeLastOutput") }.start()
        Thread { readStream(child.errorStream, "runtimeLastError") }.start()
        Thread {
            val exit = child.waitFor()
            val current = synchronized(this@RuntimeProcessController) { process === child }
            if (!current) return@Thread
            prefs.edit().putBoolean("runtimeProcessAlive", false).putString("status", if (exit == 0) "stopped" else "failed").putInt("runtimeExitCode", exit).apply()
            RuntimeEventBus.emit(if (exit == 0) "info" else "error", "runtime", "Node/DSH 进程退出，退出码=$exit", errorCode = if (exit == 0) null else "runtime_exit_nonzero")
        }.start()
    }

    private fun stageExecutable(source: File): File {
        val staged = File(context.codeCacheDir, "qqbot-runtime-node")
        if (!staged.isFile || staged.length() != source.length()) {
            source.inputStream().use { input -> FileOutputStream(staged).use { output -> input.copyTo(output, 256 * 1024) } }
        }
        staged.setReadable(true, true)
        staged.setExecutable(true, true)
        return staged
    }

    private fun readStream(stream: java.io.InputStream, key: String) {
        stream.bufferedReader().useLines { lines -> lines.forEach { line ->
            val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
            val previous = prefs.getString(key, "") ?: ""
            val next = (if (previous.isEmpty()) line else "$previous\n$line").takeLast(8192)
            prefs.edit().putString(key, next).apply()
            val lower = line.lowercase()
            val level = when {
                key != "runtimeLastError" -> "info"
                lower.contains("warning") || lower.contains("warn") -> "warn"
                else -> "error"
            }
            val module = when {
                lower.contains("plugin") || lower.contains("import") -> "plugin"
                lower.contains("qqbot") || lower.contains("websocket") || lower.contains("gateway") -> "qq"
                lower.contains("llm") || lower.contains("provider") || lower.contains("model") -> "ai"
                lower.contains("network") || lower.contains("dns") || lower.contains("tls") -> "network"
                lower.contains("session") -> "session"
                else -> "node"
            }
            val errorCode = when {
                lower.contains("failed to import") -> "plugin_import_failed"
                lower.contains("missing_credential") -> "missing_credential"
                lower.contains("connection error") -> "transport_error"
                else -> null
            }
            when (module) {
                "qq" -> {
                    val failure = lower.contains("error") || lower.contains("failed") || lower.contains("disconnect")
                    val connected = lower.contains("ready") || lower.contains("connected") || lower.contains("online")
                    val editor = prefs.edit().putString("qqStatus", when {
                        failure -> "异常"
                        connected -> "在线"
                        else -> "连接中"
                    })
                    if (failure) editor.putInt("qqFailureCount", prefs.getInt("qqFailureCount", 0) + 1)
                    if (connected) editor.putInt("qqFailureCount", 0)
                    editor.apply()
                }
                "ai" -> {
                    val failure = lower.contains("error") || lower.contains("failed") || lower.contains("missing_credential")
                    val connected = lower.contains("ready") || lower.contains("connected")
                    val editor = prefs.edit().putString("aiStatus", when {
                        failure -> "异常"
                        connected -> "在线"
                        else -> "请求中"
                    })
                    if (failure) editor.putInt("aiFailureCount", prefs.getInt("aiFailureCount", 0) + 1)
                    if (connected) editor.putInt("aiFailureCount", 0)
                    editor.apply()
                }
                "network" -> prefs.edit().putString("networkStatus", if (lower.contains("error") || lower.contains("failed")) "异常" else "连接中").apply()
            }
            RuntimeEventBus.emit(level, module, line, errorCode = errorCode)
        } }
    }

    @Synchronized fun stop() { process?.destroy(); process = null }
}
