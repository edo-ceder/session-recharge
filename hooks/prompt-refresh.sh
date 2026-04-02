#!/bin/bash
# =============================================================================
# Session Memory Prompt Trigger Hook
# =============================================================================
# PURPOSE:
#   UserPromptSubmit hook that detects when /session-recharge is invoked
#   and runs extraction + injection BEFORE Claude processes the prompt.
#   This eliminates agent orchestration — Claude sees the memory already
#   injected in its context, no tool calls needed.
#
# HOW IT WORKS:
#   1. Fires on every prompt submission (UserPromptSubmit hook)
#   2. Checks if the prompt contains "session-recharge" trigger
#   3. If triggered: runs extract.sh → reads memory file → outputs to stdout
#   4. stdout is injected into Claude's context before prompt processing
#   5. Claude sees the injected memory + the command's "summarize" instruction
#
# PERFORMANCE:
#   For non-trigger prompts: ~50ms overhead (read stdin, jq parse, grep, exit)
#   For trigger prompts: ~25-40s (Haiku extraction call is the bottleneck)
#
# INPUT:
#   JSON on stdin from CC with fields:
#     session_id       — UUID identifying the session
#     transcript_path  — absolute path to the JSONL transcript
#     prompt           — raw user input text
#
# OUTPUT:
#   When triggered: session memory on stdout (injected into Claude's context)
#   When not triggered: nothing (exits immediately)
# =============================================================================

set -euo pipefail

MEMORY_DIR="$HOME/.claude/session-memories"
LOG_FILE="$MEMORY_DIR/debug.log"
MAX_LOG_BYTES=1048576
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

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

# ---------------------------------------------------------------------------
# Read stdin — exit immediately if no input or jq unavailable
# ---------------------------------------------------------------------------

if [ -t 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')

# ---------------------------------------------------------------------------
# Trigger check — only fire for /session-recharge
# ---------------------------------------------------------------------------
# This check runs on EVERY prompt. For non-matching prompts we exit
# immediately with minimal overhead (~50ms for jq parse + grep).

if ! printf '%s' "$PROMPT" | grep -q 'session-recharge'; then
  exit 0
fi

log "=== prompt-refresh.sh triggered ==="

# ---------------------------------------------------------------------------
# Extract session info from hook input
# ---------------------------------------------------------------------------

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')

log "SESSION_ID=$SESSION_ID"
log "TRANSCRIPT_PATH=$TRANSCRIPT_PATH"

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  log "ERROR: missing session_id or transcript_path"
  exit 0
fi

# ---------------------------------------------------------------------------
# Run extraction (writes memory to ~/.claude/session-memories/{id}.md)
# ---------------------------------------------------------------------------

log "Running extract.sh..."
"$SCRIPT_DIR/extract.sh" "$SESSION_ID" "$TRANSCRIPT_PATH"

# ---------------------------------------------------------------------------
# Inject memory into Claude's context via stdout
# ---------------------------------------------------------------------------

MEMORY_FILE="$MEMORY_DIR/${SESSION_ID}.md"

if [ ! -f "$MEMORY_FILE" ]; then
  log "WARNING: extraction produced no memory file"
  exit 0
fi

log "Injecting refreshed memory ($(wc -c < "$MEMORY_FILE" | tr -d ' ') bytes)"

cat <<'HEADER'
=== SESSION MEMORY — DECISION REMINDER ===
The following are the decisions and constraints agreed upon in this
session. You MUST respect these in your next actions — unless your
intuition says a decision conflicts with what you're about to do.
In that case, STOP and describe the conflict to the user. Let them rule.

Verify any specific details (file contents, deployment state, etc.)
by checking the actual source before acting on them.

HEADER

cat "$MEMORY_FILE"

cat <<'FOOTER'

=== END SESSION MEMORY ===

After reading the above session memory, briefly acknowledge to the user
what you remember about the session (2-3 sentences summarizing the goal
and current state). This confirms the memory injection worked and helps
the user trust that context was preserved across the compaction.
FOOTER

log "Prompt-trigger injection complete"
