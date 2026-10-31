package com.shinycolors.officialbot

import android.content.Context
import java.io.File
import java.io.FileOutputStream

object RuntimeAssetInstaller {
    private const val VERSION = "node26-bundle-v43"

    fun install(context: Context): File {
        val target = File(context.filesDir, "runtime")
        val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
        val ready = prefs.getString("assetVersion", null) == VERSION &&
            File(target, "bin/node").isFile && File(target, "runtime-entry.mjs").isFile
        if (ready) {
            refreshEntry(context, target)
            refreshProfile(context, target)
            refreshPiAiManifest(context, target)
            refreshOpenAiParser(context, target)
            refreshTurnErrorNormalizer(context, target)
            refreshAndroidRuntimeOverrides(context, target)
            return target
        }
        copyTree(context, "runtime", target)
        refreshEntry(context, target)
        refreshProfile(context, target)
        refreshPiAiManifest(context, target)
        refreshOpenAiParser(context, target)
        refreshTurnErrorNormalizer(context, target)
        refreshAndroidRuntimeOverrides(context, target)
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
            val installed = File(target, "dsh-home")
            copyTree(context, source, installed)
            // Profile policy can change independently of the large Runtime bundle. Always
            // refresh this small patch so an installed app picks up Android-specific settings.
            val patchAsset = "runtime/qqbot-android.patch.yml"
            context.assets.open(patchAsset).use { input ->
                val output = File(installed, "profiles/qqbot/cordis.patch.yml")
                output.parentFile?.mkdirs()
                FileOutputStream(output).use { file -> input.copyTo(file, 8 * 1024) }
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Android asset packaging does not reliably preserve dot-prefixed files. pi-ai imports
     * this catalog as data/.manifest.json, so ship it under a visible asset name and restore
     * the exact runtime filename after extraction. This runs even on a cached bundle so a
     * previously installed v42 runtime is repaired without clearing app data.
     */
    private fun refreshPiAiManifest(context: Context, target: File) {
        val source = "runtime/node_modules/@earendil-works/pi-ai/dist/providers/data/manifest.json"
        val output = File(target, "node_modules/@earendil-works/pi-ai/dist/providers/data/.manifest.json")
        try {
            context.assets.open(source).use { input ->
                output.parentFile?.mkdirs()
                FileOutputStream(output).use { file -> input.copyTo(file, 8 * 1024) }
            }
        } catch (_: Exception) {
            // The runtime will report a precise missing-manifest error if the bundle is incomplete.
        }
    }

    /** openai's ChatCompletionStream imports this non-package entry directly at runtime. */
    private fun refreshOpenAiParser(context: Context, target: File) {
        val source = "runtime/openai-partial-json-parser/parser.mjs"
        val output = File(target, "node_modules/openai/_vendor/partial-json-parser/parser.mjs")
        try {
            context.assets.open(source).use { input ->
                output.parentFile?.mkdirs()
                FileOutputStream(output).use { file -> input.copyTo(file, 16 * 1024) }
            }
        } catch (_: Exception) {
            // An incomplete bundle will report the exact import failure in the Runtime log.
        }
    }

    /** Error normalization is a small Android override and must refresh cached bundles. */
    private fun refreshTurnErrorNormalizer(context: Context, target: File) {
        val source = "runtime/runtime/turn-error-normalizer.mjs"
        val output = File(target, "runtime/turn-error-normalizer.mjs")
        try {
            context.assets.open(source).use { input ->
                output.parentFile?.mkdirs()
                FileOutputStream(output).use { file -> input.copyTo(file, 16 * 1024) }
            }
        } catch (_: Exception) {
            // Keep the previous copy so a transient asset read does not break Runtime startup.
        }
    }

    private fun refreshAndroidRuntimeOverrides(context: Context, target: File) {
        val files = listOf(
            "runtime/node_modules/@tencent-connect/dsh-qqbot/dist/gateway/middleware-setup.js",
            "runtime/node_modules/@tencent-connect/dsh-qqbot/dist/transport/outbound.js",
            "runtime/node_modules/@tencent-connect/dsh-qqbot/dist/commands/session.js",
            "runtime/node_modules/@tencent-connect/dsh-qqbot/dist/commands/preset.js",
            "runtime/node_modules/@tencent-connect/dsh-qqbot/dist/session/session-manager.js",
            "runtime/node_modules/@tencent-connect/qqbot-nodejs/dist/middleware/typing-indicator.js",
        )
        files.forEach { assetPath ->
            try {
                context.assets.open(assetPath).use { input ->
                    val output = File(target, assetPath.removePrefix("runtime/"))
                    output.parentFile?.mkdirs()
                    FileOutputStream(output).use { file -> input.copyTo(file, 32 * 1024) }
                }
            } catch (_: Exception) {
                // Keep the bundled implementation if a future Runtime omits an override file.
            }
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
