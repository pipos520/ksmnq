package com.pipahua.cardmarket

import okhttp3.OkHttpClient
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * 服务器 API 客户端 — VPS 版本 (含 JWT 认证)
 *
 * 认证端点 (无需 token):
 *   POST /v1/auth/register
 *   POST /v1/auth/login
 *
 * 需要 Bearer token 的端点:
 *   POST /v1/devices/register
 *   POST /v1/packs          (offer/cancel/enroll)
 *   GET  /v1/market         (公开，但返回完整信息)
 *   POST /v1/packs/{pack_id}/accept
 *   GET  /v1/receipts
 *   POST /v1/receipts/{receipt_id}/ack
 *   GET  /v1/sync
 *   GET  /v1/cards?device_id=xxx
 */
class ApiClient(private val baseUrl: String) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    // ---- 用户认证 (无需 token) ----

    fun authRegister(username: String, password: String, nickname: String): ApiResult {
        val body = mapOf("username" to username, "password" to password, "nickname" to nickname)
        return postNoAuth("/v1/auth/register", body)
    }

    fun authLogin(username: String, password: String): ApiResult {
        val body = mapOf("username" to username, "password" to password)
        return postNoAuth("/v1/auth/login", body)
    }

    // ---- 1. 注册设备 (需要 token) ----
    fun register(token: String, deviceId: String, secret: String, initialCards: List<CardInfo>): ApiResult {
        val body = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "secret" to secret,
            "initial_cards" to initialCards.map { mapOf("uuid" to it.uuid, "def" to it.def) },
            "mac" to ""
        )
        body["mac"] = Crypto.sign(body, secret)
        return postAuth(token, "/v1/devices/register", body)
    }

    // ---- 2. 挂单 (offer) ----
    fun offer(token: String, deviceId: String, secret: String, seq: Long,
              packId: String, give: List<CardInfo>, wantDef: String): ApiResult {
        val body = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "seq" to seq,
            "type" to "offer",
            "pack_id" to packId,
            "give" to give.map { mapOf("uuid" to it.uuid, "def" to it.def) },
            "want" to mapOf("def" to wantDef),
            "mac" to ""
        )
        body["mac"] = Crypto.sign(body, secret)
        return postAuth(token, "/v1/packs", body)
    }

    // ---- 2b. 撤单 (cancel) ----
    fun cancel(token: String, deviceId: String, secret: String, seq: Long,
               packId: String, cancelPackId: String): ApiResult {
        val body = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "seq" to seq,
            "type" to "cancel",
            "pack_id" to packId,
            "cancel_pack_id" to cancelPackId,
            "mac" to ""
        )
        body["mac"] = Crypto.sign(body, secret)
        return postAuth(token, "/v1/packs", body)
    }

    // ---- 2c. 注册新卡 (enroll) ----
    fun enroll(token: String, deviceId: String, secret: String, seq: Long,
               packId: String, cards: List<CardInfo>): ApiResult {
        val body = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "seq" to seq,
            "type" to "enroll",
            "pack_id" to packId,
            "initial_cards" to cards.map { mapOf("uuid" to it.uuid, "def" to it.def) },
            "mac" to ""
        )
        body["mac"] = Crypto.sign(body, secret)
        return postAuth(token, "/v1/packs", body)
    }

    // ---- 3. 市场列表 (公开) ----
    fun market(page: Int = 1, def: String? = null, wantDef: String? = null): MarketResult {
        val url = buildString {
            append(baseUrl).append("/v1/market?page=").append(page)
            if (def != null) append("&def=").append(def)
            if (wantDef != null) append("&want_def=").append(wantDef)
        }
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: ""
            if (!resp.isSuccessful) return MarketResult(false, emptyList(), "HTTP ${resp.code}: $body")
            val json = JSONObject(body)
            val items = json.getJSONArray("items")
            val list = mutableListOf<MarketItem>()
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val giveArr = item.getJSONArray("give")
                val giveCards = mutableListOf<CardInfo>()
                for (j in 0 until giveArr.length()) {
                    val c = giveArr.getJSONObject(j)
                    giveCards.add(CardInfo(c.getString("uuid"), c.getString("def")))
                }
                list.add(MarketItem(
                    packId = item.getString("pack_id"),
                    nickname = item.optString("nickname", ""),
                    give = giveCards,
                    wantDef = item.getString("want_def"),
                    createdAt = item.optLong("created_at")
                ))
            }
            return MarketResult(true, list, null)
        }
    }

    // ---- 4. 接受交易 ----
    fun accept(token: String, deviceId: String, secret: String, packId: String, giveUuid: String): ApiResult {
        val body = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "give_uuid" to giveUuid,
            "mac" to ""
        )
        body["mac"] = Crypto.sign(body, secret)
        return postAuth(token, "/v1/packs/$packId/accept", body)
    }

    // ---- 5. 拉取未确认回执 ----
    fun fetchReceipts(token: String, deviceId: String): List<Receipt> {
        val url = "$baseUrl/v1/receipts?device_id=$deviceId"
        val req = Request.Builder()
            .url(url)
            .get()
            .header("Authorization", "Bearer $token")
            .build()
        client.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: return emptyList()
            if (!resp.isSuccessful) return emptyList()
            val json = JSONObject(body)
            val arr = json.getJSONArray("receipts")
            val list = mutableListOf<Receipt>()
            for (i in 0 until arr.length()) {
                val r = arr.getJSONObject(i)
                list.add(parseReceipt(r))
            }
            return list
        }
    }

    // ---- 6. 确认回执 ----
    fun ackReceipt(token: String, deviceId: String, receiptId: String): ApiResult {
        val body = mapOf("device_id" to deviceId)
        return postAuth(token, "/v1/receipts/$receiptId/ack", body)
    }

    // ---- 7. 对账同步 ----
    fun sync(token: String, deviceId: String, secret: String): SyncResult {
        val canon = Crypto.canonicalJson(mapOf("device_id" to deviceId))
        val mac = Crypto.hmacSha256Base64(secret, canon)
        val url = "$baseUrl/v1/sync?device_id=$deviceId&mac=$mac"
        val req = Request.Builder()
            .url(url)
            .get()
            .header("Authorization", "Bearer $token")
            .build()
        client.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: ""
            if (!resp.isSuccessful) return SyncResult(false, 0, emptyList(), emptyList(), "HTTP ${resp.code}")
            val json = JSONObject(body)
            val packs = mutableListOf<PackStatus>()
            val packArr = json.optJSONArray("packs") ?: JSONArray()
            for (i in 0 until packArr.length()) {
                val p = packArr.getJSONObject(i)
                packs.add(PackStatus(p.getString("pack_id"), p.getString("state")))
            }
            val unacked = mutableListOf<Receipt>()
            val unackedArr = json.optJSONArray("unacked_receipts") ?: JSONArray()
            for (i in 0 until unackedArr.length()) {
                unacked.add(parseReceipt(unackedArr.getJSONObject(i)))
            }
            return SyncResult(true, json.optLong("max_seq"), packs, unacked, null)
        }
    }

    // ---- 8. 我的卡牌列表 ----
    fun myCards(token: String, deviceId: String): List<CardInfo> {
        val url = "$baseUrl/v1/cards?device_id=$deviceId"
        val req = Request.Builder()
            .url(url)
            .get()
            .header("Authorization", "Bearer $token")
            .build()
        client.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: return emptyList()
            if (!resp.isSuccessful) return emptyList()
            val json = JSONObject(body)
            val cards = json.getJSONArray("cards")
            val list = mutableListOf<CardInfo>()
            for (i in 0 until cards.length()) {
                val c = cards.getJSONObject(i)
                list.add(CardInfo(c.getString("uuid"), c.getString("def")))
            }
            return list
        }
    }

    // ---- 内部方法 ----

    private fun postAuth(token: String, path: String, body: Map<String, Any?>): ApiResult {
        val jsonBody = mapToJsonString(body)
        val req = Request.Builder()
            .url("$baseUrl$path")
            .post(jsonBody.toRequestBody(jsonMedia))
            .header("Authorization", "Bearer $token")
            .build()
        client.newCall(req).execute().use { resp ->
            val respBody = resp.body?.string() ?: ""
            return if (resp.isSuccessful) {
                ApiResult(true, resp.code, respBody, null)
            } else {
                ApiResult(false, resp.code, respBody, respBody)
            }
        }
    }

    private fun postNoAuth(path: String, body: Map<String, Any?>): ApiResult {
        val jsonBody = mapToJsonString(body)
        val req = Request.Builder()
            .url("$baseUrl$path")
            .post(jsonBody.toRequestBody(jsonMedia))
            .build()
        client.newCall(req).execute().use { resp ->
            val respBody = resp.body?.string() ?: ""
            return if (resp.isSuccessful) {
                ApiResult(true, resp.code, respBody, null)
            } else {
                ApiResult(false, resp.code, respBody, respBody)
            }
        }
    }

    private fun mapToJsonString(map: Map<String, Any?>): String {
        val json = JSONObject()
        for ((k, v) in map) {
            when (v) {
                null -> json.put(k, JSONObject.NULL)
                is String -> json.put(k, v)
                is Number -> json.put(k, v)
                is Boolean -> json.put(k, v)
                is List<*> -> {
                    val arr = JSONArray()
                    for (item in v) {
                        if (item is Map<*, *>) {
                            val subMap = mutableMapOf<String, Any?>()
                            for (e in item.entries) {
                                if (e.key != null) subMap[e.key.toString()] = e.value
                            }
                            arr.put(JSONObject(mapToJsonString(subMap)))
                        } else {
                            arr.put(item?.toString() ?: JSONObject.NULL)
                        }
                    }
                    json.put(k, arr)
                }
                is Map<*, *> -> {
                    val subMap = mutableMapOf<String, Any?>()
                    for (e in v.entries) {
                        if (e.key != null) subMap[e.key.toString()] = e.value
                    }
                    json.put(k, JSONObject(mapToJsonString(subMap)))
                }
                else -> json.put(k, v.toString())
            }
        }
        return json.toString()
    }

    private fun parseReceipt(r: JSONObject): Receipt {
        val receiveArr = r.optJSONArray("receive") ?: JSONArray()
        val giveArr = r.optJSONArray("give_away") ?: JSONArray()
        val receive = mutableListOf<CardInfo>()
        val giveAway = mutableListOf<CardInfo>()
        for (i in 0 until receiveArr.length()) {
            val c = receiveArr.getJSONObject(i)
            receive.add(CardInfo(c.getString("uuid"), c.getString("def")))
        }
        for (i in 0 until giveArr.length()) {
            val c = giveArr.getJSONObject(i)
            giveAway.add(CardInfo(c.getString("uuid"), c.getString("def")))
        }
        return Receipt(
            receiptId = r.getString("receipt_id"),
            tradeId = r.optString("trade_id", ""),
            type = r.getString("type"),
            deviceId = r.getString("device_id"),
            packId = r.optString("pack_id", ""),
            receive = receive,
            giveAway = giveAway,
            serverTime = r.optLong("server_time"),
            mac = r.getString("mac")
        )
    }
}

// ---- 数据类 ----

data class CardInfo(val uuid: String, val def: String)

data class ApiResult(val success: Boolean, val code: Int, val body: String, val error: String?)

data class MarketItem(
    val packId: String,
    val nickname: String,
    val give: List<CardInfo>,
    val wantDef: String,
    val createdAt: Long
)

data class MarketResult(val success: Boolean, val items: List<MarketItem>, val error: String?)

data class Receipt(
    val receiptId: String,
    val tradeId: String,
    val type: String,
    val deviceId: String,
    val packId: String,
    val receive: List<CardInfo>,
    val giveAway: List<CardInfo>,
    val serverTime: Long,
    val mac: String
)

data class PackStatus(val packId: String, val state: String)

data class SyncResult(
    val success: Boolean,
    val maxSeq: Long,
    val packs: List<PackStatus>,
    val unackedReceipts: List<Receipt>,
    val error: String?
)