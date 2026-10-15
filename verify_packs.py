# -*- coding: utf-8 -*-
# 校验 local_card_packs.json 全部卡包：枚举合法性 / id唯一性 / 主题聚合 / 结构完整性
import json, sys
from collections import Counter, defaultdict

TR_OK = {'TR01','TR06','TR09','TR10','TR11','TR12','TR13','TR14','TR15','TR16','TR17','TR18'}
A_OK  = {'A01','A02','A03','A06','A07','A09','A20','A21','A23','A25','A31','A32','A33'}
T_OK  = {'T02','T03','T04','T05','T06','T10','T13','T14','T15','T16'}
EL_OK = {'火','水','风','地','光','暗'}
QL_OK = {'标准','精良','卓越','完美'}

data = json.load(open('Data/local_card_packs.json', encoding='utf-8'))
print('总卡包数:', len(data))

# 主题聚合（模拟 CardPackShop 逻辑：保持出现顺序去重）
themes = []
for p in data:
    t = p.get('theme', '沧澜古界')
    if t not in themes:
        themes.append(t)
print('主题列表(顺序):', themes)

# 逐包统计
cid_seen = set()
bad = []
total_cards = 0
total_eff = 0
theme_stats = defaultdict(lambda: [0, 0])  # theme -> [包数, 卡数]
for p in data:
    pid = p.get('pack_id')
    pd = p.get('pack_data', {})
    cards = pd.get('cards', [])
    theme_stats[p['theme']][0] += 1
    theme_stats[p['theme']][1] += len(cards)
    # 必须字段
    for req in ('id', 'pack_id', 'pack_data', 'theme'):
        if req not in p:
            bad.append((pid, 'pack缺字段', req))
    if 'name' not in pd or 'cards' not in pd:
        bad.append((pid, 'pack_data缺字段', 'name/cards'))
        continue
    for c in cards:
        total_cards += 1
        cid = c.get('id')
        if cid in cid_seen:
            bad.append((pid, '卡id重复', cid))
        cid_seen.add(cid)
        for fld in ('id','name','atk','hp','cost','star','element','quality','fields','desc'):
            if fld not in c:
                bad.append((pid, '卡缺字段:'+fld, cid or '?'))
        if c.get('element') not in EL_OK: bad.append((pid, 'element非法', c.get('element')))
        if c.get('quality') not in QL_OK: bad.append((pid, 'quality非法', c.get('quality')))
        if c.get('star') not in (1,2,3): bad.append((pid, 'star非法', c.get('star')))
        if c.get('cost', 1) < 1 or c.get('cost', 1) > 10: bad.append((pid, 'cost越界', c.get('cost')))
        for e in c.get('effects', []):
            total_eff += 1
            if e.get('trigger') not in TR_OK: bad.append((pid, c.get('name'), 'trigger非法:'+str(e.get('trigger'))))
            if e.get('action') not in A_OK: bad.append((pid, c.get('name'), 'action非法:'+str(e.get('action'))))
            if e.get('target') not in T_OK: bad.append((pid, c.get('name'), 'target非法:'+str(e.get('target'))))
            if not isinstance(e.get('value'), int): bad.append((pid, c.get('name'), 'value非整数:'+str(e.get('value'))))

print('卡牌总数:', total_cards, '| 效果总数:', total_eff, '| 唯一卡id:', len(cid_seen))
print()
print('=== 主题分布 ===')
for t, (np, nc) in theme_stats.items():
    print('  %-6s %2d包 / %3d张' % (t, np, nc))
print()
if bad:
    print('❌ 发现问题 %d 条:' % len(bad))
    for b in bad[:30]:
        print('  ', b)
    sys.exit(1)
else:
    print('✅ 全部校验通过：枚举合法、id唯一、结构完整')