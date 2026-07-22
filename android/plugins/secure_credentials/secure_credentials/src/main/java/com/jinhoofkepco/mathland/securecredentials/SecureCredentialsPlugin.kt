package com.jinhoofkepco.mathland.securecredentials

import android.content.Context
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class SecureCredentialsPlugin(godot: Godot) : GodotPlugin(godot) {
    private var storeOverride: RefreshTokenStore? = null

    internal constructor(godot: Godot, store: RefreshTokenStore) : this(godot) {
        storeOverride = store
    }

    private val store: RefreshTokenStore by lazy {
        storeOverride ?: RefreshTokenStore(
            context.applicationContext.getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            ),
            AndroidKeystoreCipher(),
        )
    }

    override fun getPluginName(): String = PLUGIN_NAME

    @UsedByGodot
    fun saveRefreshToken(token: String): Boolean {
        if (token.isEmpty()) return false
        return failClosed(false) {
            store.save(token)
            true
        }
    }

    @UsedByGodot
    fun loadRefreshToken(): String = failClosed("") { store.load().orEmpty() }

    @UsedByGodot
    fun clearRefreshToken(): Boolean = failClosed(false) {
        store.clear()
        true
    }

    @UsedByGodot
    fun hasRefreshToken(): Boolean = failClosed(false) { store.contains() }

    private inline fun <T> failClosed(defaultValue: T, operation: () -> T): T =
        try {
            operation()
        } catch (_: Exception) {
            defaultValue
        }

    private companion object {
        const val PLUGIN_NAME = "MathLandSecureCredentials"
        const val PREFERENCES_NAME = "mathland_secure_credentials"
    }
}
