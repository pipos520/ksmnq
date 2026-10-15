package com.pipahua.cardmarket

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AbstractSavedStateViewModelFactory
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.collectLatest

// ============================================================
//  MainActivity — 卡牌集市 Compose UI
// ============================================================

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = applicationContext as CardMarketApp

        setContent {
            CardMarketTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val vm: TradeViewModel = viewModel(factory = VMFactory(app))
                    CardMarketScreen(vm)
                }
            }
        }
    }
}

// ---- ViewModel Factory ----

@Suppress("UNCHECKED_CAST")
class VMFactory(private val app: CardMarketApp) : AbstractSavedStateViewModelFactory() {
    override fun <T : androidx.lifecycle.ViewModel> create(
        key: String, modelClass: Class<T>, handle: SavedStateHandle
    ): T {
        return TradeViewModel(app) as T
    }
}

// ---- 主题 ----

@Composable
fun CardMarketTheme(content: @Composable () -> Unit) {
    val darkColors = darkColorScheme(
        primary = Color(0xFFE8A547),       // 暖金
        onPrimary = Color(0xFF1A1A2E),
        secondary = Color(0xFF6FCF97),      // 薄荷绿
        onSecondary = Color(0xFF1A1A2E),
        background = Color(0xFF1A1A2E),      // 深蓝紫
        onBackground = Color(0xFFF0F0F5),
        surface = Color(0xFF252542),
        onSurface = Color(0xFFF0F0F5),
        surfaceVariant = Color(0xFF2D2D4A),
        onSurfaceVariant = Color(0xFFB0B0C8),
        error = Color(0xFFFF6B6B),
        onError = Color(0xFFFFFFFF)
    )
    MaterialTheme(colorScheme = darkColors, content = content)
}

// ---- 主界面 ----

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardMarketScreen(vm: TradeViewModel) {
    val loggedIn by vm.loggedIn.collectAsState()
    val state by vm.state.collectAsState()
    var tabIndex by remember { mutableStateOf(0) }
    val tabs = listOf("市场", "挂单", "回执")

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "卡牌集市",
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp
                    )
                },
                actions = {
                    IconButton(onClick = { vm.fetchReceipts() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "刷新回执")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.primary
                )
            )
        },
        bottomBar = {
            if (loggedIn) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                    tabs.forEachIndexed { i, label ->
                        NavigationBarItem(
                            selected = tabIndex == i,
                            onClick = {
                                tabIndex = i
                                if (i == 0) vm.refreshMarket()
                                if (i == 2) vm.fetchReceipts()
                            },
                            icon = {
                                Icon(
                                    when (i) {
                                        0 -> Icons.Default.Storefront
                                        1 -> Icons.Default.SwapHoriz
                                        else -> Icons.Default.Inbox
                                    },
                                    contentDescription = label
                                )
                            },
                            label = { Text(label, fontSize = 12.sp) }
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // 状态条
            StateBanner(state)

            if (!loggedIn) {
                LoginScreen(vm)
            } else {
                if (!vm.registered.value) {
                    DeviceRegisterScreen(vm)
                } else {
                    when (tabIndex) {
                        0 -> MarketTab(vm)
                        1 -> OfferTab(vm)
                        2 -> ReceiptsTab(vm)
                    }
                }
            }
        }
    }
}

// ---- 状态提示条 ----

@Composable
fun StateBanner(state: UiState) {
    when (state) {
        is UiState.Loading -> LinearProgressIndicator(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.primary
        )
        is UiState.Success -> Snackbar(
            modifier = Modifier.padding(8.dp),
            containerColor = MaterialTheme.colorScheme.secondary,
            contentColor = MaterialTheme.colorScheme.onSecondary
        ) { Text((state as UiState.Success).message, fontSize = 13.sp) }
        is UiState.Error -> Snackbar(
            modifier = Modifier.padding(8.dp),
            containerColor = MaterialTheme.colorScheme.error,
            contentColor = MaterialTheme.colorScheme.onError
        ) { Text((state as UiState.Error).message, fontSize = 13.sp) }
        is UiState.Idle -> { /* 不显示 */ }
    }
}

// ---- 登录/注册界面 ----
@Composable
fun LoginScreen(vm: TradeViewModel) {
    var isRegisterMode by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var nickname by remember { mutableStateOf("") }
    val errorMsg by vm.error.collectAsState()
    val busy by vm.busy.collectAsState()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.CreditCard,
            contentDescription = null,
            modifier = Modifier.size(72.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(Modifier.height(16.dp))
        Text(
            if (isRegisterMode) "创建账户" else "欢迎回来",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground
        )
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("用户名") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("密码") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
        )
        if (isRegisterMode) {
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = nickname,
                onValueChange = { nickname = it },
                label = { Text("昵称") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
        }
        if (errorMsg != null) {
            Spacer(Modifier.height(12.dp))
            Text(errorMsg!!, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = {
                if (isRegisterMode && nickname.isNotBlank()) {
                    vm.userRegister(username.trim(), password, nickname.trim())
                } else {
                    vm.userLogin(username.trim(), password)
                }
            },
            enabled = !busy && username.isNotBlank() && password.isNotBlank(),
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(if (isRegisterMode) "注册" else "登录", fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.Center) {
            Text(
                if (isRegisterMode) "已有账户?" else "没有账户?",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.width(4.dp))
            TextButton(onClick = { isRegisterMode = !isRegisterMode }) {
                Text(if (isRegisterMode) "去登录" else "去注册", color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}
// ---- 设备注册界面 ----
@Composable
fun DeviceRegisterScreen(vm: TradeViewModel) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.Smartphone,
            contentDescription = null,
            modifier = Modifier.size(72.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(Modifier.height(16.dp))
        Text(
            注册设备,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground
        )
        Spacer(Modifier.height(8.dp))
        Text(
            注册后即可开始交易卡牌,
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = { vm.registerDevice() },
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(Icons.Default.PersonAdd, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(注册设备, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

// ---- 市场列表 ----

@Composable
fun MarketTab(vm: TradeViewModel) {
    val items by vm.marketItems.collectAsState()
    var showAcceptDialog by remember { mutableStateOf<MarketItem?>(null) }

    LaunchedEffect(Unit) { vm.refreshMarket() }

    if (items.isEmpty()) {
        EmptyState(
            icon = Icons.Default.Storefront,
            title = "市场空空如也",
            subtitle = "暂时没有人挂单，下拉刷新看看"
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "在售 ${items.size} 件",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    TextButton(onClick = { vm.refreshMarket() }) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("刷新", fontSize = 13.sp)
                    }
                }
            }
            items(items) { item ->
                MarketCard(item) {
                    showAcceptDialog = item
                }
            }
        }
    }

    // 接受交易弹窗
    showAcceptDialog?.let { item ->
        AcceptDialog(
            item = item,
            onDismiss = { showAcceptDialog = null },
            onAccept = { giveUuid ->
                vm.accept(item.packId, giveUuid)
                showAcceptDialog = null
            }
        )
    }
}

@Composable
fun MarketCard(item: MarketItem, onAccept: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // 顶部：昵称 + 时间
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    item.nickname.ifEmpty { "匿名卖家" },
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    formatTime(item.createdAt),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.height(12.dp))

            // 出价卡牌
            Text("出售", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            item.give.forEach { card ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CreditCard, contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.secondary)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        card.def,
                        fontSize = 13.sp,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "· ${card.uuid.take(8)}",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(Modifier.height(12.dp))

            // 需求
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Search, contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "求购: ${item.wantDef}",
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(Modifier.height(16.dp))

            // 接受按钮
            Button(
                onClick = onAccept,
                modifier = Modifier.fillMaxWidth().height(44.dp),
                shape = RoundedCornerShape(10.dp)
            ) {
                Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("接受交易", fontSize = 14.sp)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AcceptDialog(
    item: MarketItem,
    onDismiss: () -> Unit,
    onAccept: (giveUuid: String) -> Unit
) {
    var giveUuid by remember { mutableStateOf("") }
    var uuidError by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("确认交易", fontWeight = FontWeight.Bold) },
        text = {
            Column {
                Text("对方求购: ${item.wantDef}", fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(4.dp))
                Text("你需要提供一张 ${item.wantDef} 类型的卡牌 UUID",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                OutlinedTextField(
                    value = giveUuid,
                    onValueChange = {
                        giveUuid = it
                        uuidError = it.isBlank()
                    },
                    label = { Text("卡牌 UUID") },
                    isError = uuidError,
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                    supportingText = if (uuidError) {
                        { Text("请输入卡牌 UUID") }
                    } else null
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (giveUuid.isNotBlank()) {
                        onAccept(giveUuid.trim())
                    } else {
                        uuidError = true
                    }
                }
            ) { Text("确认", fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}

// ---- 挂单界面 ----

@Composable
fun OfferTab(vm: TradeViewModel) {
    var giveUuid by remember { mutableStateOf("") }
    var giveDef by remember { mutableStateOf("") }
    var wantDef by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            "挂单出售",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground
        )
        Text(
            "填写你要出售的卡牌信息和你想要的卡牌类型",
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(4.dp))

        // 出价卡牌 UUID
        OutlinedTextField(
            value = giveUuid,
            onValueChange = { giveUuid = it },
            label = { Text("卡牌 UUID") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
            leadingIcon = { Icon(Icons.Default.CreditCard, contentDescription = null) }
        )

        // 出价卡牌类型
        OutlinedTextField(
            value = giveDef,
            onValueChange = { giveDef = it },
            label = { Text("卡牌类型 (def)") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            leadingIcon = { Icon(Icons.Default.Category, contentDescription = null) }
        )

        // 分隔线
        HorizontalDivider(
            modifier = Modifier.padding(vertical = 4.dp),
            color = MaterialTheme.colorScheme.surfaceVariant
        )

        // 求购类型
        OutlinedTextField(
            value = wantDef,
            onValueChange = { wantDef = it },
            label = { Text("求购类型 (want_def)") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) }
        )

        Spacer(Modifier.height(8.dp))

        // 提交
        Button(
            onClick = {
                if (giveUuid.isNotBlank() && giveDef.isNotBlank() && wantDef.isNotBlank()) {
                    vm.offer(giveUuid.trim(), giveDef.trim(), wantDef.trim())
                    giveUuid = ""
                    giveDef = ""
                    wantDef = ""
                }
            },
            enabled = giveUuid.isNotBlank() && giveDef.isNotBlank() && wantDef.isNotBlank(),
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(Icons.Default.Sell, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("提交挂单", fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }

        // 帮助提示
        Spacer(Modifier.height(16.dp))
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            shape = RoundedCornerShape(8.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Info, contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(8.dp))
                    Text("提示", fontSize = 13.sp, fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "• UUID 和 def 请从游戏中复制\n" +
                    "• 挂单后卡牌进入托管状态\n" +
                    "• 交易成功后会收到回执\n" +
                    "• 请确认信息无误后再提交",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 18.sp
                )
            }
        }
    }
}

// ---- 回执列表 ----

@Composable
fun ReceiptsTab(vm: TradeViewModel) {
    val receipts by vm.receipts.collectAsState()

    LaunchedEffect(Unit) { vm.fetchReceipts() }

    if (receipts.isEmpty()) {
        EmptyState(
            icon = Icons.Default.Inbox,
            title = "暂无回执",
            subtitle = "交易完成后这里会显示通知"
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "未确认 ${receipts.size} 条",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    TextButton(onClick = { vm.fetchReceipts() }) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("刷新", fontSize = 13.sp)
                    }
                }
            }
            items(receipts) { receipt ->
                ReceiptCard(receipt) {
                    vm.ackReceipt(receipt.receiptId)
                }
            }
        }
    }
}

@Composable
fun ReceiptCard(receipt: Receipt, onAck: () -> Unit) {
    val typeColor = if (receipt.type == "trade_done")
        MaterialTheme.colorScheme.secondary
    else
        MaterialTheme.colorScheme.error

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // 类型标签 + 时间
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        when (receipt.type) {
                            "trade_done" -> Icons.Default.CheckCircle
                            "refund" -> Icons.Default.Undo
                            else -> Icons.Default.Notifications
                        },
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = typeColor
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        when (receipt.type) {
                            "trade_done" -> "交易完成"
                            "refund" -> "退款通知"
                            else -> receipt.type
                        },
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = typeColor
                    )
                }
                Text(
                    formatTime(receipt.serverTime),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(Modifier.height(8.dp))

            // Trade ID / Pack ID
            Text(
                "Trade: ${receipt.tradeId}",
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // 收到的卡
            if (receipt.receive.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text("收到", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                receipt.receive.forEach { card ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.ArrowDownward, contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.secondary)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "${card.def} · ${card.uuid.take(12)}",
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }

            // 送出的卡
            if (receipt.giveAway.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text("送出", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                receipt.giveAway.forEach { card ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.ArrowUpward, contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "${card.def} · ${card.uuid.take(12)}",
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // 确认按钮
            OutlinedButton(
                onClick = onAck,
                modifier = Modifier.fillMaxWidth().height(40.dp),
                shape = RoundedCornerShape(10.dp)
            ) {
                Icon(Icons.Default.Done, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("确认收到", fontSize = 13.sp)
            }
        }
    }
}

// ---- 空状态 ----

@Composable
fun EmptyState(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        )
        Spacer(Modifier.height(16.dp))
        Text(
            title,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(4.dp))
        Text(
            subtitle,
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
        )
    }
}

// ---- 工具函数 ----

private fun formatTime(epochSeconds: Long): String {
    if (epochSeconds <= 0) return ""
    val now = System.currentTimeMillis() / 1000
    val diff = now - epochSeconds
    return when {
        diff < 60 -> "刚刚"
        diff < 3600 -> "${diff / 60}分钟前"
        diff < 86400 -> "${diff / 3600}小时前"
        diff < 2592000 -> "${diff / 86400}天前"
        else -> "${diff / 2592000}月前"
    }
}
