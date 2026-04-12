#!/bin/bash
# PostToolUse (Edit|Write): fast per-file checks after writes.
#
# Strategy:
#   - Cheap checks always run (CRLF, tabs in C#)
#   - dotnet format --include <file> runs per-file on .cs (~1-2s)
#   - Full dotnet build is too slow for per-file — runs via /build skill or CI

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

set +e

# Skip files outside the repo or in known-auto directories
case "$FILE_PATH" in
  */RobustToolbox/*) exit 0 ;;  # engine submodule, don't touch
  */bin/*|*/obj/*) exit 0 ;;    # build artifacts
  */.git/*) exit 0 ;;
esac

# Common: CRLF check
if file "$FILE_PATH" 2>/dev/null | grep -q 'CRLF'; then
  echo "File has CRLF line endings. CI requires LF." >&2
  echo "Fix: dos2unix '$FILE_PATH'" >&2
  exit 2
fi

case "$FILE_PATH" in
  *.cs)
    # Tab check (editorconfig: 4-space C# indent)
    if grep -l $'\t' "$FILE_PATH" >/dev/null 2>&1; then
      echo "C# file has tabs. Use 4-space indentation." >&2
      exit 2
    fi

    # dotnet format on the single file (fast, ~1-2s)
    if command -v dotnet &>/dev/null && [ -f "SpaceStation14.slnx" ]; then
      # Resolve absolute path for dotnet format --include
      ABS_PATH=$(realpath "$FILE_PATH")
      OUTPUT=$(dotnet format whitespace --include "$ABS_PATH" --verify-no-changes --no-restore 2>&1)
      FORMAT_EXIT=$?

      if [ $FORMAT_EXIT -ne 0 ]; then
        # Auto-fix instead of failing. Reports back what changed.
        dotnet format whitespace --include "$ABS_PATH" --no-restore >/dev/null 2>&1
        echo "Note: auto-fixed whitespace in $(basename "$FILE_PATH")" >&2
        # Don't block — the file is now correct
      fi
    fi
    ;;

  *.yml|*.yaml)
    # Tab check (YAML: 2-space indent, never tabs)
    if grep -l $'\t' "$FILE_PATH" >/dev/null 2>&1; then
      echo "YAML file has tabs. Use 2-space indentation." >&2
      exit 2
    fi
    ;;

  *.ftl)
    # Fluent files: CRLF check already ran above
    ;;
esac

exit 0
