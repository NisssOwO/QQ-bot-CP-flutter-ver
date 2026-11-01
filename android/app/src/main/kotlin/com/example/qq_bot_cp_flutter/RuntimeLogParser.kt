package com.shinycolors.officialbot

/** Turns one runtime output line into the level, module and counters the UI shows. */
object RuntimeLogParser {
    data class Parsed(
        val level: String,
        val module: String,
        val qq: String? = null,
        val ai: String? = null,
        val network: String? = null,
        val errorCode: String? = null,
    )

    fun parse(line: String, source: String): Parsed {
        if (line.startsWith("    at ") || line.startsWith("\tat ")) return Parsed("info", "trace")
        val lower = line.lowercase()
        // Chat traffic lines describe a message, never a connection state: they must not
        // flip the QQ chip back to 连接中 while the bot is online.
        val traffic = line.startsWith("[inbound]") || line.startsWith("[outbound]")
        val level = levelOf(lower, source)
        val module = when {
            traffic -> "qq"
            lower.contains("plugin") || lower.contains("import") -> "plugin"
            lower.contains("qqbot") || lower.contains("websocket") || lower.contains("gateway") -> "qq"
            lower.contains("llm") || lower.contains("provider") || lower.contains("model") -> "ai"
            lower.contains("network") || lower.contains("dns") || lower.contains("tls") -> "network"
            lower.contains("session") -> "session"
            else -> "node"
        }
        val failure = lower.contains("error") || lower.contains("failed") || lower.contains("disconnect")
        val connected = lower.contains("ready") || lower.contains("connected") || lower.contains("online")
        val botReady = lower.contains("[im-qqbot] bot ready")
        val qq = if (module == "qq" && !traffic) (if (failure) "异常" else if (connected) "在线" else "连接中") else null
        // The QQ gateway's ready signal means the configured LLM adapter finished loading
        // as part of the same DSH profile. Keep the UI out of the misleading "未知" state
        // until an actual request reports a failure.
        val ai = when {
            botReady -> "已就绪"
            module == "ai" -> if (failure || lower.contains("missing_credential")) "异常" else if (connected) "在线" else "请求中"
            else -> null
        }
        val network = if (module == "network") (if (failure) "异常" else "连接中") else null
        val errorCode = when {
            lower.contains("failed to import") -> "plugin_import_failed"
            lower.contains("missing_credential") -> "missing_credential"
            lower.contains("connection error") -> "transport_error"
            else -> null
        }
        return Parsed(level, module, qq, ai, network, errorCode)
    }

    /**
     * The level follows what the line says, not which stream printed it: Node and the DSH
     * plugins write warnings to stdout, so a stream based level painted warnings green.
     */
    private fun levelOf(lower: String, source: String): String = when {
        lower.contains("fatal") || lower.contains("panic") || lower.contains("traceback") -> "error"
        lower.contains("error") || lower.contains("failed") || lower.contains("exception") -> "error"
        lower.contains("warn") || lower.contains("deprecated") || lower.contains("timeout") ||
            lower.contains("retry") || lower.contains("disconnect") || lower.contains("fallback") -> "warn"
        source == "stderr" -> "error"
        else -> "info"
    }
}
