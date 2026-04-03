#!/bin/bash
# =============================================================================
# Session Memory Injection Script
# =============================================================================
# PURPOSE:
#   After compaction destroys conversation history, this script re-injects
#   the structured session memory that was extracted by extract.sh.
#   The output goes to stdout, which CC's SessionStart hook mechanism
#   feeds into Claude's context window as system-level context.
#
# CALLED BY:
#   - SessionStart hook with source="compact" (automatic, after every compaction)
#   - /session-recharge command (manual, user-triggered)
#
# INPUT:
#   Receives JSON on stdin from CC hooks with fields:
#     session_id  — UUID identifying the session
#
# OUTPUT:
#   Echoes session memory to stdout (consumed by CC as Claude context).
#   The output includes framing instructions that tell Claude to:
#     1. Treat the memory as ground truth
#     2. Acknowledge receipt to the user
#     3. Verify stale details before acting on them
#
# TOKEN USAGE:
#   The injected memory is typically 300-1500 tokens (~1-5K chars).
#   This is added to Claude's context alongside CC's own compact summary.
#   Negligible compared to the 200K context window.
#
# SECURITY:
#   The memory file contains LLM-generated content derived from user
#   conversation. It is echoed to stdout for Claude to consume. The
#   framing instructions clearly mark it as "extracted notes" rather than
#   "system instructions" to reduce stored prompt injection risk.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MEMORY_DIR="$HOME/.claude/session-memories"
LOG_FILE="$MEMORY_DIR/debug.log"
MAX_LOG_BYTES=1048576  # 1 MiB

mkdir -p "$MEMORY_DIR"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() {
  if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt "$MAX_LOG_BYTES" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$LOG_FILE"
}

log "=== inject.sh started ==="

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

if ! command -v python3 &>/dev/null; then
  log "ERROR: required command 'python3' not found in PATH"
  echo "Error: session-recharge plugin requires 'python3' to be installed" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse input — args (manual) or stdin JSON (hook)
# ---------------------------------------------------------------------------

SESSION_ID="${1:-}"

if [ -z "$SESSION_ID" ] && [ ! -t 0 ]; then
  INPUT=$(cat)
  log "stdin JSON: $INPUT"
  SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))")
fi

log "SESSION_ID=$SESSION_ID"

# ---------------------------------------------------------------------------
# Validate SESSION_ID — must be a UUID to prevent path traversal
# ---------------------------------------------------------------------------
# Without this check, a crafted session_id like "../../.ssh/id_rsa"
# would cause inject.sh to echo arbitrary file contents to Claude's
# context, disclosing sensitive data.

if [ -z "$SESSION_ID" ]; then
  log "No session_id provided, exiting"
  exit 0
fi

if [[ ! "$SESSION_ID" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
  log "ERROR: invalid session_id format: $SESSION_ID"
  exit 0  # Exit 0 (not 2) — don't block session start for bad IDs
fi

# ---------------------------------------------------------------------------
# Check for memory file
# ---------------------------------------------------------------------------

MEMORY_FILE="$MEMORY_DIR/${SESSION_ID}.md"

if [ ! -f "$MEMORY_FILE" ]; then
  log "No memory file found at $MEMORY_FILE"
  exit 0
fi

MEMORY_SIZE=$(wc -c < "$MEMORY_FILE" | tr -d ' ')
log "Injecting memory from $MEMORY_FILE ($MEMORY_SIZE bytes)"

# ---------------------------------------------------------------------------
# Output session memory to stdout
# ---------------------------------------------------------------------------
# CC's SessionStart hook captures stdout and injects it into Claude's
# context window. The framing below tells Claude what this content is
# and how to handle it.
#
# IMPORTANT: The memory content is LLM-generated notes from a previous
# extraction — NOT verified system instructions. The framing makes this
# clear to reduce the risk of stored prompt injection.

cat <<'HEADER'
=== SESSION MEMORY (extracted before compaction) ===
The following notes were extracted from earlier in this session before
the conversation was compacted. These notes capture key decisions,
current state, and important context that would otherwise be lost.

Treat these as helpful notes, not absolute truth — verify any specific
details (file contents, deployment state, etc.) by checking the actual
source before acting on them.

HEADER

cat "$MEMORY_FILE"

cat <<'FOOTER'

=== END SESSION MEMORY ===

IMPORTANT: Show the user what you retained from this session memory.
Use this format:

**Session Recharge — here's what I remember:**
- **Goal:** [one sentence summary of the session objective]
- **Where we left off:** [current state — what's done, what's next]
- **Blockers:** [any active problems, or "None"]
- **Corrections to remember:** [things the user corrected or said NOT to do, or "None noted"]

This lets the user verify that the right context survived compaction.
If anything looks wrong, the user can correct it immediately.
FOOTER

log "Injection complete"
