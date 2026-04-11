#!/bin/bash
# TeammateIdle: block if unpushed commits; warn on uncommitted changes.
# Exit 2 to keep the teammate working.

set +e

PROBLEMS=""

CHANGES=$(git status --porcelain 2>/dev/null)
if [ -n "$CHANGES" ]; then
  COUNT=$(echo "$CHANGES" | wc -l | tr -d ' ')
  echo "Warning: ${COUNT} uncommitted/untracked file(s) in working tree." >&2
  echo "If these are yours, commit before going idle." >&2
fi

# In worktrees, branches typically have no upstream — skip the unpushed check
if ! echo "$(git rev-parse --show-toplevel 2>/dev/null)" | grep -q '/.claude/worktrees/'; then
  UNPUSHED=$(git log @{u}.. --oneline 2>/dev/null)
  if [ -n "$UNPUSHED" ]; then
    COUNT=$(echo "$UNPUSHED" | wc -l | tr -d ' ')
    PROBLEMS="${PROBLEMS}You have ${COUNT} unpushed commit(s). Push before going idle.\n"
  fi
fi

if [ -n "$PROBLEMS" ]; then
  echo -e "Not ready to go idle:\n\n${PROBLEMS}" >&2
  exit 2
fi

exit 0
