#!/usr/bin/env bats
# Unit Tests for Backlog Manager Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-backlog-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export BACKLOG_FILE="backlog.json"
    mkdir -p .sprinty logs
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

@test "init_backlog creates backlog file" {
    init_backlog "test-project"
    
    assert_file_exists "$BACKLOG_FILE"
}

@test "init_backlog creates valid JSON" {
    init_backlog "test-project"
    
    assert_valid_json "$BACKLOG_FILE"
}

@test "init_backlog sets project name" {
    init_backlog "my-awesome-project"
    
    local project=$(get_json_field "$BACKLOG_FILE" "project")
    assert_equal "$project" "my-awesome-project"
}

@test "init_backlog starts with empty items array" {
    init_backlog "test-project"
    
    local count=$(get_json_array_length "$BACKLOG_FILE" "items")
    assert_equal "$count" "0"
}

@test "init_backlog sets metadata" {
    init_backlog "test-project"
    
    local total=$(get_json_field "$BACKLOG_FILE" "metadata.total_items")
    assert_equal "$total" "0"
}

@test "init_backlog does not overwrite existing backlog" {
    # Create initial backlog
    init_backlog "project-one"
    add_backlog_item "Task 1" "feature" 1 5
    
    # Try to re-init
    init_backlog "project-two"
    
    # Should still have project-one
    local project=$(get_json_field "$BACKLOG_FILE" "project")
    assert_equal "$project" "project-one"
}

@test "is_backlog_initialized returns true for valid backlog" {
    init_backlog "test-project"
    
    run is_backlog_initialized
    assert_success
}

@test "is_backlog_initialized returns false for missing file" {
    rm -f "$BACKLOG_FILE"
    
    run is_backlog_initialized
    assert_failure
}

# ============================================================================
# ID GENERATION TESTS
# ============================================================================

@test "get_next_task_id returns TASK-001 for empty backlog" {
    init_backlog "test-project"
    
    result=$(get_next_task_id)
    assert_equal "$result" "TASK-001"
}

@test "get_next_task_id returns TASK-001 when no backlog exists" {
    rm -f "$BACKLOG_FILE"
    
    result=$(get_next_task_id)
    assert_equal "$result" "TASK-001"
}

@test "get_next_task_id increments after adding item" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 3
    
    result=$(get_next_task_id)
    assert_equal "$result" "TASK-002"
}

@test "get_next_task_id handles multiple items" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 3
    add_backlog_item "Task 2" "bug" 1 2
    add_backlog_item "Task 3" "feature" 2 5
    
    result=$(get_next_task_id)
    assert_equal "$result" "TASK-004"
}

# ============================================================================
# ADD ITEM TESTS
# ============================================================================

@test "add_backlog_item creates item with correct id" {
    init_backlog "test-project"
    
    task_id=$(add_backlog_item "Test Task" "feature" 1 5)
    
    assert_equal "$task_id" "TASK-001"
}

@test "add_backlog_item stores title" {
    init_backlog "test-project"
    add_backlog_item "My Feature" "feature" 1 5
    
    local title=$(jq -r '.items[0].title' "$BACKLOG_FILE")
    assert_equal "$title" "My Feature"
}

@test "add_backlog_item stores type" {
    init_backlog "test-project"
    add_backlog_item "Bug Fix" "bug" 1 3
    
    local type=$(jq -r '.items[0].type' "$BACKLOG_FILE")
    assert_equal "$type" "bug"
}

@test "add_backlog_item stores story points" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 8
    
    local points=$(jq -r '.items[0].story_points' "$BACKLOG_FILE")
    assert_equal "$points" "8"
}

@test "add_backlog_item sets initial status to backlog" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "backlog"
}

@test "add_backlog_item updates metadata total_items" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    local total=$(get_json_field "$BACKLOG_FILE" "metadata.total_items")
    assert_equal "$total" "2"
}

@test "add_backlog_item updates metadata total_points" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    local total=$(get_json_field "$BACKLOG_FILE" "metadata.total_points")
    assert_equal "$total" "8"
}

@test "add_backlog_item rejects invalid type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "invalid_type" 1 5
    assert_failure
}

@test "add_backlog_item fails without initialization" {
    rm -f "$BACKLOG_FILE"
    
    run add_backlog_item "Task" "feature" 1 5
    assert_failure
}

# ============================================================================
# READ OPERATIONS TESTS
# ============================================================================

@test "get_backlog_item returns item by id" {
    init_backlog "test-project"
    add_backlog_item "My Task" "feature" 1 5
    
    result=$(get_backlog_item "TASK-001")
    title=$(echo "$result" | jq -r '.title')
    
    assert_equal "$title" "My Task"
}

@test "get_backlog_item returns empty for non-existent id" {
    init_backlog "test-project"
    add_backlog_item "My Task" "feature" 1 5
    
    result=$(get_backlog_item "TASK-999")
    
    [[ -z "$result" || "$result" == "null" ]]
}

@test "get_all_items returns all items" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "bug" 1 3
    
    result=$(get_all_items)
    count=$(echo "$result" | jq 'length')
    
    assert_equal "$count" "2"
}

@test "get_items_by_status returns matching items" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "ready"
    add_backlog_item "Task 2" "feature" 1 3
    
    result=$(get_items_by_status "ready")
    count=$(echo "$result" | jq 'length')
    
    assert_equal "$count" "1"
}

@test "count_items_by_status returns correct count" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    result=$(count_items_by_status "backlog")
    
    assert_equal "$result" "2"
}

@test "get_next_ready_task returns highest priority ready task" {
    init_backlog "test-project"
    add_backlog_item "Low Priority" "feature" 3 5
    update_item_status "TASK-001" "ready"
    add_backlog_item "High Priority" "feature" 1 3
    update_item_status "TASK-002" "ready"
    
    result=$(get_next_ready_task)
    id=$(echo "$result" | jq -r '.id')
    
    # Both have same priority in our test, so first ready item
    [[ "$id" == "TASK-001" || "$id" == "TASK-002" ]]
}

# ============================================================================
# UPDATE OPERATIONS TESTS
# ============================================================================

@test "update_item_status changes status" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    update_item_status "TASK-001" "ready"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "ready"
}

@test "update_item_status rejects invalid status" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    run update_item_status "TASK-001" "invalid_status"
    assert_failure
}

@test "update_item_status fails for non-existent task" {
    init_backlog "test-project"
    
    run update_item_status "TASK-999" "ready"
    assert_failure
}

@test "assign_to_sprint sets sprint_id and status" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    assign_to_sprint "TASK-001" 1
    
    local sprint_id=$(jq -r '.items[0].sprint_id' "$BACKLOG_FILE")
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    
    assert_equal "$sprint_id" "1"
    assert_equal "$status" "ready"
}

@test "get_sprint_backlog returns sprint tasks" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    
    result=$(get_sprint_backlog 1)
    count=$(echo "$result" | jq 'length')
    
    assert_equal "$count" "1"
}

@test "get_sprint_points returns total points for sprint" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    result=$(get_sprint_points 1)
    
    assert_equal "$result" "8"
}

@test "get_sprint_completed_points returns done points" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    
    result=$(get_sprint_completed_points 1)
    
    assert_equal "$result" "5"
}

@test "set_failure_reason sets failure field" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "qa_failed"
    
    set_failure_reason "TASK-001" "AC2 not met"
    
    local reason=$(jq -r '.items[0].failure_reason' "$BACKLOG_FILE")
    assert_equal "$reason" "AC2 not met"
}

# ============================================================================
# DELETE OPERATIONS TESTS
# ============================================================================

@test "remove_backlog_item removes item" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    remove_backlog_item "TASK-001"
    
    local count=$(get_json_array_length "$BACKLOG_FILE" "items")
    assert_equal "$count" "1"
}

@test "remove_backlog_item updates metadata" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    remove_backlog_item "TASK-001"
    
    local total=$(get_json_field "$BACKLOG_FILE" "metadata.total_items")
    local points=$(get_json_field "$BACKLOG_FILE" "metadata.total_points")
    
    assert_equal "$total" "1"
    assert_equal "$points" "3"
}

# ============================================================================
# QUERY HELPERS TESTS
# ============================================================================

@test "has_qa_failed_tasks returns true when failures exist" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "qa_failed"
    
    run has_qa_failed_tasks
    assert_success
}

@test "has_qa_failed_tasks returns false when no failures" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    run has_qa_failed_tasks
    assert_failure
}

@test "is_sprint_complete returns true when all tasks done" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    run is_sprint_complete 1
    assert_success
}

@test "is_sprint_complete returns false when tasks pending" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    
    run is_sprint_complete 1
    assert_failure
}

@test "is_project_done returns true when all tasks done" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    run is_project_done
    assert_success
}

@test "is_project_done returns false when tasks pending" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    update_item_status "TASK-001" "done"
    
    run is_project_done
    assert_failure
}

@test "is_project_done handles cancelled tasks" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "cancelled"
    
    run is_project_done
    assert_success
}

# ============================================================================
# ADD ITEM JSON TESTS
# ============================================================================

@test "add_backlog_item_json creates item from JSON" {
    init_backlog "test-project"
    
    task_id=$(add_backlog_item_json '{"title": "JSON Task", "type": "feature", "story_points": 8}')
    
    assert_equal "$task_id" "TASK-001"
}

@test "add_backlog_item_json stores title from JSON" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "My JSON Feature", "type": "bug"}'
    
    local title=$(jq -r '.items[0].title' "$BACKLOG_FILE")
    assert_equal "$title" "My JSON Feature"
}

@test "add_backlog_item_json stores type from JSON" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "Test", "type": "bug"}'
    
    local type=$(jq -r '.items[0].type' "$BACKLOG_FILE")
    assert_equal "$type" "bug"
}

@test "add_backlog_item_json stores story points from JSON" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "Test", "story_points": 13}'
    
    local points=$(jq -r '.items[0].story_points' "$BACKLOG_FILE")
    assert_equal "$points" "13"
}

@test "add_backlog_item_json uses defaults for missing fields" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "Minimal"}'
    
    local type=$(jq -r '.items[0].type' "$BACKLOG_FILE")
    local points=$(jq -r '.items[0].story_points' "$BACKLOG_FILE")
    local priority=$(jq -r '.items[0].priority' "$BACKLOG_FILE")
    
    assert_equal "$type" "feature"
    assert_equal "$points" "3"
    assert_equal "$priority" "1"
}

@test "add_backlog_item_json stores acceptance criteria from JSON" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "Test", "acceptance_criteria": ["AC1", "AC2", "AC3"]}'
    
    local count=$(jq '.items[0].acceptance_criteria | length' "$BACKLOG_FILE")
    assert_equal "$count" "3"
}

@test "add_backlog_item_json stores dependencies from JSON" {
    init_backlog "test-project"
    add_backlog_item_json '{"title": "Test", "dependencies": ["TASK-001", "TASK-002"]}'
    
    local count=$(jq '.items[0].dependencies | length' "$BACKLOG_FILE")
    assert_equal "$count" "2"
}

@test "add_backlog_item_json fails for invalid JSON" {
    init_backlog "test-project"
    
    run add_backlog_item_json "not valid json"
    
    assert_failure
}

@test "add_backlog_item_json fails without initialization" {
    rm -f "$BACKLOG_FILE"
    
    run add_backlog_item_json '{"title": "Test"}'
    
    assert_failure
}

# ============================================================================
# UPDATE ITEM FIELD TESTS
# ============================================================================

@test "update_item_field updates string field" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    update_item_field "TASK-001" "title" "Updated Title"
    
    local title=$(jq -r '.items[0].title' "$BACKLOG_FILE")
    assert_equal "$title" "Updated Title"
}

@test "update_item_field updates numeric field" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    update_item_field "TASK-001" "priority" "2"
    
    local priority=$(jq -r '.items[0].priority' "$BACKLOG_FILE")
    assert_equal "$priority" "2"
}

@test "update_item_field updates boolean field" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    # Add a boolean field
    jq '.items[0].blocked = false' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    
    update_item_field "TASK-001" "blocked" "true"
    
    local blocked=$(jq -r '.items[0].blocked' "$BACKLOG_FILE")
    assert_equal "$blocked" "true"
}

@test "update_item_field updates null field" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    update_item_field "TASK-001" "parent_id" "null"
    
    local parent=$(jq -r '.items[0].parent_id' "$BACKLOG_FILE")
    assert_equal "$parent" "null"
}

@test "update_item_field updates updated_at timestamp" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    local old_ts=$(jq -r '.items[0].updated_at' "$BACKLOG_FILE")
    
    sleep 1
    update_item_field "TASK-001" "title" "New Title"
    
    local new_ts=$(jq -r '.items[0].updated_at' "$BACKLOG_FILE")
    assert_not_equal "$old_ts" "$new_ts"
}

# ============================================================================
# ADDITIONAL STATUS TRANSITION TESTS
# ============================================================================

@test "update_item_status allows backlog to ready" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    
    update_item_status "TASK-001" "ready"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "ready"
}

@test "update_item_status allows ready to in_progress" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "ready"
    
    update_item_status "TASK-001" "in_progress"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "in_progress"
}

@test "update_item_status allows in_progress to implemented" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "in_progress"
    
    update_item_status "TASK-001" "implemented"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "implemented"
}

@test "update_item_status allows implemented to qa_in_progress" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "implemented"
    
    update_item_status "TASK-001" "qa_in_progress"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_in_progress"
}

@test "update_item_status allows qa_in_progress to qa_passed" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "qa_in_progress"
    
    update_item_status "TASK-001" "qa_passed"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_passed"
}

@test "update_item_status allows qa_in_progress to qa_failed" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "qa_in_progress"
    
    update_item_status "TASK-001" "qa_failed"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_failed"
}

@test "update_item_status allows qa_passed to done" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "qa_passed"
    
    update_item_status "TASK-001" "done"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "done"
}

@test "update_item_status allows any to cancelled" {
    init_backlog "test-project"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "in_progress"
    
    update_item_status "TASK-001" "cancelled"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "cancelled"
}

# ============================================================================
# TASK TYPES TESTS
# ============================================================================

@test "add_backlog_item accepts feature type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "feature" 1 5
    
    assert_success
}

@test "add_backlog_item accepts bug type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "bug" 1 5
    
    assert_success
}

@test "add_backlog_item accepts spike type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "spike" 1 5
    
    assert_success
}

@test "add_backlog_item accepts infra type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "infra" 1 5
    
    assert_success
}

@test "add_backlog_item accepts chore type" {
    init_backlog "test-project"
    
    run add_backlog_item "Task" "chore" 1 5
    
    assert_success
}

# ============================================================================
# SPRINT FILTERING TESTS
# ============================================================================

@test "get_sprint_backlog returns empty array for sprint with no tasks" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    
    result=$(get_sprint_backlog 99)
    count=$(echo "$result" | jq 'length')
    
    assert_equal "$count" "0"
}

@test "get_sprint_backlog returns only tasks for specified sprint" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    add_backlog_item "Task 3" "feature" 1 2
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 2
    assign_to_sprint "TASK-003" 1
    
    result=$(get_sprint_backlog 1)
    count=$(echo "$result" | jq 'length')
    
    assert_equal "$count" "2"
}

@test "get_sprint_points returns 0 for sprint with no tasks" {
    init_backlog "test-project"
    
    result=$(get_sprint_points 99)
    
    assert_equal "$result" "0"
}

@test "get_sprint_completed_points returns 0 for sprint with no done tasks" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    
    result=$(get_sprint_completed_points 1)
    
    assert_equal "$result" "0"
}

# ============================================================================
# ITEM RETRIEVAL TESTS
# ============================================================================

@test "get_backlog_item returns full item data" {
    init_backlog "test-project"
    add_backlog_item "My Task" "bug" 2 8
    
    result=$(get_backlog_item "TASK-001")
    
    local title=$(echo "$result" | jq -r '.title')
    local type=$(echo "$result" | jq -r '.type')
    local priority=$(echo "$result" | jq -r '.priority')
    local points=$(echo "$result" | jq -r '.story_points')
    
    assert_equal "$title" "My Task"
    assert_equal "$type" "bug"
    assert_equal "$priority" "2"
    assert_equal "$points" "8"
}

@test "get_all_items returns items sorted by id" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    add_backlog_item "Task 3" "feature" 1 2
    
    result=$(get_all_items)
    
    local first_id=$(echo "$result" | jq -r '.[0].id')
    assert_equal "$first_id" "TASK-001"
}

@test "get_next_ready_task returns null when no ready tasks" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    result=$(get_next_ready_task)
    
    [[ "$result" == "null" ]]
}
