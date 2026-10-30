package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.FileOutputStream

object RuntimeAssetInstaller {
    private const val VERSION = "node26-bundle-v40"

    fun install(context: Context): File {
        val target = File(context.filesDir, "runtime")
        val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
        copyTree(context, "runtime", target)
        File(target, "bin/node").setExecutable(true, false)
        prefs.edit().putString("assetVersion", VERSION).apply()
        return target
    }

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
