package com.jinhoofkepco.mathland.securecredentials

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.godotengine.godot.Godot
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SecureCredentialsInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val cipher = AndroidKeystoreCipher(KEY_ALIAS)
    private val tokenStore = RefreshTokenStore(preferences, cipher)
    private lateinit var plugin: SecureCredentialsPlugin

    @Before
    fun reset() {
        preferences.edit().clear().commit()
        cipher.deleteKey()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            plugin = SecureCredentialsPlugin(Godot.getInstance(context), tokenStore)
        }
    }

    @After
    fun cleanUp() {
        preferences.edit().clear().commit()
        cipher.deleteKey()
    }

    @Test
    fun pluginRoundTripNeverPersistsPlaintextAndClears() {
        val token = "device-refresh-token"

        assertTrue(plugin.saveRefreshToken(token))
        assertEquals(token, plugin.loadRefreshToken())
        assertTrue(plugin.hasRefreshToken())
        assertFalse(preferences.all.values.any { it.toString().contains(token) })
        assertFalse(preferencesFile().readText().contains(token))

        assertTrue(plugin.clearRefreshToken())
        assertFalse(plugin.hasRefreshToken())
        assertEquals("", plugin.loadRefreshToken())
    }

    @Test
    fun pluginClearsCorruptedCiphertext() {
        assertTrue(plugin.saveRefreshToken("device-refresh-token"))
        assertTrue(
            preferences.edit()
                .putString(RefreshTokenStore.CIPHERTEXT_KEY, "broken")
                .commit(),
        )

        assertEquals("", plugin.loadRefreshToken())
        assertFalse(plugin.hasRefreshToken())
        assertTrue(preferences.all.isEmpty())
    }

    private fun preferencesFile(): File =
        File(context.applicationInfo.dataDir, "shared_prefs/$PREFERENCES_NAME.xml")

    private companion object {
        const val PREFERENCES_NAME = "mathland_secure_credentials_instrumentation"
        const val KEY_ALIAS = "mathland.supabase.refresh.instrumentation"
    }
}
