class_name QualityConfig

## ============================================================
##  QualityConfig — 品质系统常量与查询函数（纯静态，无状态）
## ============================================================

const QUALITY_ORDER := ["废品", "瑕疵", "标准", "精良", "卓越", "完美"]
const QUALITY_MULTS := [0.7, 0.9, 1.0, 1.05, 1.1, 1.2]
const QUALITY_LEVELS := {"废品": 0, "瑕疵": 1, "标准": 2, "精良": 3, "卓越": 4, "完美": 5}
const QUALITY_COLORS := {
	"废品": Color("#9E9E9E"),
	"瑕疵": Color("#4FC3F7"),
	"标准": Color("#81C784"),
	"精良": Color("#60a5fa"),
	"卓越": Color("#c084fc"),
	"完美": Color("#f9d371"),
}

## 分享码品质编码（单字压缩）
const QUALITY_ENCODE := {"废品": "5", "瑕疵": "6", "标准": "7", "精良": "8", "卓越": "3", "完美": "4"}
const QUALITY_DECODE := {"3": "卓越", "4": "完美", "5": "废品", "6": "瑕疵", "7": "标准", "8": "精良"}


static func get_quality_rank(quality: String) -> int:
	var q = quality
	if " ~ " in q:
		var parts = q.split(" ~ ")
		q = parts[parts.size() - 1].strip_edges()
	return QUALITY_LEVELS.get(q, 0)


static func get_quality_color(quality: String) -> Color:
	var q = quality
	if " ~ " in q:
		var parts = q.split(" ~ ")
		q = parts[parts.size() - 1].strip_edges()
	return QUALITY_COLORS.get(q, Color("#a0a0b0"))


static func get_quality_mult(quality: String) -> float:
	var idx = QUALITY_ORDER.find(quality)
	if idx >= 0:
		return QUALITY_MULTS[idx]
	return 1.0
