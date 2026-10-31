package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.FileOutputStream

object RuntimeAssetInstaller {
    private const val VERSION = "node26-bundle-v42"

    fun install(context: Context): File {
        val target = File(context.filesDir, "runtime")
        val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
        val ready = prefs.getString("assetVersion", null) == VERSION &&
            File(target, "bin/node").isFile && File(target, "runtime-entry.mjs").isFile
        if (ready) {
            refreshEntry(context, target)
            refreshProfile(context, target)
            return target
        }
        copyTree(context, "runtime", target)
        refreshEntry(context, target)
        refreshProfile(context, target)
        File(target, "bin/node").setExecutable(true, false)
        prefs.edit().putString("assetVersion", VERSION).apply()
        return target
    }

    /** The entry script is a handful of bytes and carries the startup handshake, so always refresh it. */
    private fun refreshEntry(context: Context, target: File) {
        try {
            context.assets.open("runtime/runtime-entry.mjs").use { input ->
                FileOutputStream(File(target, "runtime-entry.mjs")).use { output -> input.copyTo(output, 8 * 1024) }
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Android keeps dot-directories out of the packaged asset listing, so the DSH profile that
     * `--profile qqbot` resolves under `$DSH_HOME/profiles` is mirrored here on every install.
     */
    private fun refreshProfile(context: Context, target: File) {
        val source = if (hasAssets(context, "runtime/dsh-home")) "runtime/dsh-home" else "runtime/assets-dsh-home"
        try {
            copyTree(context, source, File(target, "dsh-home"))
        } catch (_: Exception) {
        }
    }

    private fun hasAssets(context: Context, assetPath: String): Boolean =
        !context.assets.list(assetPath).isNullOrEmpty()

    private fun copyTree(context: Context, assetPath: String, target: File) {
        val children = context.assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            copyFile(context, assetPath, target)
            return
        }
        if (!target.exists()) target.mkdirs()
        children.forEach { child -> copyTree(context, "$assetPath/$child", File(target, child)) }
    }

    private fun copyFile(context: Context, assetPath: String, target: File) {
        if (target.exists() && target.length() > 0) return
        target.parentFile?.mkdirs()
        context.assets.open(assetPath).use { input -> FileOutputStream(target).use { output -> input.copyTo(output, 64 * 1024) } }
    }
}
