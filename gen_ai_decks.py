# -*- coding: utf-8 -*-
import json, copy, shutil, datetime

# 加载现有AI卡组 + 卡包
decks=json.load(open('Data/local_ai_decks.json',encoding='utf-8'))
packs=json.load(open('Data/local_card_packs.json',encoding='utf-8'))

# 备份
ts=datetime.datetime.now().strftime('%Y%m%d%H%M%S')
bak=f'Data/local_ai_decks.backup_{ts}.json'
shutil.copy('Data/local_ai_decks.json',bak)
print('备份:',bak)

# pack_id -> 卡组名映射
THEMES={
    'syjy_qw':'AI·灰冠墟',
    'syjy_wf':'AI·万法之塔',
    'syjy_sg':'AI·圣光教廷',
    'syjy_sy':'AI·深渊猎魔',
    'syjy_lj':'AI·龙脊山脉',
    'syjy_yl':'AI·幽语林',
    'syjy_hs':'AI·灰色地带',
    'syjy_sd':'AI·三约松动',
    'wq_shoutan':'AI·手谈围棋',
    'nbd_rl':'AI·热恋期日常',
}

# pack_id -> pack_data.cards
pack_map={p.get('pack_id',''):p.get('pack_data',{}).get('cards',[]) for p in packs}

def build_deck(cards):
    """按规则把 N 种卡组满30张：1费x3，2-3费x2，4费及以上x1，直到凑满30"""
    # 按cost分组
    by_cost={}
    for c in cards:
        by_cost.setdefault(c.get('cost',0),[]).append(c)
    deck=[]
    # 第一遍：低费重复
    # 1费x3, 2费x2, 3费x2, 4+x1
    def cnt(cost):
        if cost<=1: return 3
        if cost<=3: return 2
        return 1
    for cost in sorted(by_cost.keys()):
        for c in by_cost[cost]:
            deck.extend([copy.deepcopy(c)]*cnt(cost))
    # 若超出30，从高费开始裁掉多余的
    while len(deck)>30:
        # 找到当前卡组中 cost 最高且数量>1 的卡，减一张
        for cost in sorted(by_cost.keys(),reverse=True):
            group=[c for c in by_cost[cost]]
            names=[c.get('name','') for c in group]
            # 在deck里找该cost的最后一个重复项删掉
            for n in names:
                idxs=[i for i,c in enumerate(deck) if c.get('cost',0)==cost and c.get('name','')==n]
                if len(idxs)>1:
                    deck.pop(idxs[-1]); break
            else:
                continue
            break
        else:
            break
    # 若不足30，从低费开始补重复
    while len(deck)<30:
        added=False
        for cost in sorted(by_cost.keys()):
            for c in by_cost[cost]:
                deck.append(copy.deepcopy(c)); added=True
                if len(deck)>=30: break
            if len(deck)>=30: break
        if not added: break
    # 按cost排序
    deck.sort(key=lambda c:(c.get('cost',0),c.get('name','')))
    return deck

# 现有最大 id
max_id=max(d.get('id',0) for d in decks)
existing_names={d.get('deck_data',{}).get('name','') for d in decks}
added=0
for pid,dname in THEMES.items():
    if dname in existing_names:
        print('跳过(已存在):',dname); continue
    cards=pack_map.get(pid,[])
    if not cards:
        print('⚠️ 卡包无卡:',pid); continue
    deck_cards=build_deck(cards)
    max_id+=1
    newdeck={
        "id": max_id,
        "player_id": "ai_opponent",
        "deck_data": {
            "name": dname,
            "card_datas": deck_cards
        }
    }
    decks.append(newdeck)
    added+=1
    print(f'✅ 生成 {dname}: {len(deck_cards)}张 (来源{len(cards)}种卡)')

json.dump(decks,open('Data/local_ai_decks.json','w',encoding='utf-8'),ensure_ascii=False,indent=2)
print(f'\\n完成! 新增 {added} 套, 总卡组数: {len(decks)}')
