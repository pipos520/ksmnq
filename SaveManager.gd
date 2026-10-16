extends Node

## ============================================================
##  存档管理器（底层）—— 负责 JSON 文件的读写
## ============================================================

const SAVE_PATH := "user://save_data.json"

# 存档数据（内存中的完整存档）
var save_data: Dictionary = {}
# 脏标记：数据已变更但尚未写盘
var _dirty: bool = false

func _ready() -> void:
	load_save()

# ---------- 公开接口 ----------

## 获取存档中某个分类的数据
func get_section(section: String) -> Dictionary:
	return save_data.get(section, {})

## 设置存档中某个分类的数据
func set_section(section: String, data: Dictionary) -> void:
	save_data[section] = data
	_dirty = true

## 获取存档中某个分类下的具体字段
func get_value(section: String, key: String, default_value = null):
	var section_data = save_data.get(section, {})
	return section_data.get(key, default_value)

## 设置存档中某个分类下的具体字段
func set_value(section: String, key: String, value) -> void:
	if not save_data.has(section):
		save_data[section] = {}
	save_data[section][key] = value
	_dirty = true

## 写入磁盘（原子写：先写临时文件再重命名，防止写入中途崩溃导致存档损坏）
func save_to_disk() -> void:
	if not _dirty:
		return
	_dirty = false
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		print("[SaveManager] 错误：无法写入临时存档文件 ", tmp_path)
		_dirty = true
		return
	
	var json_str := JSON.stringify(save_data, "\t")
	file.store_string(json_str)
	file.close()
	
	if DirAccess.rename_absolute(tmp_path, SAVE_PATH) != OK:
		print("[SaveManager] 错误：临时存档重命名失败")
		_dirty = true
		return
	
	print("[SaveManager] 存档已保存")

## 是否有未保存的变更
func is_dirty() -> bool:
	return _dirty

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
	
	var data = json.get_data()
	if data is Dictionary:
		save_data = data
	else:
		print("[SaveManager] 存档格式异常（非字典），将创建新存档")
		save_data = {}
	print("[SaveManager] 存档加载成功")

## 重置存档
func reset_save() -> void:
	save_data = {}
	save_to_disk()
	print("[SaveManager] 存档已重置")