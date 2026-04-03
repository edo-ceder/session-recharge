Extract a fresh session memory snapshot and show the user what was captured.

## Steps

1. Find the current session's transcript:
   ```bash
   PROJECT_SLUG=$(echo "$PWD" | sed 's|^/||;s|/|-|g')
   TRANSCRIPT=$(ls -t "$HOME/.claude/projects/-${PROJECT_SLUG}/"*.jsonl 2>/dev/null | head -1)
   echo "TRANSCRIPT=$TRANSCRIPT"
   echo "SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)"
   ```

2. Find and run the extraction script. Check these locations in order:
   - `~/.claude/hooks/session-memory/extract.sh` (manual install)
   - Look for it relative to this command file in `../hooks/extract.sh` (plugin install)

   Pass session_id and transcript_path as arguments:
   ```bash
   EXTRACT="$HOME/.claude/hooks/session-memory/extract.sh"
   if [ ! -x "$EXTRACT" ]; then
     EXTRACT="$(find "$HOME/.claude" -path "*/session-recharge/hooks/extract.sh" -type f 2>/dev/null | head -1)"
   fi
   echo "EXTRACT=$EXTRACT"
   "$EXTRACT" <session_id> <transcript_path>
   ```

3. Read the resulting memory file at `~/.claude/session-memories/<session_id>.md`

4. Show the user what you retained. Use this format:

**Session Recharge — here's what I remember:**
- **Goal:** [one sentence summary of the session objective]
- **Where we left off:** [current state — what's done, what's next]
- **Blockers:** [any active problems, or "None"]
- **Corrections to remember:** [things the user corrected or said NOT to do, or "None noted"]

This lets the user verify the right context was captured. If anything looks wrong, they can correct it immediately.

$ARGUMENTS
