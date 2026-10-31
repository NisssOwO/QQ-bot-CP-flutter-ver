package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class RuntimeProcessController(private val context: Context) {
    enum class Boot { BOOTED, SILENT, EXITED, NOT_STARTED }

    private var process: Process? = null
    private var booted = CountDownLatch(1)
    private var exited = CountDownLatch(1)
    private val recorder = RuntimeLogRecorder(context)
    private val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)

    @Synchronized fun isAlive(): Boolean = process?.isAlive == true

    @Synchronized fun exitCode(): Int? = try {
        process?.takeIf { !it.isAlive }?.exitValue()
    } catch (_: IllegalThreadStateException) {
        null
    }

    @Synchronized fun start(environment: Map<String, String>) {
        if (process?.isAlive == true) return
        val root = File(context.filesDir, "runtime")
        val entry = File(root, "runtime-entry.mjs")
        require(entry.isFile) { "Runtime bundle is incomplete" }
        val node = resolveNode(root)
        booted = CountDownLatch(1)
        exited = CountDownLatch(1)
        val child = ProcessBuilder(node.absolutePath, entry.absolutePath)
            .directory(root)
            .redirectErrorStream(false)
            .apply { environment().putAll(childEnvironment(root, node, environment)) }
            .start()
        process = child
        prefs.edit().putBoolean("runtimeProcessAlive", true).apply()
        Thread { drain(child.inputStream, "stdout") }.start()
        Thread { drain(child.errorStream, "stderr") }.start()
        Thread {
            val code = child.waitFor()
            val current = synchronized(this@RuntimeProcessController) { process === child }
            if (!current) return@Thread
            prefs.edit().putBoolean("runtimeProcessAlive", false).putInt("runtimeExitCode", code).apply()
            exited.countDown()
            RuntimeEventBus.emit(if (code == 0) "info" else "error", "runtime", "Node/DSH 进程退出，退出码=$code", errorCode = if (code == 0) null else "runtime_exit_nonzero")
            // Join the readers first by closing our side, then report.
            try {
                child.outputStream.close()
            } catch (_: Exception) {
            }
            try {
                Thread.sleep(300)
            } catch (_: InterruptedException) {
            }
            if (code != 0) {
                val detail = stderrSample().firstOrNull { it.isNotBlank() } ?: "stderr 为空"
                recorder.record(RuntimeLogRecorder.Status.FAILED, "runtime.exit", "Node/DSH 进程退出，退出码=$code，首条错误：$detail", 0, "runtime_exit_nonzero")
            }
        }.start()
    }

    /** Waits for the entry script's first line so the UI can tell "spawned" from "silently running". */
    fun boot(): Boot {
        val signalled = try {
            booted.await(RuntimeProcessController.BOOT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            return Boot.SILENT
        }
        if (signalled) return Boot.BOOTED
        return if (process?.isAlive == true) Boot.SILENT else Boot.EXITED
    }

    /**
     * Node runs from the APK's native library directory, which Android always mounts
     * executable. The bundled copy is staged only when the native one is missing.
     */
    private fun resolveNode(root: File): File {
        val native = File(context.applicationInfo.nativeLibraryDir, "libnode.so")
        if (native.isFile) return native
        val bundled = File(root, "bin/node")
        require(bundled.isFile) { "Runtime bundle is incomplete" }
        return stageExecutable(bundled)
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

    /**
     * Android app processes get a very small environment; PATH, HOME and TMPDIR are
     * missing, which node and the DSH loader rely on.
     */
    private fun childEnvironment(root: File, node: File, extra: Map<String, String>): Map<String, String> {
        val env = HashMap<String, String>()
        env["PATH"] = "/system/bin:/system/xbin:/product/bin:/vendor/bin"
        env["HOME"] = context.filesDir.absolutePath
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["TMP"] = context.cacheDir.absolutePath
        env["TEMP"] = context.cacheDir.absolutePath
        env["ANDROID_DATA"] = "/data"
        env["ANDROID_ROOT"] = "/system"
        env["ANDROID_STORAGE"] = "/storage"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env.putAll(extra)
        env["SHINY_RUNTIME_ROOT"] = root.absolutePath
        env["SHINY_NODE_BIN"] = node.absolutePath
        env["LD_LIBRARY_PATH"] = "${File(root, "bin").absolutePath}:${context.applicationInfo.nativeLibraryDir}"
        return env
    }

    private fun drain(stream: java.io.InputStream, source: String) {
        stream.bufferedReader().useLines { lines ->
            var captured = 0
            lines.forEach { line ->
                if (booted.count > 0) booted.countDown()
                val parsed = RuntimeLogParser.parse(line, source)
                recorder.stream(parsed.level, parsed.module, line, parsed.qq, parsed.ai, parsed.network, parsed.errorCode)
                if (source == "stderr" && captured < 20 && line.isNotBlank()) {
                    captured++
                    stderrSample.add(line.take(240))
                }
            }
        }
    }

    /** The first stderr lines, used to explain a fast exit even after the log history rotates. */
    fun stderrSample(): List<String> = synchronized(stderrSample) { stderrSample.toList() }

    @Synchronized fun stop() {
        process?.destroy()
        process = null
        exited.countDown()
        prefs.edit().putBoolean("runtimeProcessAlive", false).apply()
    }

    val stderrSample = ArrayList<String>()
    companion object {
        const val BOOT_TIMEOUT_MS = 20_000L
    }
}