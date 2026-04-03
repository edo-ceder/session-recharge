#!/bin/bash
# Session Recharge — one-command installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK_DIR="$HOME/.claude/hooks/session-memory"
CMD_DIR="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing session-recharge..."

# Copy hooks and command
mkdir -p "$HOOK_DIR" "$CMD_DIR"
cp "$SCRIPT_DIR/hooks/extract.sh" "$SCRIPT_DIR/hooks/inject.sh" "$HOOK_DIR/"
chmod +x "$HOOK_DIR"/*.sh
cp "$SCRIPT_DIR/commands/session-recharge.md" "$CMD_DIR/"

# Merge hook config into settings.json
python3 -c "
import json, os, sys

path = sys.argv[1]
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

pre_compact = {
    'matcher': '',
    'hooks': [{'type': 'command', 'command': '\"\\$HOME/.claude/hooks/session-memory/extract.sh\"', 'timeout': 120}]
}
session_start = {
    'matcher': 'compact',
    'hooks': [{'type': 'command', 'command': '\"\\$HOME/.claude/hooks/session-memory/inject.sh\"'}]
}

# Add if not already present (check by command path)
def has_hook(entries, search):
    return any(search in h.get('command', '') for e in entries for h in e.get('hooks', []))

if not has_hook(hooks.get('PreCompact', []), 'session-memory/extract.sh'):
    hooks.setdefault('PreCompact', []).append(pre_compact)

if not has_hook(hooks.get('SessionStart', []), 'session-memory/inject.sh'):
    hooks.setdefault('SessionStart', []).append(session_start)

with open(path, 'w') as f:
    json.dump(settings, f, indent=4)
    f.write('\n')
" "$SETTINGS"

echo "Done! Session Recharge is now active."
echo ""
echo "  Automatic: extracts memory before compact, re-injects after"
echo "  Manual:    type /session-recharge anytime"
