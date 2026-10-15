extends Node

## ============================================================
##  存档管理器（底层）—— 负责 JSON 文件的读写
## ============================================================

const SAVE_PATH := "user://save_data.json"

# 存档数据（内存中的完整存档）
var save_data: Dictionary = {}

func _ready() -> void:
	load_save()

# ---------- 公开接口 ----------

## 获取存档中某个分类的数据
func get_section(section: String) -> Dictionary:
	return save_data.get(section, {})

## 设置存档中某个分类的数据
func set_section(section: String, data: Dictionary) -> void:
	save_data[section] = data

## 获取存档中某个分类下的具体字段
func get_value(section: String, key: String, default_value = null):
	var section_data = save_data.get(section, {})
	return section_data.get(key, default_value)

## 设置存档中某个分类下的具体字段
func set_value(section: String, key: String, value) -> void:
	if not save_data.has(section):
		save_data[section] = {}
	save_data[section][key] = value

## 写入磁盘
func save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		print("[SaveManager] 错误：无法写入存档文件 ", SAVE_PATH)
		return
	
	var json_str := JSON.stringify(save_data, "\t")
	file.store_string(json_str)
	file.close()
	print("[SaveManager] 存档已保存")

## 从磁盘读取
func load_save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		print("[SaveManager] 未找到存档文件，将创建新存档")
		save_data = {}
		return
	
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		print("[SaveManager] 存档解析错误：", json.get_error_message())
		save_data = {}
		return
	
	save_data = json.get_data()
	print("[SaveManager] 存档加载成功")

## 重置存档
func reset_save() -> void:
	save_data = {}
	save_to_disk()
	print("[SaveManager] 存档已重置")