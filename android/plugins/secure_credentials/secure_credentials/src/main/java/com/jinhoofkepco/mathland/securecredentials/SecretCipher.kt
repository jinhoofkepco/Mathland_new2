package com.jinhoofkepco.mathland.securecredentials

interface SecretCipher {
    fun encrypt(plaintext: ByteArray): EncryptedValue

    fun decrypt(value: EncryptedValue): ByteArray

    fun deleteKey()
}
