package com.pipahua.cardmarket

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed class UiState {
    object Idle : UiState()
    object Loading : UiState()
    data class Success(val message: String) : UiState()
    data class Error(val message: String) : UiState()
}

class TradeViewModel(private val app: CardMarketApp) : ViewModel() {
    private val _state = MutableStateFlow<UiState>(UiState.Idle)
    val state: StateFlow<UiState> = _state

    private val _marketItems = MutableStateFlow<List<MarketItem>>(emptyList())
    val marketItems: StateFlow<List<MarketItem>> = _marketItems

    private val _receipts = MutableStateFlow<List<Receipt>>(emptyList())
    val receipts: StateFlow<List<Receipt>> = _receipts

    private val _loggedIn = MutableStateFlow(app.isUserLoggedIn())
    val loggedIn: StateFlow<Boolean> = _loggedIn

    private val _myCards = MutableStateFlow<List<CardInfo>>(emptyList())
    val myCards: StateFlow<List<CardInfo>> = _myCards

    fun userRegister(username: String, password: String, nickname: String) {
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.authRegister(username, password, nickname)
                }
                if (result.success) {
                    val json = org.json.JSONObject(result.body)
                    val token = json.getString("token")
                    val user = json.getJSONObject("user")
                    val nick = user.getString("nickname")
                    app.saveUserAuth(token, username, nick)
                    _loggedIn.value = true
                    _state.value = UiState.Success("注册成功: $username")
                } else {
                    _state.value = UiState.Error("注册失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun userLogin(username: String, password: String) {
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.authLogin(username, password)
                }
                if (result.success) {
                    val json = org.json.JSONObject(result.body)
                    val token = json.getString("token")
                    val user = json.getJSONObject("user")
                    val nick = user.getString("nickname")
                    app.saveUserAuth(token, username, nick)
                    _loggedIn.value = true
                    _state.value = UiState.Success("登录成功: $username")
                } else {
                    _state.value = UiState.Error("登录失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun logout() {
        app.clearUserAuth()
        _loggedIn.value = false
        _state.value = UiState.Success("已登出")
    }

    fun registerDevice() {
        val token = app.jwtToken ?: return
        val deviceId = Crypto.randomHex(16)
        val secret = Crypto.randomHex(16)
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.register(token, deviceId, secret, emptyList())
                }
                if (result.success) {
                    app.saveCredentials(deviceId, secret)
                    _state.value = UiState.Success("设备注册成功: $deviceId")
                    refreshMarket()
                    refreshCards()
                } else {
                    _state.value = UiState.Error("设备注册失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun offer(giveUuid: String, giveDef: String, wantDef: String) {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        val secret = app.deviceSecret ?: return
        val seq = app.nextSeq()
        val packId = Crypto.uuid()
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.offer(token, deviceId, secret, seq, packId,
                        listOf(CardInfo(giveUuid, giveDef)), wantDef)
                }
                if (result.success) {
                    _state.value = UiState.Success("挂单成功: $packId")
                    refreshMarket()
                } else {
                    _state.value = UiState.Error("挂单失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun cancel(packId: String) {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        val secret = app.deviceSecret ?: return
        val seq = app.nextSeq()
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.cancel(token, deviceId, secret, seq, Crypto.uuid(), packId)
                }
                if (result.success) {
                    _state.value = UiState.Success("撤单成功: $packId")
                    refreshMarket()
                } else {
                    _state.value = UiState.Error("撤单失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun refreshMarket() {
        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.market(1)
                }
                if (result.success) {
                    _marketItems.value = result.items
                } else {
                    _state.value = UiState.Error("加载市场失败: ${result.error}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun accept(packId: String, giveUuid: String) {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        val secret = app.deviceSecret ?: return
        viewModelScope.launch {
            _state.value = UiState.Loading
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.accept(token, deviceId, secret, packId, giveUuid)
                }
                if (result.success) {
                    _state.value = UiState.Success("交易成功!")
                    refreshMarket()
                    fetchReceipts()
                } else {
                    _state.value = UiState.Error("交易失败: ${result.error ?: result.body}")
                }
            } catch (e: Exception) {
                _state.value = UiState.Error("网络错误: ${e.message}")
            }
        }
    }

    fun fetchReceipts() {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    app.api.fetchReceipts(token, deviceId)
                }
                _receipts.value = result
            } catch (e: Exception) { /* silent */ }
        }
    }

    fun ackReceipt(receiptId: String) {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    app.api.ackReceipt(token, deviceId, receiptId)
                }
                fetchReceipts()
            } catch (e: Exception) { /* silent */ }
        }
    }

    fun refreshCards() {
        val token = app.jwtToken ?: return
        val deviceId = app.deviceId ?: return
        viewModelScope.launch {
            try {
                val cards = withContext(Dispatchers.IO) {
                    app.api.myCards(token, deviceId)
                }
                _myCards.value = cards
            } catch (e: Exception) { /* silent */ }
        }
    }
}
