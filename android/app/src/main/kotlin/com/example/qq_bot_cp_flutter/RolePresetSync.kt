package com.shinycolors.officialbot

import org.json.JSONObject
import java.io.File

/** 角色卡在 Runtime 里是一份 presets 文件；只存在设置里时，模型拿不到人格。 */
internal data class RolePresetCard(val id: String, val displayName: String, val prompt: String)

internal object RolePresetSync {
    private val customId = Regex("custom\\.[a-z0-9][a-z0-9._-]{0,48}")

    /**
     * 把缺失的角色卡补写成 preset.<id>.md / preset.<id>.json。
     *
     * 重装或恢复备份后，设置里的角色卡还在而 files/runtime/presets 是空的，
     * 于是 LLM_PRESET 指向的角色卡在 Runtime 里查不到，回复就会退回默认助手语气。
     * 已存在的文件不会被覆盖，用户手改过的内容保持原样。
     */
    fun sync(directory: File, cards: Iterable<RolePresetCard>): List<String> {
        if (!directory.isDirectory && !directory.mkdirs()) return emptyList()
        val repaired = mutableListOf<String>()
        for (card in cards) {
            if (!customId.matches(card.id) || card.prompt.isBlank()) continue
            val promptFile = File(directory, "preset.${card.id}.md")
            val metadataFile = File(directory, "preset.${card.id}.json")
            if (promptFile.isFile && promptFile.length() > 0L) continue
            promptFile.writeText(card.prompt, Charsets.UTF_8)
            val metadata = JSONObject()
                .put("id", card.id)
                .put("displayName", card.displayName.ifBlank { card.id })
                .put("builtin", false)
            metadataFile.writeText(metadata.toString(), Charsets.UTF_8)
            repaired += card.id
        }
        return repaired
    }
}