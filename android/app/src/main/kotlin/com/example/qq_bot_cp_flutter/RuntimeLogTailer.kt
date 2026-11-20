package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

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
    fun split(line: String): Pair<String, String>? = parts(line)?.let { it.second to it.third }

    /**
     * 同 [split]，额外返回文件里写下的 ISO 时间戳。
     *
     * 时间戳必须一起取出来：早先只看 stream 与 message，于是“什么时候发生”被换成
     * “什么时候读到”，一份昨天写下的文件被重新读一遍就会出现一批假的新时间，事后
     * 完全分不清哪些错误是刚才发生的。
     */
    fun parts(line: String): Triple<String, String, String>? {
        val first = line.indexOf('|')
        if (first <= 0) return null
        val second = line.indexOf('|', first + 1)
        if (second <= first) return null
        val stamp = line.substring(0, first).trim()
        val stream = line.substring(first + 1, second).trim()
        val message = line.substring(second + 1)
        if (message.isBlank()) return null
        return Triple(stamp, if (stream == "stderr") "stderr" else "stdout", message)
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
        if (offset == 0L && length > 0 && logFile.lastModified() < startedAt) {
            // 文件是本次启动之前写下的：直接跳到末尾。日志页里已经有这批内容，
            // 再读一遍只会把旧错误记成新时间，让人以为是刚刚发生的故障。
            offset = length
            return
        }
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
        val parsed = RuntimeLogLine.parts(line)
        if (parsed == null) record("stdout", line, null) else record(parsed.second, parsed.third, parseStamp(parsed.first))
    }

    /** 文件里的 ISO 时间戳；解析不了就交给调用方回落到当前时刻。 */
    private fun parseStamp(iso: String): Long? = try {
        stampFormat.parse(iso)?.time
    } catch (_: Exception) {
        null
    }

    private fun record(source: String, message: String, at: Long?) {
        // 启动握手这一行由管道记录就够了，避免日志页出现两条一样的 PID。
        if (message.startsWith("QQBOT_BOOTING")) return
        val parsed = RuntimeLogParser.parse(message, source)
        recorder.stream(parsed.level, parsed.module, message, parsed.qq, parsed.ai, parsed.network, parsed.errorCode, at)
    }

    companion object {
        private const val POLL_MS = 800L
        private const val PIPE_FALLBACK_MS = 12_000L
        private const val MAX_READ = 256 * 1024
        private const val MAX_CARRY = 64 * 1024
        private var startedAt = System.currentTimeMillis()

        /**
         * 解析 android-log-tap.cjs 写下的 `<ISO-8601>|` 前缀。
         *
         * 只在 tail 线程里用，所以简单格式化的线程安全问题在这里不存在；
         * `X` 模式自 API 24 起可用，正好是本项目的最低版本。
         */
        private val stampFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

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