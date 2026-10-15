class_name QRCode
extends RefCounted

## QR码生成器（Byte模式，M纠错，版本1~18）
## 严格对齐 qrcode 标准库实现：位流编码 + RS分块/EC/交织 + 对齐图案 + map_data

# GF(256) 反对数表（EXP_TABLE）
const ANTILOG := [
	1,2,4,8,16,32,64,128,29,58,116,232,205,135,19,38,
	76,152,45,90,180,117,234,201,143,3,6,12,24,48,96,192,
	157,39,78,156,37,74,148,53,106,212,181,119,238,193,159,35,
	70,140,5,10,20,40,80,160,93,186,105,210,185,111,222,161,
	95,190,97,194,153,47,94,188,101,202,137,15,30,60,120,240,
	253,231,211,187,107,214,177,127,254,225,223,163,91,182,113,226,
	217,175,67,134,17,34,68,136,13,26,52,104,208,189,103,206,
	129,31,62,124,248,237,199,147,59,118,236,197,151,51,102,204,
	133,23,46,92,184,109,218,169,79,158,33,66,132,21,42,84,
	168,77,154,41,82,164,85,170,73,146,57,114,228,213,183,115,
	230,209,191,99,198,145,63,126,252,229,215,179,123,246,241,255,
	227,219,171,75,150,49,98,196,149,55,110,220,165,87,174,65,
	130,25,50,100,200,141,7,14,28,56,112,224,221,167,83,166,
	81,162,89,178,121,242,249,239,195,155,43,86,172,69,138,9,
	18,36,72,144,61,122,244,245,247,243,251,235,203,139,11,22,
	44,88,176,125,250,233,207,131,27,54,108,216,173,71,142,1
]

# 对数表（LOG_TABLE）
const LOGT := [-1,0,1,25,2,50,26,198,3,223,51,238,27,104,199,75,
	4,100,224,14,52,141,239,129,28,193,105,248,200,8,76,113,
	5,138,101,47,225,36,15,33,53,147,142,218,240,18,130,69,
	29,181,194,125,106,39,249,185,201,154,9,120,77,228,114,166,
	6,191,139,98,102,221,48,253,226,152,37,179,16,145,34,136,
	54,208,148,206,143,150,219,189,241,210,19,92,131,56,70,64,
	30,66,182,163,195,72,126,110,107,58,40,84,250,133,186,61,
	202,94,155,159,10,21,121,43,78,212,229,172,115,243,167,87,
	7,112,192,247,140,128,99,13,103,74,222,237,49,197,254,24,
	227,165,153,119,38,184,180,124,17,68,146,217,35,32,137,46,
	55,63,209,91,149,188,207,205,144,135,151,178,220,252,190,97,
	242,86,211,171,20,42,93,158,132,60,57,83,71,109,65,162,
	31,45,67,216,183,123,164,118,196,23,73,236,127,12,111,246,
	108,161,59,82,41,157,85,170,251,96,134,177,187,204,62,90,
	203,89,95,176,156,169,160,81,11,245,22,235,122,117,44,215,
	79,174,213,233,230,231,173,232,116,214,244,234,168,80,88,175
]

# RS块表：版本 -> { size, ec, blocks: [count,data_count]... } （M纠错）
const RS_M := {
	1: {"size":21, "ec":10, "blocks":[[1,16]]},
	2: {"size":25, "ec":16, "blocks":[[1,28]]},
	3: {"size":29, "ec":26, "blocks":[[1,44]]},
	4: {"size":33, "ec":18, "blocks":[[2,32]]},
	5: {"size":37, "ec":24, "blocks":[[2,43]]},
	6: {"size":41, "ec":16, "blocks":[[4,27]]},
	7: {"size":45, "ec":18, "blocks":[[4,31]]},
	8: {"size":49, "ec":22, "blocks":[[2,38],[2,39]]},
	9: {"size":53, "ec":22, "blocks":[[3,36],[2,37]]},
	10: {"size":57, "ec":26, "blocks":[[4,43],[1,44]]},
	11: {"size":61, "ec":30, "blocks":[[1,50],[4,51]]},
	12: {"size":65, "ec":22, "blocks":[[6,36],[2,37]]},
	13: {"size":69, "ec":22, "blocks":[[8,37],[1,38]]},
	14: {"size":73, "ec":24, "blocks":[[4,40],[5,41]]},
	15: {"size":77, "ec":24, "blocks":[[5,41],[5,42]]},
	16: {"size":81, "ec":28, "blocks":[[7,45],[3,46]]},
	17: {"size":85, "ec":28, "blocks":[[10,46],[1,47]]},
	18: {"size":89, "ec":26, "blocks":[[9,43],[4,44]]}
}

# RS生成多项式（rsPoly_LUT）
const GEN_POLY := {
	10: [1,216,194,159,111,199,94,95,113,157,193],
	16: [1,59,13,104,189,68,209,30,8,163,65,41,229,98,50,36,59],
	18: [1,239,251,183,113,149,175,199,215,240,220,73,82,173,75,32,67,217,146],
	22: [1,89,179,131,176,182,244,19,189,69,40,28,137,29,123,67,253,86,218,230,26,145,245],
	24: [1,122,118,169,70,178,237,216,102,115,150,229,73,130,72,61,43,206,1,237,247,127,217,144,117],
	26: [1,246,51,183,4,136,98,199,152,77,56,206,24,145,40,209,117,233,42,135,68,70,144,146,77,43,94],
	28: [1,252,9,28,13,18,251,208,150,103,174,100,41,167,12,247,56,117,119,233,127,181,100,121,147,176,74,58,197],
	30: [1,212,246,77,73,195,192,75,98,5,70,103,177,22,217,138,51,181,246,72,25,18,46,228,74,216,195,11,106,130,150]
}

# 版本信息（BCH(18,6)，版本7~18）
const VERSION_INFO := {
	7: 0x07C94, 8: 0x085BC, 9: 0x09A99, 10: 0x0A4D3, 11: 0x0BBF6,
	12: 0x0C762, 13: 0x0D847, 14: 0x0E60D, 15: 0x0F928, 16: 0x10B78,
	17: 0x1145D, 18: 0x12A17
}

# 对齐图案位置表
const POS_TABLE := {
	1: [], 2: [6,18], 3: [6,22], 4: [6,26], 5: [6,30], 6: [6,34],
	7: [6,22,38], 8: [6,24,42], 9: [6,26,46], 10: [6,28,50], 11: [6,30,54],
	12: [6,32,58], 13: [6,34,62], 14: [6,26,46,66], 15: [6,26,48,70],
	16: [6,26,50,74], 17: [6,30,54,78], 18: [6,30,56,82]
}

static func _pick_version(data_bytes: int) -> int:
	for v in range(1, 19):
		var total := 0
		for b in RS_M[v]["blocks"]:
			total += b[0] * b[1]
		if total >= data_bytes:
			return v
	return 18

# 位流编码：Byte mode(4bit) + 长度(8/16bit) + 数据 + 终止 + 对齐 + 填充
static func _create_data_codewords(data: String, version: int) -> PackedByteArray:
	var bytes = data.to_utf8_buffer()
	var bits := PackedByteArray()
	var bit_len := 0
	# 写入 mode=0100(4bit)
	for i in range(4):
		_set_bit(bits, bit_len, (0x4 >> (3 - i)) & 1)
		bit_len += 1
	# 写入长度
	var len_bits := 8 if version <= 9 else 16
	for i in range(len_bits):
		_set_bit(bits, bit_len, (bytes.size() >> (len_bits - 1 - i)) & 1)
		bit_len += 1
	# 写入数据
	for b in bytes:
		for i in range(8):
			_set_bit(bits, bit_len, (b >> (7 - i)) & 1)
			bit_len += 1
	# 总容量
	var total := 0
	for bb in RS_M[version]["blocks"]:
		total += bb[0] * bb[1]
	var bit_limit := total * 8
	# 终止位（最多4个0）
	for i in range(min(bit_limit - bit_len, 4)):
		bit_len += 1
	# 对齐到8位
	if bit_len % 8 != 0:
		bit_len += 8 - (bit_len % 8)
	# 写填充字节 0xEC/0x11 交替
	var pad_idx := 0
	while bit_len < bit_limit:
		var pad_byte := 0xEC if pad_idx % 2 == 0 else 0x11
		for i in range(8):
			_set_bit(bits, bit_len, (pad_byte >> (7 - i)) & 1)
			bit_len += 1
		pad_idx += 1
	# 打包成字节流
	var result := PackedByteArray()
	result.resize(total)
	for i in range(total):
		result[i] = _get_byte(bits, i * 8)
	return result

# 辅助：在bits数组的bit位置写入值（1写0不写，数组初始为0）
static func _set_bit(arr: PackedByteArray, idx: int, val: int) -> void:
	var byte_idx := int(idx / 8)
	if byte_idx >= arr.size():
		arr.resize(byte_idx + 1)
	if val != 0:
		arr[byte_idx] |= 0x80 >> (idx % 8)

# 辅助：读取一个字节（从指定bit位置开始）
static func _get_byte(arr: PackedByteArray, bit_start: int) -> int:
	var v := 0
	for i in range(8):
		var idx := bit_start + i
		if int(idx / 8) >= arr.size():
			continue
		if (arr[int(idx / 8)] >> (7 - (idx % 8))) & 1:
			v |= 0x80 >> i
	return v

static func _pad_data(data: PackedByteArray, target: int) -> PackedByteArray:
	var r = PackedByteArray(data)
	var i := r.size()
	while r.size() < target:
		r.append(0xEC if i % 2 == 0 else 0x11)
		i += 1
	return r

# RS纠错：对单块数据算EC
static func _rs_ec(data_block: Array, ec_count: int) -> Array:
	var gen: Array = GEN_POLY[ec_count]
	var gd := gen.size() - 1
	var msg := PackedByteArray()
	msg.resize(data_block.size() + ec_count)
	for i in range(data_block.size()):
		msg[i] = data_block[i]
	for i in range(data_block.size(), msg.size()):
		msg[i] = 0
	for i in range(data_block.size()):
		if msg[i] == 0:
			continue
		var lead := msg[i]
		var lead_log: int = LOGT[lead]
		for j in range(gd + 1):
			if gen[j] == 0:
				continue
			var idx := i + j
			if idx < msg.size():
				msg[idx] ^= ANTILOG[(lead_log + LOGT[gen[j]]) % 255]
	var result := PackedByteArray()
	for i in range(ec_count):
		result.append(msg[data_block.size() + i])
	return Array(result)

# 分块 + 每块EC + 交织
static func _interleave(data_codewords: PackedByteArray, version: int) -> PackedByteArray:
	var blocks_info: Array = RS_M[version]["blocks"]
	var ec_count: int = RS_M[version]["ec"]
	var blocks_list := []
	for entry in blocks_info:
		for k in range(entry[0]):
			blocks_list.append(entry[1])
	var offset := 0
	var dcdata := []
	var ecdata := []
	for data_count in blocks_list:
		var block := []
		for i in range(data_count):
			block.append(data_codewords[offset + i])
		offset += data_count
		var ecb := _rs_ec(block, ec_count)
		dcdata.append(block)
		ecdata.append(ecb)
	var max_dc := 0
	for b in dcdata:
		max_dc = max(max_dc, b.size())
	var out := PackedByteArray()
	for i in range(max_dc):
		for b in dcdata:
			if i < b.size():
				out.append(b[i])
	for i in range(ec_count):
		for b in ecdata:
			out.append(b[i])
	return out

static func _make_matrix(size: int) -> Array:
	var m := []
	for y in range(size):
		var row := []
		row.resize(size)
		row.fill(-1)
		m.append(row)
	return m

static func _place_finder(m: Array, r0: int, c0: int, size: int) -> void:
	for r in range(-1, 8):
		if r0 + r < 0 or r0 + r >= size:
			continue
		for c in range(-1, 8):
			if c0 + c < 0 or c0 + c >= size:
				continue
			if (r >= 0 and r <= 6 and (c == 0 or c == 6)) or (c >= 0 and c <= 6 and (r == 0 or r == 6)) or (r >= 2 and r <= 4 and c >= 2 and c <= 4):
				m[r0 + r][c0 + c] = 1
			else:
				m[r0 + r][c0 + c] = 0

static func _place_align(m: Array, size: int, version: int) -> void:
	var pos: Array = POS_TABLE[version]
	for row in pos:
		for col in pos:
			if row < 0 or row >= size or col < 0 or col >= size:
				continue
			if m[row][col] != -1:
				continue
			for r in range(-2, 3):
				for c in range(-2, 3):
					if abs(r) == 2 or abs(c) == 2 or (r == 0 and c == 0):
						m[row + r][col + c] = 1
					else:
						m[row + r][col + c] = 0

static func _place_timing(m: Array, size: int) -> void:
	for r in range(8, size - 8):
		if m[r][6] == -1:
			m[r][6] = 1 if r % 2 == 0 else 0
	for c in range(8, size - 8):
		if m[6][c] == -1:
			m[6][c] = 1 if c % 2 == 0 else 0

static func _place_format(m: Array, size: int, fmt: int) -> void:
	# vertical
	for i in range(15):
		var mod := (fmt >> i) & 1
		if i < 6:
			m[i][8] = mod
		elif i < 8:
			m[i + 1][8] = mod
		else:
			m[size - 15 + i][8] = mod
	# horizontal
	for i in range(15):
		var mod := (fmt >> i) & 1
		if i < 8:
			m[8][size - i - 1] = mod
		elif i < 9:
			m[8][15 - i] = mod  # 15-i-1+1 = 15-i
		else:
			m[8][15 - i - 1] = mod
	# fixed module
	m[size - 8][8] = 1

static func _place_version(m: Array, size: int, version: int) -> void:
	if version < 7:
		return
	var bits: int = VERSION_INFO[version]
	for i in range(18):
		var mod := (bits >> i) & 1
		m[int(i / 3)][i % 3 + size - 11] = mod
	for i in range(18):
		var mod := (bits >> i) & 1
		m[i % 3 + size - 11][int(i / 3)] = mod

static func _mask_func(mask: int, r: int, c: int) -> bool:
	match mask:
		0: return (r + c) % 2 == 0
		1: return r % 2 == 0
		2: return c % 3 == 0
		3: return (r + c) % 3 == 0
		4: return (int(r / 2) + int(c / 3)) % 2 == 0
		5: return (r * c) % 2 + (r * c) % 3 == 0
		6: return ((r * c) % 2 + (r * c) % 3) % 2 == 0
		7: return ((r + c) % 2 + (r * c) % 3) % 2 == 0
	return false

static func _map_data(m: Array, data: PackedByteArray, size: int, mask: int) -> void:
	var inc := -1
	var row := size - 1
	var bit_index := 7
	var byte_index := 0
	var data_len := data.size()
	var col := size - 1
	while col > 0:
		# 模拟标准库 for col in range(size-1, 0, -2)：col<=6时列对起点再-1
		var cc := col
		if cc <= 6:
			cc -= 1
		var cols := [cc, cc - 1]
		while true:
			for c in cols:
				if row < 0 or row >= size:
					continue
				if m[row][c] == -1:
					var dark := false
					if byte_index < data_len:
						dark = ((data[byte_index] >> bit_index) & 1) == 1
					if _mask_func(mask, row, c):
						dark = not dark
					m[row][c] = 1 if dark else 0
					bit_index -= 1
					if bit_index == -1:
						byte_index += 1
						bit_index = 7
			row += inc
			if row < 0 or row >= size:
				row -= inc
				inc = -inc
				break
		col -= 2

# 计算格式信息（M纠错=00，mask）：BCH(15,5) XOR 0x5412
static func _calc_format(mask: int) -> int:
	var data := mask
	var fmt := data << 10
	var gen := 0b10100110111
	for i in range(4, -1, -1):
		if (fmt >> (i + 10)) & 1:
			fmt ^= gen << i
	fmt = (data << 10) | fmt
	fmt ^= 0x5412
	return fmt & 0x7FFF

## 生成QR码矩阵（返回二维数组，0/1=白/黑）
static func generate(data: String, mask: int = 0) -> Array:
	var bytes = data.to_utf8_buffer()
	var version := _pick_version(bytes.size())
	var size: int = RS_M[version]["size"]
	var data_cw := _create_data_codewords(data, version)
	var all_data := _interleave(data_cw, version)
	var m := _make_matrix(size)
	_place_finder(m, 0, 0, size)
	_place_finder(m, size - 7, 0, size)
	_place_finder(m, 0, size - 7, size)
	_place_align(m, size, version)
	_place_timing(m, size)
	_place_format(m, size, _calc_format(mask))
	_place_version(m, size, version)
	_map_data(m, all_data, size, mask)
	for r in range(size):
		for c in range(size):
			if m[r][c] == -1:
				m[r][c] = 0
	return m

## 将QR码矩阵转为Image（黑白像素图）
static func to_image(matrix: Array, scale: int = 4, border: int = 2) -> Image:
	var size = matrix.size()
	var img_size = (size + border * 2) * scale
	var img = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	for y in range(size):
		for x in range(size):
			if matrix[y][x] == 1:
				for dy in range(scale):
					for dx in range(scale):
						var px = (x + border) * scale + dx
						var py = (y + border) * scale + dy
						img.set_pixel(px, py, Color(0, 0, 0, 1))
	return img

## 便捷方法：生成QR码Image
static func generate_image(data: String, scale: int = 4, border: int = 2) -> Image:
	var matrix = generate(data)
	return to_image(matrix, scale, border)