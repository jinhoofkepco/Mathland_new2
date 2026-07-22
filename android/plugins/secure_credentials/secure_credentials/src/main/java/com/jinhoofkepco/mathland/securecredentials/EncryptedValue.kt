package com.jinhoofkepco.mathland.securecredentials

data class EncryptedValue(
    val iv: ByteArray,
    val ciphertext: ByteArray,
)
