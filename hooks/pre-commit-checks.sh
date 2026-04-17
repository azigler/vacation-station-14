#!/bin/bash
# PreToolUse (Bash): checks before git commit for SS14 project.
# Exit 2 = block the commit and feed errors to agent.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block overly-broad git add at ANY time, not just when chained with commit.
# Matches `git add -A`, `git add --all`, and `git add .` (bare dot, optionally
# followed by whitespace/end/chain operator). Anchored so `git add -Ax` or
# `git add Ax` don't false-positive.
if echo "$COMMAND" | grep -qE '(^|[[:space:];&|])git add[[:space:]]+(-A([[:space:]]|$)|--all([[:space:]]|$)|\.([[:space:]]|$|[;&|]))'; then
  echo "Blocked: use 'git add <specific-files>', never 'git add .', 'git add -A', or 'git add --all'." >&2
  echo "Reason: selective staging prevents accidentally committing secrets, WIP, or gitignored state." >&2
  exit 2
fi

# Only intercept git commit commands for the rest of the checks below
case "$COMMAND" in
  git\ commit*|*"&& git commit"*|*"; git commit"*) ;;
  *) exit 0 ;;
esac

# If git add is chained before git commit, run it now so staged files are visible
if echo "$COMMAND" | grep -qP 'git add .+&&'; then
  ADD_CMD=$(echo "$COMMAND" | grep -oP 'git add [^&;]+')
  if echo "$ADD_CMD" | grep -qP 'git add\s+(-A|--all|\.\s*$)'; then
    echo "Blocked: use 'git add <specific-files>', never 'git add .', 'git add -A', or 'git add --all'." >&2
    exit 2
  fi
  eval "$ADD_CMD" 2>/dev/null
fi

set +e

# 1. Sync bead state (skip auto-stage in worktrees)
if command -v br &>/dev/null; then
  br sync --flush-only 2>/dev/null || true
  if ! echo "$(git rev-parse --show-toplevel 2>/dev/null)" | grep -q '/.claude/worktrees/'; then
    git add .beads/issues.jsonl 2>/dev/null || true
  fi
fi

# 2. Warn on missing bead trailer
if ! echo "$COMMAND" | grep -q 'Bead:'; then
  echo "Warning: commit message has no Bead: trailer." >&2
fi

# 3. Hard blocks for SS14 CI
STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

if echo "$STAGED" | grep -q '^RobustToolbox$'; then
  echo "BLOCKED: RobustToolbox submodule is staged. CI will reject this PR." >&2
  echo "Fix: git checkout upstream/master RobustToolbox" >&2
  exit 2
fi

# 4. CRLF check on staged files
if [ -n "$STAGED" ]; then
  CRLF_FILES=""
  while IFS= read -r file; do
    case "$file" in
      */RobustToolbox/*) continue ;;  # engine submodule
    esac
    if [ -f "$file" ] && file "$file" 2>/dev/null | grep -q 'CRLF'; then
      CRLF_FILES="${CRLF_FILES}${file}\n"
    fi
  done <<< "$STAGED"

  if [ -n "$CRLF_FILES" ]; then
    echo "BLOCKED: files with CRLF line endings (CI will reject):" >&2
    echo -e "$CRLF_FILES" >&2
    echo "Fix: dos2unix <file>" >&2
    exit 2
  fi
fi

# 5. dotnet format --verify-no-changes on staged C# files (only VS14 code)
#    Skip in worktrees (slower, orchestrator runs quality gate)
CS_STAGED=$(echo "$STAGED" | grep -E '^(Content\.(Server|Client|Shared))/_VS/.*\.cs$' || true)
if [ -n "$CS_STAGED" ] \
   && ! echo "$(git rev-parse --show-toplevel 2>/dev/null)" | grep -q '/.claude/worktrees/' \
   && command -v dotnet &>/dev/null \
   && [ -f "SpaceStation14.slnx" ]; then
  # Build the --include list
  INCLUDE_ARGS=""
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    INCLUDE_ARGS="$INCLUDE_ARGS --include $file"
  done <<< "$CS_STAGED"

  if [ -n "$INCLUDE_ARGS" ]; then
    OUTPUT=$(dotnet format whitespace $INCLUDE_ARGS --verify-no-changes --no-restore 2>&1)
    if [ $? -ne 0 ]; then
      echo "BLOCKED: dotnet format whitespace check failed on _VS/ files." >&2
      echo "$OUTPUT" >&2
      echo "Fix: dotnet format whitespace $INCLUDE_ARGS --no-restore" >&2
      exit 2
    fi
  fi
fi

exit 0
