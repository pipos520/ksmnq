extends Node

## ============================================================
##  AudioManager — 音效池管理（Autoload）
##  每个音效预建独立 AudioStreamPlayer 并预绑 stream
##  播放时只调 .play()，零中间操作，最低延迟
## ============================================================

var _sfx_pool: Dictionary = {}
var _sfx_enabled: bool = true

## 音效名 → 文件路径 映射
const SFX_MAP := {
	"click": "res://assets/audio/ui/click1.wav",
	"click_alt": "res://assets/audio/ui/click2.wav",
	"hover": "res://assets/audio/ui/rollover1.wav",
	"switch": "res://assets/audio/ui/switch1.wav",
	"confirm": "res://assets/audio/ui/positive.wav",
	"cancel": "res://assets/audio/ui/negative.wav",
	"save": "res://assets/audio/ui/save.wav",
	"load": "res://assets/audio/ui/load.wav",
	"menu": "res://assets/audio/ui/misc_menu.wav",
	"error": "res://assets/audio/ui/negative_2.wav",
	"echo": "res://assets/audio/ui/sharp_echo.wav",
	"draw": "res://assets/audio/card/draw.wav",
	"deal": "res://assets/audio/card/deal.wav",
	"deal_alt": "res://assets/audio/card/deal_alt.wav",
	"flip": "res://assets/audio/ui/misc_menu_2.wav",
	"fan": "res://assets/audio/ui/rollover2.wav",
	"pack_open": "res://assets/audio/ui/misc_sound.wav",
	"pack_take": "res://assets/audio/ui/rollover3.wav",
	"shuffle": "res://assets/audio/ui/switch2.wav",
	"attack_hit": "res://assets/audio/card/attack_hit.wav",
	"effect_cast": "res://assets/audio/ui/sharp_echo.wav",
	"card_death": "res://assets/audio/card/card_death.wav",
	"damage": "res://assets/audio/system/damage.wav",
	"heal": "res://assets/audio/ui/positive.wav",
	"destroy": "res://assets/audio/card/destroy.wav",
	"coin": "res://assets/audio/ui/switch3.wav",
	"coin_stack": "res://assets/audio/ui/switch4.wav",
	"dice": "res://assets/audio/ui/switch5.wav",
}


func _ready() -> void:
	_init_sfx()


func _init_sfx() -> void:
	if _sfx_pool.size() > 0:
		return
	for key in SFX_MAP.keys():
		var res = load(SFX_MAP[key])
		if not res and SFX_MAP[key].ends_with(".wav"):
			res = _load_wav_from_file(SFX_MAP[key])
		if res:
			var p = AudioStreamPlayer.new()
			p.name = "Sfx_" + key
			p.stream = res
			p.volume_db = 0.0
			add_child(p)
			_sfx_pool[key] = p
		else:
			print("[SFX] 加载失败: %s" % SFX_MAP[key])
	print("[SFX] 音效池初始化完成，共 %d 个" % _sfx_pool.size())


## 从文件系统直接读取wav构建AudioStreamWAV
func _load_wav_from_file(res_path: String) -> AudioStreamWAV:
	var file_path = res_path.replace("res://", "")
	var fa = FileAccess.open(file_path, FileAccess.READ)
	if not fa:
		print("[SFX] 文件打开失败: %s" % file_path)
		return null
	var riff = fa.get_buffer(4)
	if riff.get_string_from_ascii() != "RIFF":
		fa.close()
		return null
	fa.get_32()
	var wave = fa.get_buffer(4)
	if wave.get_string_from_ascii() != "WAVE":
		fa.close()
		return null
	var format_code := 0
	var num_channels := 1
	var sample_rate := 44100
	var byte_rate := 0
	var block_align := 0
	var bits_per_sample := 16
	var audio_data := PackedByteArray()
	while fa.get_position() < fa.get_length():
		var chunk_id = fa.get_buffer(4).get_string_from_ascii()
		var chunk_size = fa.get_32()
		if chunk_id == "fmt ":
			format_code = fa.get_16()
			num_channels = fa.get_16()
			sample_rate = fa.get_32()
			byte_rate = fa.get_32()
			block_align = fa.get_16()
			bits_per_sample = fa.get_16()
			if chunk_size > 16:
				fa.seek(fa.get_position() + chunk_size - 16)
		elif chunk_id == "data":
			audio_data = fa.get_buffer(chunk_size)
		else:
			fa.seek(fa.get_position() + chunk_size)
		if chunk_size % 2 == 1:
			var pos = fa.get_position()
			fa.seek(pos + 1)
	fa.close()
	if audio_data.is_empty():
		return null
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = num_channels == 2
	stream.data = audio_data
	return stream


func play_sfx(sfx_name: String) -> void:
	if not _sfx_enabled:
		return
	if _sfx_pool.has(sfx_name):
		_sfx_pool[sfx_name].play()
	else:
		print("[SFX] 未知音效: %s" % sfx_name)


func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
