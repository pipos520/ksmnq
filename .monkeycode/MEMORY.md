# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[Project Knowledge Summary]
- Date: 2026-10-15
- Context: Discovered by Agent while fixing battle-screen bugs in BattleScene3D.gd
- Category: Testing Methods
- Instructions:
  - The sandbox has no Godot binary (`godot`, `godot4`, `godot3` all absent), so GDScript can only be verified by static reading. Never claim a GDScript edit was runtime-tested; tell the user it must be loaded in the Godot editor to confirm.
  - Useful static checks that work without Godot: (1) a clause-pairing scan that walks backwards from every `else:`/`elif` to confirm a matching `if` (catches orphaned `else` left behind by mechanical edits); (2) strip strings and `#` comments, then verify `{}` `()` `[]` counts match; (3) `grep -o "^func [a-zA-Z_][a-zA-Z0-9_]*" | awk '{print $2}' | sort | uniq -d` to catch duplicate function definitions.
  - Both GDScript files in this repo use tab-only indentation with zero space-indented lines; keep new code tab-indented or the file mixes styles.

[Project Knowledge Summary]
- Date: 2026-10-15
- Context: Discovered by Agent while fixing label rendering bugs in BattleScene3D.gd
- Category: Troubleshooting & Debugging
- Instructions:
  - `assets/share/font_pixel.ttf` is assigned to the 25 Label3D info labels (BattleScene3D.gd sets the font explicitly) and does NOT contain emoji glyphs. Missing: `❤ ⚡ 📚 📷 ⚔ ░ ▒ ▰ ▱ ♥`. Present: `█ ▓ ■ □ ● ○ ★ ☆ ◆ — ·` and the CJK needed for 血量/蓝量/能量/回合/卡组/牌组/攻防. Use `█`/`□` block characters for progress bars, not `⚡`/`❤`/`░`.
  - `assets/share/font.ttf` is also missing `❤ ⚡ ▰`.
  - 2D `Button`/`Label` emoji (`📷` view button, `⚔` phase button, effect popups, grave rows, tutorial strings) cannot be verified: `assets/theme/pixel_theme.tres` sets `default_font_size = 48` but has no `default_font`, and `project.godot` has no `fonts/font/fallback`, so the fallback chain is unknown. Leave those strings untouched unless a font is added.
  - Inspect TTF glyph coverage headlessly with `python3 -c` plus `fonttools` (`pip3 install --break-system-packages -q fonttools`); no GUI needed.

[Project Knowledge Summary]
- Date: 2026-10-15
- Context: Discovered by Agent while replacing the root-level one-off Python scripts with a card-pool validator
- Category: Build Methods
- Instructions:
  - The canonical card pool is `Data/local_card_packs.json` (a list of `{id, pack_id, pack_data: {name, desc, cards: [...]}}`). 31 packs, 519 cards as of 2026-10-15. The ~14 `Data/*.backup*.json` files are stale historical snapshots, not live data.
  - The circuit component whitelist is declared in `Global.gd`: `circuit_triggers` / `circuit_conditions` / `circuit_actions` / `circuit_targets` / `circuit_constraints` (around lines 569-690), plus `circuit_mutex["action_target_pairs"]` for invalid action×target combos. Entries commented out in that file (TR02/03/04/07/08, A04-A08, A10-A19, A22-A24, A26-A30, T01/T07-T09/T11/T12, C11/C13/C14/C15, CO01/CO02/CO06-CO16) are disabled; `T01` is still consumed by the engine as the implicit default target.
  - Valid elements come from `Global.gd:get_element_affinity()` (火/风/地/水/光/暗 plus 无). Valid qualities are 废品/瑕疵/标准/精良/卓越/完美.
  - Run `python3 scripts/validate_card_pool.py` to check the pool. Whitelists are parsed out of `Global.gd` at runtime so they cannot drift. Exit code 1 on ERROR. Use `--verbose` for INFO level (cards missing optional `desc`/`fields`/`effects`), `--file` to point at another pool file.
