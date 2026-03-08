#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_OWNER:?PROJECT_OWNER is required}"
: "${PROJECT_NUMBER:?PROJECT_NUMBER is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"
: "${COMMIT_MESSAGE:?COMMIT_MESSAGE is required}"
: "${COMMIT_TIMESTAMP:?COMMIT_TIMESTAMP is required}"

# Graceful skip when GH token cannot access Project API (common with wrong PAT type/scopes).
if ! gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json >/dev/null 2>&1; then
  echo "Project metadata sync skipped: token cannot access project ${PROJECT_OWNER}/${PROJECT_NUMBER}."
  exit 0
fi

PROJECT_OWNER="${PROJECT_OWNER}"
PROJECT_NUMBER="${PROJECT_NUMBER}"
COMMIT_SHA="${COMMIT_SHA}"
COMMIT_MESSAGE="${COMMIT_MESSAGE}"
COMMIT_TIMESTAMP="${COMMIT_TIMESTAMP}"
ISSUE_LINK="${ISSUE_LINK:-}"
AUTO_CREATE_MISSING="${AUTO_CREATE_MISSING:-false}"

SHORT_SHA="${COMMIT_SHA:0:7}"
LAST_UPDATE_DATE="$(echo "$COMMIT_TIMESTAMP" | cut -d'T' -f1)"

FIELDS_JSON=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json)
PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json --jq '.id')
ITEMS_JSON=$(gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 300 --format json)

field_id() {
  local name="$1"
  echo "$FIELDS_JSON" | jq -r --arg n "$name" '.fields[] | select(.name==$n) | .id'
}
opt_id() {
  local field="$1" opt="$2"
  echo "$FIELDS_JSON" | jq -r --arg f "$field" --arg o "$opt" '.fields[] | select(.name==$f) | .options[] | select(.name==$o) | .id'
}
find_item_id_by_sprint() {
  local sprint="$1"
  echo "$ITEMS_JSON" | jq -r --arg s "$sprint" '.items[] | select((.sprint // "") == $s) | .id' | head -n1
}

LAST_COMMIT_FIELD=$(field_id "Last Commit")
COMMIT_TS_FIELD=$(field_id "Commit Timestamp")
LAST_UPDATE_FIELD=$(field_id "Last Update")
ISSUE_LINK_FIELD=$(field_id "Issue Link")
DELIVERY_MODE_FIELD=$(field_id "Delivery Mode")
WORK_ORIGIN_FIELD=$(field_id "Work Origin")
SPRINT_FIELD=$(field_id "Sprint")
WAVE_FIELD=$(field_id "Wave")
TYPE_FIELD=$(field_id "Type")
PRIORITY_FIELD=$(field_id "Priority")
SQL_REQUIRED_FIELD=$(field_id "SQL Required")

MODE_ADV=$(opt_id "Delivery Mode" "Advancing")
MODE_REVIEW=$(opt_id "Delivery Mode" "Review Loop")
ORIGIN_SPRINT=$(opt_id "Work Origin" "Sprint Planned")
ORIGIN_ISSUE=$(opt_id "Work Origin" "Issue-Driven")

TYPE_HOTFIX=$(opt_id "Type" "Hotfix")
PRIO_HIGH=$(opt_id "Priority" "High")
SQL_NO=$(opt_id "SQL Required" "No")

if [[ -z "$LAST_COMMIT_FIELD" || -z "$LAST_UPDATE_FIELD" || -z "$COMMIT_TS_FIELD" ]]; then
  echo "Required project fields missing. Expected: Last Commit, Commit Timestamp, Last Update" >&2
  exit 1
fi

if [[ "$COMMIT_MESSAGE" =~ ^fix: ]]; then
  MODE_OPT="$MODE_REVIEW"
  ORIGIN_OPT="$ORIGIN_ISSUE"
else
  MODE_OPT="$MODE_ADV"
  ORIGIN_OPT="$ORIGIN_SPRINT"
fi

set_text() {
  local item_id="$1" field_id="$2" value="$3"
  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$field_id" --text "$value" >/dev/null
}
set_date() {
  local item_id="$1" field_id="$2" value="$3"
  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$field_id" --date "$value" >/dev/null
}
set_select() {
  local item_id="$1" field_id="$2" option_id="$3"
  gh project item-edit --id "$item_id" --project-id "$PROJECT_ID" --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
}

create_missing_item() {
  local sprint="$1"
  local title="$2"
  gh project item-create "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --title "$title" --body "Auto-created from commit: $SHORT_SHA" --format json --jq '.id'
}

extract_sprints() {
  local msg="$1"
  echo "$msg" | grep -Eo 'S-COM[0-9]+|S-HF[0-9]+|S-[A-Z]{2,6}[0-9]+|S[0-9]+[a-z]?' | sort -u || true
}

SPRINTS=$(extract_sprints "$COMMIT_MESSAGE")
if [[ -z "$SPRINTS" ]]; then
  echo "No sprint token found in commit message; skipping item updates."
  exit 0
fi

while IFS= read -r sprint; do
  [[ -z "$sprint" ]] && continue
  item_id=$(find_item_id_by_sprint "$sprint")
  if [[ -z "$item_id" && "$AUTO_CREATE_MISSING" == "true" ]]; then
    item_id=$(create_missing_item "$sprint" "$sprint - Auto tracked")
    if [[ -n "$SPRINT_FIELD" ]]; then set_text "$item_id" "$SPRINT_FIELD" "$sprint"; fi
    if [[ -n "$WAVE_FIELD" ]]; then set_text "$item_id" "$WAVE_FIELD" "Auto"; fi
    if [[ -n "$TYPE_FIELD" && -n "$TYPE_HOTFIX" ]]; then set_select "$item_id" "$TYPE_FIELD" "$TYPE_HOTFIX"; fi
    if [[ -n "$PRIORITY_FIELD" && -n "$PRIO_HIGH" ]]; then set_select "$item_id" "$PRIORITY_FIELD" "$PRIO_HIGH"; fi
    if [[ -n "$SQL_REQUIRED_FIELD" && -n "$SQL_NO" ]]; then set_select "$item_id" "$SQL_REQUIRED_FIELD" "$SQL_NO"; fi
  fi

  if [[ -z "$item_id" ]]; then
    echo "No project item found for sprint token: $sprint"
    continue
  fi

  set_text "$item_id" "$LAST_COMMIT_FIELD" "$SHORT_SHA"
  set_text "$item_id" "$COMMIT_TS_FIELD" "$COMMIT_TIMESTAMP"
  set_date "$item_id" "$LAST_UPDATE_FIELD" "$LAST_UPDATE_DATE"

  if [[ -n "$DELIVERY_MODE_FIELD" && -n "$MODE_OPT" ]]; then
    set_select "$item_id" "$DELIVERY_MODE_FIELD" "$MODE_OPT"
  fi
  if [[ -n "$WORK_ORIGIN_FIELD" && -n "$ORIGIN_OPT" ]]; then
    set_select "$item_id" "$WORK_ORIGIN_FIELD" "$ORIGIN_OPT"
  fi
  if [[ -n "$ISSUE_LINK_FIELD" && -n "$ISSUE_LINK" ]]; then
    set_text "$item_id" "$ISSUE_LINK_FIELD" "$ISSUE_LINK"
  fi

  echo "Updated project item for $sprint with commit $SHORT_SHA"
done <<< "$SPRINTS"
