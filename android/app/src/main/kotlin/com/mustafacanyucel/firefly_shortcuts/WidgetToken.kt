package com.mustafacanyucel.firefly_shortcuts

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// The widget's copy of the access token, encrypted with a non-exportable
// Android Keystore key. Keystore keys never leave the device, so a copy of
// the prefs file is useless elsewhere; after a restore the token simply reads
// as missing and the widget asks the user to sign in.
object WidgetToken {
    private const val KEY_ENCRYPTED = "access_token_enc"
    // Plaintext copy written by 1.0.2 and earlier.
    private const val KEY_LEGACY = "access_token"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "widget_access_token"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_LENGTH = 12
    private const val TAG_BITS = 128

    fun isStored(prefs: SharedPreferences): Boolean =
        prefs.contains(KEY_ENCRYPTED) || prefs.contains(KEY_LEGACY)

    fun read(prefs: SharedPreferences): String? {
        prefs.getString(KEY_LEGACY, null)?.takeIf { it.isNotEmpty() }?.let { legacy ->
            // Encrypt in place so the widget keeps working after an update
            // until the app is next opened.
            prefs.edit().also { write(it, legacy) }.apply()
            return legacy
        }
        val stored = prefs.getString(KEY_ENCRYPTED, null) ?: return null
        return try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val key = keyStore().getKey(KEY_ALIAS, null) as SecretKey? ?: return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, bytes, 0, IV_LENGTH))
            String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    /** Stores [token], or removes it when null or empty. */
    fun write(editor: SharedPreferences.Editor, token: String?) {
        editor.remove(KEY_LEGACY)
        if (token.isNullOrEmpty()) {
            editor.remove(KEY_ENCRYPTED)
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        editor.putString(KEY_ENCRYPTED, Base64.encodeToString(encrypted, Base64.NO_WRAP))
    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun key(): SecretKey {
        (keyStore().getKey(KEY_ALIAS, null) as SecretKey?)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build()
            )
        }.generateKey()
    }
}
