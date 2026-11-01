package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets

/**
 * 记录文件日志是否真的在写，[RuntimeProcessController] 用它决定是否退回读管道。
 *
 * 管道只在 DSH 还没接管自己的输出之前有数据，之后就会安静下来；健康标记为真时
 * 所有日志都来自文件，避免同一行既走管道又走文件被记两次。
 */
object LogTapHealth {
    @Volatile var healthy = false
    @Volatile var pipeFallback = false
}

/**
 * 增量读取 `files/runtime/logs/runtime.log`，把新行交给日志页。
 *
 * 文件由 android-log-tap.cjs 在 DSH 进程内写入，格式是
 * `<ISO 时间>|<stdout|stderr|host>|<原始行>`；只按完整行推进偏移，所以半行、
 * 文件轮转和进程重启都不会丢内容。
 */
/** 一行文件日志的拆分规则，单独放出来便于单测。 */
internal object RuntimeLogLine {
    /**
     * `<ISO 时间>|<stdout|stderr|host>|<原始行>` → `stream to message`。
     * 不是这个格式时返回 null，交给调用方按原始 stdout 行处理。
     */
    fun split(line: String): Pair<String, String>? {
        val first = line.indexOf('|')
        if (first <= 0) return null
        val second = line.indexOf('|', first + 1)
        if (second <= first) return null
        val stream = line.substring(first + 1, second).trim()
        val message = line.substring(second + 1)
        if (message.isBlank()) return null
        return (if (stream == "stderr") "stderr" else "stdout") to message
    }
}

class RuntimeLogTailer private constructor(private val context: Context) {
    private val logFile = File(File(context.filesDir, "runtime"), "logs/runtime.log")
    private val recorder = RuntimeLogRecorder(context)
    private var offset = 0L
    @Volatile private var running = false
    private var worker: Thread? = null
    private var carry = StringBuilder()

    private fun start() {
        if (running) return
        running = true
        // 文件里留着上一次会话的内容，从末尾开始读才不会把旧日志重放一遍。
        if (logFile.isFile) offset = logFile.length()
        worker = Thread({ loop() }, "runtime-log-tail").apply {
            priority = Thread.MIN_PRIORITY
            start()
        }
    }

    private fun stop() {
        running = false
        worker?.interrupt()
        worker = null
    }

    private fun loop() {
        while (running) {
            try {
                readOnce()
            } catch (_: Exception) {
                // 轮转中的文件可能短暂不可读，下一轮继续。
            }
            if (!running) break
            try {
                Thread.sleep(POLL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun readOnce() {
        val processAtStart = System.currentTimeMillis()
        if (!logFile.isFile) {
            if (processAtStart - startedAt > PIPE_FALLBACK_MS) LogTapHealth.pipeFallback = true
            return
        }
        val length = logFile.length()
        if (length < offset) {
            // 轮转后从新文件开头读，旧内容已经在界面里了。
            offset = 0
            carry = StringBuilder()
        }
        if (length <= offset) return
        RandomAccessFile(logFile, "r").use { file ->
            file.seek(offset)
            val size = (length - offset).coerceAtMost(MAX_READ.toLong()).toInt()
            val chunk = ByteArray(size)
            val read = file.read(chunk)
            if (read <= 0) return
            var complete = read
            while (complete > 0 && chunk[complete - 1] != '\n'.code.toByte()) complete--
            if (complete == 0) return
            offset += complete
            carry.append(String(chunk, 0, complete, StandardCharsets.UTF_8))
            if (carry.length > MAX_CARRY) carry = StringBuilder()
            var newline = carry.indexOf("\n")
            while (newline >= 0) {
                consume(carry.substring(0, newline))
                carry.delete(0, newline + 1)
                newline = carry.indexOf("\n")
            }
        }
        if (!LogTapHealth.healthy) {
            LogTapHealth.healthy = true
            // 文件已经在写了，管道里的同一批行不用再记一次。
            LogTapHealth.pipeFallback = false
        }
    }

    private fun consume(line: String) {
        if (line.isBlank()) return
        val parsed = RuntimeLogLine.split(line)
        if (parsed == null) record("stdout", line) else record(parsed.first, parsed.second)
    }

    private fun record(source: String, message: String) {
        // 启动握手这一行由管道记录就够了，避免日志页出现两条一样的 PID。
        if (message.startsWith("QQBOT_BOOTING")) return
        val parsed = RuntimeLogParser.parse(message, source)
        recorder.stream(parsed.level, parsed.module, message, parsed.qq, parsed.ai, parsed.network, parsed.errorCode)
    }

    companion object {
        private const val POLL_MS = 800L
        private const val PIPE_FALLBACK_MS = 12_000L
        private const val MAX_READ = 256 * 1024
        private const val MAX_CARRY = 64 * 1024
        private var startedAt = System.currentTimeMillis()

        @Volatile private var shared: RuntimeLogTailer? = null

        /** 服务启动时调用；之后每次重启 Runtime 都复用同一个读偏移。 */
        fun ensureStarted(context: Context) {
            val instance = shared ?: synchronized(this) {
                shared ?: RuntimeLogTailer(context.applicationContext).also {
                    startedAt = System.currentTimeMillis()
                    shared = it
                }
            }
            instance.start()
        }

        fun stopShared() {
            synchronized(this) {
                shared?.stop()
                shared = null
            }
        }
    }
}