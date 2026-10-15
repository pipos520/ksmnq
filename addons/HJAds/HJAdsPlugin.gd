extends Node
class_name HJAdsNode

## 灰鲸(HJ)广告SDK - Godot GDScript桥接层
## 用于激励视频广告的加载、展示和奖励回调
##
## 使用方法：
##   1. 在场景中添加 HJAdsNode 节点
##   2. 连接信号处理奖励回调
##   3. 调用 init() -> loadRewardedAd() -> showRewardedAd()

# ==================== 导出属性（在Inspector中可配置） ====================
## 灰鲸广告平台的应用ID
@export var app_id: String = "234475"
## 激励视频广告位ID
@export var rewarded_placement_id: String = "9701263723893953"
## 是否开启调试日志
@export var debug_mode: bool = true

# ==================== 信号 ====================
## 激励视频加载成功
signal ad_loaded(placement_id: String)
## 激励视频开始播放
signal ad_play_start()
## 获得奖励！rewarded=true 表示获得奖励
signal video_rewarded(rewarded: bool)
## 广告关闭。result: "rewarded" 完整播放获得奖励, "skipped" 跳过未获得
signal ad_closed(result: String)
## 广告出错。error_msg: 错误描述
signal ad_failed(error_msg: String)

# ==================== 内部变量 ====================
var _is_initialized: bool = false
var _init_attempted: bool = false

# 直接获取插件单例的辅助函数
func _get_plugin():
	if Engine.has_singleton("HJAds"):
		return Engine.get_singleton("HJAds")
	return null

# ==================== 信号桥接（用于Java回调→GDScript信号） ====================
var _signal_callbacks: Dictionary = {}

func _init_signal_bridge():
	_signal_callbacks = {
		"on_ad_loaded": Callable(self, "_on_ad_loaded"),
		"on_ad_play_start": Callable(self, "_on_ad_play_start"),
		"on_video_rewarded": Callable(self, "_on_video_rewarded"),
		"on_ad_closed": Callable(self, "_on_ad_closed"),
		"on_ad_failed": Callable(self, "_on_ad_failed"),
	}

func _ready():
	_init_signal_bridge()
	_find_plugin()

func _find_plugin():
	var p = _get_plugin()
	if p != null:
		_debug("✅ 找到插件单例 HJAds")
		
		# 连接Java插件的信号到GDScript
		p.connect("on_ad_loaded", Callable(self, "_on_ad_loaded"))
		p.connect("on_ad_play_start", Callable(self, "_on_ad_play_start"))
		p.connect("on_video_rewarded", Callable(self, "_on_video_rewarded"))
		p.connect("on_ad_closed", Callable(self, "_on_ad_closed"))
		p.connect("on_ad_failed", Callable(self, "_on_ad_failed"))
		
		# 自动初始化
		if app_id != "":
			init(app_id)
		else:
			_debug("⚠️ app_id 未设置，请先调用 init(appId)")
	else:
		_debug("❌ 未找到插件单例 HJAds，请确认 Android 插件已正确编译")
		print("[HJAds] 错误: Android 插件未找到！请确保已编译 hjads.aar 并放入插件目录")

# ==================== 内部日志 ====================
func _debug(msg: String):
	if debug_mode:
		print("[HJAds] " + msg)

# ==================== Java回调处理 ====================
func _on_ad_loaded(placement_id: String):
	_debug("📢 激励视频加载成功: " + placement_id)
	emit_signal("ad_loaded", placement_id)

func _on_ad_play_start():
	_debug("▶️ 激励视频开始播放")
	emit_signal("ad_play_start")

func _on_video_rewarded(rewarded: bool):
	_debug("🎁 获得奖励: " + str(rewarded))
	emit_signal("video_rewarded", rewarded)

func _on_ad_closed(result: String):
	_debug("🔚 激励视频关闭: " + result)
	emit_signal("ad_closed", result)

func _on_ad_failed(error_msg: String):
	_debug("❌ 广告错误: " + error_msg)
	emit_signal("ad_failed", error_msg)

# ==================== 公开API ====================

## 初始化灰鲸广告SDK
## @param appId: 应用ID（如果不传，使用export变量app_id）
func init(appId: String = "") -> void:
	if appId == "":
		appId = app_id
	if appId == "":
		_debug("❌ 初始化失败: 未提供 appId")
		return
	
	_init_attempted = true
	var p = _get_plugin()
	if p != null:
		_debug("🚀 初始化 HJAds SDK, appId=" + appId)
		p.init(appId)
		_is_initialized = true
	else:
		_debug("⏳ 插件尚未就绪，延迟初始化")
		# 如果插件还没准备好，尝试重新查找
		_find_plugin()
		p = _get_plugin()
		if p != null:
			p.init(appId)
			_is_initialized = true

## 加载激励视频广告
## @param placementId: 广告位ID（如果不传，使用export变量rewarded_placement_id）
## @param userId: 用户ID（可选）
## @param customData: 自定义数据（可选，用于服务端验证）
func loadRewardedAd(placementId: String = "", userId: String = "", customData: String = "") -> void:
	if placementId == "":
		placementId = rewarded_placement_id
	if placementId == "":
		_debug("❌ 加载失败: 未提供 placementId")
		return
	
	var p = _get_plugin()
	if p == null:
		_debug("❌ 加载失败: 插件未就绪")
		emit_signal("ad_failed", "plugin_not_ready")
		return
	
	_debug("📥 加载激励视频: placementId=" + placementId)
	p.loadRewardedAd(placementId, userId, customData)

## 展示激励视频广告
## 需要先调用 loadRewardedAd() 并等待 ad_loaded 信号
func showRewardedAd() -> void:
	var p = _get_plugin()
	if p == null:
		_debug("❌ 展示失败: 插件未就绪")
		emit_signal("ad_failed", "plugin_not_ready")
		return
	
	if p.isRewardedAdReady():
		_debug("▶️ 展示激励视频")
		p.showRewardedAd()
	else:
		_debug("❌ 展示失败: 广告未就绪")
		emit_signal("ad_failed", "not_ready")

## 检查激励视频是否已就绪
func isRewardedAdReady() -> bool:
	var p = _get_plugin()
	if p == null:
		return false
	return p.isRewardedAdReady()

## 销毁广告对象，释放资源
func destroy() -> void:
	var p = _get_plugin()
	if p != null:
		p.destroy()
		_debug("🗑️ 广告插件已销毁")
	_is_initialized = false