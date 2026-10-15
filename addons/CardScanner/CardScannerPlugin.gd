@tool
extends EditorPlugin

## 卡牌扫码导入插件 - Android导出配置
## Godot 4.2+ v2 Android 插件架构
## 通过 EditorExportPlugin 告知 Godot 导出器插件的 aar 二进制路径

# 插件导出器实例
var export_plugin : AndroidExportPlugin

func _enter_tree():
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree():
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	# 插件名（须与 getPluginName() 一致）
	var _plugin_name = "CardScanner"

	# 指定支持的平台（仅 Android）
	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	# 返回插件的 aar 二进制路径（相对 addons 目录）
	func _get_android_libraries(platform, debug):
		# CardScanner 主插件 + zxing 扫码库（含 CaptureActivity）
		return PackedStringArray([
			"res://addons/CardScanner/cardscanner-debug.aar",
			"res://addons/CardScanner/zxing-android-embedded-4.3.0.aar"
		])

	# 返回插件名
	func _get_name():
		return _plugin_name