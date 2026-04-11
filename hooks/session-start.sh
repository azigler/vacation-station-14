#!/bin/bash
# SessionStart: inject project context so the agent starts oriented.

echo "=== Vacation Station 14 Session Context ==="

# Detect worktree: .git is a file (not a dir) in worktrees, and path contains /.claude/worktrees/
IN_WORKTREE=false
GIT_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -f ".git" ] || echo "$GIT_TOPLEVEL" | grep -q '/.claude/worktrees/'; then
  IN_WORKTREE=true
fi

if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  echo "Branch: ${BRANCH:-detached}"
  DIRTY=$(git status --short 2>/dev/null | head -10)
  if [ -n "$DIRTY" ]; then
    echo "Dirty files:"
    echo "$DIRTY"
  fi

  # Check RobustToolbox submodule
  if [ -d "RobustToolbox" ] && [ ! -f "RobustToolbox/Robust.Shared/Robust.Shared.csproj" ]; then
    echo ""
    echo "WARNING: RobustToolbox submodule not initialized."
    echo "Run: python RUN_THIS.py  (or: git submodule update --init --recursive)"
  fi
fi

if command -v br &>/dev/null; then
  # In a worktree, symlink .beads/ to the main worktree's copy (single source of truth)
  if $IN_WORKTREE && [ -d ".beads" ] && [ ! -L ".beads" ]; then
    MAIN_WT=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
    CUR_WT=$(pwd -P)
    if [ -n "$MAIN_WT" ] && [ -d "$MAIN_WT/.beads" ] && [ "$CUR_WT" != "$MAIN_WT" ]; then
      rm -rf .beads
      ln -sn "$MAIN_WT/.beads" .beads
      echo "Symlinked .beads/ -> $MAIN_WT/.beads/"
    fi
  fi

  # Ensure .gitattributes has merge=union for JSONL (needed for worktree merges)
  if ! $IN_WORKTREE && [ -d ".beads" ] && ! grep -q 'merge=union' .gitattributes 2>/dev/null; then
    echo '.beads/*.jsonl merge=union' >> .gitattributes
    git add .gitattributes && git commit -q -m ":wrench: config: add gitattributes for JSONL merge" 2>/dev/null
  fi

  br sync --import-only 2>/dev/null
  BEADS=$(br list 2>/dev/null)
  if [ -n "$BEADS" ]; then
    echo ""
    echo "Open beads:"
    echo "$BEADS"
  fi
fi

echo ""
echo "Pipeline: /orient -> /spec -> /review -> /test -> /impl -> /branch"
echo ""

exit 0
