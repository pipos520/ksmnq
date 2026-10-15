# -*- coding: utf-8 -*-
import json, os, shutil, datetime
from collections import Counter
ROOT='/storage/emulated/0/Documents/ksmnqsp'
DOC='/storage/emulated/0/Documents/卡师模拟器卡牌世界设计文档'
d=json.load(open(ROOT+'/Data/local_card_packs.json',encoding='utf-8'))
cc_map={}
for p in d:
    pid=p.get('pack_id') or p.get('id')
    cards=p.get('pack_data',{}).get('cards',[])
    cc_map[pid]=Counter(c.get('cost',0) for c in cards)
def seq(cc):
    return ', '.join('%d费×%d'%x for x in sorted(cc.items()))
def maxc(cc): return max(cc) if cc else 0
plan=[
 ('三约纪元/卡包设计_三约纪元.txt',['syjy_qw','syjy_wf','syjy_sg','syjy_sy','syjy_lj','syjy_yl','syjy_hs','syjy_sd']),
 ('围棋术语/卡包设计_围棋术语.txt',['wq_shoutan']),
 ('你不对劲/卡包设计_你不对劲.txt',['nbd_rl']),
]
ts=datetime.datetime.now().strftime('%Y%m%d%H%M%S')
bakdir='/sdcard/Download/sync_backup_'+ts
os.makedirs(bakdir,exist_ok=True)
for rel,pids in plan:
    fp=os.path.join(DOC,rel)
    if not os.path.exists(fp): continue
    shutil.copyfile(fp,bakdir+'/'+rel.replace('/','__'))
    lines=open(fp,encoding='utf-8').read().split('\n')
    idx=[i for i,ln in enumerate(lines) if '费用曲线' in ln]
    for k,i in enumerate(idx):
        if k>=len(pids): break
        cc=cc_map.get(pids[k])
        if not cc: continue
        lines[i]='- 费用曲线：'+seq(cc)+' — 上限%d，平滑'%maxc(cc)
        print('%s %s -> %s'%(rel,pids[k],lines[i]))
    open(fp,'w',encoding='utf-8').write('\n'.join(lines))
print('备份:',bakdir)