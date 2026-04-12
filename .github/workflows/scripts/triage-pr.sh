#!/usr/bin/env bash
# triage-pr.sh -- triage a single PR.
#
# Responsibilities (in order):
#   1. Close if the PR is a draft (polite template).
#   2. Close if the author is in .github/banned-authors.yml.
#   3. If author is a trusted bot AND diff is size-XS AND CI is green,
#      apply the `auto-merge` label.
#   4. Post (or refresh) the triage-summary comment.
#
# Environment:
#   GH_TOKEN           -- GitHub token (required)
#   GH_REPO            -- owner/repo (required)
#   TRIAGE_POST_SUMMARY-- "true" always, "if-missing" only when marker absent,
#                         "false" to skip the comment entirely
#
# Usage: triage-pr.sh <pr-number>
#
# The output comment carries the HTML marker <!-- vs14-triage-summary -->
# so downstream agents (see .claude/skills/vibe-maintainer) can locate
# and parse it reliably.

set -euo pipefail

PR="${1:?pr-number required}"
REPO="${GH_REPO:?GH_REPO required}"
MODE="${TRIAGE_POST_SUMMARY:-true}"

MARKER="<!-- vs14-triage-summary -->"
TRUSTED_FILE=".github/trusted-authors.yml"
BANNED_FILE=".github/banned-authors.yml"

# --- Close-template helpers --------------------------------------------------

draft_close_body() {
  cat <<'EOF'
Closing this PR because it is marked as a draft.

VS14 policy (see [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md)) is to
open a PR when you want review and keep work-in-progress on your own
branch. Please re-open (or push a fresh PR) once the change is ready.

Thanks for the contribution -- no hard feelings, this is automation.
EOF
}

banned_close_body() {
  cat <<'EOF'
Closing this PR because the author is on the VS14 no-contact list
(`.github/banned-authors.yml`). This is a maintainer decision, not an
automated accident. If you believe this is in error, contact the
maintainer directly; do not open a replacement PR from the same account.
EOF
}

# --- Fetch PR context --------------------------------------------------------

pr_json=$(gh pr view "$PR" --repo "$REPO" --json \
  number,title,author,isDraft,state,mergeable,baseRefName,headRefOid,labels,files,additions,deletions,changedFiles,statusCheckRollup,url)

state=$(jq -r '.state' <<<"$pr_json")
if [ "$state" != "OPEN" ]; then
  echo "PR #$PR is $state; nothing to do."
  exit 0
fi

author=$(jq -r '.author.login' <<<"$pr_json")
is_draft=$(jq -r '.isDraft' <<<"$pr_json")
mergeable=$(jq -r '.mergeable' <<<"$pr_json")
additions=$(jq -r '.additions' <<<"$pr_json")
deletions=$(jq -r '.deletions' <<<"$pr_json")
changed_files=$(jq -r '.changedFiles' <<<"$pr_json")
labels=$(jq -r '[.labels[].name] | join(", ")' <<<"$pr_json")

# Author logins for bots carry a `[bot]` suffix in `gh pr view`.
author_key="$author"
if jq -e '.author.is_bot // false' <<<"$pr_json" >/dev/null 2>&1; then
  author_key="${author}[bot]"
fi

# --- Draft close -------------------------------------------------------------

if [ "$is_draft" = "true" ]; then
  echo "PR #$PR is a draft; closing."
  draft_close_body | gh pr comment "$PR" --repo "$REPO" --body-file -
  gh pr close "$PR" --repo "$REPO"
  exit 0
fi

# --- Banned-author close -----------------------------------------------------

if [ -f "$BANNED_FILE" ]; then
  if yq -e ".users[] | select(. == \"$author_key\")" "$BANNED_FILE" >/dev/null 2>&1; then
    echo "PR #$PR author $author_key is banned; closing."
    banned_close_body | gh pr comment "$PR" --repo "$REPO" --body-file -
    gh pr close "$PR" --repo "$REPO"
    exit 0
  fi
fi

# --- CI rollup ---------------------------------------------------------------

ci_summary=$(jq -r '
  [.statusCheckRollup[]? | {
    name: (.name // .context // "check"),
    conclusion: (.conclusion // .state // "PENDING")
  }]
' <<<"$pr_json")

ci_failing=$(jq '[.[] | select(.conclusion as $c |
  ["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED"] | index($c))] | length' <<<"$ci_summary")
ci_pending=$(jq '[.[] | select(.conclusion as $c |
  ["PENDING","IN_PROGRESS","QUEUED","WAITING"] | index($c))] | length' <<<"$ci_summary")
ci_success=$(jq '[.[] | select(.conclusion == "SUCCESS")] | length' <<<"$ci_summary")
ci_total=$(jq 'length' <<<"$ci_summary")

if [ "$ci_total" -eq 0 ]; then
  ci_state="none"
elif [ "$ci_failing" -gt 0 ]; then
  ci_state="failing"
elif [ "$ci_pending" -gt 0 ]; then
  ci_state="pending"
else
  ci_state="green"
fi

# --- Size classification (mirrors labeler-size.yml bucket boundaries) --------

total_lines=$((additions + deletions))
if [ "$total_lines" -lt 10 ]; then
  size_bucket="XS"
elif [ "$total_lines" -lt 100 ]; then
  size_bucket="S"
elif [ "$total_lines" -lt 1000 ]; then
  size_bucket="M"
elif [ "$total_lines" -lt 5000 ]; then
  size_bucket="L"
else
  size_bucket="XL"
fi

# --- Conflict status ---------------------------------------------------------

case "$mergeable" in
  MERGEABLE)   conflict_state="clean" ;;
  CONFLICTING) conflict_state="conflicts" ;;
  *)           conflict_state="unknown" ;;
esac

# --- Trusted-bot auto-merge label --------------------------------------------

trusted_bot="false"
if [ -f "$TRUSTED_FILE" ]; then
  if yq -e ".bots[] | select(. == \"$author_key\")" "$TRUSTED_FILE" >/dev/null 2>&1; then
    trusted_bot="true"
  fi
fi
trusted_human="false"
if [ -f "$TRUSTED_FILE" ]; then
  if yq -e ".humans[] | select(. == \"$author_key\")" "$TRUSTED_FILE" >/dev/null 2>&1; then
    trusted_human="true"
  fi
fi

should_auto_merge="false"
if [ "$trusted_bot" = "true" ] && [ "$size_bucket" = "XS" ] && [ "$ci_state" = "green" ] && [ "$conflict_state" = "clean" ]; then
  should_auto_merge="true"
fi

if [ "$should_auto_merge" = "true" ]; then
  if ! echo "$labels" | grep -q "auto-merge"; then
    echo "PR #$PR qualifies for auto-merge (trusted bot + XS + green); labeling."
    gh pr edit "$PR" --repo "$REPO" --add-label "auto-merge" || true
  fi
fi

# --- Categorization hint -----------------------------------------------------

# Top-level areas touched (used both for categorization and pr-hygiene).
areas=$(jq -r '[.files[].path] |
  map(
    if   startswith("Content.Server/_VS/")    then "vs-server"
    elif startswith("Content.Client/_VS/")    then "vs-client"
    elif startswith("Content.Shared/_VS/")    then "vs-shared"
    elif startswith("Content.Server/")        then "server"
    elif startswith("Content.Client/")        then "client"
    elif startswith("Content.Shared/")        then "shared"
    elif startswith("Resources/Prototypes/")  then "prototypes"
    elif startswith("Resources/Locale/")      then "locale"
    elif startswith("Resources/Textures/")    then "textures"
    elif startswith("Resources/Audio/")       then "audio"
    elif startswith("Resources/")             then "resources"
    elif startswith("ops/")                   then "ops"
    elif startswith("docs/")                  then "docs"
    elif startswith(".github/")               then "github"
    elif startswith(".claude/")               then "claude"
    else "other"
    end
  ) | unique | join(",")' <<<"$pr_json")

if [ "$should_auto_merge" = "true" ]; then
  category="easy-win"
elif [ "$ci_state" = "failing" ] || [ "$conflict_state" = "conflicts" ]; then
  category="fix-merge-candidate"
elif [ "$size_bucket" = "XS" ] || [ "$size_bucket" = "S" ]; then
  category="easy-win"
elif [ "$trusted_human" = "true" ] && [ "$size_bucket" != "XL" ]; then
  category="easy-win"
else
  category="needs-deeper-look"
fi

# --- Build and post triage summary ------------------------------------------

should_post="true"
if [ "$MODE" = "false" ]; then
  should_post="false"
fi
if [ "$MODE" = "if-missing" ]; then
  existing=$(gh pr view "$PR" --repo "$REPO" --json comments \
    --jq "[.comments[] | select(.body | contains(\"$MARKER\"))] | length")
  if [ "$existing" != "0" ]; then
    should_post="false"
  fi
fi

if [ "$should_post" = "true" ]; then
  tmpfile=$(mktemp)
  {
    printf '%s\n' "$MARKER"
    printf '## Triage summary\n\n'
    printf '<!-- This block is machine-readable; see .claude/skills/vibe-maintainer. -->\n\n'
    printf '| key | value |\n'
    printf '|-----|-------|\n'
    printf '| author | `%s` |\n' "$author_key"
    printf '| trusted-bot | `%s` |\n' "$trusted_bot"
    printf '| trusted-human | `%s` |\n' "$trusted_human"
    printf '| size-bucket | `%s` |\n' "$size_bucket"
    printf '| files-changed | `%s` |\n' "$changed_files"
    printf '| additions | `%s` |\n' "$additions"
    printf '| deletions | `%s` |\n' "$deletions"
    printf '| ci-state | `%s` |\n' "$ci_state"
    printf '| ci-success | `%s` |\n' "$ci_success"
    printf '| ci-failing | `%s` |\n' "$ci_failing"
    printf '| ci-pending | `%s` |\n' "$ci_pending"
    printf '| conflicts | `%s` |\n' "$conflict_state"
    printf '| areas | `%s` |\n' "$areas"
    printf '| category | `%s` |\n' "$category"
    printf '| labels | `%s` |\n' "$labels"
    printf '| auto-merge-eligible | `%s` |\n' "$should_auto_merge"

    printf '\n### CI checks\n\n'
    if [ "$ci_total" -eq 0 ]; then
      printf '_No status checks reported yet._\n'
    else
      printf '| check | conclusion |\n|---|---|\n'
      jq -r '.[] | "| \(.name) | `\(.conclusion)` |"' <<<"$ci_summary"
    fi

    printf '\n_Posted by `.github/workflows/pr-triage.yml`. Re-run with the\n'
    printf "%s\n" '`PR Triage` workflow'"'"'s `workflow_dispatch` button to refresh._'
  } >"$tmpfile"

  # Replace any prior marker-comment: find + delete, then post fresh.
  prior_ids=$(gh api "repos/$REPO/issues/$PR/comments" \
    --jq "[.[] | select(.body | contains(\"$MARKER\")) | .id] | .[]" || true)
  for cid in $prior_ids; do
    gh api -X DELETE "repos/$REPO/issues/comments/$cid" >/dev/null 2>&1 || true
  done

  gh pr comment "$PR" --repo "$REPO" --body-file "$tmpfile"
  rm -f "$tmpfile"
fi

echo "Triage complete for PR #$PR (category=$category, ci=$ci_state, size=$size_bucket)."
