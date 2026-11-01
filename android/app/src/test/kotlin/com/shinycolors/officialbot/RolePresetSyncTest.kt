package com.shinycolors.officialbot

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RolePresetSyncTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private fun directory(): File = File(temporary.root, "runtime/presets")

    @Test
    fun writesTheCardThatHasNoPresetFile() {
        val repaired = RolePresetSync.sync(directory(), listOf(RolePresetCard("custom.role", "测试角色", "# 角色卡")))

        assertEquals(listOf("custom.role"), repaired)
        assertEquals("# 角色卡", File(directory(), "preset.custom.role.md").readText())
        val metadata = JSONObject(File(directory(), "preset.custom.role.json").readText())
        assertEquals("custom.role", metadata.getString("id"))
        assertEquals("测试角色", metadata.getString("displayName"))
        assertEquals(false, metadata.getBoolean("builtin"))
    }

    @Test
    fun createsThePresetsDirectoryOnAFreshInstall() {
        assertTrue(directory().exists().not())

        RolePresetSync.sync(directory(), listOf(RolePresetCard("custom.role", "测试角色", "# 角色卡")))

        assertTrue(directory().isDirectory)
    }

    @Test
    fun keepsAPromptTheUserAlreadyEdited() {
        directory().mkdirs()
        File(directory(), "preset.custom.role.md").writeText("# 手改过的提示词")

        val repaired = RolePresetSync.sync(directory(), listOf(RolePresetCard("custom.role", "测试角色", "# 设置里的提示词")))

        assertEquals(emptyList<String>(), repaired)
        assertEquals("# 手改过的提示词", File(directory(), "preset.custom.role.md").readText())
    }

    @Test
    fun ignoresCardsWithoutPromptAndIdsTheRuntimeCannotResolve() {
        val repaired = RolePresetSync.sync(
            directory(),
            listOf(
                RolePresetCard("custom.empty", "空提示词", "  "),
                RolePresetCard("persona", "不合法 ID", "# 角色卡"),
                RolePresetCard("custom.role", "测试角色", "# 角色卡"),
            ),
        )

        assertEquals(listOf("custom.role"), repaired)
        assertEquals(listOf("preset.custom.role.json", "preset.custom.role.md"), directory().list()!!.sorted())
    }
}