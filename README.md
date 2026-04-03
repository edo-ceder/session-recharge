# Session Recharge

Preserves important architectural decisions and user requests that get lost during compaction and long sessions. Automatically extracts structured session memory (goals, decisions, state, blockers, corrections) before compaction and re-injects it after. Can also be triggered mid-session anytime you want Claude to refocus on what's been decided.

## The Problem

Important architectural decisions and user requests get lost during compaction and long sessions. Neither `CLAUDE.md` nor auto-memory help — they aren't designed for session-specific context.

- **CLAUDE.md** holds project-level rules, not "we agreed to use approach X because of Y"
- **Auto-memory** captures user preferences and project facts, not session-specific decisions
- **Compact summaries** compress the conversation flow but drop the specifics — decisions, corrections, blockers, what's done vs. pending

## What This Plugin Does

Session Recharge gives Claude a structured, decision-focused snapshot of the session that survives compaction and drift.

**Automatically** — hooks into the compaction lifecycle to extract memory before compact and re-inject it after. Architectural decisions from hour 1 survive through compact 5.

**Manually** — type `/session-recharge` when Claude is drifting, contradicting earlier decisions, or before a major code change. Claude re-extracts and displays what it remembers so you can verify and correct.

## How It Works

```
    ┌─────────────────────────────────┐
    │  AUTOMATIC (around compaction)  │
    └─────────────┬───────────────────┘
                  │
    PreCompact hook fires
                  │
    extract.sh reads user prompts + assistant summaries
    from the JSONL transcript and sends them to Haiku
                  │
    Haiku produces a focused summary:
    • Session goal
    • Key decisions (with WHY)
    • Current state (files, deployments, commits)
    • Active blockers
    • Corrections / things NOT to do
    • User preferences for this session
                  │
    Written to ~/.claude/session-memories/{session-id}.md
                  │
    CC compacts the conversation
                  │
    SessionStart hook fires (source: compact)
                  │
    inject.sh reads the memory file
    and outputs it to Claude's fresh context
                  │
    Claude's next response is informed by
    the injected session memory ✓


    ┌─────────────────────────────────┐
    │  MANUAL (anytime mid-session)   │
    └─────────────┬───────────────────┘
                  │
    User types /session-recharge
                  │
    Claude runs extract.sh directly via Bash
    (same extraction pipeline as PreCompact)
                  │
    Claude reads the resulting memory file
    and shows a structured summary:
    • Goal, Where we left off, Blockers, Corrections
                  │
    User verifies the summary is correct ✓
                  │
    Use when:
    • Claude is drifting or contradicting earlier decisions
    • Before a major code change or refactor
    • After a long stretch of tool-heavy work
```

### Incremental Memory

If a session compacts multiple times, each extraction builds on the previous one. Decisions from hour 1 survive through compact 5.

## Token Usage & Cost

Each extraction only sends **new messages since the last extraction** — user prompts and assistant text-only responses (no tool calls, no thinking blocks). Earlier decisions are already captured in the existing memory file, which Haiku merges with the new content. This keeps input small even in long sessions: tool-heavy stretches produce very little extractable text.

| Phase | Tokens | Notes |
|-------|--------|-------|
| **Extraction input** | Varies | New messages since last extraction only (user prompts + assistant summaries, tool calls skipped) |
| **Extraction output** | ~300-1,500 | Structured summary |
| **Injection** | ~300-1,500 | Added to Claude's post-compact context |
| **Model** | Haiku | Via `claude -p` (uses your CC subscription) |
| **Time added to compact** | Varies | Scales with new content since last extraction — Haiku call is the bottleneck |

**Billing:** The extraction runs via `claude -p --model haiku` using your Claude Code subscription. Token usage depends on how much user + assistant summary text exists — tool-heavy sessions are cheap, discussion-heavy sessions cost more. Output is always ~300-1,500 tokens. A typical extraction costs ~$0.04. A per-call safety cap of $1.00 (`--max-budget-usd`) prevents runaway costs.

## Installation

```bash
git clone https://github.com/edo-ceder/session-recharge.git
cd session-recharge && ./install.sh
```

The installer copies hooks and the command to `~/.claude/` and merges hook config into your `settings.json`. No reload required — hooks are active immediately.

<details>
<summary>Plugin marketplace (pending approval)</summary>

Once approved by Anthropic, installation will be:

```
/plugin marketplace add edo-ceder/session-recharge
/plugin install session-recharge
```
</details>

### Requirements

- **Claude Code** (with active subscription — Haiku calls use your CC auth)
- **python3** (for JSONL transcript parsing and hook JSON input parsing)

`python3` is pre-installed on most macOS and Linux systems. The plugin checks for it on startup and gives a clear error message if missing.

## Commands

| Command | Description |
|---------|-------------|
| `/session-recharge` | Run a fresh extraction, read the result, and display a structured summary. Use before critical decisions or when Claude is drifting. |

## Files

```
session-recharge/
├── install.sh                  # One-command installer
├── .claude-plugin/
│   ├── plugin.json             # Plugin manifest
│   └── marketplace.json        # Marketplace listing metadata
├── hooks/
│   ├── hooks.json              # Hook event bindings
│   ├── extract.sh              # PreCompact: user prompts + summaries → Haiku → memory file
│   └── inject.sh               # SessionStart: memory file → Claude context
├── commands/
│   └── session-recharge.md     # /session-recharge command (runs extract + read + display)
└── README.md
```

## Viewing Session Memories

Memory files are stored at:

```
~/.claude/session-memories/{session-id}.md
```

Each file is a standalone markdown document with this structure:

```markdown
<!-- Session: 80b8df76-c7ae-40c9-bd43-7eeff2422644 -->
<!-- Updated: 2026-03-14T21:59:43Z -->
<!-- Source: 80b8df76-c7ae-40c9-bd43-7eeff2422644.jsonl -->
<!-- LastLine: 847 -->

### Session Goal
User is refining the v3 orchestrator prompts to fix module decomposition...

### Key Decisions Made
- **Prompts modeled on prd-generation.ts**: Uses proven structure — purpose/audience → ...
- **Module overview must be comprehensive**: Most readers only see Level 1...
- **Depth hard limit: 2 levels default**: Optional 3rd level only when genuinely needed...

### Current State
**Prompts Updated (ready to deploy):**
- `codeToPrdV3Service.ts:493` — Orchestrator system prompt: business-first framing...
- `codeToPrdV3Agents.ts:19` — Analyst prompt: comprehensive overview example...
**Database State:**
- Last successful run: 1,880 nodes (6 modules, 8 levels deep)...

### Active Problems / Blockers
**Phase 3 cross-link failure (0/1307 links)**: Agent chose Bash/Read over MCP tools...

### Important Context
- **Module_summary schema was contradictory**: Analyst wrote "2–3 sentences", tree builder expected "comprehensive"...
- **Verify with data, not code**: User correction — always query the DB first...

### User Preferences (this session)
- **Wants independent review feedback first**: Before re-running...
- **Evidence-based communication**: Specific findings, not speculation...
```

You can view them directly:

```bash
# List all session memories
ls -lt ~/.claude/session-memories/*.md

# View the most recent one
cat "$(ls -t ~/.claude/session-memories/*.md | head -1)"

# View debug log (hook execution history)
cat ~/.claude/session-memories/debug.log
```

Or within a Claude Code session, use `/session-recharge` to have Claude re-extract and re-read its own memory.

## How It Compares to Other Context Tools

| | CLAUDE.md | Auto-Memory | CC Compact Summary | Session Recharge |
|---|---|---|---|---|
| **Scope** | Project-level | Cross-session | Current session | Current session |
| **Contains** | Rules, conventions | User prefs, project facts | General conversation flow | Decisions, state, corrections |
| **Session decisions?** | No | No | Sometimes | Yes (explicit section) |
| **Corrections?** | No | Sometimes | Rarely | Yes (explicit section) |
| **Format** | Freeform | Freeform | Narrative prose | Structured headings |
| **Survives compact?** | Always loaded | Always loaded | Replaces conversation | Injected post-compact |
| **Cost** | Free | Free | Free | Varies (Haiku tokens) |

They all complement each other. CLAUDE.md sets the rules, auto-memory builds the user profile, CC's summary preserves the broad narrative, and Session Recharge captures the session-specific decisions and state that keep Claude on track.

## Data & Privacy

- Memory files are stored locally at `~/.claude/session-memories/`
- Conversation transcripts are read from `~/.claude/projects/` (CC's own storage)
- Transcript content is sent to Haiku via `claude -p --tools ""` — uses your CC subscription auth. `--tools ""` disables all tools at the system level (enforced, not just instructed), so the call can only generate text
- No data leaves your machine except through the standard Claude API (via CC)
- Debug logs at `~/.claude/session-memories/debug.log` (auto-rotated at 1 MB)

## Security

The scripts include protections for community distribution:

- **UUID validation** on session IDs (prevents path traversal)
- **Path validation** on transcript paths (must be under `~/.claude/`)
- **Temp file isolation** (private directory, cleanup trap)
- **Dependency checks** (fails fast with clear errors)
- **Prompt injection mitigation** (XML-tagged transcript boundaries)
- **Tool use disabled** (`--tools ""` on the inner `claude -p` call — disables all tools at the system level, so even a successful prompt injection cannot trigger Bash, file writes, or any other tool. No `--dangerously-skip-permissions` needed because there are no tools to approve)
- **Budget cap** ($1.00 per extraction via `--max-budget-usd` — ~25x the typical cost, acts as a safety valve)
- **Log rotation** (prevents unbounded disk growth)

## License

MIT
