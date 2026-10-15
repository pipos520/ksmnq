with open('CardEngraving.gd') as f:
    lines = f.readlines()

# The match block starts at line 2537 (0-indexed 2536)
# We need to fix the entire match block indentation
# Current: patterns at 4 tabs, bodies at 5 tabs
# Problem: nested if/elif/else bodies should be at 6 tabs, not 5

# Let me just rewrite the entire match block from scratch
# The correct structure:
# match prefix:                 # 3 tabs
#   "TR":                       # 4 tabs
#       tr_energy = ...         # 5 tabs
#   "C":                        # 4 tabs
#       var ce = ...            # 5 tabs
#       var params_type = ...   # 5 tabs
#       if params_type == "数值":   # 5 tabs
#           var param_val = ... # 6 tabs
#           c_energy -= ...     # 6 tabs
#       elif params_type == "比较符+数值":  # 5 tabs
#           var param_val = ... # 6 tabs
#           c_energy -= ...     # 6 tabs
#       else:                   # 5 tabs
#           c_energy -= ...     # 6 tabs
#   "A":                        # 4 tabs
#       var base = ...          # 5 tabs
#       if base is float or base is int:  # 5 tabs
#           a_energy = ...      # 6 tabs
#       elif base is String:    # 5 tabs
#           var parts = ...     # 6 tabs
#           if parts.size() == 2:  # 6 tabs
#               var param_key = ...  # 7 tabs
#               var multiplier = ... # 7 tabs
#               var param_val = ...  # 7 tabs
#               a_energy = ...      # 7 tabs
#   "T":                        # 4 tabs
#       t_modifier = ...        # 5 tabs
#   "CO":                       # 4 tabs
#       var adj = ...           # 5 tabs
#       if adj is float or adj is int:  # 5 tabs
#           co_adjust += ...    # 6 tabs
#       elif adj is String:     # 5 tabs
#           if "X" in adj and "×" in adj:  # 6 tabs
#               var parts = ... # 7 tabs
#               if parts.size() == 2:  # 7 tabs
#                   var param_key = ...  # 8 tabs
#                   var multiplier = ... # 8 tabs
#                   var param_val = ...  # 8 tabs
#                   co_adjust += ...    # 8 tabs
#           else:               # 6 tabs
#               var trimmed = ... # 7 tabs
#               if trimmed.is_valid_float():  # 7 tabs
#                   co_adjust += ...  # 8 tabs

# Strategy: scan the match block, compute the correct indentation based on nesting level
# We track the current nesting level by looking at control flow keywords

match_start = 2536  # 0-indexed, "match prefix:"
in_match = False
nest_stack = []  # stack of indentation levels

fixes = 0
for i in range(match_start, len(lines)):
    stripped = lines[i].lstrip('\t')
    raw_tabs = len(lines[i]) - len(stripped)
    
    if i == match_start:
        in_match = True
        continue
    
    if not in_match:
        break
    
    # Check if we've left the match block - back to 2 tabs or less
    if raw_tabs <= 2 and stripped.strip() and not stripped.startswith('#'):
        break
    
    # Calculate correct indentation based on the previous line's structure
    # Patterns are at 4 tabs, pattern body at 5 tabs
    # If body at n+1, elif/else at same level as if
    
    if stripped.startswith('"TR"') or stripped.startswith('"C"') or stripped.startswith('"A"') or stripped.startswith('"T"') or stripped.startswith('"CO"'):
        # Match pattern - should be at 4 tabs
        correct = 4
    elif stripped.startswith('if ') or stripped.startswith('elif ') or stripped.startswith('else:') or stripped.startswith('else\n'):
        # if/elif/else at 5 tabs (pattern body level)
        correct = 5
    elif stripped.startswith('for ') or stripped.startswith('while '):
        # loop at 5 tabs
        correct = 5
    else:
        # Everything else - check what level it was at
        # Body of if/elif/else should be at 6 tabs
        # Body of nested if should be at 7 tabs, etc.
        # Let me just check: if the previous line was at 5 tabs and it's an if/elif/else,
        # then this line should be at 6 tabs
        if raw_tabs == 5:
            correct = 5  # keep as is for now
        elif raw_tabs == 6:
            correct = 6
        elif raw_tabs == 7:
            correct = 7
        elif raw_tabs == 8:
            correct = 8
        else:
            correct = raw_tabs
    
    if raw_tabs != correct:
        lines[i] = '\t' * correct + stripped
        fixes += 1

print(f'Fixed {fixes} lines')

# Print the first 50 lines of the match block
print()
print('=== Match block preview ===')
for i in range(match_start, min(match_start + 50, len(lines))):
    stripped = lines[i].lstrip('\t')
    tabs = len(lines[i]) - len(stripped)
    print(f'{i+1}: tabs={tabs} | {stripped[:60].rstrip()}')

with open('CardEngraving.gd', 'w') as f:
    f.writelines(lines)
print('Saved.')