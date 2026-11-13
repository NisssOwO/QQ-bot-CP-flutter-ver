package com.shinycolors.officialbot

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * 读取 Node 侧写入的网关状态快照（`filesDir/.dsh-qqbot/gateway-status.json`）。
 *
 * 这个文件由 dsh-qqbot 的 `gateway-status.js` 原子写入，是 App 判断
 * “进程活着”与“真的在线”之间差异的唯一依据。看门狗靠它决定是否自愈。
 */
object GatewayStatusStore {
    private const val DIR = ".dsh-qqbot"
    private const val FILE_NAME = "gateway-status.json"

    /** 在线但心跳停了这么久，视为连接已经没人维护。Node 侧心跳是 20 秒一次。 */
    const val ONLINE_STALE_MS = 120_000L

    /** 连接中/重连中这么久没有任何状态写入，视为重连循环卡死。 */
    const val RETRY_STALL_MS = 180_000L

    data class Snapshot(
        val state: String,
        val updatedAt: Long,
        val attempts: Int,
        val code: Int?,
        val reason: String,
        val error: String,
        val lastError: String,
    ) {
        val isOnline: Boolean get() = state == "online"

        fun age(now: Long = System.currentTimeMillis()): Long =
            if (updatedAt <= 0) Long.MAX_VALUE else (now - updatedAt).coerceAtLeast(0)

        /**
         * 是否需要自愈重启。
         *
         * - `offline` / `failed`：SDK 已经放弃，只有重启能救。
         * - `online` 但心跳超过 [ONLINE_STALE_MS]：进程还在，连接已经不动。
         * - `connecting` / `reconnecting` 超过 [RETRY_STALL_MS] 没有进展：重连循环卡死。
         *
         * 没有写入过（`updatedAt <= 0`）说明 Runtime 还没启动完，不能据此重启。
         */
        fun needsRecovery(now: Long = System.currentTimeMillis()): Boolean {
            if (updatedAt <= 0) return false
            val span = age(now)
            return when (state) {
                "online" -> span > ONLINE_STALE_MS
                "connecting", "reconnecting" -> span > RETRY_STALL_MS
                "offline", "failed" -> true
                else -> false
            }
        }

        fun describe(now: Long = System.currentTimeMillis()): String {
            val head = when (state) {
                "online" -> "在线但心跳停了 ${age(now) / 1000} 秒"
                "connecting" -> "连接中已停滞 ${age(now) / 1000} 秒"
                "reconnecting" -> "第 $attempts 次重连后停滞 ${age(now) / 1000} 秒"
                "offline" -> "SDK 已放弃重连"
                "failed" -> "启动失败"
                else -> "状态未知"
            }
            val detail = when {
                error.isNotEmpty() -> "$head：$error"
                lastError.isNotEmpty() -> "$head：$lastError"
                reason.isNotEmpty() -> "$head：$reason"
                else -> head
            }
            return if (code != null) "$detail（code $code）" else detail
        }
    }

    fun file(context: Context): File = File(context.filesDir, "$DIR/$FILE_NAME")

    fun read(context: Context): Snapshot? {
        val file = file(context)
        if (!file.exists() || file.length() == 0L) return null
        return try {
            val raw = JSONObject(file.readText())
            Snapshot(
                state = raw.optString("state", ""),
                updatedAt = raw.optLong("updatedAt", 0L),
                attempts = raw.optInt("attempts", 0),
                code = if (raw.has("code") && !raw.isNull("code")) raw.optInt("code") else null,
                reason = raw.optString("reason", ""),
                error = raw.optString("error", ""),
                lastError = raw.optString("lastError", ""),
            )
        } catch (_: Exception) {
            // 原子写过程中读到半个文件或格式变化都当作没有状态，绝不因为解析失败去重启。
            null
        }
    }
}