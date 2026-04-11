#!/bin/bash
# PostToolUse (Edit|Write): light checks after file writes.
# For C#, a full build is too slow per-file. We do syntax/style checks only.
# Full build verification happens at commit time or via /build skill.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

set +e

case "$FILE_PATH" in
  *.cs)
    # Check for CRLF (CI rejects it)
    if file "$FILE_PATH" 2>/dev/null | grep -q 'CRLF'; then
      echo "File has CRLF line endings. CI requires LF." >&2
      echo "Fix: dos2unix $FILE_PATH" >&2
      exit 2
    fi

    # Check for tabs (editorconfig requires 4-space indent for C#)
    if grep -l $'\t' "$FILE_PATH" >/dev/null 2>&1; then
      echo "File has tabs. C# files must use 4-space indentation." >&2
      exit 2
    fi
    ;;
  *.yml|*.yaml)
    # Check for CRLF
    if file "$FILE_PATH" 2>/dev/null | grep -q 'CRLF'; then
      echo "File has CRLF line endings. CI requires LF." >&2
      exit 2
    fi

    # Check for tabs (YAML requires spaces, 2-space indent for this project)
    if grep -l $'\t' "$FILE_PATH" >/dev/null 2>&1; then
      echo "YAML file has tabs. Use 2-space indentation." >&2
      exit 2
    fi
    ;;
  *.ftl)
    # Fluent files: just CRLF check
    if file "$FILE_PATH" 2>/dev/null | grep -q 'CRLF'; then
      echo "File has CRLF line endings. CI requires LF." >&2
      exit 2
    fi
    ;;
esac

exit 0
