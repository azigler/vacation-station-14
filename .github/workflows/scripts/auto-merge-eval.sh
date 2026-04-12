#!/usr/bin/env bash
# auto-merge-eval.sh -- decide whether a single PR is ready to auto-merge.
#
# Gates (all must pass):
#   * label `auto-merge` present
#   * no label in AUTO_MERGE_BLOCKLIST
#   * PR is mergeable (no conflicts) and not draft
#   * CI rollup is fully green
#   * diff size bucket is XS (<10 lines touched)
#   * soak window AUTO_MERGE_SOAK_HOURS has elapsed since label was applied
#
# On failure of a soak invariant (CI goes red), the label is removed and
# a comment posted so the contributor knows why.
#
# On merge, appends the PR number to $GITHUB_WORKSPACE/.auto-merged for
# the Discord notification step.

set -euo pipefail

PR="${1:?pr-number required}"
REPO="${GH_REPO:?GH_REPO required}"
LABEL="${AUTO_MERGE_LABEL:-auto-merge}"
BLOCK="${AUTO_MERGE_BLOCKLIST:-needsreview}"
SOAK_HOURS="${AUTO_MERGE_SOAK_HOURS:-12}"
MERGED_FILE="${GITHUB_WORKSPACE:-.}/.auto-merged"

pr_json=$(gh pr view "$PR" --repo "$REPO" --json \
  number,state,isDraft,mergeable,mergeStateStatus,labels,additions,deletions,author,statusCheckRollup)

state=$(jq -r '.state' <<<"$pr_json")
is_draft=$(jq -r '.isDraft' <<<"$pr_json")
mergeable=$(jq -r '.mergeable' <<<"$pr_json")

if [ "$state" != "OPEN" ]; then
  echo "PR #$PR is $state; skipping."
  exit 0
fi
if [ "$is_draft" = "true" ]; then
  echo "PR #$PR is draft; skipping."
  exit 0
fi

labels_csv=$(jq -r '[.labels[].name] | join(",")' <<<"$pr_json")
has_label=false
case ",$labels_csv," in
  *",$LABEL,"*) has_label=true ;;
esac
if [ "$has_label" != "true" ]; then
  echo "PR #$PR does not carry $LABEL; skipping."
  exit 0
fi

# Blocklist
IFS=',' read -r -a blockers <<<"$BLOCK"
for b in "${blockers[@]}"; do
  [ -z "$b" ] && continue
  case ",$labels_csv," in
    *",$b,"*)
      echo "PR #$PR carries blocking label '$b'; skipping."
      exit 0
      ;;
  esac
done

# Size gate (XS only)
additions=$(jq -r '.additions' <<<"$pr_json")
deletions=$(jq -r '.deletions' <<<"$pr_json")
total=$((additions + deletions))
if [ "$total" -ge 10 ]; then
  echo "PR #$PR size=$total lines exceeds XS threshold; removing label."
  gh pr edit "$PR" --repo "$REPO" --remove-label "$LABEL" || true
  gh pr comment "$PR" --repo "$REPO" --body \
    "Removed \`$LABEL\` label: diff grew past the XS size bucket ($total lines). A human should review." || true
  exit 0
fi

# CI rollup
ci_failing=$(jq '[.statusCheckRollup[]? | select(.conclusion as $c |
  ["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED"] | index($c))] | length' <<<"$pr_json")
ci_pending=$(jq '[.statusCheckRollup[]? | select(.conclusion as $c |
  ["PENDING","IN_PROGRESS","QUEUED","WAITING",null] | index($c))] | length' <<<"$pr_json")

if [ "$ci_failing" -gt 0 ]; then
  echo "PR #$PR CI failing ($ci_failing); stripping $LABEL."
  gh pr edit "$PR" --repo "$REPO" --remove-label "$LABEL" || true
  gh pr comment "$PR" --repo "$REPO" --body \
    "Removed \`$LABEL\` label: CI is red. Re-apply once the failures are resolved." || true
  exit 0
fi
if [ "$ci_pending" -gt 0 ]; then
  echo "PR #$PR CI still pending; waiting."
  exit 0
fi

# Conflict gate
if [ "$mergeable" = "CONFLICTING" ]; then
  echo "PR #$PR has conflicts; stripping $LABEL."
  gh pr edit "$PR" --repo "$REPO" --remove-label "$LABEL" || true
  gh pr comment "$PR" --repo "$REPO" --body \
    "Removed \`$LABEL\` label: merge conflicts detected. Rebase and re-label to resume." || true
  exit 0
fi
if [ "$mergeable" != "MERGEABLE" ]; then
  echo "PR #$PR mergeable=$mergeable; waiting for GitHub to compute."
  exit 0
fi

# Soak timer: label must have been applied at least SOAK_HOURS ago.
labeled_at=$(gh api "repos/$REPO/issues/$PR/events" --paginate \
  --jq "[.[] | select(.event == \"labeled\" and .label.name == \"$LABEL\") | .created_at] | last" \
  || echo "")
if [ -z "$labeled_at" ] || [ "$labeled_at" = "null" ]; then
  echo "PR #$PR: could not determine label time; waiting."
  exit 0
fi

now_s=$(date -u +%s)
labeled_s=$(date -u -d "$labeled_at" +%s)
elapsed_h=$(( (now_s - labeled_s) / 3600 ))
if [ "$elapsed_h" -lt "$SOAK_HOURS" ]; then
  remaining=$(( SOAK_HOURS - elapsed_h ))
  echo "PR #$PR soaking ($elapsed_h/${SOAK_HOURS}h, ${remaining}h remaining)."
  exit 0
fi

echo "PR #$PR passes all gates; squash-merging."
gh pr merge "$PR" --repo "$REPO" --squash --delete-branch --auto || \
  gh pr merge "$PR" --repo "$REPO" --squash --delete-branch

echo "$PR" >> "$MERGED_FILE"
echo "Merged PR #$PR."
