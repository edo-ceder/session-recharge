#!/bin/bash
# =============================================================================
# Session Memory Refresh Script
# =============================================================================
# PURPOSE:
#   Single-command refresh: detects the current session, extracts memory,
#   and outputs it for Claude to consume. Used by /session-recharge.
#
# USAGE:
#   Called by Claude via the /session-recharge command.
#   Detects the current session automatically from the working directory.
#
# HOW IT FINDS THE CURRENT SESSION:
#   CC stores transcripts at ~/.claude/projects/{project-dir}/{session-id}.jsonl
#   where {project-dir} is the CWD with '/' replaced by '-'.
#   The most recently modified .jsonl file in that directory is the current session.
# =============================================================================

set -euo pipefail

MEMORY_DIR="$HOME/.claude/session-memories"
LOG_FILE="$MEMORY_DIR/debug.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

mkdir -p "$MEMORY_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$LOG_FILE"
}

log "=== refresh.sh started ==="

# ---------------------------------------------------------------------------
# Detect the project directory in ~/.claude/projects/
# ---------------------------------------------------------------------------
# CC uses the CWD path with '/' replaced by '-' as the project directory name.
# We try the provided CWD first, falling back to PWD.

CWD="${1:-$(pwd)}"
PROJECT_DIR_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g')
PROJECT_PATH="$HOME/.claude/projects/$PROJECT_DIR_NAME"

log "CWD=$CWD"
log "Looking for project at: $PROJECT_PATH"

if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: no Claude Code project found for directory: $CWD" >&2
  echo "Expected: $PROJECT_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Find the most recent session transcript
# ---------------------------------------------------------------------------
# The current session is the most recently modified .jsonl file.

TRANSCRIPT=$(ls -t "$PROJECT_PATH"/*.jsonl 2>/dev/null | head -1)

if [ -z "$TRANSCRIPT" ]; then
  echo "Error: no session transcripts found in $PROJECT_PATH" >&2
  exit 1
fi

# Extract session ID from the filename (strip path and .jsonl extension)
SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)

log "Found session: $SESSION_ID"
log "Transcript: $TRANSCRIPT"

# ---------------------------------------------------------------------------
# Validate session ID is a UUID
# ---------------------------------------------------------------------------

if [[ ! "$SESSION_ID" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]; then
  echo "Error: transcript filename is not a valid session UUID: $SESSION_ID" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run extraction
# ---------------------------------------------------------------------------

log "Running extract.sh..."
"$SCRIPT_DIR/extract.sh" "$SESSION_ID" "$TRANSCRIPT"

# ---------------------------------------------------------------------------
# Output the memory file for Claude to consume
# ---------------------------------------------------------------------------

MEMORY_FILE="$MEMORY_DIR/${SESSION_ID}.md"

if [ ! -f "$MEMORY_FILE" ]; then
  echo "Warning: extraction produced no memory file" >&2
  exit 0
fi

echo "SESSION_ID=$SESSION_ID"
echo "MEMORY_FILE=$MEMORY_FILE"
