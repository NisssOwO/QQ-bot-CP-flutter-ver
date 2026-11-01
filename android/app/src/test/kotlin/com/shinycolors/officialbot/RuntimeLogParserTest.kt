package com.shinycolors.officialbot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The log page paints rows by this level, so it has to follow the text, not the stream. */
class RuntimeLogParserTest {
    private fun parse(line: String, source: String = "stdout") = RuntimeLogParser.parse(line, source)

    @Test
    fun `stdout warning becomes warn so the filter can find it`() {
        val parsed = parse("dsh: warning: 15 entries did not activate")

        assertEquals("warn", parsed.level)
    }

    @Test
    fun `stdout failure becomes error`() {
        assertEquals("error", parse("im-qqbot: sendMarkdown failed: 500").level)
        assertEquals("error", parse("Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'got'").level)
    }

    @Test
    fun `plain stdout stays information`() {
        assertEquals("info", parse("QQBOT_BOOTING pid=1234").level)
    }

    @Test
    fun `stderr stays loud unless it only warns`() {
        assertEquals("error", parse("at processTicksAndRejections", "stderr").level)
        assertEquals("warn", parse("Warning: something is deprecated", "stderr").level)
    }

    @Test
    fun `chat traffic is a qq row that never touches the connection chip`() {
        val inbound = parse("[inbound] 收到群消息 · 1CDE5232 · 12 字 · \"你好\"")

        assertEquals("info", inbound.level)
        assertEquals("qq", inbound.module)
        assertNull(inbound.qq)

        val outbound = parse("[outbound] 已回复私聊 · 86 字 · 1 段 · 1240 ms")

        assertEquals("qq", outbound.module)
        assertNull(outbound.qq)
    }

    @Test
    fun `gateway ready still marks qq online and ai ready`() {
        val parsed = parse("[im-qqbot] Bot ready! appId=100000000")

        assertEquals("qq", parsed.module)
        assertEquals("在线", parsed.qq)
        assertEquals("已就绪", parsed.ai)
    }

    @Test
    fun `network retries are warnings on the network module`() {
        val parsed = parse("network.retry 第 2 次重连 3000ms")

        assertEquals("warn", parsed.level)
        assertEquals("network", parsed.module)
    }

    @Test
    fun `stack frames stay quiet`() {
        val parsed = parse("\tat Module._load (node:internal/modules/cjs/loader:1:1)")

        assertEquals("info", parsed.level)
        assertEquals("trace", parsed.module)
    }
}