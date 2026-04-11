#!/bin/bash
# TaskCompleted: verify modified files don't have CRLF or tab issues.
# Full dotnet build is too slow to run here; it runs via /build skill or CI.

set +e

DIRTY=$(git diff --name-only 2>/dev/null)
STAGED=$(git diff --cached --name-only 2>/dev/null)
MODIFIED=$(printf '%s\n%s' "$DIRTY" "$STAGED" | sort -u | grep -v '^$')

[ -z "$MODIFIED" ] && exit 0

ERRORS=""

# Check for CRLF line endings in any modified file
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ ! -f "$file" ] && continue
  case "$file" in
    *.cs|*.yml|*.yaml|*.ftl|*.md|*.sh|*.py)
      if file "$file" 2>/dev/null | grep -q 'CRLF'; then
        ERRORS="${ERRORS}CRLF line endings: ${file}\n"
      fi
      ;;
  esac
done <<< "$MODIFIED"

# Check for tabs in C# files
CS_FILES=$(echo "$MODIFIED" | grep -E '\.cs$')
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ ! -f "$file" ] && continue
  if grep -l $'\t' "$file" >/dev/null 2>&1; then
    ERRORS="${ERRORS}Tabs in C# file (use 4-space indent): ${file}\n"
  fi
done <<< "$CS_FILES"

# Check for RobustToolbox submodule changes
if echo "$MODIFIED" | grep -q '^RobustToolbox$'; then
  ERRORS="${ERRORS}RobustToolbox submodule modified - CI will reject.\n"
fi

if [ -n "$ERRORS" ]; then
  echo -e "Task has issues. Fix before marking complete:\n\n${ERRORS}" >&2
  exit 2
fi

exit 0
