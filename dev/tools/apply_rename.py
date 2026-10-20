# -*- coding: utf-8 -*-
"""叙事重命名全量应用脚本（§9 待办 3/4/6）
范围：5 区域 / 36 普通怪 / 14 BOSS（name+desc）/ 16 套 AI deck 名（仅 deck_data.name）/
AU 素材 desc 同步 + 4 个 AU 名 / 代码显示层（MAPS、MAP_NAMES、ENEMY_NAME_TO_DATA、full_names、
帮助标签、AUX_NAME_TO_ID、解锁条件串、tscn 文本）。
铁律：不动 effects/数值/id/卡牌 name/desc/fields。幂等：替换基于旧名，重跑无变化。
"""
import json, re

ROOT = r'C:\Users\Administrator\Documents\ksmnq'

REGION = {
    '迷雾森林': '沉雾植物园',
    '火焰洞穴': '烬燃热电厂',
    '风暴高塔': '雷鸣电视塔',
    '暗影沼泽': '沉陷湿地公园',
    '传说遗迹': '圮城博物馆',
}

MON = {  # 旧裸名/旧全名 -> (新名, 新desc, emoji)
 '树苗精': ('催芽藓偶', '沉雾植物园催芽箱里冒出来的苔藓傀儡，见苗就缠。', '🌱'),
 '雾角鹿': ('雾栖鹿偶', '园区里的雕塑鹿，大裂断之后开始在雾里自己挪位。', '🦌'),
 '蘑菇人': ('霉斑菌傀', '菌房的霉斑一夜之间凝成的人形，孢子随呼吸散开。', '🍄'),
 '草蜥蜴': ('灼背蜥', '贴着地暖管道晒背的蜥蜴，背脊烫得能点燃落叶。', '🦎'),
 '螳螂刀客': ('刈草螳', '捡走园丁镰刀的螳螂，双臂快得像一台割草机。', '🦗'),
 '青鳞蛇': ('灌渠鳞蛇', '在灌溉渠底潜行的青鳞长虫，水面只留一圈涟漪。', '🐍'),
 '岩石傀儡': ('假山傀儡', '枯山水假山站起来了，走路时碎石哗啦作响。', '🪨'),
 '熔岩蠕虫': ('暖管蠕虫', '钻进地暖管网里的蠕虫，所过之处管道发烫。', '🔥'),
 '暗晶蝎': ('沥青蝎', '从步道裂缝析出的蝎子，甲壳是半融的沥青。', '🦂'),
 '水元素': ('喷泉水灵', '喷泉池里活过来的水，水柱就是它的拳头。', '💧'),
 '风灵蝶': ('玻璃翼蝶', '翅膀透明得像温室玻璃，落在哪哪就跟着消失。', '🦋'),
 '光棱镜': ('聚光蜮', '会聚光的小怪，被它盯上的叶子十秒冒烟。', '🔮'),
 '岩石巨人': ('叠石巨人', '叠石景观一块块码起来的巨人，倒下就散回石头。', '🗻'),
 '暗影鸦': ('掠影寒鸦', '只在影子的落点停留的鸦，数它的影子比数它容易。', '🐦‍⬛'),
 '风暴鹰': ('贯雾鹰', '俯冲时能把雾墙撕开一道口的鹰。', '🦅'),
 '暗穴蜘蛛': ('井穴蜘蛛', '地下井道里的织网者，井盖就是它的门。', '🕷️'),
 '熔岩龟': ('锅炉龟', '背甲就是一台小锅炉的龟，生气时压力阀会响。', '🐢'),
 '幻光蝶': ('灯诱光蝶', '被园区夜景灯诱变的蝶，绕着灯能转到天亮。', '🦋'),
 '熔岩元素': ('煤渣火灵', '从煤斗里蹦出来的火精，落地就烧，烧完就散。', '🔥'),
 '熔岩支配者': ('炉渣暴君', '炉渣堆里长出的掠夺性聚合体，谁热它抢谁。', '👑'),
 '熔岩毒蝎': ('熔渣蝎', '在熔渣缝里打洞的蝎子，尾针通红。', '🦂'),
 '炎晶蛇': ('燃缆火蛇', '顺着燃烧电缆游走的蛇，鳞片间蹦着电火花。', '🐍'),
 '熔岩猎犬': ('炉门火犬', '蹲在炉门口的看火犬，火光就是它的吼声。', '🐕'),
 '火焰占星师': ('焰瞳占卜师', '从火苗的抖动里读征兆的异兽，读到的全是坏消息。', '🔮'),
 '熔岩巨像': ('冷塔巨像', '冷却塔里站起来的巨像，水汽是它的呼吸。', '🪨'),
 '火焰咒术师': ('焚化咒师', '焚化炉的烟凝成的咒师，咒文写在灰上。', '🔮'),
 '黑曜石傀儡': ('焦砖傀儡', '车间焦砖一块块压成的傀儡，比假山傀儡更硬。', '🪨'),
 '熔岩水母': ('蒸汽水母', '漂在蒸汽管网上的水母，触须是几股白汽。', '🪼'),
 '熔岩飞龙': ('烟囱火龙', '盘踞烟囱顶的火龙，全厂的黑烟都从它背后冒。', '🐉'),
 '岩浆蠕虫': ('熔管蠕虫', '输热主管里的巨虫，管壁的鼓包暴露它的路径。', '🐛'),
 '地狱三头犬': ('三缸火犬', '机组废墟里长出的三头犬，三颗头共用一台引擎。', '🐕'),
 '火焰萨满': ('点炉火祝', '主持点炉仪式的火祝，仪式从来没停过。', '🔥'),
 '熔岩幽灵': ('余烬幽灵', '熄炉之后还不肯散的余烬，飘着飘着就成了形。', '👻'),
 '亡灵炼金师': ('废料炼金师', '在废料场里捣鼓什么的怪影，没人看清过它的脸。', '💀'),
 '深渊掠夺者': ('窃火者', '从虚渊钻进来偷炉火的掠食者，得手就跑。', '👁️'),
 '暗影支配者': ('黑烟暴君', '全厂黑烟凝成的暴君，烟往哪飘它说了算。', '👿'),
 '迷雾守护者·古木': ('沉雾园主·古荫', '沉雾植物园最深处那棵老树，整座园子的雾都听它的。', '👑'),
 '迷雾守护者·烈焰': ('沉雾园主·炉心', '温室锅炉里长出的园主分体，把整条暖路烧成火网。', '👑'),
 '迷雾守护者·暗影': ('沉雾园主·夜幕', '只在闭园后睁眼的园主分体，黑暗里所有影子都是它的枝。', '👑'),
 '熔岩支配者·炎帝': ('烬燃厂主·炎宰', '烬燃热电厂自封的主人，炉温就是它的心跳。', '👑'),
 '熔核巨人·格隆': ('熔核巨像·格隆', '整台熔核机组拼成的巨像，格隆是机身铭牌上的编号。', '👑'),
 '炎魔领主·萨弗隆': ('过热领主·萨弗隆', '过热蒸汽凝成的领主，压力表爆表才是它的常态。', '👑'),
}
BOSS_SEQ = {  # 占位名按 id 定名（enemies.json 与 .gd 内联字典共用）
 'ST_BOSS_1': ('雷鸣塔主·过载', '雷鸣电视塔的塔主之一，永远处在放电的边缘。'),
 'ST_BOSS_2': ('雷鸣塔主·失真', '塔主之一，它出现时信号里全是不该有的声音。'),
 'ST_BOSS_3': ('雷鸣塔主·惊蛰', '塔主之一，每年第一声春雷其实是它在换班。'),
 'SS_BOSS_2': ('沉渊沼主·淤眠', '沉陷湿地公园最深处的沼主，它睡着的这些年湿地又陷了半米。'),
 'SS_BOSS_3': ('沉渊沼主·雾溺', '沼主之一，它吐出的雾能让游泳的人忘记上岸。'),
 'LR_BOSS_1': ('圮城馆主·典守', '圮城博物馆的馆主之一，守着没人来借的档案。'),
 'LR_BOSS_2': ('圮城馆主·断代', '馆主之一，它路过的展柜年代都会错乱。'),
 'LR_BOSS_3': ('圮城馆主·镇馆', '馆主之一，严格来说它自己就是镇馆之宝。'),
}
# BOSS 在 .gd 内联字典里用短名做键（匹配帮助标签里的 "过载/失真/惊蛰"）
BOSS_SHORT = {
 'MF_BOSS_1': '古荫', 'MF_BOSS_2': '炉心', 'MF_BOSS_3': '夜幕',
 'FC_BOSS_1': '炎宰', 'FC_BOSS_2': '熔核', 'FC_BOSS_3': '过热',
 'ST_BOSS_1': '过载', 'ST_BOSS_2': '失真', 'ST_BOSS_3': '惊蛰',
 'SS_BOSS_2': '淤眠', 'SS_BOSS_3': '雾溺',
 'LR_BOSS_1': '典守', 'LR_BOSS_2': '断代', 'LR_BOSS_3': '镇馆',
}
AUX_NAME_MAP = {'草蜥蜴鳞片': '灼背蜥鳞片', '熔岩龟甲': '锅炉龟甲', '炎晶蛇牙': '燃缆蛇牙', '熔岩犬爪': '炉门犬爪'}
DECK_RENAME = {
 2: 'AI·环刃猎手团', 3: 'AI·刻印调律师', 4: 'AI·回路布设局',
 6: 'AI·港卫北垒军', 7: 'AI·公会执律司',
 8: 'AI·白鹭书院·浩然社', 9: 'AI·白鹭书院·观渊社',
 10: 'AI·太一钟楼·守钟会', 11: 'AI·太一钟楼·封档秘录',
 12: 'AI·霜月气象台·极夜观测厅', 13: 'AI·霜月气象台·月见旧档',
 14: 'AI·金顶寺·香火巡礼', 15: 'AI·金顶寺·苦海渡引',
 18: 'AI·南疆雨林·百寨巡守', 19: 'AI·南疆雨林·无字碑林',
 20: 'AI·环刃团·九刃谱',
}
MAPS_DESC = {
 '幽暗的森林中弥漫着神秘雾气，\\n据说深处藏着古老的卡牌碎片。':
 '大裂断吞没的城市植物园，\\n雾气催生了温室般的异兽生态。',
 '灼热的岩浆在地底流淌，\\n火焰精灵守护着珍贵的火系素材。':
 '废弃热电厂的地下熔炉仍在运转，\\n管网深处游荡着火的异兽。',
}
HELP_LABELS = [
 ('  • 迷雾森林 → 古木/烈焰/暗影', '  • 沉雾植物园 → 古荫/炉心/夜幕'),
 ('  • 火焰洞穴 → 岩浆/熔核/炎魔', '  • 烬燃热电厂 → 炎宰/熔核/过热'),
 ('  • 风暴高塔 → 雷电/风暴/云龙', '  • 雷鸣电视塔 → 过载/失真/惊蛰'),
 ('  • 暗影沼泽 → 暗影/沼泽/毒雾', '  • 沉陷湿地公园 → 淤眠/雾溺'),
 ('  • 传说遗迹 → 遗迹/守护/星空', '  • 圮城博物馆 → 典守/断代/镇馆'),
]

def swap_regions(s):
    for a, b in REGION.items():
        s = s.replace(a, b)
    return s

# ---------- 1. enemies.json ----------
def do_enemies():
    p = ROOT + r'\Data\enemies.json'
    d = json.load(open(p, encoding='utf-8'))
    n_name = n_desc = 0
    for mk, mv in d['maps'].items():
        if isinstance(mv.get('name'), str):
            nv = swap_regions(mv['name'])
            if nv != mv['name']:
                mv['name'] = nv
                n_name += 1
        bundles = []
        for tv in mv.get('terrains', {}).values():
            bundles += tv.get('monsters', [])
        b = mv.get('boss')
        if isinstance(b, dict):
            bundles.append(b)
        elif isinstance(b, list):
            bundles += b
        for m in bundles:
            mid = m.get('id', '')
            raw = m.get('name', '')
            emoji, _, bare = raw.partition(' ')
            if not bare:
                bare, emoji = raw, ''
            if bare in MON:
                new, desc, _e = MON[bare]
                if new != bare:
                    m['name'] = (emoji + ' ' + new).strip()
                    n_name += 1
                if m.get('desc') != desc:
                    m['desc'] = desc
                    n_desc += 1
            elif mid in BOSS_SEQ:
                new, desc = BOSS_SEQ[mid]
                m['name'] = ((emoji or '👑') + ' ' + new).strip()
                m['desc'] = desc
                n_name += 1
                n_desc += 1
            else:
                nd = swap_regions(m.get('desc', ''))
                if nd != m.get('desc', ''):
                    m['desc'] = nd
                    n_desc += 1
    # 渊母 desc 微调（区域词已不在新命名里）
    ym = d['maps']['shadow_swamp']
    for b in (ym['boss'] if isinstance(ym['boss'], list) else [ym['boss']]):
        if b['id'] == 'SS_BOSS_1' and '沼泽深处' in b['desc']:
            b['desc'] = '沉陷湿地最深处的母体，一切渊蚀根系的源头。'
            n_desc += 1
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'enemies.json: name {n_name}, desc {n_desc}')

# ---------- 2. materials.json ----------
def do_materials():
    p = ROOT + r'\Data\materials.json'
    d = json.load(open(p, encoding='utf-8'))
    n = 0
    for cat, lst in d['materials'].items():
        for x in lst:
            for f in ('area', 'desc'):
                if isinstance(x.get(f), str):
                    ns = swap_regions(x[f])
                    if ns != x[f]:
                        x[f] = ns
                        n += 1
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'materials.json: {n} fields')

# ---------- 3. aux_items.json ----------
def do_aux():
    p = ROOT + r'\Data\aux_items.json'
    top = json.load(open(p, encoding='utf-8'))
    items = top if isinstance(top, list) else top.get('aux_items', [])
    n = 0
    # 按长度降序替换，防止 '熔岩支配者·炎帝' 被 '熔岩支配者' 先截断
    pairs = sorted(MON.items(), key=lambda t: -len(t[0]))
    for it in items:
        if it.get('name') in AUX_NAME_MAP:
            it['name'] = AUX_NAME_MAP[it['name']]
            n += 1
        for f in ('description', 'desc'):
            s = it.get(f)
            if isinstance(s, str):
                ns = swap_regions(s)
                for a, v in pairs:
                    if a in ns:
                        ns = ns.replace(a, v[0])
                if ns != s:
                    it[f] = ns
                    n += 1
    json.dump(top, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'aux_items.json: {n} fields')

# ---------- 4. local_ai_decks.json（仅 deck 名） ----------
def do_decks():
    p = ROOT + r'\Data\local_ai_decks.json'
    d = json.load(open(p, encoding='utf-8'))
    n = 0
    for x in d:
        i = x.get('id')
        if i in DECK_RENAME and x['deck_data'].get('name') != DECK_RENAME[i]:
            x['deck_data']['name'] = DECK_RENAME[i]
            n += 1
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'local_ai_decks.json: {n} deck names')

# ---------- 5. .gd 内联字典块重建 ----------
def regen_enemy_dict(src):
    start = src.index('const ENEMY_NAME_TO_DATA := {')
    end = src.index('\n}', start)
    block = src[start:end]
    out = ['const ENEMY_NAME_TO_DATA := {']
    for line in block.splitlines()[1:]:
        m = re.match(r'\t"([^"]+)": \{(.*)\},?$', line)
        if not m:
            continue
        key, inner = m.groups()
        mid = re.search(r'"id": "([^"]+)"', inner).group(1)
        newkey, newdesc = None, None
        if mid in BOSS_SHORT:
            newkey = BOSS_SHORT[mid]
            if mid in BOSS_SEQ:
                newdesc = BOSS_SEQ[mid][1]
            else:  # MF/FC BOSS 短名 -> MON 全名 desc
                for full, (nn, nd, _e) in MON.items():
                    if nn.endswith('·' + BOSS_SHORT[mid]) or BOSS_SHORT[mid] in nn:
                        newdesc = nd
                        break
        elif key in MON:
            newkey, newdesc, _e = MON[key]
        if newkey is None:
            newkey, newdesc = key, swap_regions(re.search(r'"desc": "([^"]*)"', inner).group(1))
        inner = re.sub(r'"desc": "[^"]*"', '"desc": "%s"' % newdesc, inner)
        out.append('\t"%s": {%s},' % (newkey, inner))
    out.append('}')
    return src[:start] + '\n'.join(out) + src[end + 2:]

def regen_full_names(src):
    start = src.index('var full_names := {')
    end = src.index('\n\t}', start)
    block = src[start:end]
    # 收集已重建的 ENEMY_NAME_TO_DATA 的键（短名=BOSS，全名=普通怪）
    dstart = src.index('const ENEMY_NAME_TO_DATA := {')
    dend = src.index('\n}', dstart)
    keys = re.findall(r'\t"([^"]+)": \{', src[dstart:dend])
    out = ['var full_names := {']
    for i in range(0, len(keys), 3):
        row = []
        for k in keys[i:i + 3]:
            e = '👑'
            for full, (_n, _d, em) in MON.items():
                if k == _n:
                    e = em
                    break
            row.append('"%s": "%s %s"' % (k, e, k))
        out.append('\t\t' + ', '.join(row) + ',')
    out.append('\t}')
    return src[:start] + '\n'.join(out) + src[end + 3:]

def patch_gd(path, label):
    src = open(path, encoding='utf-8').read()
    orig = src
    if 'const ENEMY_NAME_TO_DATA := {' in src:
        src = regen_enemy_dict(src)
        if label == 'MapNodeScene.gd':
            src = regen_full_names(src)
        for a, b in HELP_LABELS:
            src = src.replace(a, b)
        for a, b in AUX_NAME_MAP.items():
            src = src.replace('"%s"' % a, '"%s"' % b)
    for a, b in MAPS_DESC.items():
        src = src.replace(a, b)
    src = swap_regions(src)
    if src != orig:
        open(path, 'w', encoding='utf-8').write(src)
        print(f'{label}: patched')
    else:
        print(f'{label}: no change')

def patch_plain(path, label):
    s = open(path, encoding='utf-8').read()
    ns = swap_regions(s)
    if ns != s:
        open(path, 'w', encoding='utf-8').write(ns)
        print(f'{label}: patched')
    else:
        print(f'{label}: no change')

if __name__ == '__main__':
    do_enemies()
    do_materials()
    do_aux()
    do_decks()
    P = ROOT + '\\'
    patch_gd(P + 'MapNodeScene.gd', 'MapNodeScene.gd')
    patch_gd(P + 'Exploration.gd', 'Exploration.gd')
    patch_plain(P + 'Global.gd', 'Global.gd')
    patch_plain(P + 'CircuitManager.gd', 'CircuitManager.gd')
    patch_plain(P + 'PlayerManager.gd', 'PlayerManager.gd')
    patch_plain(P + 'Exploration.tscn', 'Exploration.tscn')
