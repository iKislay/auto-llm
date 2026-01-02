# Auto-LLM

> Your AI teammate that works while you sleep 🤖

**Auto-LLM** is a unified CLI tool that runs LLM CLIs (Claude or Gemini) in a continuous, iterative development loop with automatic PR management.

## Features

- 🔄 **Iterative Development Loop** - Branch → Run LLM → Commit → PR → CI → Merge → Repeat
- 🤖 **Multi-Provider Support** - Works with both Claude CLI and Gemini CLI
- 📝 **Persistent Context** - Maintains notes across iterations via `SHARED_TASK_NOTES.md`
- ⏱️ **Flexible Limits** - Stop by iteration count, cost budget, or time duration
- 🌿 **Worktree Support** - Run multiple instances in parallel
- 🎨 **Beautiful UX** - Spinners, progress bars, color-coded output

## Installation

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/iKislay/auto-llm/main/install.sh | bash

# Manual install
curl -fsSL https://raw.githubusercontent.com/iKislay/auto-llm/main/auto_llm.sh -o auto-llm
chmod +x auto-llm
sudo mv auto-llm /usr/local/bin/
```

## Quick Start

```bash
# Run 5 iterations with Claude
auto-llm --provider claude -p "Add unit tests for all functions" -m 5

# Run with Gemini and a cost limit
auto-llm --provider gemini -p "Improve documentation" --max-cost 10.00

# Run for a maximum of 2 hours
auto-llm --provider claude -p "Refactor legacy code" --max-duration 2h

# Set default provider via environment variable
export LLM_PROVIDER=claude
auto-llm -p "Fix all linter errors" -m 5
```

## Usage

```
auto-llm --provider <claude|gemini> -p "prompt" [options]

PROVIDER OPTIONS:
    --provider <claude|gemini>    LLM provider to use (or set LLM_PROVIDER env var)

REQUIRED:
    -p, --prompt <text>           The prompt/goal for the LLM
    -m, --max-runs <number>       Maximum iterations (use 0 for unlimited)
    --max-cost <dollars>          Stop when cost reaches this amount
    --max-duration <duration>     Stop after duration (e.g., "2h", "30m")

OPTIONS:
    --owner <owner>               GitHub repository owner
    --repo <repo>                 GitHub repository name
    --disable-commits             Run without creating PRs
    --dry-run                     Simulate execution
    --worktree <name>             Run in a git worktree
    --quiet                       Minimal output
    --no-banner                   Skip ASCII banner
```

## Requirements

- **One of:**
  - [Claude Code CLI](https://claude.ai/code)
  - Gemini CLI
- [GitHub CLI](https://cli.github.com) (`gh`) - authenticated
- `jq` - JSON parsing
- Git repository

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Auto-LLM Loop                            │
│                                                              │
│  1. Create Branch (auto-claude/iteration-N/...)            │
│  2. Read SHARED_TASK_NOTES.md (if exists)                  │
│  3. Run LLM with Enhanced Prompt                           │
│  4. LLM Updates SHARED_TASK_NOTES.md                       │
│  5. Generate Commit Message (nested LLM call)              │
│  6. Create PR via GitHub CLI                               │
│  7. Wait for CI Checks (30min timeout)                     │
│  8. Merge PR → Pull main → Delete branch                   │
│  9. Repeat until limit reached                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Migration from auto-claude / auto-gemini

If you were using the standalone tools:

```bash
# Before (auto-claude)
auto-claude -p "your task" -m 5

# After (auto-llm)
auto-llm --provider claude -p "your task" -m 5

# Or set default provider
export LLM_PROVIDER=claude
auto-llm -p "your task" -m 5
```

## Author

Built by **Kumar Kislay**

[![Website](https://img.shields.io/badge/Website-kislay.is--a.dev-blue?style=flat-square)](https://kislay.is-a.dev)
[![Twitter](https://img.shields.io/badge/Twitter-@whykislay-1DA1F2?style=flat-square&logo=twitter&logoColor=white)](https://twitter.com/whykislay)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-kislayy-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://linkedin.com/in/kislayy)
[![Email](https://img.shields.io/badge/Email-kislay@syncally.app-EA4335?style=flat-square&logo=gmail&logoColor=white)](mailto:kislay@syncally.app)

---

🚀 **Check out [Syncally](https://syncally.app)** - AI-powered knowledge base for modern engineering teams

---

## License

MIT
