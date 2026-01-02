#!/bin/bash

VERSION="v1.0.0"

# Provider configuration (set via --provider flag or LLM_PROVIDER env var)
PROVIDER=""
PROVIDER_CLI=""

# Provider-specific settings (populated by init_provider)
PROVIDER_BRAND_COLOR=""
PROVIDER_BRAND_COLOR_LIGHT=""
PROVIDER_REPO=""

# Provider-specific flags (set by init_provider)
ADDITIONAL_FLAGS=""

NOTES_FILE="SHARED_TASK_NOTES.md"
AUTO_UPDATE=false
DISABLE_UPDATES=false

PROMPT_JQ_INSTALL="Please install jq for JSON parsing"

PROMPT_COMMIT_MESSAGE="Please review all uncommitted changes in the git repository (both modified and new files). Write a commit message that follows the conventional commit format. The commit message should have: (1) a type (e.g., feat, fix, docs, style, refactor, test, chore), (2) a scope (e.g., auth, api, db), (3) a short, imperative-tense description of the change, (4) a blank line, (5) a detailed explanation of the change. Do not include any footers or metadata like 'Generated with AI' or 'Co-Authored-By'. Feel free to look at the last few commits to get a sense of the commit message style for consistency. First run 'git add .' to stage all changes including new untracked files, then commit using 'git commit -m \"your message\"' (don't push, just commit, no need to ask for confirmation)."

PROMPT_WORKFLOW_CONTEXT="## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations. You might run once, then a human developer might make changes, then you run again, and so on. This could happen daily or on any schedule.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI). Think of it as a relay race where you're passing the baton.

**Project Completion Signal**: If you determine that not just your current task but the ENTIRE project goal is fully complete (nothing more to be done on the overall goal), only include the exact phrase \"COMPLETION_SIGNAL_PLACEHOLDER\" in your response. Only use this when absolutely certain that the whole project is finished, not just your individual task. We will stop working on this project when multiple developers independently determine that the project is complete.

## PRIMARY GOAL"

PROMPT_NOTES_UPDATE_EXISTING="Update the \`$NOTES_FILE\` file with relevant context for the next iteration. Add new notes and remove outdated information to keep it current and useful."

PROMPT_NOTES_CREATE_NEW="Create a \`$NOTES_FILE\` file with relevant context and instructions for the next iteration."

PROMPT_NOTES_GUIDELINES="

This file helps coordinate work across iterations (both human and AI developers). It should:

- Contain relevant context and instructions for the next iteration
- Stay concise and actionable (like a notes file, not a detailed report)
- Help the next developer understand what to do next

The file should NOT include:
- Lists of completed work or full reports
- Information that can be discovered by running tests/coverage
- Unnecessary details"

PROMPT=""
MAX_RUNS=""
MAX_COST=""
MAX_DURATION=""
ENABLE_COMMITS=true
GIT_BRANCH_PREFIX=""  # Set by init_provider based on provider
MERGE_STRATEGY="squash"
GITHUB_OWNER=""
GITHUB_REPO=""
WORKTREE_NAME=""
WORKTREE_BASE_DIR=""  # Set by init_provider based on provider
CLEANUP_WORKTREE=false
LIST_WORKTREES=false
DRY_RUN=false
COMPLETION_SIGNAL=""  # Set by init_provider based on provider
COMPLETION_THRESHOLD=3
ERROR_LOG=""
error_count=0
extra_iterations=0
successful_iterations=0
total_cost=0
completion_signal_count=0
i=1
EXTRA_CLI_FLAGS=()
start_time=""

# UX Options
QUIET_MODE=false
NO_BANNER=false
NO_COLOR=false
spinner_pid=""

# Terminal colors and styles (will be set in init_colors)
C_RED=""
C_GREEN=""
C_YELLOW=""
C_BLUE=""
C_MAGENTA=""
C_CYAN=""
C_WHITE=""
C_BOLD=""
C_DIM=""
C_RESET=""
C_BRAND=""       # Provider's brand color
C_BRAND_LIGHT="" # Lighter version for accents

# Spinner animation frames
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Provider initialization
init_provider() {
    # Determine provider from flag or environment or prompt user
    if [ -z "$PROVIDER" ]; then
        if [ -n "$LLM_PROVIDER" ]; then
            PROVIDER="$LLM_PROVIDER"
        fi
    fi

    # Validate provider
    case "$PROVIDER" in
        claude)
            PROVIDER_CLI="claude"
            PROVIDER_BRAND_COLOR='\033[38;5;173m'       # Coral/salmon - Claude's brand
            PROVIDER_BRAND_COLOR_LIGHT='\033[38;5;216m' # Lighter peach/coral
            PROVIDER_REPO="iKislay/auto-llm"
            GIT_BRANCH_PREFIX="${GIT_BRANCH_PREFIX:-auto-claude/}"
            WORKTREE_BASE_DIR="${WORKTREE_BASE_DIR:-../auto-llm-worktrees}"
            COMPLETION_SIGNAL="${COMPLETION_SIGNAL:-AUTO_CLAUDE_PROJECT_COMPLETE}"
            ADDITIONAL_FLAGS="--dangerously-skip-permissions --output-format json"
            ;;
        gemini)
            PROVIDER_CLI="gemini"
            PROVIDER_BRAND_COLOR='\033[38;5;33m'        # Bright blue - Gemini's brand
            PROVIDER_BRAND_COLOR_LIGHT='\033[38;5;75m'  # Light blue
            PROVIDER_REPO="iKislay/auto-llm"
            GIT_BRANCH_PREFIX="${GIT_BRANCH_PREFIX:-auto-gemini/}"
            WORKTREE_BASE_DIR="${WORKTREE_BASE_DIR:-../auto-llm-worktrees}"
            COMPLETION_SIGNAL="${COMPLETION_SIGNAL:-AUTO_GEMINI_PROJECT_COMPLETE}"
            ADDITIONAL_FLAGS="--yolo --output-format json"
            ;;
        "")
            # Provider not set - will be handled by interactive prompt or validation
            ;;
        *)
            echo "❌ Error: Unknown provider '$PROVIDER'. Supported providers: claude, gemini" >&2
            exit 1
            ;;
    esac
}

# Interactive provider selection
select_provider_interactive() {
    if [ -n "$PROVIDER" ]; then
        return 0
    fi

    echo "" >&2
    echo "🤖 Select your LLM provider:" >&2
    echo "" >&2
    echo "  1) Claude (claude-code CLI)" >&2
    echo "  2) Gemini (gemini CLI)" >&2
    echo "" >&2
    echo -n "Enter choice [1-2]: " >&2

    local choice
    if ! read -t 60 -r choice; then
        echo "" >&2
        echo "⏱️  No response received within 60 seconds." >&2
        exit 1
    fi

    case "$choice" in
        1|claude)
            PROVIDER="claude"
            ;;
        2|gemini)
            PROVIDER="gemini"
            ;;
        *)
            echo "❌ Invalid choice. Please enter 1 or 2." >&2
            exit 1
            ;;
    esac

    echo "" >&2
    echo "💡 Tip: Set LLM_PROVIDER=$PROVIDER in your shell profile to skip this prompt." >&2
    echo "   Or use: --provider $PROVIDER" >&2
    echo "" >&2

    init_provider
}

# Session management
SESSION_DIR=".auto-llm"
SESSION_FILE=""
INTERACTIVE_MODE=false

init_session_path() {
    mkdir -p "$SESSION_DIR"
    SESSION_FILE="$SESSION_DIR/session.json"
}

save_session() {
    if [ -z "$SESSION_FILE" ]; then
        init_session_path
    fi
    
    local session_data=$(cat << EOF
{
    "provider": "$PROVIDER",
    "fallback_provider": "$FALLBACK_PROVIDER",
    "prompt": $(echo "$PROMPT" | jq -Rs .),
    "max_runs": ${MAX_RUNS:-null},
    "max_cost": ${MAX_COST:-null},
    "max_duration": ${MAX_DURATION:-null},
    "enable_commits": $ENABLE_COMMITS,
    "github_owner": "$GITHUB_OWNER",
    "github_repo": "$GITHUB_REPO",
    "successful_iterations": $successful_iterations,
    "total_cost": $total_cost,
    "iteration": $i,
    "last_updated": "$(date -Iseconds)"
}
EOF
)
    echo "$session_data" > "$SESSION_FILE"
}

load_session() {
    if [ -z "$SESSION_FILE" ]; then
        init_session_path
    fi
    
    if [ ! -f "$SESSION_FILE" ]; then
        return 1
    fi
    
    if ! jq -e . "$SESSION_FILE" >/dev/null 2>&1; then
        return 1
    fi
    
    local loaded_provider=$(jq -r '.provider // empty' "$SESSION_FILE")
    local loaded_fallback=$(jq -r '.fallback_provider // empty' "$SESSION_FILE")
    local loaded_prompt=$(jq -r '.prompt // empty' "$SESSION_FILE")
    local loaded_max_runs=$(jq -r '.max_runs // empty' "$SESSION_FILE")
    local loaded_iterations=$(jq -r '.successful_iterations // 0' "$SESSION_FILE")
    local loaded_i=$(jq -r '.iteration // 1' "$SESSION_FILE")
    
    [ -n "$loaded_provider" ] && [ "$loaded_provider" != "null" ] && PROVIDER="$loaded_provider"
    [ -n "$loaded_fallback" ] && [ "$loaded_fallback" != "null" ] && FALLBACK_PROVIDER="$loaded_fallback"
    [ -n "$loaded_prompt" ] && [ "$loaded_prompt" != "null" ] && PROMPT="$loaded_prompt"
    [ -n "$loaded_max_runs" ] && [ "$loaded_max_runs" != "null" ] && MAX_RUNS="$loaded_max_runs"
    [ -n "$loaded_iterations" ] && [ "$loaded_iterations" != "null" ] && successful_iterations="$loaded_iterations"
    [ -n "$loaded_i" ] && [ "$loaded_i" != "null" ] && i="$loaded_i"
    
    return 0
}

show_welcome_banner() {
    clear >&2
    echo "" >&2
    local C_ORANGE='\033[38;5;208m'
    local C_BLUE='\033[38;5;33m'
    local C_DIM_TXT='\033[2m'
    local C_RESET_TXT='\033[0m'
    
    echo -e "${C_ORANGE}    ╔═══════════════════════════════════════════════════════════════╗" >&2
    echo -e "    ║                                                               ║" >&2
    echo -e "    ║       █████╗ ██╗   ██╗████████╗ ██████╗                       ║" >&2
    echo -e "    ║      ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗                      ║" >&2
    echo -e "    ║      ███████║██║   ██║   ██║   ██║   ██║                      ║" >&2
    echo -e "    ║      ██╔══██║██║   ██║   ██║   ██║   ██║                      ║" >&2
    echo -e "    ║      ██║  ██║╚██████╔╝   ██║   ╚██████╔╝                      ║${C_RESET_TXT}" >&2
    echo -e "${C_BLUE}    ║      ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝                       ║" >&2
    echo -e "    ║                                                               ║" >&2
    echo -e "    ║        ██╗     ██╗     ███╗   ███╗                            ║" >&2
    echo -e "    ║        ██║     ██║     ████╗ ████║                            ║" >&2
    echo -e "    ║        ██║     ██║     ██╔████╔██║                            ║" >&2
    echo -e "    ║        ██║     ██║     ██║╚██╔╝██║                            ║" >&2
    echo -e "    ║        ███████╗███████╗██║ ╚═╝ ██║                            ║" >&2
    echo -e "    ║        ╚══════╝╚══════╝╚═╝     ╚═╝                            ║" >&2
    echo -e "    ║                                                               ║" >&2
    echo -e "    ╚═══════════════════════════════════════════════════════════════╝${C_RESET_TXT}" >&2
    echo "" >&2
    echo -e "    ${C_DIM_TXT}Version $VERSION • Built by Kumar Kislay${C_RESET_TXT}" >&2
    echo -e "    ${C_DIM_TXT}🐦 @whykislay  •  💼 linkedin.com/in/kislayy  •  🐙 github.com/iKislay${C_RESET_TXT}" >&2
    echo "" >&2
}

run_interactive_wizard() {
    INTERACTIVE_MODE=true
    init_session_path
    show_welcome_banner
    
    # Check for existing session
    if [ -f "$SESSION_FILE" ]; then
        echo -e "\033[1m📁 Previous session found\033[0m" >&2
        echo "" >&2
        local prev_prompt=$(jq -r '.prompt // "N/A"' "$SESSION_FILE" | head -c 50)
        local prev_provider=$(jq -r '.provider // "N/A"' "$SESSION_FILE")
        local prev_iterations=$(jq -r '.successful_iterations // 0' "$SESSION_FILE")
        echo -e "  Provider: \033[36m$prev_provider\033[0m" >&2
        echo -e "  Prompt: \033[33m${prev_prompt}...\033[0m" >&2
        echo -e "  Progress: \033[32m$prev_iterations\033[0m iterations" >&2
        echo "" >&2
        echo -e "  \033[1m1)\033[0m Resume this session" >&2
        echo -e "  \033[1m2)\033[0m Start a new session" >&2
        echo "" >&2
        echo -n "  Choice [1]: " >&2
        
        local resume_choice
        read -r resume_choice
        
        if [ "$resume_choice" != "2" ]; then
            load_session
            init_provider
            echo -e "\n  \033[32m✓\033[0m Resuming session...\n" >&2
            return 0
        fi
        echo "" >&2
    fi
    
    # Step 1: Provider
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo -e "\033[1m  Step 1/5: Choose your LLM provider\033[0m" >&2
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo "" >&2
    echo -e "  \033[1m1)\033[0m \033[38;5;208m◉\033[0m Claude  \033[2m(claude CLI)\033[0m" >&2
    echo -e "  \033[1m2)\033[0m \033[38;5;33m◉\033[0m Gemini  \033[2m(gemini CLI)\033[0m" >&2
    echo "" >&2
    echo -n "  Enter choice [1]: " >&2
    
    local provider_choice
    read -r provider_choice
    case "$provider_choice" in
        2|gemini) PROVIDER="gemini" ;;
        *) PROVIDER="claude" ;;
    esac
    init_provider
    echo -e "  \033[32m✓\033[0m Selected: $PROVIDER\n" >&2
    
    # Step 2: Fallback
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo -e "\033[1m  Step 2/5: Configure fallback\033[0m" >&2
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo "" >&2
    local other_provider="gemini"
    [ "$PROVIDER" = "gemini" ] && other_provider="claude"
    echo -e "  \033[1m1)\033[0m Enable fallback to \033[36m$other_provider\033[0m" >&2
    echo -e "  \033[1m2)\033[0m No fallback" >&2
    echo "" >&2
    echo -n "  Enter choice [2]: " >&2
    
    local fallback_choice
    read -r fallback_choice
    if [ "$fallback_choice" = "1" ]; then
        FALLBACK_PROVIDER="$other_provider"
        echo -e "  \033[32m✓\033[0m Fallback: $FALLBACK_PROVIDER\n" >&2
    else
        echo -e "  \033[32m✓\033[0m No fallback\n" >&2
    fi
    
    # Step 3: Limits
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo -e "\033[1m  Step 3/5: Set limits\033[0m" >&2
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo "" >&2
    echo -n "  Max iterations [5]: " >&2
    
    local max_runs_input
    read -r max_runs_input
    MAX_RUNS="${max_runs_input:-5}"
    echo -e "  \033[32m✓\033[0m Max iterations: $MAX_RUNS\n" >&2
    
    # Step 4: PR settings
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo -e "\033[1m  Step 4/5: Git & PR settings\033[0m" >&2
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo "" >&2
    echo -e "  \033[1m1)\033[0m Enable commits & PRs" >&2
    echo -e "  \033[1m2)\033[0m Disable commits (testing)" >&2
    echo "" >&2
    echo -n "  Enter choice [1]: " >&2
    
    local commit_choice
    read -r commit_choice
    if [ "$commit_choice" = "2" ]; then
        ENABLE_COMMITS=false
        echo -e "  \033[32m✓\033[0m Commits disabled\n" >&2
    else
        ENABLE_COMMITS=true
        local detected_info
        if detected_info=$(detect_github_repo 2>/dev/null); then
            GITHUB_OWNER=$(echo "$detected_info" | awk '{print $1}')
            GITHUB_REPO=$(echo "$detected_info" | awk '{print $2}')
            echo -e "  \033[32m✓\033[0m Auto-detected: $GITHUB_OWNER/$GITHUB_REPO\n" >&2
        else
            echo -e "  \033[32m✓\033[0m Commits enabled\n" >&2
        fi
    fi
    
    # Step 5: Prompt
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo -e "\033[1m  Step 5/5: Enter your task prompt\033[0m" >&2
    echo -e "\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" >&2
    echo "" >&2
    echo -n "  > " >&2
    
    read -r PROMPT
    
    if [ -z "$PROMPT" ]; then
        echo -e "\n  \033[31m❌ Prompt is required\033[0m" >&2
        exit 1
    fi
    
    echo -e "\n  \033[32m✓\033[0m Task configured!\n" >&2
    save_session
}

init_colors() {
    if [ "$NO_COLOR" = "true" ] || [ ! -t 2 ]; then
        # No colors if disabled or not a terminal
        C_RED=""
        C_GREEN=""
        C_YELLOW=""
        C_BLUE=""
        C_MAGENTA=""
        C_CYAN=""
        C_WHITE=""
        C_BOLD=""
        C_DIM=""
        C_RESET=""
        C_BRAND=""
        C_BRAND_LIGHT=""
    else
        # Provider brand colors
        C_BRAND="$PROVIDER_BRAND_COLOR"
        C_BRAND_LIGHT="$PROVIDER_BRAND_COLOR_LIGHT"

        # Standard colors
        C_RED='\033[38;5;203m'
        C_GREEN='\033[38;5;114m'
        C_YELLOW='\033[38;5;221m'
        C_BLUE='\033[38;5;110m'
        C_MAGENTA='\033[38;5;176m'
        C_CYAN='\033[38;5;116m'
        C_WHITE='\033[0;37m'
        C_BOLD='\033[1m'
        C_DIM='\033[2m'
        C_RESET='\033[0m'
    fi
}

# Spinner functions
start_spinner() {
    local message="$1"
    if [ "$QUIET_MODE" = "true" ]; then
        return
    fi

    (
        local idx=0
        while true; do
            printf "\r${C_BRAND}${SPINNER_FRAMES[$idx]}${C_RESET} %s" "$message" >&2
            idx=$(( (idx + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.1
        done
    ) &
    spinner_pid=$!
}

stop_spinner() {
    local success="${1:-true}"
    local message="${2:-}"

    if [ -n "$spinner_pid" ] && kill -0 "$spinner_pid" 2>/dev/null; then
        kill "$spinner_pid" 2>/dev/null
        wait "$spinner_pid" 2>/dev/null || true
    fi
    spinner_pid=""

    # Clear the spinner line
    printf "\r\033[K" >&2

    # Show completion status
    if [ -n "$message" ]; then
        if [ "$success" = "true" ]; then
            echo -e "${C_GREEN}✓${C_RESET} $message" >&2
        else
            echo -e "${C_RED}✗${C_RESET} $message" >&2
        fi
    fi
}

# Graceful interrupt handler
handle_interrupt() {
    echo "" >&2
    echo -e "${C_YELLOW}⚠️  Interrupted by user${C_RESET}" >&2
    stop_spinner false "Cancelled"

    # Show what was accomplished
    if [ $successful_iterations -gt 0 ] || [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ]; then
        echo "" >&2
        echo -e "${C_BOLD}Session Summary (interrupted)${C_RESET}" >&2
        echo -e "  Completed iterations: $successful_iterations" >&2
        [ -n "$total_cost" ] && printf "  Cost so far: \$%.3f\n" "$total_cost" >&2
    fi

    cleanup_worktree
    rm -f "$ERROR_LOG"
    exit 130
}

# Progress bar display
show_progress_bar() {
    local current=$1
    local total=$2
    local width=30

    if [ "$QUIET_MODE" = "true" ] || [ "$total" -eq 0 ]; then
        return
    fi

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "  ${C_DIM}Progress:${C_RESET} [" >&2
    for ((j=0; j<filled; j++)); do printf "${C_GREEN}█${C_RESET}" >&2; done
    for ((j=0; j<empty; j++)); do printf "${C_DIM}░${C_RESET}" >&2; done
    printf "] %3d%% (%d/%d)\n" "$percentage" "$current" "$total" >&2
}

# Step display with status
show_step() {
    local step_num="$1"
    local total_steps="$2"
    local step_name="$3"
    local status="${4:-pending}"

    if [ "$QUIET_MODE" = "true" ]; then
        return
    fi

    local status_icon=""
    local status_color=""

    case "$status" in
        "pending")
            status_icon="○"
            status_color="${C_DIM}"
            ;;
        "running")
            status_icon="●"
            status_color="${C_BRAND}"
            ;;
        "success")
            status_icon="✓"
            status_color="${C_GREEN}"
            ;;
        "error")
            status_icon="✗"
            status_color="${C_RED}"
            ;;
    esac

    echo -e "  ${status_color}${status_icon}${C_RESET} ${C_DIM}[$step_num/$total_steps]${C_RESET} $step_name" >&2
}

# Startup banner
show_startup_banner() {
    if [ "$NO_BANNER" = "true" ] || [ "$QUIET_MODE" = "true" ]; then
        return
    fi

    echo "" >&2
    echo -e "${C_BRAND}${C_BOLD}" >&2

    if [ "$PROVIDER" = "claude" ]; then
        cat << 'EOF' >&2
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     █████╗ ██╗   ██╗████████╗ ██████╗                         ║
    ║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗                        ║
    ║    ███████║██║   ██║   ██║   ██║   ██║                        ║
    ║    ██╔══██║██║   ██║   ██║   ██║   ██║                        ║
    ║    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝                        ║
    ║    ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝                         ║
    ║     ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗          ║
    ║    ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝          ║
    ║    ██║     ██║     ███████║██║   ██║██║  ██║█████╗            ║
    ║    ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝            ║
    ║    ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗          ║
    ║     ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝          ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
        echo -e "${C_RESET}" >&2
        echo -e "${C_DIM}    Version $VERSION • Built by Kumar Kislay${C_RESET}" >&2
        echo -e "${C_DIM}    🐦 @whykislay  •  💼 linkedin.com/in/kislayy  •  🐙 github.com/iKislay${C_RESET}" >&2
    else
        cat << 'EOF' >&2
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     █████╗ ██╗   ██╗████████╗ ██████╗                         ║
    ║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗                        ║
    ║    ███████║██║   ██║   ██║   ██║   ██║                        ║
    ║    ██╔══██║██║   ██║   ██║   ██║   ██║                        ║
    ║    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝                        ║
    ║    ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝                         ║
    ║     ██████╗ ███████╗███╗   ███╗██╗███╗   ██╗██╗               ║
    ║    ██╔════╝ ██╔════╝████╗ ████║██║████╗  ██║██║               ║
    ║    ██║  ███╗█████╗  ██╔████╔██║██║██╔██╗ ██║██║               ║
    ║    ██║   ██║██╔══╝  ██║╚██╔╝██║██║██║╚██╗██║██║               ║
    ║    ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║██║               ║
    ║     ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝               ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
EOF
        echo -e "${C_RESET}" >&2
        echo -e "${C_DIM}    Version $VERSION • Built by Kumar Kislay${C_RESET}" >&2
        echo -e "${C_DIM}    🐦 @whykislay  •  💼 linkedin.com/in/kislayy  •  🐙 github.com/iKislay${C_RESET}" >&2
    fi
    echo "" >&2
}

# Configuration summary
show_config_summary() {
    if [ "$QUIET_MODE" = "true" ]; then
        return
    fi

    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo -e "${C_BOLD}  📋 Configuration${C_RESET}" >&2
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo "" >&2

    # Provider
    echo -e "  ${C_BRAND}🤖 Provider:${C_RESET} $PROVIDER ($PROVIDER_CLI)" >&2

    # Prompt (truncated)
    local prompt_display="${PROMPT:0:55}"
    [ ${#PROMPT} -gt 55 ] && prompt_display+="..."
    echo -e "  ${C_BRAND}📝 Prompt:${C_RESET} $prompt_display" >&2

    # Limits
    local limits=""
    [ -n "$MAX_RUNS" ] && [ "$MAX_RUNS" -ne 0 ] && limits+="${MAX_RUNS} iterations  "
    [ -n "$MAX_COST" ] && limits+="\$${MAX_COST} budget  "
    [ -n "$MAX_DURATION" ] && limits+="$(format_duration $MAX_DURATION) duration  "
    [ -z "$limits" ] && limits="None (unlimited)"
    echo -e "  ${C_BRAND}🎯 Limits:${C_RESET} $limits" >&2

    # Repository
    if [ "$ENABLE_COMMITS" = "true" ]; then
        echo -e "  ${C_BRAND}📦 Repository:${C_RESET} $GITHUB_OWNER/$GITHUB_REPO" >&2
        echo -e "  ${C_BRAND}🔀 Merge Strategy:${C_RESET} $MERGE_STRATEGY" >&2
    else
        echo -e "  ${C_BRAND}📦 Repository:${C_RESET} ${C_DIM}commits disabled${C_RESET}" >&2
    fi

    # Worktree
    [ -n "$WORKTREE_NAME" ] && echo -e "  ${C_BRAND}🌿 Worktree:${C_RESET} $WORKTREE_NAME" >&2

    # Completion settings
    echo -e "  ${C_BRAND}🎉 Auto-stop:${C_RESET} After $COMPLETION_THRESHOLD completion signals" >&2

    echo "" >&2
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo "" >&2
}

# Real-time stats display
show_realtime_stats() {
    if [ "$QUIET_MODE" = "true" ]; then
        return
    fi

    local elapsed=""
    if [ -n "$start_time" ]; then
        local current_time=$(date +%s)
        elapsed=$(format_duration $((current_time - start_time)))
    fi

    echo "" >&2
    echo -e "${C_DIM}┌─────────────────────────────────────────────────┐${C_RESET}" >&2
    echo -e "${C_DIM}│${C_RESET} ${C_BOLD}📊 Live Statistics${C_RESET}                              ${C_DIM}│${C_RESET}" >&2
    echo -e "${C_DIM}├─────────────────────────────────────────────────┤${C_RESET}" >&2
    printf "${C_DIM}│${C_RESET}  Iterations: ${C_GREEN}%d successful${C_RESET} / ${C_RED}%d errors${C_RESET}        ${C_DIM}│${C_RESET}\n" "$successful_iterations" "$error_count" >&2
    [ -n "$elapsed" ] && printf "${C_DIM}│${C_RESET}  Elapsed: ${C_YELLOW}%-20s${C_RESET}              ${C_DIM}│${C_RESET}\n" "$elapsed" >&2
    [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ] && printf "${C_DIM}│${C_RESET}  Cost: ${C_BRAND}\$%.3f${C_RESET}                                 ${C_DIM}│${C_RESET}\n" "$total_cost" >&2
    [ $completion_signal_count -gt 0 ] && printf "${C_DIM}│${C_RESET}  Completion signals: ${C_MAGENTA}%d/%d${C_RESET}                    ${C_DIM}│${C_RESET}\n" "$completion_signal_count" "$COMPLETION_THRESHOLD" >&2
    echo -e "${C_DIM}└─────────────────────────────────────────────────┘${C_RESET}" >&2
    echo "" >&2
}

parse_duration() {
    local duration_str="$1"

    # Remove all whitespace
    duration_str=$(echo "$duration_str" | tr -d '[:space:]')

    if [ -z "$duration_str" ]; then
        return 1
    fi

    local total_seconds=0
    local remaining="$duration_str"

    # Parse hours (e.g., "2h" or "2H")
    if [[ "$remaining" =~ ([0-9]+)[hH] ]]; then
        local hours="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + hours * 3600))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi

    # Parse minutes (e.g., "30m" or "30M")
    if [[ "$remaining" =~ ([0-9]+)[mM] ]]; then
        local minutes="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + minutes * 60))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi

    # Parse seconds (e.g., "45s" or "45S")
    if [[ "$remaining" =~ ([0-9]+)[sS] ]]; then
        local seconds="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + seconds))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi

    # Check if anything unparsed remains (invalid format)
    if [ -n "$remaining" ]; then
        return 1
    fi

    # Must have parsed at least something
    if [ $total_seconds -eq 0 ]; then
        return 1
    fi

    echo "$total_seconds"
    return 0
}

format_duration() {
    local seconds="$1"

    if [ -z "$seconds" ] || [ "$seconds" -eq 0 ]; then
        echo "0s"
        return
    fi

    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    local result=""
    if [ $hours -gt 0 ]; then
        result="${hours}h"
    fi
    if [ $minutes -gt 0 ]; then
        result="${result}${minutes}m"
    fi
    if [ $secs -gt 0 ] || [ -z "$result" ]; then
        result="${result}${secs}s"
    fi

    echo "$result"
}

show_help() {
    local provider_name="LLM"
    [ -n "$PROVIDER" ] && provider_name="$PROVIDER"
    
    cat << EOF
Auto-LLM - Run LLM CLI (Claude/Gemini) iteratively with automatic PR management

USAGE:
    auto-llm --provider <claude|gemini> -p "prompt" (-m max-runs | --max-cost max-cost | --max-duration duration) [options]
    auto-llm update

PROVIDER OPTIONS:
    --provider <claude|gemini>    LLM provider to use (can also set LLM_PROVIDER env var)

REQUIRED OPTIONS:
    -p, --prompt <text>           The prompt/goal for the LLM to work on
    -m, --max-runs <number>       Maximum number of successful iterations (use 0 for unlimited with --max-cost or --max-duration)
    --max-cost <dollars>          Maximum cost in USD to spend (alternative to --max-runs)
    --max-duration <duration>     Maximum duration to run (e.g., "2h", "30m", "1h30m") (alternative to --max-runs)

OPTIONAL FLAGS:
    -h, --help                    Show this help message
    -v, --version                 Show version information
    --owner <owner>               GitHub repository owner (auto-detected from git remote if not provided)
    --repo <repo>                 GitHub repository name (auto-detected from git remote if not provided)
    --disable-commits             Disable automatic commits and PR creation
    --auto-update                 Automatically install updates when available
    --disable-updates             Skip all update checks and prompts
    --git-branch-prefix <prefix>  Branch prefix for iterations (default: "auto-<provider>/")
    --merge-strategy <strategy>   PR merge strategy: squash, merge, or rebase (default: "squash")
    --notes-file <file>           Shared notes file for iteration context (default: "SHARED_TASK_NOTES.md")
    --worktree <name>             Run in a git worktree for parallel execution (creates if needed)
    --worktree-base-dir <path>    Base directory for worktrees (default: "../auto-llm-worktrees")
    --cleanup-worktree            Remove worktree after completion
    --list-worktrees              List all active git worktrees and exit
    --dry-run                     Simulate execution without making changes
    --completion-signal <phrase>  Phrase that agents output when project is complete
    --completion-threshold <num>  Number of consecutive signals to stop early (default: 3)

DISPLAY OPTIONS:
    --quiet                       Minimal output, only errors and final summary
    --no-banner                   Skip the startup ASCII banner
    --no-color                    Disable colored output

COMMANDS:
    update                        Check for and install the latest version

EXAMPLES:
    # Run 5 iterations with Claude
    auto-llm --provider claude -p "Fix all linter errors" -m 5

    # Run with Gemini and cost limit
    auto-llm --provider gemini -p "Add tests" --max-cost 10.00

    # Run for a maximum duration
    auto-llm --provider claude -p "Add documentation" --max-duration 2h

    # Run without commits (testing mode)
    auto-llm --provider gemini -p "Refactor code" -m 3 --disable-commits

    # Use environment variable for provider
    export LLM_PROVIDER=claude
    auto-llm -p "Fix bugs" -m 5

REQUIREMENTS:
    - Claude Code CLI (if using --provider claude): https://claude.ai/code
    - Gemini CLI (if using --provider gemini)
    - GitHub CLI (gh) - authenticated with 'gh auth login'
    - jq - JSON parsing utility
    - Git repository (unless --disable-commits is used)

For more information, visit: https://github.com/iKislay/auto-llm
EOF
}

show_version() {
    echo "auto-llm version $VERSION"
    if [ -n "$PROVIDER" ]; then
        echo "Provider: $PROVIDER ($PROVIDER_CLI)"
    fi
}

get_latest_version() {
    local latest_version
    if ! command -v gh &> /dev/null; then
        return 1
    fi

    latest_version=$(gh release view --repo "$PROVIDER_REPO" --json tagName --jq '.tagName' 2>/dev/null)
    if [ -z "$latest_version" ]; then
        return 1
    fi

    echo "$latest_version"
    return 0
}

compare_versions() {
    local ver1="$1"
    local ver2="$2"

    ver1="${ver1#v}"
    ver2="${ver2#v}"
    ver1="${ver1%%-*}"
    ver2="${ver2%%-*}"

    if [ "$ver1" = "$ver2" ]; then
        return 0
    fi

    local IFS=.
    local i ver1_arr ver2_arr
    read -ra ver1_arr <<< "$ver1"
    read -ra ver2_arr <<< "$ver2"

    for ((i=${#ver1_arr[@]}; i<${#ver2_arr[@]}; i++)); do
        ver1_arr[i]=0
    done
    for ((i=${#ver2_arr[@]}; i<${#ver1_arr[@]}; i++)); do
        ver2_arr[i]=0
    done

    for ((i=0; i<${#ver1_arr[@]}; i++)); do
        local c1="${ver1_arr[i]}"
        local c2="${ver2_arr[i]}"
        if [[ "$c1" =~ ^[0-9]+$ ]] && [[ "$c2" =~ ^[0-9]+$ ]]; then
            if ((10#$c1 < 10#$c2)); then
                return 1
            fi
            if ((10#$c1 > 10#$c2)); then
                return 2
            fi
        else
            if [[ "$c1" < "$c2" ]]; then
                return 1
            fi
            if [[ "$c1" > "$c2" ]]; then
                return 2
            fi
        fi
    done

    return 0
}

get_script_path() {
    local script_path
    script_path=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
    echo "$script_path"
}

download_and_install_update() {
    local latest_version="$1"
    local script_path="$2"

    echo "📥 Downloading version $latest_version..." >&2

    local temp_file=$(mktemp)
    local download_url="https://raw.githubusercontent.com/${PROVIDER_REPO}/${latest_version}/auto_llm.sh"
    local checksum_url="https://raw.githubusercontent.com/${PROVIDER_REPO}/${latest_version}/auto_llm.sh.sha256"
    
    if ! curl -fsSL "$download_url" -o "$temp_file"; then
        echo "❌ Failed to download update" >&2
        rm -f "$temp_file"
        return 1
    fi

    local checksum_file=$(mktemp)
    if ! curl -fsSL "$checksum_url" -o "$checksum_file"; then
        echo "⚠️  Warning: Failed to download checksum file (skipping verification)" >&2
        rm -f "$checksum_file"
    else
        local expected_checksum
        expected_checksum=$(cat "$checksum_file" | awk '{print $1}')
        local actual_checksum
        actual_checksum=$(sha256sum "$temp_file" | awk '{print $1}')
        if [ "$expected_checksum" != "$actual_checksum" ]; then
            echo "❌ Checksum verification failed! Update aborted." >&2
            rm -f "$temp_file" "$checksum_file"
            return 1
        fi
        rm -f "$checksum_file"
    fi

    if ! bash -n "$temp_file" 2>/dev/null; then
        echo "❌ Downloaded file has invalid syntax" >&2
        rm -f "$temp_file"
        return 1
    fi

    chmod +x "$temp_file"

    if ! mv "$temp_file" "$script_path"; then
        echo "❌ Failed to replace script (permission denied?)" >&2
        rm -f "$temp_file"
        return 1
    fi

    echo "✅ Updated to version $latest_version" >&2
    return 0
}

check_for_updates() {
    local skip_prompt="$1"

    if [ "$DISABLE_UPDATES" = "true" ]; then
        return 0
    fi

    local latest_version
    if ! latest_version=$(get_latest_version); then
        return 0
    fi

    compare_versions "$VERSION" "$latest_version"
    local comparison=$?

    if [ $comparison -eq 1 ]; then
        echo "" >&2
        echo "🆕 A new version of auto-llm is available: $latest_version (current: $VERSION)" >&2

        if [ "$skip_prompt" = "true" ]; then
            return 0
        fi

        local response
        if [ "$AUTO_UPDATE" = "true" ]; then
            response="y"
        else
            echo -n "Would you like to update now? [y/N] " >&2
            if ! read -t 60 -r response; then
                echo "" >&2
                echo "⏱️  No response received within 60 seconds, skipping update." >&2
                response="n"
            fi
        fi

        if [[ "$response" =~ ^[Yy]$ ]]; then
            local script_path=$(get_script_path)

            if download_and_install_update "$latest_version" "$script_path"; then
                echo "🔄 Restarting with new version..." >&2
                exec "$script_path" "$@"
            else
                echo "⚠️  Update failed. Continuing with current version." >&2
            fi
        else
            echo "⏭️  Skipping update. You can update later with: auto-llm update" >&2
        fi
    fi

    return 0
}

handle_update_command() {
    if [ "$DISABLE_UPDATES" = "true" ]; then
        echo "⚠️  Updates are disabled via --disable-updates flag. Skipping." >&2
        exit 0
    fi

    echo "🔍 Checking for updates..." >&2

    local latest_version
    if ! latest_version=$(get_latest_version); then
        echo "❌ Failed to check for updates. Make sure 'gh' CLI is installed and authenticated." >&2
        exit 1
    fi

    compare_versions "$VERSION" "$latest_version"
    local comparison=$?

    if [ $comparison -eq 0 ]; then
        echo "✅ You're already on the latest version ($VERSION)" >&2
        exit 0
    elif [ $comparison -eq 2 ]; then
        echo "ℹ️  You're on a newer version ($VERSION) than the latest release ($latest_version)" >&2
        exit 0
    fi

    echo "🆕 New version available: $latest_version (current: $VERSION)" >&2

    local response
    if [ "$AUTO_UPDATE" = "true" ]; then
        response="y"
    else
        echo -n "Would you like to update now? [y/N] " >&2
        if ! read -t 60 -r response; then
            echo "" >&2
            echo "⏱️  No response received within 60 seconds, skipping update." >&2
            response="n"
        fi
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        local script_path=$(get_script_path)

        if download_and_install_update "$latest_version" "$script_path"; then
            echo "✅ Update complete! Version $latest_version is now installed." >&2
            exit 0
        else
            echo "❌ Update failed." >&2
            exit 1
        fi
    else
        echo "⏭️  Update cancelled." >&2
        exit 0
    fi
}

detect_github_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 1
    fi

    local remote_url
    if ! remote_url=$(git remote get-url origin 2>/dev/null); then
        return 1
    fi

    local owner=""
    local repo=""

    if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    repo="${repo%.git}"

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        return 1
    fi

    echo "$owner $repo"
    return 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                init_provider  # Needed for help display
                show_help
                exit 0
                ;;
            -v|--version)
                init_provider
                show_version
                exit 0
                ;;
            --provider)
                PROVIDER="$2"
                shift 2
                ;;
            -p|--prompt)
                PROMPT="$2"
                shift 2
                ;;
            -m|--max-runs)
                MAX_RUNS="$2"
                shift 2
                ;;
            --max-cost)
                MAX_COST="$2"
                shift 2
                ;;
            --max-duration)
                MAX_DURATION="$2"
                shift 2
                ;;
            --git-branch-prefix)
                GIT_BRANCH_PREFIX="$2"
                shift 2
                ;;
            --merge-strategy)
                MERGE_STRATEGY="$2"
                shift 2
                ;;
            --owner)
                GITHUB_OWNER="$2"
                shift 2
                ;;
            --repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --disable-commits)
                ENABLE_COMMITS=false
                shift
                ;;
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --disable-updates)
                DISABLE_UPDATES=true
                shift
                ;;
            --notes-file)
                NOTES_FILE="$2"
                shift 2
                ;;
            --worktree)
                WORKTREE_NAME="$2"
                shift 2
                ;;
            --worktree-base-dir)
                WORKTREE_BASE_DIR="$2"
                shift 2
                ;;
            --cleanup-worktree)
                CLEANUP_WORKTREE=true
                shift
                ;;
            --list-worktrees)
                LIST_WORKTREES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --completion-signal)
                COMPLETION_SIGNAL="$2"
                shift 2
                ;;
            --completion-threshold)
                COMPLETION_THRESHOLD="$2"
                shift 2
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --no-banner)
                NO_BANNER=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            *)
                # Collect unknown flags to forward to the LLM CLI
                EXTRA_CLI_FLAGS+=("$1")
                shift
                ;;
        esac
    done
}

parse_update_flags() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --provider)
                PROVIDER="$2"
                shift 2
                ;;
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --disable-updates)
                DISABLE_UPDATES=true
                shift
                ;;
            -h|--help)
                init_provider
                show_help
                exit 0
                ;;
            *)
                echo "❌ Unknown flag for update command: $1" >&2
                exit 1
                ;;
        esac
    done
}

validate_arguments() {
    if [ -z "$PROMPT" ]; then
        echo "❌ Error: Prompt is required. Use -p to provide a prompt." >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [ -z "$MAX_RUNS" ] && [ -z "$MAX_COST" ] && [ -z "$MAX_DURATION" ]; then
        echo "❌ Error: Either --max-runs, --max-cost, or --max-duration is required." >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [ -n "$MAX_RUNS" ] && ! [[ "$MAX_RUNS" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: --max-runs must be a non-negative integer" >&2
        exit 1
    fi

    if [ -n "$MAX_COST" ]; then
        if ! [[ "$MAX_COST" =~ ^[0-9]+\.?[0-9]*$ ]] || [ "$(awk "BEGIN {print ($MAX_COST <= 0)}")" = "1" ]; then
            echo "❌ Error: --max-cost must be a positive number" >&2
            exit 1
        fi
    fi

    if [ -n "$MAX_DURATION" ]; then
        local duration_seconds
        if ! duration_seconds=$(parse_duration "$MAX_DURATION"); then
            echo "❌ Error: --max-duration must be a valid duration (e.g., '2h', '30m', '1h30m', '90s')" >&2
            exit 1
        fi
        MAX_DURATION="$duration_seconds"
    fi

    if [[ ! "$MERGE_STRATEGY" =~ ^(squash|merge|rebase)$ ]]; then
        echo "❌ Error: --merge-strategy must be one of: squash, merge, rebase" >&2
        exit 1
    fi

    if [ -n "$COMPLETION_THRESHOLD" ]; then
        if ! [[ "$COMPLETION_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$COMPLETION_THRESHOLD" -lt 1 ]; then
            echo "❌ Error: --completion-threshold must be a positive integer" >&2
            exit 1
        fi
    fi

    # Only require GitHub info if commits are enabled
    if [ "$ENABLE_COMMITS" = "true" ]; then
        if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
            local detected_info
            if detected_info=$(detect_github_repo); then
                local detected_owner=$(echo "$detected_info" | awk '{print $1}')
                local detected_repo=$(echo "$detected_info" | awk '{print $2}')

                if [ -z "$GITHUB_OWNER" ]; then
                    GITHUB_OWNER="$detected_owner"
                fi
                if [ -z "$GITHUB_REPO" ]; then
                    GITHUB_REPO="$detected_repo"
                fi
            fi
        fi

        if [ -z "$GITHUB_OWNER" ]; then
            echo "❌ Error: GitHub owner is required. Use --owner to provide the owner, or run from a git repository with a GitHub remote." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi

        if [ -z "$GITHUB_REPO" ]; then
            echo "❌ Error: GitHub repo is required. Use --repo to provide the repo, or run from a git repository with a GitHub remote." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi
    fi
}

validate_requirements() {
    if ! command -v "$PROVIDER_CLI" &> /dev/null; then
        echo "❌ Error: $PROVIDER_CLI is not installed." >&2
        if [ "$PROVIDER" = "claude" ]; then
            echo "   Install Claude Code CLI: https://claude.ai/code" >&2
        else
            echo "   Install Gemini CLI from your provider" >&2
        fi
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "⚠️ jq is required for JSON parsing but is not installed. Asking $PROVIDER_CLI to install it..." >&2
        $PROVIDER_CLI -p "$PROMPT_JQ_INSTALL" --allowedTools "Bash,Read"
        if ! command -v jq &> /dev/null; then
            echo "❌ Error: jq is still not installed after $PROVIDER_CLI attempt." >&2
            exit 1
        fi
    fi

    if [ "$ENABLE_COMMITS" = "true" ]; then
        if ! command -v gh &> /dev/null; then
            echo "❌ Error: GitHub CLI (gh) is not installed: https://cli.github.com" >&2
            exit 1
        fi

        if ! gh auth status >/dev/null 2>&1; then
            echo "❌ Error: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
            exit 1
        fi
    fi
}

wait_for_pr_checks() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local iteration_display="$4"
    local max_iterations=180
    local iteration=0

    local prev_check_count=""
    local prev_success_count=""
    local prev_pending_count=""
    local prev_failed_count=""
    local prev_review_status=""
    local prev_no_checks_configured=""
    local waiting_message_printed=false

    while [ $iteration -lt $max_iterations ]; do
        local checks_json
        local no_checks_configured=false
        if ! checks_json=$(gh pr checks "$pr_number" --repo "$owner/$repo" --json state,bucket 2>&1); then
            if echo "$checks_json" | grep -q "no checks"; then
                no_checks_configured=true
                checks_json="[]"
            else
                echo "⚠️  $iteration_display Failed to get PR checks status: $checks_json" >&2
                return 1
            fi
        fi

        local check_count=$(echo "$checks_json" | jq 'length' 2>/dev/null || echo "0")

        local all_completed=true
        local all_success=true

        if [ "$no_checks_configured" = "false" ] && [ "$check_count" -eq 0 ]; then
            all_completed=false
        fi

        local pending_count=0
        local success_count=0
        local failed_count=0

        if [ "$check_count" -gt 0 ]; then
            local idx=0
            while [ $idx -lt $check_count ]; do
                local state=$(echo "$checks_json" | jq -r ".[$idx].state")
                local bucket=$(echo "$checks_json" | jq -r ".[$idx].bucket // \"pending\"")

                if [ "$bucket" = "pending" ] || [ "$bucket" = "null" ]; then
                    all_completed=false
                    pending_count=$((pending_count + 1))
                elif [ "$bucket" = "fail" ]; then
                    all_success=false
                    failed_count=$((failed_count + 1))
                else
                    success_count=$((success_count + 1))
                fi

                idx=$((idx + 1))
            done
        fi

        local pr_info
        if ! pr_info=$(gh pr view "$pr_number" --repo "$owner/$repo" --json reviewDecision,reviewRequests 2>&1); then
            echo "⚠️  $iteration_display Failed to get PR review status: $pr_info" >&2
            return 1
        fi

        local review_decision=$(echo "$pr_info" | jq -r 'if .reviewDecision == "" then "null" else (.reviewDecision // "null") end')
        local review_requests_count=$(echo "$pr_info" | jq '.reviewRequests | length' 2>/dev/null || echo "0")

        local reviews_pending=false
        if [ "$review_decision" = "REVIEW_REQUIRED" ] || [ "$review_requests_count" -gt 0 ]; then
            reviews_pending=true
        fi

        local review_status="None"
        if [ -n "$review_decision" ] && [ "$review_decision" != "null" ]; then
            review_status="$review_decision"
        elif [ "$review_requests_count" -gt 0 ]; then
            review_status="$review_requests_count review(s) requested"
        fi

        local state_changed=false
        if [ "$check_count" != "$prev_check_count" ] || \
           [ "$success_count" != "$prev_success_count" ] || \
           [ "$pending_count" != "$prev_pending_count" ] || \
           [ "$failed_count" != "$prev_failed_count" ] || \
           [ "$review_status" != "$prev_review_status" ] || \
           [ "$no_checks_configured" != "$prev_no_checks_configured" ] || \
           [ -z "$prev_check_count" ]; then
            state_changed=true
        fi

        if [ "$state_changed" = "true" ]; then
            echo "" >&2
            echo "🔍 $iteration_display Checking PR status (iteration $((iteration + 1))/$max_iterations)..." >&2

            if [ "$no_checks_configured" = "true" ]; then
                echo "   📊 No checks configured" >&2
            else
                echo "   📊 Found $check_count check(s)" >&2
            fi

            if [ "$check_count" -gt 0 ]; then
                echo "   🟢 $success_count    🟡 $pending_count    🔴 $failed_count" >&2
            fi

            echo "   👁️  Review status: $review_status" >&2

            prev_check_count="$check_count"
            prev_success_count="$success_count"
            prev_pending_count="$pending_count"
            prev_failed_count="$failed_count"
            prev_review_status="$review_status"
            prev_no_checks_configured="$no_checks_configured"
        fi

        if [ "$check_count" -eq 0 ] && [ "$checks_json" = "[]" ] && [ "$no_checks_configured" = "false" ]; then
            if [ "$iteration" -lt 18 ]; then
                if [ "$waiting_message_printed" = "false" ]; then
                    echo -n "⏳ Waiting for checks to start... (will timeout after 3 minutes) " >&2
                    waiting_message_printed=true
                fi
                echo -n "." >&2
                sleep 10
                iteration=$((iteration + 1))
                continue
            else
                echo "" >&2
                echo "   ⚠️  No checks found after waiting, proceeding without checks" >&2
                all_completed=true
                all_success=true
            fi
        else
            if [ "$waiting_message_printed" = "true" ]; then
                echo "" >&2
            fi
            waiting_message_printed=false
        fi

        if [ "$all_completed" = "true" ] && [ "$all_success" = "true" ] && [ "$reviews_pending" = "false" ]; then
            if [ "$review_decision" = "APPROVED" ]; then
                echo "✅ $iteration_display All PR checks and reviews passed" >&2
                return 0
            elif { [ "$review_decision" = "null" ] || [ -z "$review_decision" ]; } && [ "$review_requests_count" -eq 0 ]; then
                echo "✅ $iteration_display All PR checks and reviews passed" >&2
                return 0
            fi
        fi

        if [ "$all_completed" = "true" ] && [ "$all_success" = "true" ] && [ "$reviews_pending" = "true" ]; then
            if [ "$state_changed" = "true" ]; then
                echo "   ✅ All checks passed, but waiting for review..." >&2
            fi
        fi

        if [ "$all_completed" = "true" ] && [ "$all_success" = "false" ]; then
            echo "❌ $iteration_display PR checks failed" >&2
            return 1
        fi

        if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
            echo "❌ $iteration_display PR has changes requested in review" >&2
            return 1
        fi

        local waiting_items=()

        if [ "$all_completed" = "false" ]; then
            waiting_items+=("checks to complete")
        fi

        if [ "$reviews_pending" = "true" ]; then
            waiting_items+=("code review")
        fi

        if [ ${#waiting_items[@]} -gt 0 ] && [ "$state_changed" = "true" ]; then
            echo "⏳ Waiting for: ${waiting_items[*]}" >&2
        fi

        sleep 10
        iteration=$((iteration + 1))
    done

    echo "⏱️  $iteration_display Timeout waiting for PR checks and reviews (30 minutes)" >&2
    return 1
}

merge_pr_and_cleanup() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local branch_name="$4"
    local iteration_display="$5"
    local current_branch="$6"

    echo "🔄 $iteration_display Updating branch with latest from main..." >&2
    local update_output
    if update_output=$(gh pr update-branch "$pr_number" --repo "$owner/$repo" 2>&1); then
        echo "📥 $iteration_display Branch updated, re-checking PR status..." >&2
        if ! wait_for_pr_checks "$pr_number" "$owner" "$repo" "$iteration_display"; then
            echo "❌ $iteration_display PR checks failed after branch update" >&2
            return 1
        fi
    else
        if echo "$update_output" | grep -qi "already up-to-date\|is up to date"; then
            echo "✅ $iteration_display Branch already up-to-date" >&2
        else
            echo "⚠️  $iteration_display Branch update failed: $update_output" >&2
            return 1
        fi
    fi

    local merge_flag=""
    case "$MERGE_STRATEGY" in
        squash) merge_flag="--squash" ;;
        merge) merge_flag="--merge" ;;
        rebase) merge_flag="--rebase" ;;
    esac

    echo "🔀 $iteration_display Merging PR #$pr_number with strategy: $MERGE_STRATEGY..." >&2
    if ! gh pr merge "$pr_number" --repo "$owner/$repo" $merge_flag >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to merge PR (may have conflicts or be blocked)" >&2
        return 1
    fi

    echo "📥 $iteration_display Pulling latest from main..." >&2
    if ! git checkout "$current_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $current_branch" >&2
        return 1
    fi

    if ! git pull origin "$current_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to pull from $current_branch" >&2
        return 1
    fi

    echo "🗑️  $iteration_display Deleting local branch: $branch_name" >&2
    git branch -d "$branch_name" >/dev/null 2>&1 || true

    return 0
}

create_iteration_branch() {
    local iteration_display="$1"
    local iteration_num="$2"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo ""
        return 0
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    if [[ "$current_branch" == ${GIT_BRANCH_PREFIX}* ]]; then
        echo "⚠️  $iteration_display Already on iteration branch: $current_branch" >&2
        git checkout main >/dev/null 2>&1 || return 1
        current_branch="main"
    fi

    local date_str=$(date +%Y-%m-%d)

    local random_hash
    if command -v openssl >/dev/null 2>&1; then
        random_hash=$(openssl rand -hex 4)
    elif [ -r /dev/urandom ]; then
        random_hash=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 8)
    else
        random_hash=$(printf "%x" $(($(date +%s) % 100000000)))$(printf "%x" $$)
        random_hash=${random_hash:0:8}
    fi

    # Create meaningful branch name from prompt (sanitized)
    local slug=""
    if [ -n "$PROMPT" ]; then
        # Take first 30 chars of prompt, lowercase, replace spaces/special chars with dashes
        slug=$(echo "$PROMPT" | head -c 30 | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    fi
    slug="${slug:-task}"
    
    local branch_name="${GIT_BRANCH_PREFIX}${slug}/${date_str}-${random_hash}"

    echo "🌿 $iteration_display Creating branch: $branch_name" >&2

    if [ "$DRY_RUN" = "true" ]; then
        echo "   (DRY RUN) Would create branch $branch_name" >&2
        echo "$branch_name"
        return 0
    fi

    if ! git checkout -b "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to create branch" >&2
        echo ""
        return 1
    fi

    echo "$branch_name"
    return 0
}

auto_llm_commit() {
    local iteration_display="$1"
    local branch_name="$2"
    local main_branch="$3"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    local has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        has_changes=true
    fi

    if [ -z "$(git ls-files --others --exclude-standard)" ]; then
        : # no untracked files
    else
        has_changes=true
    fi

    if [ "$has_changes" = "false" ]; then
        echo "🫙 $iteration_display No changes detected, cleaning up branch..." >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo "💬 $iteration_display (DRY RUN) Would commit changes..." >&2
        echo "📦 $iteration_display (DRY RUN) Changes committed on branch: $branch_name" >&2
        echo "📤 $iteration_display (DRY RUN) Would push branch..." >&2
        echo "🔨 $iteration_display (DRY RUN) Would create pull request..." >&2
        echo "✅ $iteration_display (DRY RUN) PR merged: <commit title would appear here>" >&2
        return 0
    fi

    echo "💬 $iteration_display Committing changes..." >&2

    if ! $PROVIDER_CLI -p "$PROMPT_COMMIT_MESSAGE" --allowedTools "Bash(git)" --dangerously-skip-permissions "${EXTRA_CLI_FLAGS[@]}" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to commit changes" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "⚠️  $iteration_display Commit command ran but changes still present (uncommitted or untracked files remain)" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "📦 $iteration_display Changes committed on branch: $branch_name" >&2

    local commit_message=$(git log -1 --format="%B" "$branch_name")
    local commit_title=$(echo "$commit_message" | head -n 1)
    local commit_body=$(echo "$commit_message" | tail -n +4)

    echo "📤 $iteration_display Pushing branch..." >&2
    if ! git push -u origin "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to push branch" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔨 $iteration_display Creating pull request..." >&2
    local pr_output
    if ! pr_output=$(gh pr create --repo "$GITHUB_OWNER/$GITHUB_REPO" --title "$commit_title" --body "$commit_body" --base "$main_branch" 2>&1); then
        echo "⚠️  $iteration_display Failed to create PR: $pr_output" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    local pr_number=$(echo "$pr_output" | grep -oE '(pull/|#)[0-9]+' | grep -oE '[0-9]+' | head -n 1)
    if [ -z "$pr_number" ]; then
        echo "⚠️  $iteration_display Failed to extract PR number from: $pr_output" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔍 $iteration_display PR #$pr_number created, waiting 5 seconds for GitHub to set up..." >&2
    sleep 5
    if ! wait_for_pr_checks "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$iteration_display"; then
        echo "⚠️  $iteration_display PR checks failed or timed out, closing PR and deleting remote branch..." >&2
        gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --delete-branch >/dev/null 2>&1 || true
        echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 1
    fi

    if ! merge_pr_and_cleanup "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$branch_name" "$iteration_display" "$main_branch"; then
        local pr_state=$(gh pr view "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
        if [ "$pr_state" = "OPEN" ]; then
            echo "⚠️  $iteration_display Failed to merge PR, closing it and deleting remote branch..." >&2
            gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --delete-branch >/dev/null 2>&1 || true
        else
            echo "⚠️  $iteration_display PR was merged but cleanup failed" >&2
        fi
        echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 1
    fi

    echo "✅ $iteration_display PR #$pr_number merged: $commit_title" >&2

    if ! git checkout "$main_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $main_branch" >&2
        return 1
    fi

    return 0
}

list_worktrees() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Error: Not in a git repository" >&2
        exit 1
    fi

    echo "📋 Active Git Worktrees:"
    echo ""

    if ! git worktree list 2>/dev/null; then
        echo "❌ Error: Failed to list worktrees" >&2
        exit 1
    fi

    exit 0
}

setup_worktree() {
    if [ -z "$WORKTREE_NAME" ]; then
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Error: Not in a git repository. Worktrees require a git repository." >&2
        exit 1
    fi

    local main_repo_dir=$(git rev-parse --show-toplevel)
    local worktree_path="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"

    if [[ "$worktree_path" != /* ]]; then
        worktree_path="${main_repo_dir}/${worktree_path}"
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    if [ -d "$worktree_path" ]; then
        echo "🌿 Worktree '$WORKTREE_NAME' already exists at: $worktree_path" >&2
        echo "📂 Switching to worktree directory..." >&2

        if ! cd "$worktree_path"; then
            echo "❌ Error: Failed to change to worktree directory: $worktree_path" >&2
            exit 1
        fi

        echo "📥 Pulling latest changes from $current_branch..." >&2
        if ! git pull origin "$current_branch" >/dev/null 2>&1; then
            echo "⚠️  Warning: Failed to pull latest changes (continuing anyway)" >&2
        fi
    else
        echo "🌿 Creating new worktree '$WORKTREE_NAME' at: $worktree_path" >&2

        local base_dir=$(dirname "$worktree_path")
        if [ ! -d "$base_dir" ]; then
            mkdir -p "$base_dir" || {
                echo "❌ Error: Failed to create worktree base directory: $base_dir" >&2
                exit 1
            }
        fi

        if ! git worktree add "$worktree_path" "$current_branch" 2>&1; then
            echo "❌ Error: Failed to create worktree" >&2
            exit 1
        fi

        echo "📂 Switching to worktree directory..." >&2
        if ! cd "$worktree_path"; then
            echo "❌ Error: Failed to change to worktree directory: $worktree_path" >&2
            exit 1
        fi
    fi

    echo "✅ Worktree '$WORKTREE_NAME' ready at: $worktree_path" >&2
    return 0
}

cleanup_worktree() {
    if [ -z "$WORKTREE_NAME" ] || [ "$CLEANUP_WORKTREE" = "false" ]; then
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    local worktree_path="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"

    local main_repo_dir=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$main_repo_dir" ]; then
        if [[ "$worktree_path" != /* ]]; then
            worktree_path="${main_repo_dir}/${worktree_path}"
        fi
    fi

    echo "" >&2
    echo "🗑️  Cleaning up worktree '$WORKTREE_NAME'..." >&2

    local current_dir=$(pwd)
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)

    if [ -n "$git_common_dir" ]; then
        local main_repo=$(dirname "$git_common_dir")
        if [ -d "$main_repo" ]; then
            cd "$main_repo" 2>/dev/null || true
        fi
    fi

    if git worktree remove "$worktree_path" --force 2>/dev/null; then
        echo "✅ Worktree removed successfully" >&2
    else
        echo "⚠️  Warning: Failed to remove worktree (may need manual cleanup)" >&2
        echo "   You can manually remove it with: git worktree remove $worktree_path --force" >&2
    fi
}

get_iteration_display() {
    local iteration_num=$1
    local max_runs=$2
    local extra_iters=$3

    if [ $max_runs -eq 0 ]; then
        echo "($iteration_num)"
    else
        local total=$((max_runs + extra_iters))
        echo "($iteration_num/$total)"
    fi
}

run_llm_iteration() {
    local prompt="$1"
    local flags="$2"
    local error_log="$3"

    if [ "$DRY_RUN" = "true" ]; then
        echo "🤖 (DRY RUN) Would run $PROVIDER_CLI with prompt: $prompt" >&2
        echo "📝 (DRY RUN) Output: This is a simulated response from $PROVIDER_CLI." > "$error_log"
        return 0
    fi

    local temp_stdout=$(mktemp)
    local temp_stderr=$(mktemp)
    local exit_code=0

    $PROVIDER_CLI -p "$prompt" $flags "${EXTRA_CLI_FLAGS[@]}" >"$temp_stdout" 2>"$temp_stderr" || exit_code=$?

    if [ -f "$temp_stdout" ] && [ -s "$temp_stdout" ]; then
        cat "$temp_stdout"
    fi

    if [ -f "$temp_stderr" ] && [ -s "$temp_stderr" ]; then
        cat "$temp_stderr" >&2
        cat "$temp_stderr" > "$error_log"
    fi

    if [ $exit_code -ne 0 ]; then
        if [ ! -s "$error_log" ] && [ -f "$temp_stdout" ] && [ -s "$temp_stdout" ]; then
            local json_error=$(cat "$temp_stdout" | jq -r 'if type == "array" then .[-1] else . end | if .is_error == true then .result // .error // "Unknown error" else empty end' 2>/dev/null || echo "")
            if [ -n "$json_error" ]; then
                echo "$json_error" > "$error_log"
                echo "$json_error" >&2
            fi
        fi

        if [ ! -s "$error_log" ]; then
            {
                echo "$PROVIDER_CLI exited with code $exit_code but produced no error output"
                echo ""
                echo "This usually means:"
                echo "  - $PROVIDER_CLI crashed or failed to start"
                echo "  - An authentication or permission issue occurred"
                echo "  - The command arguments are invalid"
                echo ""
                echo "Try running this command directly to see the full error:"
                echo "  $PROVIDER_CLI -p \"$prompt\" $flags ${EXTRA_CLI_FLAGS[*]}"
            } >> "$error_log"
        fi

        rm -f "$temp_stdout" "$temp_stderr"
        return $exit_code
    fi

    rm -f "$temp_stdout" "$temp_stderr"

    return 0
}

parse_llm_result() {
    local result="$1"

    if ! echo "$result" | jq -e . >/dev/null 2>&1; then
        echo "invalid_json"
        return 1
    fi

    local is_error=$(echo "$result" | jq -r 'if type == "array" then .[-1].is_error // false else .is_error // false end')
    if [ "$is_error" = "true" ]; then
        echo "llm_error"
        return 1
    fi

    echo "success"
    return 0
}

handle_iteration_error() {
    local iteration_display="$1"
    local error_type="$2"
    local error_output="$3"

    error_count=$((error_count + 1))
    extra_iterations=$((extra_iterations + 1))

    case "$error_type" in
        "exit_code")
            echo "" >&2
            echo "❌ $iteration_display Error occurred ($error_count consecutive errors):" >&2
            echo "" >&2
            if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
                echo "Error details:" >&2
                cat "$ERROR_LOG" >&2
            else
                echo "No error details captured in log file" >&2
                echo "Error log path: $ERROR_LOG" >&2
            fi
            echo "" >&2
            ;;
        "invalid_json")
            echo "" >&2
            echo "❌ $iteration_display Error: Invalid JSON response ($error_count consecutive errors):" >&2
            echo "" >&2
            echo "$error_output" >&2
            echo "" >&2
            ;;
        "llm_error")
            echo "" >&2
            echo "❌ $iteration_display Error in $PROVIDER_CLI response ($error_count consecutive errors):" >&2
            echo "" >&2
            echo "$error_output" | jq -r 'if type == "array" then .[-1].result // .[-1] else .result // . end' >&2
            echo "" >&2
            ;;
    esac

    if [ $error_count -ge 3 ]; then
        echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
        exit 1
    fi

    return 1
}

handle_iteration_success() {
    local iteration_display="$1"
    local result="$2"
    local branch_name="$3"
    local main_branch="$4"

    show_step 3 5 "Processing output" "running"

    local result_text=$(echo "$result" | jq -r 'if type == "array" then .[-1].result // empty else .result // empty end')
    if [ -n "$result_text" ] && [ "$QUIET_MODE" != "true" ]; then
        echo "" >&2
        echo -e "  ${C_DIM}Output preview:${C_RESET}" >&2
        echo -e "  ${C_DIM}─────────────────────────────────────────${C_RESET}" >&2
        echo "$result_text" | head -n 3 | while read -r line; do
            echo -e "  ${C_DIM}│${C_RESET} ${line:0:60}" >&2
        done
        local line_count=$(echo "$result_text" | wc -l)
        [ "$line_count" -gt 3 ] && echo -e "  ${C_DIM}│ ... ($((line_count - 3)) more lines)${C_RESET}" >&2
        echo "" >&2
    fi

    if [ -n "$result_text" ] && [[ "$result_text" == *"$COMPLETION_SIGNAL"* ]]; then
        completion_signal_count=$((completion_signal_count + 1))
        echo -e "  ${C_MAGENTA}🎯 Completion signal detected ($completion_signal_count/$COMPLETION_THRESHOLD)${C_RESET}" >&2
    else
        if [ $completion_signal_count -gt 0 ]; then
            echo -e "  ${C_DIM}↻ Completion signal not found, resetting counter${C_RESET}" >&2
        fi
        completion_signal_count=0
    fi

    local cost=$(echo "$result" | jq -r 'if type == "array" then .[-1].total_cost_usd // empty else .total_cost_usd // empty end')
    if [ -n "$cost" ]; then
        printf "  ${C_YELLOW}💰 Cost: \$%.3f${C_RESET}\n" "$cost" >&2
        total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $cost}")
    fi

    show_step 3 5 "Output processed" "success"

    if [ "$ENABLE_COMMITS" = "true" ]; then
        show_step 4 5 "Committing and creating PR" "running"
        if ! auto_llm_commit "$iteration_display" "$branch_name" "$main_branch"; then
            error_count=$((error_count + 1))
            extra_iterations=$((extra_iterations + 1))
            show_step 4 5 "PR merge failed ($error_count consecutive errors)" "error"
            if [ $error_count -ge 3 ]; then
                echo -e "${C_RED}❌ Fatal: 3 consecutive errors occurred. Exiting.${C_RESET}" >&2
                exit 1
            fi
            return 1
        fi
        show_step 4 5 "PR merged successfully" "success"
    else
        show_step 4 5 "Commits disabled, skipping PR" "success"
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
    fi

    show_step 5 5 "Iteration complete" "success"

    show_realtime_stats

    error_count=0
    if [ $extra_iterations -gt 0 ]; then
        extra_iterations=$((extra_iterations - 1))
    fi
    successful_iterations=$((successful_iterations + 1))
    return 0
}

execute_single_iteration() {
    local iteration_num=$1

    local iteration_display=$(get_iteration_display $iteration_num $MAX_RUNS $extra_iterations)

    echo "" >&2
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo -e "${C_BOLD}  🔄 Iteration $iteration_display${C_RESET}" >&2
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo "" >&2

    if [ -n "$MAX_RUNS" ] && [ "$MAX_RUNS" -ne 0 ]; then
        show_progress_bar $successful_iterations $MAX_RUNS
        echo "" >&2
    fi

    local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local branch_name=""

    if [ "$ENABLE_COMMITS" = "true" ]; then
        show_step 1 5 "Creating iteration branch" "running"
        branch_name=$(create_iteration_branch "$iteration_display" "$iteration_num")
        if [ $? -ne 0 ] || [ -z "$branch_name" ]; then
            if git rev-parse --git-dir > /dev/null 2>&1; then
                show_step 1 5 "Creating iteration branch" "error"
                handle_iteration_error "$iteration_display" "exit_code" ""
                return 1
            fi
            branch_name=""
        else
            show_step 1 5 "Created branch: ${branch_name##*/}" "success"
        fi
    fi

    local enhanced_prompt="${PROMPT_WORKFLOW_CONTEXT//COMPLETION_SIGNAL_PLACEHOLDER/$COMPLETION_SIGNAL}

$PROMPT

"

    if [ -f "$NOTES_FILE" ]; then
        local notes_content
        notes_content=$(cat "$NOTES_FILE")
        enhanced_prompt+="## CONTEXT FROM PREVIOUS ITERATION

The following is from $NOTES_FILE, maintained by previous iterations to provide context:

$notes_content

"
    fi

    enhanced_prompt+="## ITERATION NOTES

"

    if [ -f "$NOTES_FILE" ]; then
        enhanced_prompt+="$PROMPT_NOTES_UPDATE_EXISTING"
    else
        enhanced_prompt+="$PROMPT_NOTES_CREATE_NEW"
    fi

    enhanced_prompt+="$PROMPT_NOTES_GUIDELINES"

    show_step 2 5 "Running $PROVIDER_CLI..." "running"

    start_spinner "$PROVIDER_CLI is working... (this may take a few minutes)"

    local result
    local llm_exit_code=0
    result=$(run_llm_iteration "$enhanced_prompt" "$ADDITIONAL_FLAGS" "$ERROR_LOG") || llm_exit_code=$?

    stop_spinner

    if [ $llm_exit_code -ne 0 ]; then
        show_step 2 5 "$PROVIDER_CLI failed (exit code: $llm_exit_code)" "error"
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
        handle_iteration_error "$iteration_display" "exit_code" ""
        return 1
    fi

    show_step 2 5 "$PROVIDER_CLI completed" "success"

    local parse_result=$(parse_llm_result "$result")
    if [ "$?" != "0" ]; then
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
        handle_iteration_error "$iteration_display" "$parse_result" "$result"
        return 1
    fi

    handle_iteration_success "$iteration_display" "$result" "$branch_name" "$main_branch"
    return 0
}

main_loop() {
    start_time=$(date +%s)

    while true; do
        local should_continue=false

        if [ -z "$MAX_RUNS" ] || [ "$MAX_RUNS" -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; then
            should_continue=true
        fi

        if [ -n "$MAX_COST" ] && [ "$(awk "BEGIN {print ($total_cost >= $MAX_COST)}")" = "1" ]; then
            should_continue=false
        fi

        if [ -n "$MAX_DURATION" ] && [ -n "$start_time" ]; then
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -ge $MAX_DURATION ]; then
                echo "" >&2
                echo "⏱️  Maximum duration reached ($(format_duration $elapsed_time))" >&2
                should_continue=false
            fi
        fi

        if [ -n "$MAX_RUNS" ] && [ "$MAX_RUNS" -ne 0 ] && [ $successful_iterations -ge $MAX_RUNS ]; then
            should_continue=false
        fi

        if [ $completion_signal_count -ge $COMPLETION_THRESHOLD ]; then
            echo "" >&2
            echo "🎉 Project completion signal detected $completion_signal_count times consecutively!" >&2
            should_continue=false
        fi

        if [ "$should_continue" = "false" ]; then
            break
        fi

        execute_single_iteration $i

        sleep 1
        i=$((i + 1))
    done
}

show_completion_summary() {
    local elapsed_time=0
    if [ -n "$start_time" ]; then
        local current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
    fi

    echo "" >&2
    echo -e "${C_BOLD}╔═══════════════════════════════════════════════════════════════╗${C_RESET}" >&2
    echo -e "${C_BOLD}║                    🎉 Session Complete!                        ║${C_RESET}" >&2
    echo -e "${C_BOLD}╚═══════════════════════════════════════════════════════════════╝${C_RESET}" >&2
    echo "" >&2

    echo -e "  ${C_BOLD}📊 Final Statistics${C_RESET}" >&2
    echo -e "  ─────────────────────────────────────────" >&2
    echo -e "  ${C_GREEN}✓${C_RESET} Successful iterations: $successful_iterations" >&2
    [ $error_count -gt 0 ] && echo -e "  ${C_RED}✗${C_RESET} Failed iterations: $error_count" >&2
    echo -e "  ${C_BRAND}⏱${C_RESET}  Total time: $(format_duration $elapsed_time)" >&2
    [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ] && printf "  ${C_YELLOW}💰${C_RESET} Total cost: \$%.3f\n" "$total_cost" >&2

    echo "" >&2
    echo -e "  ${C_BOLD}🏁 Stop Reason${C_RESET}" >&2
    echo -e "  ─────────────────────────────────────────" >&2

    if [ $completion_signal_count -ge $COMPLETION_THRESHOLD ]; then
        echo -e "  ${C_GREEN}✨${C_RESET} Project completed! (Detected $completion_signal_count completion signals)" >&2
    elif [ -n "$MAX_RUNS" ] && [ "$MAX_RUNS" -ne 0 ] && [ $successful_iterations -ge $MAX_RUNS ]; then
        echo -e "  ${C_BLUE}🎯${C_RESET} Reached maximum iterations ($MAX_RUNS)" >&2
    elif [ -n "$MAX_COST" ] && [ "$(awk "BEGIN {print ($total_cost >= $MAX_COST)}")" = "1" ]; then
        echo -e "  ${C_YELLOW}💵${C_RESET} Reached budget limit (\$$MAX_COST)" >&2
    elif [ -n "$MAX_DURATION" ] && [ $elapsed_time -ge $MAX_DURATION ]; then
        echo -e "  ${C_MAGENTA}⏰${C_RESET} Reached time limit ($(format_duration $MAX_DURATION))" >&2
    else
        echo -e "  ${C_DIM}Session ended${C_RESET}" >&2
    fi

    echo "" >&2

    if [ $completion_signal_count -lt $COMPLETION_THRESHOLD ] && [ "$QUIET_MODE" != "true" ]; then
        echo -e "  ${C_BOLD}💡 Next Steps${C_RESET}" >&2
        echo -e "  ─────────────────────────────────────────" >&2
        echo -e "  • Check ${C_BRAND}$NOTES_FILE${C_RESET} for iteration notes" >&2
        echo -e "  • Re-run with ${C_DIM}auto-llm --provider $PROVIDER -p \"...\" -m 5${C_RESET} to continue" >&2
        echo "" >&2
    fi
}

main() {
    # Handle "update" command before parsing arguments
    if [ "$1" = "update" ]; then
        shift
        parse_update_flags "$@"
        init_provider
        init_colors
        handle_update_command
        exit 0
    fi

    parse_arguments "$@"

    # Initialize provider (from flag or environment)
    init_provider

    # If no prompt provided, run interactive wizard
    if [ -z "$PROMPT" ]; then
        run_interactive_wizard
    fi

    # Initialize colors after parsing and provider init
    init_colors

    # Skip validation if came from wizard (already validated)
    if [ "$INTERACTIVE_MODE" != "true" ]; then
        validate_arguments
    fi
    validate_requirements

    # Check for updates at startup
    check_for_updates false "$@"

    # Handle --list-worktrees flag
    if [ "$LIST_WORKTREES" = "true" ]; then
        list_worktrees
    fi

    # Setup worktree if specified
    setup_worktree

    # Show startup banner and configuration
    show_startup_banner
    show_config_summary

    ERROR_LOG=$(mktemp)

    # Setup graceful interrupt handling
    trap "handle_interrupt" SIGINT SIGTERM
    trap "rm -f $ERROR_LOG; cleanup_worktree" EXIT

    main_loop
    show_completion_summary

    # Cleanup worktree if requested
    cleanup_worktree
}

if [ -z "$TESTING" ]; then
    main "$@"
fi
