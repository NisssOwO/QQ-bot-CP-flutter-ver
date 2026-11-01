package com.shinycolors.officialbot

import org.json.JSONArray
import org.json.JSONObject

/**
 * 不同网关返回的模型列表格式并不统一：
 * 直接是数组、包在 data 里、包在 models 里，元素可能是对象也可能只是字符串。
 * 这里统一解析成去重排序后的模型 id 列表，解析失败时返回空列表。
 */
internal object ModelIdParser {
    fun parse(body: String): List<String> {
        val text = body.trim()
        if (text.isEmpty()) return emptyList()
        val values = mutableListOf<String>()

        fun collect(array: JSONArray?) {
            if (array == null) return
            for (index in 0 until array.length()) {
                val item = array.opt(index)
                val id = when (item) {
                    is JSONObject -> listOf("id", "name", "model").firstNotNullOfOrNull { key ->
                        item.optString(key).trim().takeIf { it.isNotEmpty() }
                    }
                    is String -> item.trim().takeIf { it.isNotEmpty() }
                    else -> null
                }
                if (id != null) values += id
            }
        }

        try {
            if (text.startsWith("[")) {
                collect(JSONArray(text))
            } else {
                val json = JSONObject(text)
                collect(json.optJSONArray("data"))
                if (values.isEmpty()) collect(json.optJSONArray("models"))
            }
        } catch (_: Exception) {
            return emptyList()
        }
        return values.distinct().sorted()
    }
}