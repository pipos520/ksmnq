@tool
extends EditorPlugin

## 灰鲸(HJ)广告SDK - Godot Editor插件
## 负责在导出Android包时注入aar和Gradle依赖配置

var export_plugin: AndroidExportPlugin
var hj_ads_icon

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)
	
	# 加载图标（可选）
	# hj_ads_icon = load("res://addons/HJAds/icon.png")
	
	# 注册自定义节点（方便在场景中直接添加）
	add_custom_type(
		"HJAdsNode",          # 节点类型名
		"Node",               # 基类
		preload("res://addons/HJAds/HJAdsPlugin.gd"),  # 脚本
		null                  # 图标（可选）
	)

func _exit_tree() -> void:
	remove_custom_type("HJAdsNode")
	if export_plugin:
		remove_export_plugin(export_plugin)
		export_plugin = null


# ==================== 导出插件类 ====================
class AndroidExportPlugin extends EditorExportPlugin:
	var plugin_name = "HJAds"

	func _supports_platform(platform):
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform, debug):
		# 返回插件aar文件路径（相对于 res://android/ 目录）
		if debug:
			return PackedStringArray(["../addons/HJAds/hjads-debug.aar"])
		else:
			return PackedStringArray(["../addons/HJAds/hjads-release.aar"])

	func _get_android_dependencies(platform, debug):
		# 灰鲸SDK所需的远程依赖
		return PackedStringArray([
			"com.google.code.gson:gson:2.9.0",
			"com.squareup.okhttp3:okhttp:3.8.0",
			"com.squareup.okio:okio:1.13.0",
			"com.github.bumptech.glide:glide:3.7.0",
			"com.google.android.material:material:1.1.0",
			"androidx.appcompat:appcompat:1.2.0",
			"androidx.legacy:legacy-support-v4:1.0.0",
			"androidx.recyclerview:recyclerview:1.2.0",
			"androidx.multidex:multidex:2.0.1",
			"androidx.cardview:cardview:1.0.0",
			"androidx.constraintlayout:constraintlayout:2.0.4"
		])

	func _get_android_manifest_activity_element_contents(platform, debug):
		# AndroidManifest中需要的Provider配置
		# 这部分已放在主项目的AndroidManifest中
		return ""

	func _get_android_manifest_element_contents(platform, debug):
		# 在manifest标签内注入SDK需要的自定义permission
		# 注意：部分权限已在主AndroidManifest中声明
		return ""

	func _get_name():
		return plugin_name