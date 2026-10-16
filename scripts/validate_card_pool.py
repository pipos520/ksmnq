#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""卡池数据校验脚本。

校验 Data/local_card_packs.json（正式卡池）的字段合法性：
  1. 必填字段是否存在且类型正确
  2. element / quality / star 是否在白名单内
  3. cost 是否落在该 star 的合法区间
  4. atk / hp 是否为合法整数
  5. effects 里的 action / trigger / target / condition / constraint 编码
     是否都在 Global.gd 的电路注册表里（白名单从 Global.gd 动态解析，避免漂移）
  6. action × target 是否踩到 Global.gd 声明的互斥对
  7. id 是否在全池/单包内重复

用法：
    python3 scripts/validate_card_pool.py
    python3 scripts/validate_card_pool.py --file Data/local_card_packs.json
    python3 scripts/validate_card_pool.py --fix-report  # 只统计，不检查互斥对

退出码：0 = 无 ERROR，1 = 存在 ERROR。WARNING 不影响退出码。
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict


# 元素白名单：来自 Global.gd 的 get_element_affinity() 属性表
ELEMENTS = {"无", "火", "风", "地", "水", "光", "暗"}

# 品质白名单：来自 CardDragController.gd 的 TRAIL_COLORS 与卡池实际取值
QUALITIES = {"废品", "瑕疵", "标准", "精良", "卓越", "完美"}

# 每张卡的 star 允许 cost 区间（下界/上界）。
# 上界取自卡池现存分布，下界按"星级不弱于费用"的设计约束。
STAR_COST_RANGE = {1: (1, 6), 2: (2, 9), 3: (3, 10)}

STAR_ALLOWED = {1, 2, 3}


def _strip_comment(line: str) -> str:
    """去掉 GDScript 行尾注释，保留字符串内的 #。"""
    out = []
    in_str = False
    quote = ""
    for ch in line:
        if in_str:
            out.append(ch)
            if ch == quote:
                in_str = False
        elif ch in ('"', "'"):
            in_str = True
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out)


def _parse_circuit_block(global_src: str, block_name: str):
    """从 Global.gd 解析某个电路注册表块里的 id 列表（跳过注释行）。"""
    pat = re.compile(r"^var\s+" + re.escape(block_name) + r"\s*:=", re.MULTILINE)
    m = pat.search(global_src)
    if not m:
        return set(), "block not found: %s" % block_name
    start = m.start()
    end = global_src.find("\n]", start)
    if end < 0:
        end = global_src.find("\n}\n", start)
    if end < 0:
        return set(), "unterminated block: %s" % block_name
    block = global_src[start:end]
    ids = set()
    for line in block.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        cleaned = _strip_comment(line)
        for hit in re.findall(r'"id"\s*:\s*"([A-Za-z0-9_]+)"', cleaned):
            ids.add(hit)
    return ids, None


def _parse_mutex_pairs(global_src: str) -> set:
    """解析 Global.gd 的 action_target_pairs 互斥对。"""
    pat = re.compile(r'"action_target_pairs"\s*:\s*\[', re.MULTILINE)
    m = pat.search(global_src)
    if not m:
        return set()
    end = global_src.find("\n\t]", m.start())
    if end < 0:
        return set()
    block = global_src[m.start():end]
    pairs = set()
    for line in block.splitlines():
        cleaned = _strip_comment(line)
        hit = re.match(r'\s*\[\s*"(A\d+)"\s*,\s*"(T\d+)"\s*\]', cleaned)
        if hit:
            pairs.add((hit.group(1), hit.group(2)))
    return pairs


def load_whitelists(global_path: str):
    """从 Global.gd 动态读取电路白名单与互斥对。"""
    err = None
    if os.path.exists(global_path):
        with open(global_path, encoding="utf-8") as f:
            src = f.read()
        sets = {}
        for block, key in (
            ("circuit_triggers", "triggers"),
            ("circuit_conditions", "conditions"),
            ("circuit_actions", "actions"),
            ("circuit_targets", "targets"),
            ("circuit_constraints", "constraints"),
        ):
            ids, blk_err = _parse_circuit_block(src, block)
            sets[key] = ids
            if blk_err:
                err = blk_err
        mutex = _parse_mutex_pairs(src)
        if mutex:
            return sets, mutex, err
        return sets, set(), err
    return (
        {"triggers": set(), "conditions": set(), "actions": set(),
         "targets": set(), "constraints": set()},
        set(),
        "Global.gd not found at %s" % global_path,
    )


def load_packs(path: str):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    packs = []
    for pack in data:
        if not isinstance(pack, dict):
            continue
        pd = pack.get("pack_data") or {}
        cards = pd.get("cards") or []
        packs.append({
            "pack_id": pack.get("pack_id", ""),
            "name": pd.get("name", ""),
            "cards": [c for c in cards if isinstance(c, dict)],
        })
    return packs


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def validate(packs, wl, mutex, check_mutex=True):
    """返回 (errors, warnings, infos)。每条是 (location, message)。"""
    errors = []
    warnings = []
    infos = []
    seen_ids = defaultdict(list)

    for pack in packs:
        pid = pack["pack_id"] or pack["name"] or "<unknown pack>"
        for idx, card in enumerate(pack["cards"]):
            cid = str(card.get("id", ""))
            loc = "%s / %s[%d]" % (pid, cid or card.get("name", "?"), idx)

            for key in ("id", "name", "element", "quality", "star", "cost", "atk", "hp"):
                if key not in card:
                    errors.append((loc, "缺少必填字段 %r" % key))
            for key in ("desc", "fields", "effects"):
                if key not in card:
                    infos.append((loc, "缺少可选字段 %r" % key))

            if not cid:
                continue
            seen_ids[cid].append(pid)

            element = card.get("element", "")
            if element not in ELEMENTS:
                errors.append((loc, "未知元素 %r（合法：%s）"
                               % (element, "、".join(sorted(ELEMENTS)))))

            quality = card.get("quality", "")
            if quality not in QUALITIES:
                errors.append((loc, "未知品质 %r（合法：%s）"
                               % (quality, "、".join(sorted(QUALITIES)))))

            star = card.get("star")
            if not _is_int(star) or star not in STAR_ALLOWED:
                errors.append((loc, "star 非法：%r（应为 1/2/3）" % (star,)))
            else:
                cost = card.get("cost")
                lo, hi = STAR_COST_RANGE[star]
                if not _is_int(cost):
                    errors.append((loc, "cost 非整数：%r" % (cost,)))
                elif cost < 0:
                    errors.append((loc, "cost 为负：%d" % cost))
                elif cost > hi:
                    errors.append((loc, "cost %d 超出 star%d 上限 %d" % (cost, star, hi)))
                elif cost < lo:
                    warnings.append((loc, "cost %d 低于 star%d 下限 %d（低费高阶卡）"
                                     % (cost, star, lo)))

            for key in ("atk", "hp"):
                v = card.get(key)
                if not _is_int(v):
                    errors.append((loc, "%s 非整数：%r" % (key, v)))
                elif v < 0:
                    errors.append((loc, "%s 为负：%d" % (key, v)))

            fields = card.get("fields")
            if fields is not None:
                if not isinstance(fields, list):
                    errors.append((loc, "fields 应为数组"))
                else:
                    for fi, f in enumerate(fields):
                        if not isinstance(f, str) or not f.strip():
                            errors.append((loc, "fields[%d] 非法：%r" % (fi, f)))

            effects = card.get("effects")
            if effects is not None:
                if not isinstance(effects, list):
                    errors.append((loc, "effects 应为数组"))
                else:
                    for ei, eff in enumerate(effects):
                        if not isinstance(eff, dict):
                            errors.append((loc, "effects[%d] 不是对象" % ei))
                            continue
                        for kind in ("action", "trigger", "target"):
                            val = eff.get(kind)
                            if val is None:
                                warnings.append((loc, "effects[%d] 缺少 %s" % (ei, kind)))
                                continue
                            kind_key = kind + "s"
                            known = wl.get(kind_key, set())
                            if not known:
                                continue
                            if val not in known:
                                msg = "effects[%d].%s=%r 不在电路注册表中" % (ei, kind, val)
                                if kind == "target":
                                    # T01（自身）在注册表里被注释掉，但引擎按默认值使用
                                    if val == "T01":
                                        warnings.append((loc, msg + "（引擎默认值，保留兼容）"))
                                        continue
                                errors.append((loc, msg))
                        cond = eff.get("condition")
                        if cond and wl.get("conditions") and cond not in wl["conditions"]:
                            errors.append((loc, "effects[%d].condition=%r 不在注册表中"
                                           % (ei, cond)))
                        cons = eff.get("constraints")
                        if isinstance(cons, list) and wl.get("constraints"):
                            for ci, c in enumerate(cons):
                                if c not in wl["constraints"]:
                                    errors.append((loc, "effects[%d].constraints[%d]=%r 不在注册表中"
                                                   % (ei, ci, c)))
                        if check_mutex and mutex:
                            act = eff.get("action")
                            tgt = eff.get("target")
                            if (act, tgt) in mutex:
                                errors.append((loc, "effects[%d] 动作×目标互斥：%s × %s"
                                               % (ei, act, tgt)))

    for cid, owners in seen_ids.items():
        if len(owners) > 1:
            errors.append(("<cross-pack>", "id 重复：%s 出现在 %s"
                           % (cid, "、".join(sorted(set(owners))))))
    return errors, warnings, infos


def main():
    parser = argparse.ArgumentParser(description="校验卡池 JSON 数据合法性")
    parser.add_argument("--file", default="Data/local_card_packs.json",
                        help="卡池 JSON 路径（默认 Data/local_card_packs.json）")
    parser.add_argument("--global-gd", dest="global_gd", default="Global.gd",
                        help="Global.gd 路径，用于动态解析电路白名单")
    parser.add_argument("--skip-mutex", action="store_true",
                        help="跳过 action×target 互斥检查")
    parser.add_argument("--verbose", action="store_true",
                        help="同时打印 INFO 级提示（缺少可选字段等）")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    wl, mutex, wl_err = load_whitelists(args.global_gd)
    packs = load_packs(args.file)

    print("=" * 72)
    print("卡池校验：%s" % args.file)
    total = sum(len(p["cards"]) for p in packs)
    print("包数量：%d  卡总数：%d" % (len(packs), total))
    print("电路注册表：triggers=%d conditions=%d actions=%d targets=%d constraints=%d 互斥对=%d"
          % (len(wl["triggers"]), len(wl["conditions"]), len(wl["actions"]),
             len(wl["targets"]), len(wl["constraints"]), len(mutex)))
    if wl_err:
        print("[!] 白名单解析告警：%s" % wl_err)
        print("    编码合法性检查将跳过，仅做字段/数值/重复检查")
    print("=" * 72)

    errors, warnings, infos = validate(packs, wl, mutex, check_mutex=not args.skip_mutex)

    print("\n-- ERROR (%d) --" % len(errors))
    for loc, msg in errors:
        print("  [%s] %s" % (loc, msg))

    print("\n-- WARNING (%d) --" % len(warnings))
    for loc, msg in warnings:
        print("  [%s] %s" % (loc, msg))

    if args.verbose:
        print("\n-- INFO (%d) --" % len(infos))
        for loc, msg in infos:
            print("  [%s] %s" % (loc, msg))

    print("\n-- 分布 --")
    ecnt, qcnt, scnt, ccnt = Counter(), Counter(), Counter(), Counter()
    for p in packs:
        for c in p["cards"]:
            ecnt[c.get("element")] += 1
            qcnt[c.get("quality")] += 1
            scnt[c.get("star")] += 1
            if c.get("star") in STAR_COST_RANGE:
                ccnt[c.get("cost")] += 1
    print("  元素  : %s" % dict(sorted(ecnt.items())))
    print("  品质  : %s" % dict(sorted(qcnt.items(), key=lambda kv: str(kv[0]))))
    print("  星级  : %s" % dict(sorted(scnt.items(), key=lambda kv: str(kv[0]))))
    print("  费用  : %s" % dict(sorted(ccnt.items(), key=lambda kv: str(kv[0]))))

    print("\n%s" % ("OK：无 ERROR" if not errors else "FAIL：%d 个 ERROR 待修复" % len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
