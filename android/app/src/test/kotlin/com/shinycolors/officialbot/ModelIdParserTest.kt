package com.shinycolors.officialbot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 各家网关的 /models 响应格式不同，用户换个中转就可能拉不到模型。
 * 这里把常见格式都钉住，避免解析逻辑回退。
 */
class ModelIdParserTest {
    @Test
    fun `openai data array with id`() {
        val body = """{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"o3-mini"}]}"""
        assertEquals(listOf("gpt-4o", "o3-mini"), ModelIdParser.parse(body))
    }

    @Test
    fun `models array falling back to name or model keys`() {
        val body = """{"models":[{"name":"deepseek-chat"},{"model":"deepseek-reasoner"},{"id":"deepseek-coder"}]}"""
        assertEquals(
            listOf("deepseek-chat", "deepseek-coder", "deepseek-reasoner"),
            ModelIdParser.parse(body),
        )
    }

    @Test
    fun `bare array of strings`() {
        val body = """["qwen-max","qwen-plus"]"""
        assertEquals(listOf("qwen-max", "qwen-plus"), ModelIdParser.parse(body))
    }

    @Test
    fun `bare array of objects`() {
        val body = """[{"id":"glm-4"},{"name":"glm-4-air"}]"""
        assertEquals(listOf("glm-4", "glm-4-air"), ModelIdParser.parse(body))
    }

    @Test
    fun `duplicates are removed and output is sorted`() {
        val body = """{"data":[{"id":"b"},{"id":"a"},{"id":"b"},{"name":" "}]}"""
        assertEquals(listOf("a", "b"), ModelIdParser.parse(body))
    }

    @Test
    fun `data array wins over models array`() {
        val body = """{"data":[{"id":"primary"}],"models":[{"id":"ignored"}]}"""
        assertEquals(listOf("primary"), ModelIdParser.parse(body))
    }

    @Test
    fun `empty and invalid responses yield empty list`() {
        assertTrue(ModelIdParser.parse("").isEmpty())
        assertTrue(ModelIdParser.parse("   ").isEmpty())
        assertTrue(ModelIdParser.parse("<html>502 Bad Gateway</html>").isEmpty())
        assertTrue(ModelIdParser.parse("""{"object":"list"}""").isEmpty())
    }

    @Test
    fun `non string entries and blank ids are skipped`() {
        val body = """{"data":["ok",42,null,{"id":""},{"note":"no id"}]}"""
        assertEquals(listOf("ok"), ModelIdParser.parse(body))
    }
}