#!/usr/bin/env bash
# Sprinty Backlog Manager
# CRUD operations for backlog.json using jq

set -e

# Source utilities (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKLOG_FILE="${BACKLOG_FILE:-backlog.json}"

# Valid task statuses
VALID_STATUSES=("backlog" "ready" "in_progress" "implemented" "qa_in_progress" "qa_passed" "qa_failed" "done" "cancelled")

# Valid task types
VALID_TYPES=("feature" "bug" "spike" "infra" "chore")

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize empty backlog
init_backlog() {
    local project_name=${1:-"my-project"}
    
    if [[ -f "$BACKLOG_FILE" ]]; then
        log_status "WARN" "Backlog already exists: $BACKLOG_FILE"
        return 0
    fi
    
    cat > "$BACKLOG_FILE" << EOF
{
  "project": "$project_name",
  "items": [],
  "metadata": {
    "total_items": 0,
    "total_points": 0,
    "created_at": "$(get_iso_timestamp)",
    "last_updated": "$(get_iso_timestamp)"
  }
}
EOF
    
    log_status "SUCCESS" "Initialized backlog: $BACKLOG_FILE"
}

# Check if backlog exists and is valid
is_backlog_initialized() {
    if [[ ! -f "$BACKLOG_FILE" ]]; then
        return 1
    fi
    
    # Validate JSON structure
    if ! jq -e '.items' "$BACKLOG_FILE" > /dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# ID GENERATION
# ============================================================================

# Get next task ID
# Returns: TASK-XXX format
get_next_task_id() {
    if [[ ! -f "$BACKLOG_FILE" ]]; then
        echo "TASK-001"
        return
    fi
    
    local max_num=$(jq -r '
        [.items[].id | 
         capture("TASK-(?<n>[0-9]+)").n | 
         tonumber] | 
        max // 0
    ' "$BACKLOG_FILE" 2>/dev/null || echo "0")
    
    printf "TASK-%03d" $((max_num + 1))
}

# ============================================================================
# CREATE OPERATIONS
# ============================================================================

# Add a new backlog item
# Usage: add_backlog_item "title" "type" "priority" "story_points" ["acceptance_criteria_json"]
add_backlog_item() {
    local title=$1
    local type=${2:-"feature"}
    local priority=${3:-1}
    local story_points=${4:-3}
    local acceptance_criteria=${5:-"[]"}
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Validate type
    local valid_type=false
    for t in "${VALID_TYPES[@]}"; do
        if [[ "$type" == "$t" ]]; then
            valid_type=true
            break
        fi
    done
    if [[ "$valid_type" == "false" ]]; then
        log_status "ERROR" "Invalid type: $type (valid: ${VALID_TYPES[*]})"
        return 1
    fi
    
    local task_id=$(get_next_task_id)
    local timestamp=$(get_iso_timestamp)
    
    # Create new item
    local new_item=$(jq -n \
        --arg id "$task_id" \
        --arg title "$title" \
        --arg type "$type" \
        --argjson priority "$priority" \
        --argjson points "$story_points" \
        --argjson ac "$acceptance_criteria" \
        --arg created "$timestamp" \
        '{
            id: $id,
            title: $title,
            type: $type,
            priority: $priority,
            story_points: $points,
            status: "backlog",
            sprint_id: null,
            acceptance_criteria: $ac,
            dependencies: [],
            parent_id: null,
            subtasks: [],
            created_at: $created,
            updated_at: $created
        }')
    
    # Add to backlog and update metadata
    jq --argjson item "$new_item" --arg ts "$timestamp" '
        .items += [$item] |
        .metadata.total_items = (.items | length) |
        .metadata.total_points = ([.items[].story_points] | add // 0) |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "SUCCESS" "Added task $task_id: $title"
    echo "$task_id"
}

# Add item with full specification (for JSON input)
add_backlog_item_json() {
    local item_json=$1
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Validate JSON
    if ! echo "$item_json" | jq '.' > /dev/null 2>&1; then
        log_status "ERROR" "Invalid JSON input"
        return 1
    fi
    
    local task_id=$(get_next_task_id)
    local timestamp=$(get_iso_timestamp)
    
    # Ensure required fields and add defaults
    local new_item=$(echo "$item_json" | jq \
        --arg id "$task_id" \
        --arg ts "$timestamp" '
        {
            id: $id,
            title: (.title // "Untitled"),
            type: (.type // "feature"),
            priority: (.priority // 1),
            story_points: (.story_points // 3),
            status: "backlog",
            sprint_id: null,
            acceptance_criteria: (.acceptance_criteria // []),
            dependencies: (.dependencies // []),
            parent_id: (.parent_id // null),
            subtasks: (.subtasks // []),
            created_at: $ts,
            updated_at: $ts
        }')
    
    # Add to backlog
    jq --argjson item "$new_item" --arg ts "$timestamp" '
        .items += [$item] |
        .metadata.total_items = (.items | length) |
        .metadata.total_points = ([.items[].story_points] | add // 0) |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "SUCCESS" "Added task $task_id"
    echo "$task_id"
}

# ============================================================================
# READ OPERATIONS
# ============================================================================

# Get a single item by ID
get_backlog_item() {
    local id=$1
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    jq --arg id "$id" '.items[] | select(.id == $id)' "$BACKLOG_FILE"
}

# Get all backlog items
get_all_items() {
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    jq '.items' "$BACKLOG_FILE"
}

# Get items by status
get_items_by_status() {
    local status=$1
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    jq --arg status "$status" '[.items[] | select(.status == $status)]' "$BACKLOG_FILE"
}

# Get sprint backlog (items assigned to a sprint)
get_sprint_backlog() {
    local sprint_id=$1
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    jq --argjson s "$sprint_id" '[.items[] | select(.sprint_id == $s)]' "$BACKLOG_FILE"
}

# Get next ready task (highest priority)
get_next_ready_task() {
    if ! is_backlog_initialized; then
        return 1
    fi
    
    jq '[.items[] | select(.status == "ready")] | sort_by(.priority) | first' "$BACKLOG_FILE"
}

# Count items by status
count_items_by_status() {
    local status=$1
    
    if ! is_backlog_initialized; then
        echo "0"
        return
    fi
    
    jq --arg status "$status" '[.items[] | select(.status == $status)] | length' "$BACKLOG_FILE"
}

# Get total story points for a sprint
get_sprint_points() {
    local sprint_id=$1
    
    if ! is_backlog_initialized; then
        echo "0"
        return
    fi
    
    jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s) | .story_points] | add // 0
    ' "$BACKLOG_FILE"
}

# Get completed points for a sprint
get_sprint_completed_points() {
    local sprint_id=$1
    
    if ! is_backlog_initialized; then
        echo "0"
        return
    fi
    
    jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s and .status == "done") | .story_points] | add // 0
    ' "$BACKLOG_FILE"
}

# ============================================================================
# UPDATE OPERATIONS
# ============================================================================

# Update task status
update_item_status() {
    local id=$1
    local new_status=$2
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Validate status
    local valid_status=false
    for s in "${VALID_STATUSES[@]}"; do
        if [[ "$new_status" == "$s" ]]; then
            valid_status=true
            break
        fi
    done
    if [[ "$valid_status" == "false" ]]; then
        log_status "ERROR" "Invalid status: $new_status (valid: ${VALID_STATUSES[*]})"
        return 1
    fi
    
    # Get current status for validation
    local current_status=$(jq -r --arg id "$id" '.items[] | select(.id == $id) | .status' "$BACKLOG_FILE")
    
    if [[ -z "$current_status" || "$current_status" == "null" ]]; then
        log_status "ERROR" "Task not found: $id"
        return 1
    fi
    
    local timestamp=$(get_iso_timestamp)
    
    jq --arg id "$id" --arg status "$new_status" --arg ts "$timestamp" '
        (.items[] | select(.id == $id)).status = $status |
        (.items[] | select(.id == $id)).updated_at = $ts |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "INFO" "Updated $id: $current_status -> $new_status"
}

# Assign task to sprint
assign_to_sprint() {
    local id=$1
    local sprint_id=$2
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    local timestamp=$(get_iso_timestamp)
    
    jq --arg id "$id" --argjson sprint "$sprint_id" --arg ts "$timestamp" '
        (.items[] | select(.id == $id)).sprint_id = $sprint |
        (.items[] | select(.id == $id)).status = "ready" |
        (.items[] | select(.id == $id)).updated_at = $ts |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "INFO" "Assigned $id to sprint $sprint_id"
}

# Update item field
update_item_field() {
    local id=$1
    local field=$2
    local value=$3
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    local timestamp=$(get_iso_timestamp)
    
    # Handle different value types
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        # Numeric value
        jq --arg id "$id" --arg field "$field" --argjson val "$value" --arg ts "$timestamp" '
            (.items[] | select(.id == $id))[$field] = $val |
            (.items[] | select(.id == $id)).updated_at = $ts |
            .metadata.last_updated = $ts
        ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    elif [[ "$value" == "null" || "$value" == "true" || "$value" == "false" ]]; then
        # Boolean or null
        jq --arg id "$id" --arg field "$field" --argjson val "$value" --arg ts "$timestamp" '
            (.items[] | select(.id == $id))[$field] = $val |
            (.items[] | select(.id == $id)).updated_at = $ts |
            .metadata.last_updated = $ts
        ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    else
        # String value
        jq --arg id "$id" --arg field "$field" --arg val "$value" --arg ts "$timestamp" '
            (.items[] | select(.id == $id))[$field] = $val |
            (.items[] | select(.id == $id)).updated_at = $ts |
            .metadata.last_updated = $ts
        ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    fi
    
    log_debug "Updated $id.$field = $value"
}

# Set failure reason (for QA failed tasks)
set_failure_reason() {
    local id=$1
    local reason=$2
    
    update_item_field "$id" "failure_reason" "$reason"
}

# ============================================================================
# DELETE OPERATIONS
# ============================================================================

# Remove item from backlog
remove_backlog_item() {
    local id=$1
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    local timestamp=$(get_iso_timestamp)
    
    jq --arg id "$id" --arg ts "$timestamp" '
        .items = [.items[] | select(.id != $id)] |
        .metadata.total_items = (.items | length) |
        .metadata.total_points = ([.items[].story_points] | add // 0) |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "INFO" "Removed task $id"
}

# ============================================================================
# QUERY HELPERS
# ============================================================================

# Check if there are QA failed tasks
has_qa_failed_tasks() {
    local count=$(count_items_by_status "qa_failed")
    [[ $count -gt 0 ]]
}

# Check if all sprint tasks are done
is_sprint_complete() {
    local sprint_id=$1
    
    local undone=$(jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s and .status != "done" and .status != "cancelled")] | length
    ' "$BACKLOG_FILE")
    
    [[ $undone -eq 0 ]]
}

# Check if project is complete
is_project_done() {
    local undone=$(jq '
        [.items[] | select(.status != "done" and .status != "cancelled")] | length
    ' "$BACKLOG_FILE")
    
    local p1_bugs=$(jq '
        [.items[] | select(.type == "bug" and .priority == 1 and .status != "done")] | length
    ' "$BACKLOG_FILE")
    
    [[ $undone -eq 0 ]] && [[ $p1_bugs -eq 0 ]]
}

# ============================================================================
# TASK BREAKDOWN
# ============================================================================

# Break down a large task into subtasks
# Usage: break_down_task <parent_id> <subtask_title> <subtask_points> [subtask_description]
# Returns: The new subtask ID
break_down_task() {
    local parent_id=$1
    local subtask_title=$2
    local subtask_points=$3
    local subtask_description=${4:-""}
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Verify parent exists
    local parent=$(get_backlog_item "$parent_id")
    if [[ -z "$parent" || "$parent" == "null" ]]; then
        log_status "ERROR" "Parent task not found: $parent_id"
        return 1
    fi
    
    # Get parent's sprint_id and priority
    local parent_sprint=$(echo "$parent" | jq -r '.sprint_id // "null"')
    local parent_priority=$(echo "$parent" | jq -r '.priority')
    local parent_ac=$(echo "$parent" | jq '.acceptance_criteria // []')
    
    # Generate subtask ID (parent_id + letter suffix: TASK-001a, TASK-001b, etc.)
    local existing_subtasks=$(jq --arg pid "$parent_id" '[.items[] | select(.parent_id == $pid)] | length' "$BACKLOG_FILE")
    local suffix_num=$((97 + existing_subtasks))  # ASCII 'a' = 97
    local suffix=$(printf "\\$(printf '%03o' $suffix_num)")
    local subtask_id="${parent_id}${suffix}"
    
    local timestamp=$(get_iso_timestamp)
    
    # Create subtask
    local subtask=$(jq -n \
        --arg id "$subtask_id" \
        --arg title "$subtask_title" \
        --arg desc "$subtask_description" \
        --argjson priority "$parent_priority" \
        --argjson points "$subtask_points" \
        --argjson sprint "$parent_sprint" \
        --arg parent "$parent_id" \
        --argjson ac "$parent_ac" \
        --arg ts "$timestamp" \
        '{
            id: $id,
            title: $title,
            description: $desc,
            type: "feature",
            priority: $priority,
            story_points: $points,
            status: "ready",
            sprint_id: $sprint,
            acceptance_criteria: $ac,
            dependencies: [],
            parent_id: $parent,
            subtasks: [],
            created_at: $ts,
            updated_at: $ts
        }')
    
    # Add subtask to items
    jq --argjson subtask "$subtask" --arg ts "$timestamp" '
        .items += [$subtask] |
        .metadata.total_items = (.items | length) |
        .metadata.total_points = ([.items[].story_points] | add // 0) |
        .metadata.last_updated = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    # Update parent's subtasks array
    jq --arg pid "$parent_id" --arg sid "$subtask_id" --arg ts "$timestamp" '
        (.items[] | select(.id == $pid) | .subtasks) += [$sid] |
        (.items[] | select(.id == $pid) | .updated_at) = $ts
    ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    log_status "SUCCESS" "Created subtask $subtask_id under $parent_id"
    echo "$subtask_id"
}

# Check if a task needs breakdown (>8 points per PRD)
needs_breakdown() {
    local task_id=$1
    
    local task=$(get_backlog_item "$task_id")
    if [[ -z "$task" || "$task" == "null" ]]; then
        return 1
    fi
    
    local points=$(echo "$task" | jq -r '.story_points')
    local has_subtasks=$(echo "$task" | jq '.subtasks | length > 0')
    
    # Task needs breakdown if:
    # - Has >= 9 story points (mandatory per PRD)
    # - Doesn't already have subtasks
    if [[ "$has_subtasks" == "false" && $points -ge 9 ]]; then
        return 0  # Needs breakdown
    fi
    
    return 1  # Doesn't need breakdown
}

# Get all subtasks for a parent
get_subtasks() {
    local parent_id=$1
    
    if ! is_backlog_initialized; then
        echo "[]"
        return
    fi
    
    jq --arg pid "$parent_id" '[.items[] | select(.parent_id == $pid)]' "$BACKLOG_FILE"
}

# Update parent status based on subtasks (rollup)
update_parent_status() {
    local parent_id=$1
    
    local subtasks=$(get_subtasks "$parent_id")
    local subtask_count=$(echo "$subtasks" | jq 'length')
    
    if [[ $subtask_count -eq 0 ]]; then
        return 0  # No subtasks, nothing to rollup
    fi
    
    # Check subtask statuses (priority order per PRD)
    local has_qa_failed=$(echo "$subtasks" | jq '[.[] | select(.status == "qa_failed")] | length > 0')
    local has_in_progress=$(echo "$subtasks" | jq '[.[] | select(.status == "in_progress")] | length > 0')
    local has_implemented=$(echo "$subtasks" | jq '[.[] | select(.status == "implemented")] | length > 0')
    local has_qa_in_progress=$(echo "$subtasks" | jq '[.[] | select(.status == "qa_in_progress")] | length > 0')
    local all_done=$(echo "$subtasks" | jq 'all(.status == "done" or .status == "cancelled")')
    local all_qa_passed=$(echo "$subtasks" | jq 'all(.status == "qa_passed" or .status == "done" or .status == "cancelled")')
    
    local new_status=""
    
    # Determine parent status based on subtask statuses
    if [[ "$has_qa_failed" == "true" ]]; then
        new_status="qa_failed"
    elif [[ "$has_in_progress" == "true" ]]; then
        new_status="in_progress"
    elif [[ "$has_implemented" == "true" || "$has_qa_in_progress" == "true" ]]; then
        new_status="implemented"
    elif [[ "$all_qa_passed" == "true" && "$all_done" != "true" ]]; then
        new_status="qa_passed"
    elif [[ "$all_done" == "true" ]]; then
        new_status="done"
    fi
    
    if [[ -n "$new_status" ]]; then
        update_item_status "$parent_id" "$new_status"
    fi
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

# List backlog items (formatted)
list_backlog() {
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      Backlog Items                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    jq -r '.items | sort_by(.priority) | .[] | 
        "\(.id)\t\(.status)\t\(.story_points)pt\t\(.title)"
    ' "$BACKLOG_FILE" | while IFS=$'\t' read -r id status points title; do
        local color=$NC
        case $status in
            "done")          color=$GREEN ;;
            "in_progress")   color=$YELLOW ;;
            "qa_failed")     color=$RED ;;
            "implemented"|"qa_passed") color=$CYAN ;;
        esac
        printf "${color}%-10s %-15s %3s  %s${NC}\n" "$id" "$status" "$points" "$title"
    done
    
    echo ""
    local total=$(jq '.metadata.total_items' "$BACKLOG_FILE")
    local points=$(jq '.metadata.total_points' "$BACKLOG_FILE")
    echo "Total: $total items, $points story points"
}

# Show backlog summary
show_backlog_summary() {
    if ! is_backlog_initialized; then
        return 1
    fi
    
    echo -e "${BLUE}Backlog Summary:${NC}"
    
    for status in "${VALID_STATUSES[@]}"; do
        local count=$(count_items_by_status "$status")
        if [[ $count -gt 0 ]]; then
            echo "  $status: $count"
        fi
    done
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export BACKLOG_FILE
export VALID_STATUSES VALID_TYPES

export -f init_backlog
export -f is_backlog_initialized
export -f get_next_task_id
export -f add_backlog_item
export -f add_backlog_item_json
export -f get_backlog_item
export -f get_all_items
export -f get_items_by_status
export -f get_sprint_backlog
export -f get_next_ready_task
export -f count_items_by_status
export -f get_sprint_points
export -f get_sprint_completed_points
export -f update_item_status
export -f assign_to_sprint
export -f update_item_field
export -f set_failure_reason
export -f remove_backlog_item
export -f has_qa_failed_tasks
export -f is_sprint_complete
export -f is_project_done
export -f break_down_task
export -f needs_breakdown
export -f get_subtasks
export -f update_parent_status
export -f list_backlog
export -f show_backlog_summary
