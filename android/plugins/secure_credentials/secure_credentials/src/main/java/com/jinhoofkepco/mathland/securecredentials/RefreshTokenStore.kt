package com.jinhoofkepco.mathland.securecredentials

import android.content.SharedPreferences
import android.util.Base64
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.security.GeneralSecurityException

class RefreshTokenStore(
    private val preferences: SharedPreferences,
    private val cipher: SecretCipher,
) {
    fun save(token: String) {
        val encrypted = cipher.encrypt(token.toByteArray(StandardCharsets.UTF_8))
        require(encrypted.iv.isNotEmpty()) { "Encrypted credential IV must not be empty" }
        require(encrypted.ciphertext.isNotEmpty()) { "Encrypted credential must not be empty" }

        val committed = preferences.edit()
            .putString(IV_KEY, encode(encrypted.iv))
            .putString(CIPHERTEXT_KEY, encode(encrypted.ciphertext))
            .commit()
        if (!committed) {
            invalidateStoredCredential()
            throw IOException("Unable to persist encrypted credential")
        }
    }

    fun load(): String? {
        val encodedIv = preferences.getString(IV_KEY, null)
        val encodedCiphertext = preferences.getString(CIPHERTEXT_KEY, null)
        if (encodedIv == null && encodedCiphertext == null) return null
        if (encodedIv == null || encodedCiphertext == null) {
            invalidateStoredCredential()
            return null
        }

        return try {
            val decrypted = cipher.decrypt(
                EncryptedValue(
                    iv = decodeCanonical(encodedIv),
                    ciphertext = decodeCanonical(encodedCiphertext),
                ),
            )
            String(decrypted, StandardCharsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            invalidateStoredCredential()
            null
        } catch (_: GeneralSecurityException) {
            invalidateStoredCredential()
            null
        }
    }

    fun clear() {
        val committed = removeStoredMaterial()
        cipher.deleteKey()
        if (!committed) throw IOException("Unable to clear encrypted credential")
    }

    fun contains(): Boolean =
        preferences.contains(IV_KEY) && preferences.contains(CIPHERTEXT_KEY)

    private fun decodeCanonical(encoded: String): ByteArray {
        if (encoded.isEmpty()) throw IllegalArgumentException("Empty encrypted credential material")
        val decoded = Base64.decode(encoded, Base64.NO_WRAP)
        if (decoded.isEmpty() || encode(decoded) != encoded) {
            throw IllegalArgumentException("Non-canonical encrypted credential material")
        }
        return decoded
    }

    private fun encode(value: ByteArray): String = Base64.encodeToString(value, Base64.NO_WRAP)

    private fun invalidateStoredCredential() {
        removeStoredMaterial()
        try {
            cipher.deleteKey()
        } catch (_: Exception) {
            // The persisted material is already unusable and removed; do not expose key errors or secrets.
        }
    }

    private fun removeStoredMaterial(): Boolean = preferences.edit()
        .remove(IV_KEY)
        .remove(CIPHERTEXT_KEY)
        .commit()

    companion object {
        const val IV_KEY = "refresh_iv_v1"
        const val CIPHERTEXT_KEY = "refresh_ciphertext_v1"
    }
}
