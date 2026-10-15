import sys
with open("BattleManager.gd") as f:
    s = f.read()

# 1) banish_action T02
old = '\t\t"T02":  # 敌方单体\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\topponent.banish_card(target_card)\n\t\t\t\t\tbanished_cards.append(target_card)\n\t\t\t\t\tprint("  -> 除外敌方 ", target_card.get_display_name())\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\topponent.banish_card(target_card)\n\t\t\t\t\tbanished_cards.append(target_card)\n\t\t\t\t\tprint("  -> 除外敌方 ", target_card.get_display_name())'
if old in s:
    s = s.replace(old, new)
    print("banish T02 OK")
else:
    print("banish T02 NOT FOUND")

# 2) stat_buff T02
old = '\t\t"T02":  # 敌方单体（减益）\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_buff(stat_type, value)\n\t\t\t\t\tprint("  -> 敌方 ", target_card.get_display_name(), " ", stat_type, value)\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_buff(stat_type, value)\n\t\t\t\t\tprint("  -> 敌方 ", target_card.get_display_name(), " ", stat_type, value)'
if old in s:
    s = s.replace(old, new)
    print("stat_buff T02 OK")
else:
    print("stat_buff T02 NOT FOUND")

# 3) stat_buff T03
old = '\t\t"T03":  # 己方单体\n\t\t\tfor i in range(owner.max_field_size):\n\t\t\t\tvar target_card = owner.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_buff(stat_type, value)\n\t\t\t\t\tprint("  -> 己方 ", target_card.get_display_name(), " ", stat_type, "+", value)\n\t\t\t\t\tbreak'
new = '\t\t"T03":  # 己方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < owner.max_field_size:\n\t\t\t\tvar target_card = owner.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_buff(stat_type, value)\n\t\t\t\t\tprint("  -> 己方 ", target_card.get_display_name(), " ", stat_type, "+", value)'
if old in s:
    s = s.replace(old, new)
    print("stat_buff T03 OK")
else:
    print("stat_buff T03 NOT FOUND")

# 4) bounce_to_hand T02
old = '\t\t"T02":  # 敌方单体\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\topponent.field[i] = null\n\t\t\t\t\topponent.hand.append(target_card)\n\t\t\t\t\tbounced_owner = opponent\n\t\t\t\t\tprint("  -> 弹回敌方 ", target_card.get_display_name(), " 到手牌")\n\t\t\t\t\topponent.field_changed.emit()\n\t\t\t\t\topponent.hand_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\topponent.field[target_slot] = null\n\t\t\t\t\topponent.hand.append(target_card)\n\t\t\t\t\tbounced_owner = opponent\n\t\t\t\t\tprint("  -> 弹回敌方 ", target_card.get_display_name(), " 到手牌")\n\t\t\t\t\topponent.field_changed.emit()\n\t\t\t\t\topponent.hand_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("bounce_to_hand T02 OK")
else:
    print("bounce_to_hand T02 NOT FOUND")

# 5) bounce_to_hand T03
old = '\t\t"T03":  # 己方单体\n\t\t\tfor i in range(owner.max_field_size):\n\t\t\t\tvar target_card = owner.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\towner.field[i] = null\n\t\t\t\t\towner.hand.append(target_card)\n\t\t\t\t\tbounced_owner = owner\n\t\t\t\t\tprint("  -> 弹回己方 ", target_card.get_display_name(), " 到手牌")\n\t\t\t\t\towner.field_changed.emit()\n\t\t\t\t\towner.hand_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t"T03":  # 己方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < owner.max_field_size:\n\t\t\t\tvar target_card = owner.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\towner.field[target_slot] = null\n\t\t\t\t\towner.hand.append(target_card)\n\t\t\t\t\tbounced_owner = owner\n\t\t\t\t\tprint("  -> 弹回己方 ", target_card.get_display_name(), " 到手牌")\n\t\t\t\t\towner.field_changed.emit()\n\t\t\t\t\towner.hand_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("bounce_to_hand T03 OK")
else:
    print("bounce_to_hand T03 NOT FOUND")

# 6) bounce_to_deck T02
old = '\t\t"T02":  # 敌方单体\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\topponent.field[i] = null\n\t\t\t\t\topponent.deck.add_card(target_card)\n\t\t\t\t\tbounced_owner = opponent\n\t\t\t\t\tprint("  -> 弹回敌方 ", target_card.get_display_name(), " 到卡组")\n\t\t\t\t\topponent.field_changed.emit()\n\t\t\t\t\topponent.deck_count_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.reset_for_leave_field()\n\t\t\t\t\ttarget_card.is_on_field = false\n\t\t\t\t\ttarget_card.slot_index = -1\n\t\t\t\t\topponent.field[target_slot] = null\n\t\t\t\t\topponent.deck.add_card(target_card)\n\t\t\t\t\tbounced_owner = opponent\n\t\t\t\t\tprint("  -> 弹回敌方 ", target_card.get_display_name(), " 到卡组")\n\t\t\t\t\topponent.field_changed.emit()\n\t\t\t\t\topponent.deck_count_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("bounce_to_deck T02 OK")
else:
    print("bounce_to_deck T02 NOT FOUND")

# 7) send_to_grave_action T02
old = '\t\t"T02":  # 敌方单体\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\topponent.send_to_grave(target_card)\n\t\t\t\t\t_trigger_on_destroy(opponent, target_card, i)\n\t\t\t\t\tprint("  -> 送墓敌方 ", target_card.get_display_name())\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\topponent.send_to_grave(target_card)\n\t\t\t\t\t_trigger_on_destroy(opponent, target_card, target_slot)\n\t\t\t\t\tprint("  -> 送墓敌方 ", target_card.get_display_name())'
if old in s:
    s = s.replace(old, new)
    print("send_to_grave T02 OK")
else:
    print("send_to_grave T02 NOT FOUND")

# 8) temp_stat_change T02
old = '\t\t"T02":  # 敌方单体\n\t\t\tfor i in range(opponent.max_field_size):\n\t\t\t\tvar target_card = opponent.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_temp_buff(stat, value)\n\t\t\t\t\tprint("  -> 敌方 ", target_card.get_display_name(), " 回合内", stat, value)\n\t\t\t\t\tbreak'
new = '\t\t"T02":  # 敌方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < opponent.max_field_size:\n\t\t\t\tvar target_card = opponent.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_temp_buff(stat, value)\n\t\t\t\t\tprint("  -> 敌方 ", target_card.get_display_name(), " 回合内", stat, value)'
if old in s:
    s = s.replace(old, new)
    print("temp_stat_change T02 OK")
else:
    print("temp_stat_change T02 NOT FOUND")

# 9) temp_stat_change T03
old = '\t\t"T03":  # 己方单体\n\t\t\tfor i in range(owner.max_field_size):\n\t\t\t\tvar target_card = owner.field[i]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_temp_buff(stat, value)\n\t\t\t\t\tprint("  -> 己方 ", target_card.get_display_name(), " 回合内", stat, value)\n\t\t\t\t\tbreak'
new = '\t\t"T03":  # 己方单体（使用预解析的槽位）\n\t\t\tif target_slot >= 0 and target_slot < owner.max_field_size:\n\t\t\t\tvar target_card = owner.field[target_slot]\n\t\t\t\tif target_card != null and target_card.is_alive():\n\t\t\t\t\ttarget_card.add_temp_buff(stat, value)\n\t\t\t\t\tprint("  -> 己方 ", target_card.get_display_name(), " 回合内", stat, value)'
if old in s:
    s = s.replace(old, new)
    print("temp_stat_change T03 OK")
else:
    print("temp_stat_change T03 NOT FOUND")

# 10) swap_atk_hp T02
old = '\t\t\tfor i in range(target.max_field_size):\n\t\t\t\tvar card = target.field[i]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tvar old_atk = card.current_atk\n\t\t\t\t\tvar old_hp = card.current_hp\n\t\t\t\t\tcard.base_atk = old_hp\n\t\t\t\t\tcard.base_hp = old_atk\n\t\t\t\t\tcard.current_atk = old_hp\n\t\t\t\t\tcard.current_hp = old_atk\n\t\t\t\t\tprint("  -> 交换攻防: ", card.get_display_name(), " (", old_atk, "/", old_hp, " -> ", card.current_atk, "/", card.current_hp, ")")\n\t\t\t\t\ttarget.field_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t\tif target_slot >= 0 and target_slot < target.max_field_size:\n\t\t\t\tvar card = target.field[target_slot]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tvar old_atk = card.current_atk\n\t\t\t\t\tvar old_hp = card.current_hp\n\t\t\t\t\tcard.base_atk = old_hp\n\t\t\t\t\tcard.base_hp = old_atk\n\t\t\t\t\tcard.current_atk = old_hp\n\t\t\t\t\tcard.current_hp = old_atk\n\t\t\t\t\tprint("  -> 交换攻防: ", card.get_display_name(), " (", old_atk, "/", old_hp, " -> ", card.current_atk, "/", card.current_hp, ")")\n\t\t\t\t\ttarget.field_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("swap_atk_hp OK")
else:
    print("swap_atk_hp NOT FOUND")

# 11) cannot_attack T02
old = '\t\t\tfor i in range(target.max_field_size):\n\t\t\t\tvar card = target.field[i]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tcard.cannot_attack = true\n\t\t\t\t\tprint("  -> 无法攻击: ", card.get_display_name())\n\t\t\t\t\ttarget.field_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t\tif target_slot >= 0 and target_slot < target.max_field_size:\n\t\t\t\tvar card = target.field[target_slot]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tcard.cannot_attack = true\n\t\t\t\t\tprint("  -> 无法攻击: ", card.get_display_name())\n\t\t\t\t\ttarget.field_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("cannot_attack OK")
else:
    print("cannot_attack NOT FOUND")

# 12) change_form T02
old = '\t\t\tfor i in range(target.max_field_size):\n\t\t\t\tvar card = target.field[i]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tcard.is_turned = not card.is_turned\n\t\t\t\t\tprint("  -> 变更表示形式: ", card.get_display_name(), " -> ", "守备" if card.is_turned else "攻击")\n\t\t\t\t\ttarget.field_changed.emit()\n\t\t\t\t\tbreak'
new = '\t\t\tif target_slot >= 0 and target_slot < target.max_field_size:\n\t\t\t\tvar card = target.field[target_slot]\n\t\t\t\tif card != null and card.is_alive():\n\t\t\t\t\tcard.is_turned = not card.is_turned\n\t\t\t\t\tprint("  -> 变更表示形式: ", card.get_display_name(), " -> ", "守备" if card.is_turned else "攻击")\n\t\t\t\t\ttarget.field_changed.emit()'
if old in s:
    s = s.replace(old, new)
    print("change_form OK")
else:
    print("change_form NOT FOUND")

with open("BattleManager.gd", "w") as f:
    f.write(s)
print("All done!")