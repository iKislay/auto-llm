# Auto-LLM

> Your AI teammate that works while you sleep 🤖

**Auto-LLM** is a unified CLI tool that runs LLM CLIs (Claude or Gemini) in a continuous, iterative development loop with automatic PR management.

## Features

- 🚀 **Interactive Wizard** - Don't remember flags? Run `auto-llm` with no arguments to get a guided setup.
- 🔄 **Iterative Development** - Continuous loop of Branch → Run LLM → Commit → PR → CI → Merge → Repeat.
- 🤖 **Multi-Provider Support** - Works with both Claude and Gemini CLIs.
- 📉 **Fallback Provider** - Automatically switch to a fallback (e.g., `gemini`) if your primary provider (`claude`) hits a rate limit.
- 📝 **Persistent Context** - Maintains notes across iterations via `SHARED_TASK_NOTES.md`.
- 💾 **Session Management** - Automatically saves your session and can resume from where you left off.
- ⏱️ **Flexible Limits** - Stop by iteration count, cost budget, or time duration.
- 🌿 **Worktree Support** - Run multiple instances in parallel on the same repository without conflict.
- ✨ **Auto-Update** - The script can check for updates and install the latest version.
- 🎨 **Beautiful UX** - Richly formatted output with spinners, progress bars, and color-coded logs.

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

The easiest way to get started is to run the interactive wizard:

```bash
# Run without arguments to open the wizard
auto-llm
```

The wizard will guide you through selecting a provider, setting limits, and writing your prompt.

For direct CLI usage:

```bash
# Run 5 iterations with Claude
auto-llm --provider claude -p "Add unit tests for all functions" -m 5

# Run with Gemini and a cost limit
auto-llm --provider gemini -p "Improve documentation" --max-cost 10.00

# Set default provider via environment variable
export LLM_PROVIDER=claude
auto-llm -p "Fix all linter errors" -m 5
```

## Interactive Wizard

If you run `auto-llm` without any arguments, it will launch a step-by-step wizard to configure your session.

It helps you:
1.  **Choose a provider** (Claude or Gemini).
2.  **Configure a fallback** provider in case of quota limits.
3.  **Set limits** (iterations, cost, or duration).
4.  **Configure Git settings** and auto-detect your repository.
5.  **Write your prompt**.

<img width="800" alt="Auto-LLM Interactive Wizard" src="https://github.com/iKislay/auto-llm/assets/1 Kislay/e1e69b59-54d1-41d3-9f44-d62e7a17730e">

## Session Management

`auto-llm` automatically saves the configuration and progress of your session in `.auto-llm/session.json`.

- **Resuming a Session**: If a previous session is found, the wizard will ask if you want to resume it.
- **State**: It tracks the provider, prompt, limits, and progress (iterations completed, cost spent).

## Updating

You can easily update the script to the latest version.

```bash
# Check for updates and install the latest version
auto-llm update
```

The script also automatically checks for new versions when it starts. You can enable automatic updates with the `--auto-update` flag or disable checks entirely with `--disable-updates`.


## Usage

```
auto-llm [options]
auto-llm update

COMMANDS:
    update                        Check for and install the latest version of the script.

REQUIRED OPTIONS:
    -p, --prompt <text>           The prompt/goal for the LLM to work on.
    One of the following limits must be provided:
    -m, --max-runs <number>       Maximum number of successful iterations.
    --max-cost <dollars>          Maximum cost in USD to spend.
    --max-duration <duration>     Maximum duration to run (e.g., "2h", "30m").

PROVIDER OPTIONS:
    --provider <claude|gemini>    LLM provider to use. Can also be set via the LLM_PROVIDER environment variable.
    --fallback <claude|gemini>    A secondary provider to use if the primary one hits a quota limit.

GIT & REPOSITORY OPTIONS:
    --owner <owner>               GitHub repository owner (auto-detected from git remote).
    --repo <repo>                 GitHub repository name (auto-detected from git remote).
    --disable-commits             Disable automatic commits and PR creation. Useful for local testing.
    --git-branch-prefix <prefix>  Prefix for branches created during iterations (default: "auto-<provider>/").
    --merge-strategy <strategy>   PR merge strategy: squash, merge, or rebase (default: "squash").

WORKTREE OPTIONS:
    --worktree <name>             Run in a git worktree for parallel execution. The worktree is created if it doesn't exist.
    --worktree-base-dir <path>    Base directory where worktrees are created (default: "../auto-llm-worktrees").
    --cleanup-worktree            Automatically remove the worktree after the session completes.
    --list-worktrees              List all active git worktrees and exit.

SESSION & AUTOMATION OPTIONS:
    --notes-file <file>           Path to the shared notes file for iteration context (default: "SHARED_TASK_NOTES.md").
    --completion-signal <phrase>  A specific phrase the AI can output to signal that the entire project is complete.
    --completion-threshold <num>  The number of consecutive completion signals required to automatically stop the script (default: 3).

UPDATE OPTIONS:
    --auto-update                 Automatically install updates when available without prompting.
    --disable-updates             Skip all update checks.

DISPLAY OPTIONS:
    --quiet                       Minimal output, showing only errors and the final summary.
    --no-banner                   Skip the startup ASCII banner.
    --no-color                    Disable all colored output.

OTHER OPTIONS:
    -h, --help                    Show this help message.
    -v, --version                 Show version information.
    --dry-run                     Simulate execution without running the LLM or making any changes.
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
