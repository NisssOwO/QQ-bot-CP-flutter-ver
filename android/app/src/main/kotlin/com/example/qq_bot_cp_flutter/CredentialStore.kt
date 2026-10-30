package com.example.qq_bot_cp_flutter

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class CredentialStore(context: Context) {
    private val context = context.applicationContext
    private val prefs = context.getSharedPreferences("encrypted-credentials", Context.MODE_PRIVATE)

    fun has(name: String) = prefs.contains("$name.value")

    fun save(name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        prefs.edit().putString("$name.iv", Base64.getEncoder().encodeToString(cipher.iv))
            .putString("$name.value", Base64.getEncoder().encodeToString(encrypted)).apply()
    }

    fun read(name: String): String {
        val iv = Base64.getDecoder().decode(prefs.getString("$name.iv", ""))
        val encrypted = Base64.getDecoder().decode(prefs.getString("$name.value", ""))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "qq-bot-cp-credentials-v1"
        if (store.containsAlias(alias)) return (store.getEntry(alias, null) as KeyStore.SecretKeyEntry).secretKey
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(128).build())
        return generator.generateKey()
    }
}
