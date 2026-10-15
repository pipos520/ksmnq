extends Node
class_name CardScannerNode

## 卡牌扫码导入 - Godot GDScript桥接层
## 用于启动相机扫码，将扫描结果（压缩卡牌码）回传到 GDScript
##
## 使用方法：
##   1. 场景中添加 CardScannerNode 节点
##   2. 连接 scan_success 信号处理扫描结果
##   3. 调用 startScan() 启动扫码

# ==================== 信号 ====================
## 扫码成功，返回扫描到的内容（卡牌压缩码）
signal scan_success(content: String)
## 用户取消扫码
signal scan_cancelled()
## 扫码出错。error_msg: 错误描述
signal scan_error(error_msg: String)

# ==================== 内部变量 ====================
var _is_ready: bool = false

# 直接获取插件单例的辅助函数
func _get_plugin():
	if Engine.has_singleton("CardScanner"):
		return Engine.get_singleton("CardScanner")
	return null

func _ready():
	_find_plugin()

func _find_plugin():
	var p = _get_plugin()
	if p != null:
		print("[CardScanner] ✅ 找到插件单例 CardScanner")
		# 连接Java插件的信号到GDScript
		p.connect("scan_success", Callable(self, "_on_scan_success"))
		p.connect("scan_cancelled", Callable(self, "_on_scan_cancelled"))
		p.connect("scan_error", Callable(self, "_on_scan_error"))
		_is_ready = true
	else:
		print("[CardScanner] ❌ 未找到Android插件单例 CardScanner，请确认插件已编译并打包")

# ==================== Java回调处理 ====================
func _on_scan_success(content: String):
	print("[CardScanner] 📷 扫码成功: ", content)
	emit_signal("scan_success", content)

func _on_scan_cancelled():
	print("[CardScanner] 🙅 用户取消扫码")
	emit_signal("scan_cancelled")

func _on_scan_error(error_msg: String):
	print("[CardScanner] ❌ 扫码错误: ", error_msg)
	emit_signal("scan_error", error_msg)

# ==================== 公开API ====================

## 启动相机扫码
func startScan() -> void:
	var p = _get_plugin()
	if p == null:
		emit_signal("scan_error", "plugin_not_ready")
		return
	p.startScan()

## 检查相机是否可用
func isCameraAvailable() -> bool:
	var p = _get_plugin()
	if p == null:
		return false
	return p.isCameraAvailable()

## 保存PNG图片到系统相册（MediaStore方式，兼容Android 10+）
## @param src_path 源图片绝对路径（如 user:// 对应的实际路径）
func saveImageToGallery(src_path: String) -> bool:
	var p = _get_plugin()
	if p == null:
		print("[CardScanner] ❌ 保存失败: 插件未就绪")
		return false
	var ok = p.saveImageToGallery(src_path)
	print("[CardScanner] 📸 保存图片到相册: ", "成功" if ok else "失败")
	return ok

## 是否就绪
func isReady() -> bool:
	return _is_ready