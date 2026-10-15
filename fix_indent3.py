with open('CardEngraving.gd') as f:
    lines = f.readlines()

# Fix the match block: correct indentation is:
# match prefix:         # 3 tabs
#     "TR":             # 4 tabs (pattern)
#         body...       # 5 tabs (pattern body)
#     "C":              # 4 tabs
#         body...       # 5 tabs

# Current state: patterns and body are BOTH at 4 tabs
# Need to move all pattern body lines to 5 tabs (or more for nested)

# Strategy: find the match block (line 2537), then fix all lines until the end of the block
# The block ends at the first line that's at 2 tabs (back to for g in groups level)

match_line = 2536  # 0-indexed
in_match = False
changes = 0

for i in range(match_line, len(lines)):
    stripped = lines[i].lstrip('\t')
    tabs = len(lines[i]) - len(stripped)
    
    # First line of match block
    if i == match_line:
        in_match = True
        continue
    
    if not in_match:
        break
    
    # Check if we've left the match block (back to 2 tabs or less)
    # The for loop over g is at 1 tab, so the match block body should be at 2+ tabs
    # Actually let me check: for g in groups: is at tabs=1, the for idx in g: is at tabs=2
    # match prefix: is at tabs=3, so patterns at tabs=4, pattern body at tabs=5
    # After the match block, we go back to for idx in g level (tabs=2)
    
    if tabs <= 2 and stripped and not stripped.startswith('#') and not stripped.startswith('\n'):
        # We've left the match block (the # 每组能量 comment is at tabs=2)
        break
    
    # Lines that are at 4 tabs (pattern level) - check if they're pattern bodies, not patterns
    if tabs == 4:
        # Pattern lines start with "TR", "C", "A", "T", "CO"
        if stripped.startswith('"TR"') or stripped.startswith('"C"') or stripped.startswith('"A"') or stripped.startswith('"T"') or stripped.startswith('"CO"'):
            # This IS a pattern - keep at 4 tabs
            pass
        else:
            # This is pattern body that got collapsed to 4 tabs - should be 5 tabs
            lines[i] = '\t' * 5 + stripped
            changes += 1

print(f'Fixed {changes} lines')
print(f'First 5 lines of match block:')
for i in range(match_line, min(match_line + 10, len(lines))):
    stripped = lines[i].lstrip('\t')
    tabs = len(lines[i]) - len(stripped)
    print(f'  {i+1}: tabs={tabs} | {stripped[:50].rstrip()}')

with open('CardEngraving.gd', 'w') as f:
    f.writelines(lines)
print('Saved.')