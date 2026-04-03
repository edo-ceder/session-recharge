Extract a fresh session memory snapshot and show the user what was captured.

## Steps

1. Find the transcript and run extraction in a single script:
   ```bash
   PROJECT_SLUG=$(echo "$PWD" | sed 's|^/||;s|/|-|g')
   TRANSCRIPT=$(ls -t "$HOME/.claude/projects/-${PROJECT_SLUG}/"*.jsonl 2>/dev/null | head -1)
   SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)
   EXTRACT="$HOME/.claude/hooks/session-memory/extract.sh"
   if [ ! -x "$EXTRACT" ]; then
     EXTRACT="$(find "$HOME/.claude" -path "*/session-recharge/hooks/extract.sh" -type f 2>/dev/null | head -1)"
   fi
   echo "SESSION_ID=$SESSION_ID"
   echo "TRANSCRIPT=$TRANSCRIPT"
   echo "EXTRACT=$EXTRACT"
   "$EXTRACT" "$SESSION_ID" "$TRANSCRIPT"
   ```

2. Read the resulting memory file at `~/.claude/session-memories/$SESSION_ID.md` (use the SESSION_ID from step 1).

3. Show the user what you retained. Use this format:

**Session Recharge — here's what I remember:**
- **Goal:** [one sentence summary of the session objective]
- **Where we left off:** [current state — what's done, what's next]
- **Blockers:** [any active problems, or "None"]
- **Corrections to remember:** [things the user corrected or said NOT to do, or "None noted"]

This lets the user verify the right context was captured. If anything looks wrong, they can correct it immediately.

$ARGUMENTS
