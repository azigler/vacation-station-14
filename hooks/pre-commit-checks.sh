#!/bin/bash
# PreToolUse (Bash): checks before git commit for SS14 project.
# Exit 2 = block the commit and feed errors to agent.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
case "$COMMAND" in
  git\ commit*|*"&& git commit"*|*"; git commit"*) ;;
  *) exit 0 ;;
esac

# If git add is chained before git commit, run it now so staged files are visible
if echo "$COMMAND" | grep -qP 'git add .+&&'; then
  ADD_CMD=$(echo "$COMMAND" | grep -oP 'git add [^&;]+')
  # Block overly-broad staging
  if echo "$ADD_CMD" | grep -qP 'git add\s+(-A|--all|\.\s*$)'; then
    echo "Blocked: use 'git add <specific-files>', never 'git add .', 'git add -A', or 'git add --all'." >&2
    exit 2
  fi
  eval "$ADD_CMD" 2>/dev/null
fi

set +e
FAILED=0

# 1. Sync bead state (skip auto-stage in worktrees)
if command -v br &>/dev/null; then
  br sync --flush-only 2>/dev/null || true
  if ! echo "$(git rev-parse --show-toplevel 2>/dev/null)" | grep -q '/.claude/worktrees/'; then
    git add .beads/issues.jsonl 2>/dev/null || true
  fi
fi

if ! echo "$COMMAND" | grep -q 'Bead:'; then
  echo "Warning: commit message has no Bead: trailer." >&2
fi

# 2. Check for RobustToolbox submodule in staged changes (CI rejects this)
STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

if echo "$STAGED" | grep -q '^RobustToolbox$'; then
  echo "BLOCKED: RobustToolbox submodule is staged. CI will reject this PR." >&2
  echo "Fix: git checkout upstream/master RobustToolbox" >&2
  exit 2
fi

# 3. Check for CRLF line endings in staged files (CI rejects them)
if [ -n "$STAGED" ]; then
  CRLF_FILES=""
  while IFS= read -r file; do
    if [ -f "$file" ] && file "$file" 2>/dev/null | grep -q 'CRLF'; then
      CRLF_FILES="${CRLF_FILES}${file}\n"
    fi
  done <<< "$STAGED"

  if [ -n "$CRLF_FILES" ]; then
    echo "BLOCKED: files with CRLF line endings (CI will reject):" >&2
    echo -e "$CRLF_FILES" >&2
    echo "Fix: dos2unix <file> or re-save with LF endings" >&2
    exit 2
  fi
fi

if [ $FAILED -ne 0 ]; then
  echo "Pre-commit checks failed. Fix errors before committing." >&2
  exit 2
fi

exit 0
