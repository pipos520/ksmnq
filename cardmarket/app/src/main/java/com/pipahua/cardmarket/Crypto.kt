package com.pipahua.cardmarket

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.math.BigInteger

/**
 * Canonical JSON 序列化 + HMAC-SHA256
 *
 * 必须与服务器端 crypto.ts 逐字节一致：
 * - 递归按 key 字典序排序
 * - 无空白
 * - 非 ASCII 保持原文，禁止 \uXXXX 转义
 */
object Crypto {

    fun canonicalJson(v: Any?): String {
        return when {
            v == null -> "null"
            v is Boolean -> if (v) "true" else "false"
            v is Number -> {
                val d = v.toDouble()
                if (d == d.toLong().toDouble()) d.toLong().toString() else d.toString()
            }
            v is String -> jsonString(v)
            v is List<*> -> "[" + v.joinToString(",") { canonicalJson(it) } + "]"
            v is Map<*, *> -> {
                val keys = v.keys.filter { v[it] != null }.map { it.toString() }.sorted()
                "{" + keys.joinToString(",") { k -> jsonString(k) + ":" + canonicalJson(v[k]) } + "}"
            }
            else -> "null"
        }
    }

    private fun jsonString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            val code = c.code
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c == '\n' -> sb.append("\\n")
                c == '\r' -> sb.append("\\r")
                c == '\t' -> sb.append("\\t")
                c == '\b' -> sb.append("\\b")
                c == '\u000C' -> sb.append("\\f")
                code < 0x20 -> sb.append("\\u%04x".format(code))
                else -> sb.append(c)  // UTF-8 原文，不转义
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    fun hmacSha256Base64(secretHex: String, data: String): String {
        val key = hexToBytes(secretHex)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val sig = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return android.util.Base64.encodeToString(sig, android.util.Base64.NO_WRAP)
    }

    fun sign(obj: Map<String, Any?>, secretHex: String): String {
        val copy = obj.toMutableMap()
        copy.remove("mac")
        val canonical = canonicalJson(copy)
        return hmacSha256Base64(secretHex, canonical)
    }

    fun verifyMac(obj: Map<String, Any?>, secretHex: String): Boolean {
        val expectMac = obj["mac"] as? String ?: return false
        val computed = sign(obj, secretHex)
        return computed == expectMac
    }

    private fun hexToBytes(hex: String): ByteArray {
        val len = hex.length / 2
        val out = ByteArray(len)
        for (i in 0 until len) {
            out[i] = hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
        return out
    }

    fun randomHex(bytes: Int = 16): String {
        val random = java.security.SecureRandom()
        val buf = ByteArray(bytes)
        random.nextBytes(buf)
        return String.format("%0${bytes * 2}x", BigInteger(1, buf))
    }

    fun uuid(): String {
        return java.util.UUID.randomUUID().toString()
    }

    fun now(): Long {
        return System.currentTimeMillis() / 1000
    }
}