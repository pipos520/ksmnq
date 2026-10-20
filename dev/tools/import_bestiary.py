# -*- coding: utf-8 -*-
"""异兽图鉴数据导入（任务 B）：Docs/异兽图鉴与掉落设计.md → Data/*.json
解析 §6.1-6.3（54 怪+1 BOSS）、§11.1-11.3（18 素材+36 辅材+21 怪），
写入 enemies.json / aux_items.json / materials.json。幂等：已存在的 id 跳过。
"""
import json, re, sys

DOC = 'Docs/异兽图鉴与掉落设计.md'
doc = open(DOC, encoding='utf-8').read()

ELEM_EMOJI = {'风': '🍃', '暗': '🌑', '水': '💧', '地': '🪨', '光': '✨', '火': '🔥', '无': '🌀'}

def load(p):
    return json.load(open(p, encoding='utf-8'))

def save(p, o):
    json.dump(o, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

# ---------- 解析工具 ----------
def parse_monster_tables(text, section_start, section_end, id_prefix):
    """解析 | ID | 名称 | 地形 | level | hp | element | aux_drops | desc | 表格"""
    seg = text.split(section_start)[1].split(section_end)[0] if section_end in text else text.split(section_start)[1]
    rows = []
    for line in seg.splitlines():
        line = line.strip()
        if not line.startswith('|') or line.startswith('|--') or 'id' in line.split('|')[1] or '----' in line:
            continue
        cells = [c.strip() for c in line.strip('|').split('|')]
        if len(cells) < 8 or not cells[0].startswith(id_prefix):
            continue
        drops = []
        for m in re.finditer(r'(AU\d+)\s*([^\s/（(]*)(?:（([\d.]+)）)?', cells[6]):
            prob = float(m.group(3)) if m.group(3) else 0.05
            drops.append({'id': m.group(1), 'name': m.group(2), 'prob': prob})
        rows.append({'id': cells[0], 'name': cells[1], 'terrain': cells[2],
                     'level': int(cells[3]), 'hp': int(cells[4]), 'element': cells[5],
                     'drops': drops, 'desc': cells[7]})
    return rows

# ---------- 1. 普通怪 54 + SS_BOSS_1 ----------
monsters = []
monsters += parse_monster_tables(doc, '### 6.1 风暴高塔', '### 6.2', 'ST_')
monsters += parse_monster_tables(doc, '### 6.2 暗影沼泽', '### 6.3', 'SS_')
monsters += parse_monster_tables(doc, '### 6.3 传说遗迹', '## 7.', 'LR_')

# SS_BOSS_1（§6.2 末段固定文本）
ss_boss = {'id': 'SS_BOSS_1', 'name': '渊母·沉沦之怀', 'level': 50, 'hp': 250,
           'element': '暗', 'terrain': '',
           'drops': [{'id': 'AU124', 'name': '蚀根瘤', 'prob': 0.08}, {'id': 'AU148', 'name': '视者瞳', 'prob': 0.08}],
           'desc': '沼泽最深处的母体，一切渊蚀根系的源头。', 'is_boss': True}

# ---------- 2. 高级怪 21（§11.3）----------
vr = parse_monster_tables(doc, '### 11.3 高级敌人', '**BOSS 三变体', 'VR_')
monsters += vr
# VR BOSS 三变体（注意：'**BOSS 三变体' 在 §1.3 有更早引用，必须用带参数的键）
vr_boss_seg = doc.split('**BOSS 三变体（层 14 层末')[1].split('### 11.4')[0]
for line in vr_boss_seg.splitlines():
    line = line.strip()
    if not line.startswith('| VR_BOSS'):
        continue
    cells = [c.strip() for c in line.strip('|').split('|')]
    drops = []
    for m in re.finditer(r'(AU\d+)（([\d.]+)）', cells[5]):
        drops.append({'id': m.group(1), 'prob': float(m.group(2))})
    monsters.append({'id': cells[0], 'name': cells[1], 'level': 75, 'hp': 375,
                     'element': cells[2], 'drops': drops, 'desc': cells[6], 'is_boss': True, 'terrain': ''})

# ---------- 3. AU 辅材定义 ----------
aux_defs = {}

def aux_effect_for(au_num):
    """AU78-185 规则化效果（零新效果类型，稀有档数值，平衡表 §11.2 档位表）"""
    elems = ['火', '水', '风', '地', '光', '暗']
    cycle = [
        ('boost', {'atk_bonus': 2}, '攻击强化'),
        ('boost', {'hp_bonus': 3}, '生命强化'),
        ('protect', {'shield': 3}, '护盾'),
        ('element', {'element': elems[au_num % 6], 'element_power': 0.15}, '元素增幅'),
        ('special', {'energy_reduce': 1}, '能量减免'),
    ]
    t, eff, cn = cycle[au_num % len(cycle)]
    return t, eff, cn

# 从 §6 表格收集 AU78-149（名称在掉落列）
seg6 = doc.split('### 6.1')[1].split('## 7.')[0]
for m in re.finditer(r'(AU\d+)\s+([\u4e00-\u9fff]{2,6})', seg6):
    aux_defs[m.group(1)] = m.group(2)
# §11.3 掉落列 AU186-221 只有编号（名称在 §11.2 绑定表）
# 绑定表：| 来源怪 | AU186 嵌卡残基（boost·atk 4） | AU187 ... |
# element 类是中文属性（element·光·0.25），kind 后的段允许任意非·）字符
hi_aux = {}
bind_seg = doc.split('**绑定表**（每怪 2 个')[1].split('### 11.3')[0]
for line in bind_seg.splitlines():
    if not line.strip().startswith('|'):
        continue
    for m in re.finditer(r'(AU\d+)\s+([\u4e00-\u9fff]{2,6})（([a-z]+)·([^·）]+?)(?:·([\d.]+))?）', line):
        au, name, typ, field, val = m.group(1), m.group(2), m.group(3), m.group(4).strip(), m.group(5)
        # "boost·atk 4" 的值跟在空格后（element·光·0.25 的值在第三个·后）
        if ' ' in field and not val:
            field, val = field.split(' ', 1)
        hi_aux[au] = {'name': name, 'type': typ, 'field': field, 'val': val}
# §11.3 掉落列里的 AU 名称兜底
for row in vr:
    for d in row['drops']:
        hi_aux.setdefault(d['id'], None)

def build_aux(au):
    num = int(au[2:])
    if num >= 186 and au in hi_aux and hi_aux[au]:
        spec = hi_aux[au]
        rarity = '史诗' if num <= 203 else '传说'
        f = spec['field']
        v = spec['val']
        if f.replace('.', '', 1).isdigit():
            v = f  # "poison·2"：类型即字段，数值在字段位
            f = spec['type']
        if spec['type'] == 'element':
            effect = {'element': f, 'element_power': float(v or 0.25)}
        elif f == 'atk':
            effect = {'atk_bonus': int(float(v or 4))}
        elif f == 'hp':
            effect = {'hp_bonus': int(float(v or 5))}
        elif f == 'shield':
            effect = {'shield': int(float(v or 4))}
        elif f == 'damage_reduce':
            effect = {'damage_reduce': int(float(v or 2))}
        elif f == 'energy_reduce':
            effect = {'energy_reduce': int(float(v or 1))}
        elif f == 'revive':
            effect = {'revive_chance': float(v or 0.6)}
        elif f == 'poison':
            effect = {'poison': int(float(v or 2))}
        else:
            effect = {f: 1}  # haste/combo 布尔型
        return {'id': au, 'name': spec['name'], 'type': spec['type'], 'rarity': rarity,
                'description': '%s，虚渊高级辅材（%s）' % (spec['name'], rarity), 'effect': effect}
    # AU78-185：规则化稀有档
    if num >= 78:
        t, eff, cn = aux_effect_for(num)
        return {'id': au, 'name': aux_defs.get(au, au), 'type': t, 'rarity': '稀有',
                'description': '%s，来自深层裂隙异兽的辅材（%s）' % (aux_defs.get(au, au), cn), 'effect': eff}
    return None

# ---------- 4. 敌 deck：从现有怪取最近等级的 deck ----------
enemies = load('Data/enemies.json')
existing = []
for mid, m in enemies['maps'].items():
    for tname, tdata in m.get('terrains', {}).items():
        for mo in tdata.get('monsters', []):
            existing.append((mo.get('level', 1), mo.get('deck', [])))
    for b in m.get('boss', []):
        existing.append((b.get('level', 1), b.get('deck', [])))
existing.sort(key=lambda x: x[0])

def deck_for(level):
    best = min(existing, key=lambda x: abs(x[0] - level)) if existing else (1, [])
    return list(best[1])

# ---------- 5. 写 enemies.json ----------
REGION_OF = {'ST_': 'storm_tower', 'SS_': 'shadow_swamp', 'LR_': 'legendary_ruins', 'VR_': 'void_rift'}
def region_of(id_):
    for p, r in REGION_OF.items():
        if id_.startswith(p):
            return r
    return ''

added_m = 0
for row in monsters:
    rid = region_of(row['id'])
    if rid not in enemies['maps']:
        enemies['maps'][rid] = {'name': {'storm_tower': '风暴高塔', 'shadow_swamp': '暗影沼泽',
                                          'legendary_ruins': '传说遗迹', 'void_rift': '渊门之后'}[rid],
                                 'terrains': {}, 'boss': []}
    mp = enemies['maps'][rid]
    emoji = '👑 ' if row.get('is_boss') else ELEM_EMOJI.get(row['element'], '') + ' '
    mo = {'id': row['id'], 'name': emoji + row['name'], 'level': row['level'],
          'hp': row['hp'], 'max_hp': row['hp'],
          'energy': 4 if row.get('is_boss') else 3, 'max_energy': 4 if row.get('is_boss') else 3,
          'element': row['element'], 'desc': row['desc'],
          'aux_drops': [{'id': d['id'], 'prob': d.get('prob', 0.05)} for d in row['drops']],
          'deck': deck_for(row['level'])}
    if row.get('is_boss'):
        if not any(b['id'] == row['id'] for b in mp['boss']):
            mp['boss'].append(mo)
            added_m += 1
    else:
        tname = row['terrain']
        if tname not in mp['terrains']:
            mp['terrains'][tname] = {'monsters': [], 'gather': []}
        if not any(x['id'] == row['id'] for x in mp['terrains'][tname]['monsters']):
            mp['terrains'][tname]['monsters'].append(mo)
            added_m += 1
# SS_BOSS_1
mp = enemies['maps']['shadow_swamp']
emoji = '👑 '
mo = {'id': ss_boss['id'], 'name': emoji + ss_boss['name'], 'level': ss_boss['level'],
      'hp': ss_boss['hp'], 'max_hp': ss_boss['hp'], 'energy': 4, 'max_energy': 4,
      'element': ss_boss['element'], 'desc': ss_boss['desc'],
      'aux_drops': [{'id': d['id'], 'prob': d['prob']} for d in ss_boss['drops']],
      'deck': deck_for(ss_boss['level'])}
if not any(b['id'] == 'SS_BOSS_1' for b in mp['boss']):
    mp['boss'].append(mo)
    added_m += 1

# SS/ST/LR 既有 BOSS（enemies.json 历史上只有迷雾/火焰两张图，其余 BOSS 活在
# MapNodeScene 内联表）→ 从内联表抽取合并进 enemies.json，图鉴/掉落走统一数据源
gd = open('MapNodeScene.gd', encoding='utf-8').read()
inline_pat = re.compile(r'"[^"]*": \{"id": "((?:ST|SS|LR)_BOSS_\d)", "level": (\d+), "hp": (\d+), "element": "([^"]+)", "desc": "([^"]+)", "aux_drops": \[([^\]]*)\]')
for m in inline_pat.finditer(gd):
    bid, lvl, hp, elem, desc, drops_raw = m.groups()
    rid = REGION_OF[bid[:3]]
    mp2 = enemies['maps'].setdefault(rid, {'name': rid, 'terrains': {}, 'boss': []})
    if any(b['id'] == bid for b in mp2['boss']):
        continue
    aux_drops = [{'id': d, 'prob': 0.08} for d in re.findall(r'"(AU\d+)"', drops_raw)]
    mp2['boss'].append({'id': bid, 'name': '👑 ' + bid.split('_')[0] + '之主',
                        'level': int(lvl), 'hp': int(hp), 'max_hp': int(hp),
                        'energy': 4, 'max_energy': 4, 'element': elem, 'desc': desc,
                        'aux_drops': aux_drops, 'deck': deck_for(int(lvl))})
    added_m += 1

# ST BOSS 掉落洞补全（§6.1 末段）：雷电/风暴/云龙 绑 AU102/AU106 0.08
for b in enemies['maps']['storm_tower']['boss']:
    if b['id'].startswith('ST_BOSS') and len(b.get('aux_drops', [])) == 0:
        b['aux_drops'] = [{'id': 'AU102', 'prob': 0.08}, {'id': 'AU106', 'prob': 0.08}]
# SS_BOSS 掉落同绑（沼泽/毒雾 同绑）
for b in enemies['maps']['shadow_swamp']['boss']:
    if b['id'].startswith('SS_BOSS') and len(b.get('aux_drops', [])) == 0:
        b['aux_drops'] = [{'id': 'AU124', 'prob': 0.08}, {'id': 'AU148', 'prob': 0.08}]
# LR BOSS 掉落洞修复（文档未给绑定表，绑传说遗迹最高档 AU184/AU185 [PLACEHOLDER]）
for b in enemies['maps']['legendary_ruins']['boss']:
    if b['id'].startswith('LR_BOSS') and len(b.get('aux_drops', [])) == 0:
        b['aux_drops'] = [{'id': 'AU184', 'prob': 0.08}, {'id': 'AU185', 'prob': 0.08}]

# ---------- 6. 写 aux_items.json ----------
# AU78+ 全部为脚本产物：先清掉历史写入（含早期版本的坏数据）再全量重建，保证幂等干净
aux = load('Data/aux_items.json')
aux['aux_items'] = [a for a in aux['aux_items'] if int(a['id'][2:]) < 78]
have = {a['id'] for a in aux['aux_items']}
added_a = 0
for au in sorted(set(list(aux_defs.keys()) + list(hi_aux.keys()))):
    if au in have:
        continue
    d = build_aux(au)
    if d:
        aux['aux_items'].append(d)
        added_a += 1

# ---------- 7. 写 materials.json（§11.1 18 件虚渊素材）----------
mats = load('Data/materials.json')
CAT = {'F': 'fiber', 'M': 'mineral', 'R': 'resin', 'E': 'extract', 'P': 'pigment', 'B': 'binder'}
seg11 = doc.split('### 11.1')[1].split('### 11.2')[0]
added_mat = 0
have_mat = {x['id'] for lst in mats['materials'].values() for x in lst}
for line in seg11.splitlines():
    line = line.strip()
    m = re.match(r'\| ([FMR EPB]\d{2}) \| ([\u4e00-\u9fff]{2,6}) \| (.*?) \| (.*?) \| (\w+), ([\d.]+) \|', line)
    if not m:
        continue
    mid, name, attrs, tendency, terrain, prob = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6)
    if mid in have_mat:
        continue
    cat = CAT[mid[0]]
    item = {'id': mid, 'name': name, 'rarity': '传说', 'area': '虚渊深层',
            'gather': {'void_rift': [{'terrain': terrain, 'min': 1, 'max': 1, 'prob': float(prob)}]}}
    for pair in attrs.split(' / '):
        k, v = pair.split()
        item[k] = int(v)
    if tendency and tendency != '—':
        tm = re.match(r'([\u4e00-\u9fff])(\d)', tendency)
        if tm:
            item['tendency'] = tm.group(1) + tm.group(2)
    mats['materials'][cat].append(item)
    added_mat += 1

save('Data/enemies.json', enemies)
save('Data/aux_items.json', aux)
save('Data/materials.json', mats)
print('新增怪:', added_m, ' 新增辅材:', added_a, ' 新增素材:', added_mat)
print('boss 分布:', {mid: len(m['boss']) for mid, m in enemies['maps'].items()})
