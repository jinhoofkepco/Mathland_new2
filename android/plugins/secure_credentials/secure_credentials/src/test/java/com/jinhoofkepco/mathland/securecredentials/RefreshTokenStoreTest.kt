package com.jinhoofkepco.mathland.securecredentials

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.security.GeneralSecurityException
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RefreshTokenStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val prefs = context.getSharedPreferences("credentials-test", Context.MODE_PRIVATE)
    private val cipher = FakeCipher()
    private val store = RefreshTokenStore(prefs, cipher)

    @Before
    fun reset() {
        prefs.edit().clear().commit()
        cipher.deleted = false
        cipher.rejectDecrypt = false
        cipher.rejectEncrypt = false
    }

    @Test
    fun roundTripNeverStoresPlaintext() {
        store.save("refresh-secret-123")

        assertEquals("refresh-secret-123", store.load())
        assertFalse(prefs.all.values.any { it.toString().contains("refresh-secret-123") })
        assertTrue(store.contains())
    }

    @Test
    fun corruptedCiphertextIsClearedAndReturnsMissing() {
        store.save("refresh-secret-123")
        prefs.edit().putString(RefreshTokenStore.CIPHERTEXT_KEY, "broken").commit()

        assertNull(store.load())
        assertFalse(store.contains())
        assertTrue(prefs.all.isEmpty())
        assertTrue(cipher.deleted)
    }

    @Test
    fun keyInvalidationIsClearedAndReturnsMissing() {
        store.save("refresh-secret-123")
        cipher.rejectDecrypt = true

        assertNull(store.load())
        assertTrue(prefs.all.isEmpty())
        assertTrue(cipher.deleted)
    }

    @Test
    fun partialMaterialIsNeverReportedAsPresent() {
        prefs.edit().putString(RefreshTokenStore.IV_KEY, "aXY=").commit()

        assertFalse(store.contains())
        assertNull(store.load())
        assertTrue(prefs.all.isEmpty())
    }

    @Test
    fun clearRemovesAllStoredMaterialAndKey() {
        store.save("refresh-secret-123")

        store.clear()

        assertNull(store.load())
        assertTrue(prefs.all.isEmpty())
        assertTrue(cipher.deleted)
    }

    @Test
    fun encryptionFailureDoesNotWritePartialMaterial() {
        cipher.rejectEncrypt = true

        assertThrows(GeneralSecurityException::class.java) { store.save("refresh-secret-123") }
        assertTrue(prefs.all.isEmpty())
    }

    private class FakeCipher : SecretCipher {
        var deleted = false
        var rejectDecrypt = false
        var rejectEncrypt = false

        override fun encrypt(plaintext: ByteArray): EncryptedValue {
            if (rejectEncrypt) throw GeneralSecurityException("test encryption failure")
            return EncryptedValue(
                iv = byteArrayOf(1, 2, 3, 4),
                ciphertext = plaintext.reversedArray(),
            )
        }

        override fun decrypt(value: EncryptedValue): ByteArray {
            if (rejectDecrypt || !value.iv.contentEquals(byteArrayOf(1, 2, 3, 4))) {
                throw GeneralSecurityException("test decryption failure")
            }
            val canonical = Base64.getEncoder().encodeToString(value.ciphertext)
            if (canonical.isEmpty()) throw GeneralSecurityException("test malformed value")
            return value.ciphertext.reversedArray()
        }

        override fun deleteKey() {
            deleted = true
        }
    }
}
