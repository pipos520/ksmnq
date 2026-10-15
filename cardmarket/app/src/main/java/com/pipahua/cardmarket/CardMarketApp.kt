package com.pipahua.cardmarket

import android.app.Application

/**
 * 全局 Application
 * 持有 ApiClient 单例、用户凭证和设备凭证
 */
class CardMarketApp : Application() {

    lateinit var api: ApiClient
        private set

    // 服务器地址 (VPS)
    private val serverUrl: String =
        "http://103.119.2.145:8000"

    // ---- 用户凭证 ----
    var jwtToken: String? = null
        private set
    var username: String? = null
        private set
    var nickname: String? = null
        private set

    // ---- 设备凭证 (持久化到 SharedPreferences) ----
    var deviceId: String? = null
        private set
    var deviceSecret: String? = null
        private set
    var seq: Long = 0
        private set

    override fun onCreate() {
        super.onCreate()
        api = ApiClient(serverUrl)
        loadCredentials()
    }

    fun loadCredentials() {
        val prefs = getSharedPreferences("cardmarket", MODE_PRIVATE)
        // 用户凭证
        jwtToken = prefs.getString("jwt_token", null)
        username = prefs.getString("username", null)
        nickname = prefs.getString("nickname", null)
        // 设备凭证
        deviceId = prefs.getString("device_id", null)
        deviceSecret = prefs.getString("device_secret", null)
        seq = prefs.getLong("seq", 0)
    }

    fun saveCredentials(deviceId: String, secret: String) {
        this.deviceId = deviceId
        this.deviceSecret = secret
        getSharedPreferences("cardmarket", MODE_PRIVATE).edit().apply {
            putString("device_id", deviceId)
            putString("device_secret", secret)
            putLong("seq", seq)
            apply()
        }
    }

    fun saveUserAuth(token: String, username: String, nickname: String) {
        this.jwtToken = token
        this.username = username
        this.nickname = nickname
        getSharedPreferences("cardmarket", MODE_PRIVATE).edit().apply {
            putString("jwt_token", token)
            putString("username", username)
            putString("nickname", nickname)
            apply()
        }
    }

    fun clearUserAuth() {
        this.jwtToken = null
        this.username = null
        this.nickname = null
        getSharedPreferences("cardmarket", MODE_PRIVATE).edit().apply {
            remove("jwt_token")
            remove("username")
            remove("nickname")
            apply()
        }
    }

    fun nextSeq(): Long {
        seq += 1
        getSharedPreferences("cardmarket", MODE_PRIVATE).edit().putLong("seq", seq).apply()
        return seq
    }

    fun isRegistered(): Boolean = deviceId != null && deviceSecret != null

    fun isUserLoggedIn(): Boolean = jwtToken != null
}