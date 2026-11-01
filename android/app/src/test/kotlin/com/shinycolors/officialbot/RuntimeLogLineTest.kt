package com.shinycolors.officialbot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeLogLineTest {
    @Test
    fun `splits a stdout line into source and message`() {
        val parsed = RuntimeLogLine.split("2026-11-01T13:22:33.123Z|stdout|[inbound] 收到私聊 · 3fed20c6 · 4 字")
        assertEquals("stdout", parsed?.first)
        assertEquals("[inbound] 收到私聊 · 3fed20c6 · 4 字", parsed?.second)
    }

    @Test
    fun `keeps pipe characters inside the message`() {
        val parsed = RuntimeLogLine.split("2026-11-01T13:22:33.123Z|stderr|a|b|c")
        assertEquals("stderr", parsed?.first)
        assertEquals("a|b|c", parsed?.second)
    }

    @Test
    fun `treats an unknown stream as stdout`() {
        val parsed = RuntimeLogLine.split("2026-11-01T13:22:33.123Z|host|runtime-entry boot pid=1")
        assertEquals("stdout", parsed?.first)
        assertEquals("runtime-entry boot pid=1", parsed?.second)
    }

    @Test
    fun `rejects lines without the tap prefix`() {
        assertNull(RuntimeLogLine.split("WARNING: linker: unused DT entry"))
        assertNull(RuntimeLogLine.split("2026-11-01T13:22:33.123Z|stdout|"))
        assertNull(RuntimeLogLine.split("|stdout|missing timestamp"))
    }
}
