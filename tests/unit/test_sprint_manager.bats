#!/usr/bin/env bats
# Unit Tests for Sprint Manager Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-sprint-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    export BACKLOG_FILE="backlog.json"
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

@test "init_sprint_state creates sprint state file" {
    init_sprint_state
    
    assert_file_exists "$SPRINT_STATE_FILE"
}

@test "init_sprint_state creates valid JSON" {
    init_sprint_state
    
    assert_valid_json "$SPRINT_STATE_FILE"
}

@test "init_sprint_state sets current_sprint to 0" {
    init_sprint_state
    
    local sprint=$(jq -r '.current_sprint' "$SPRINT_STATE_FILE")
    assert_equal "$sprint" "0"
}

@test "init_sprint_state sets current_phase to initialization" {
    init_sprint_state
    
    local phase=$(jq -r '.current_phase' "$SPRINT_STATE_FILE")
    assert_equal "$phase" "initialization"
}

@test "init_sprint_state sets project_done to false" {
    init_sprint_state
    
    local done=$(jq -r '.project_done' "$SPRINT_STATE_FILE")
    assert_equal "$done" "false"
}

@test "init_sprint_state creates sprints directory" {
    init_sprint_state
    
    assert_dir_exists "$SPRINTS_DIR"
}

@test "init_sprint_state creates reviews directory" {
    init_sprint_state
    
    assert_dir_exists "$REVIEWS_DIR"
}

@test "init_sprint_state does not overwrite valid existing state" {
    # Create initial state
    init_sprint_state
    update_sprint_state "current_sprint" 5
    
    # Try to re-init
    init_sprint_state
    
    # Should still have sprint 5
    local sprint=$(jq -r '.current_sprint' "$SPRINT_STATE_FILE")
    assert_equal "$sprint" "5"
}

@test "init_sprint_state recreates invalid JSON" {
    mkdir -p .sprinty
    echo "invalid json" > "$SPRINT_STATE_FILE"
    
    init_sprint_state
    
    assert_valid_json "$SPRINT_STATE_FILE"
}

# ============================================================================
# STATE QUERIES TESTS
# ============================================================================

@test "get_sprint_state returns field value" {
    init_sprint_state
    
    result=$(get_sprint_state "current_sprint")
    assert_equal "$result" "0"
}

@test "get_current_sprint returns 0 initially" {
    init_sprint_state
    
    result=$(get_current_sprint)
    assert_equal "$result" "0"
}

@test "get_current_phase returns initialization initially" {
    init_sprint_state
    
    result=$(get_current_phase)
    assert_equal "$result" "initialization"
}

@test "get_phase_loop_count returns 0 initially" {
    init_sprint_state
    
    result=$(get_phase_loop_count)
    assert_equal "$result" "0"
}

@test "get_rework_count returns 0 initially" {
    init_sprint_state
    
    result=$(get_rework_count)
    assert_equal "$result" "0"
}

@test "is_project_marked_done returns false initially" {
    init_sprint_state
    
    run is_project_marked_done
    assert_failure
}

# ============================================================================
# STATE UPDATES TESTS
# ============================================================================

@test "update_sprint_state updates integer field" {
    init_sprint_state
    
    update_sprint_state "current_sprint" 5
    
    local sprint=$(jq -r '.current_sprint' "$SPRINT_STATE_FILE")
    assert_equal "$sprint" "5"
}

@test "update_sprint_state updates boolean field" {
    init_sprint_state
    
    update_sprint_state "project_done" "true"
    
    local done=$(jq -r '.project_done' "$SPRINT_STATE_FILE")
    assert_equal "$done" "true"
}

@test "update_sprint_state updates string field" {
    init_sprint_state
    
    update_sprint_state "current_phase" "implementation"
    
    local phase=$(jq -r '.current_phase' "$SPRINT_STATE_FILE")
    assert_equal "$phase" "implementation"
}

@test "update_sprint_state updates last_updated timestamp" {
    init_sprint_state
    local old_ts=$(jq -r '.last_updated' "$SPRINT_STATE_FILE")
    
    sleep 1
    update_sprint_state "current_sprint" 1
    
    local new_ts=$(jq -r '.last_updated' "$SPRINT_STATE_FILE")
    assert_not_equal "$old_ts" "$new_ts"
}

@test "set_current_phase changes phase" {
    init_sprint_state
    
    set_current_phase "implementation"
    
    local phase=$(get_current_phase)
    assert_equal "$phase" "implementation"
}

@test "set_current_phase resets phase_loop_count" {
    init_sprint_state
    update_sprint_state "phase_loop_count" 5
    
    set_current_phase "qa"
    
    local count=$(get_phase_loop_count)
    assert_equal "$count" "0"
}

@test "set_current_phase rejects invalid phase" {
    init_sprint_state
    
    run set_current_phase "invalid_phase"
    assert_failure
}

@test "set_current_phase accepts all valid phases" {
    init_sprint_state
    
    for phase in initialization planning implementation qa review; do
        set_current_phase "$phase"
        result=$(get_current_phase)
        assert_equal "$result" "$phase"
    done
}

@test "increment_phase_loop increments counter" {
    init_sprint_state
    
    result=$(increment_phase_loop)
    assert_equal "$result" "1"
    
    result=$(increment_phase_loop)
    assert_equal "$result" "2"
}

# ============================================================================
# SPRINT LIFECYCLE TESTS
# ============================================================================

@test "start_sprint increments sprint number" {
    init_sprint_state
    
    result=$(start_sprint)
    assert_equal "$result" "1"
    
    result=$(start_sprint)
    assert_equal "$result" "2"
}

@test "start_sprint sets phase to planning" {
    init_sprint_state
    
    start_sprint
    
    local phase=$(get_current_phase)
    assert_equal "$phase" "planning"
}

@test "start_sprint resets phase_loop_count" {
    init_sprint_state
    update_sprint_state "phase_loop_count" 10
    
    start_sprint
    
    local count=$(get_phase_loop_count)
    assert_equal "$count" "0"
}

@test "start_sprint resets rework_count" {
    init_sprint_state
    update_sprint_state "rework_count" 2
    
    start_sprint
    
    local count=$(get_rework_count)
    assert_equal "$count" "0"
}

@test "start_sprint creates sprint directory" {
    init_sprint_state
    
    start_sprint
    
    assert_dir_exists "$SPRINTS_DIR/sprint_1"
}

@test "start_sprint adds to sprints_history" {
    init_sprint_state
    
    start_sprint
    
    local history_count=$(jq '.sprints_history | length' "$SPRINT_STATE_FILE")
    assert_equal "$history_count" "1"
    
    local sprint_id=$(jq '.sprints_history[0].sprint' "$SPRINT_STATE_FILE")
    assert_equal "$sprint_id" "1"
}

@test "start_sprint returns 21 when max sprints reached" {
    init_sprint_state
    update_sprint_state "current_sprint" 10
    
    run start_sprint
    assert_equal "$status" "21"
}

@test "end_sprint updates sprint history status" {
    init_sprint_state
    start_sprint
    
    end_sprint "completed"
    
    local status=$(jq -r '.sprints_history[0].status' "$SPRINT_STATE_FILE")
    assert_equal "$status" "completed"
}

@test "end_sprint sets ended_at timestamp" {
    init_sprint_state
    start_sprint
    
    end_sprint "completed"
    
    local ended=$(jq -r '.sprints_history[0].ended_at' "$SPRINT_STATE_FILE")
    [[ "$ended" != "null" ]]
}

@test "increment_rework increments rework_count" {
    init_sprint_state
    
    result=$(increment_rework)
    assert_equal "$result" "1"
    
    result=$(increment_rework)
    assert_equal "$result" "2"
}

@test "is_rework_limit_exceeded returns false under limit" {
    init_sprint_state
    
    run is_rework_limit_exceeded
    assert_failure
}

@test "is_rework_limit_exceeded returns true at limit" {
    init_sprint_state
    update_sprint_state "rework_count" 3
    
    run is_rework_limit_exceeded
    assert_success
}

# ============================================================================
# PHASE COMPLETION TESTS
# ============================================================================

@test "get_max_loops_for_phase returns correct values" {
    init_sprint_state
    
    assert_equal "$(get_max_loops_for_phase planning)" "$DEFAULT_PLANNING_MAX_LOOPS"
    assert_equal "$(get_max_loops_for_phase implementation)" "$DEFAULT_IMPLEMENTATION_MAX_LOOPS"
    assert_equal "$(get_max_loops_for_phase qa)" "$DEFAULT_QA_MAX_LOOPS"
    assert_equal "$(get_max_loops_for_phase review)" "$DEFAULT_REVIEW_MAX_LOOPS"
}

@test "get_max_loops_for_phase returns 10 for unknown phase" {
    init_sprint_state
    
    result=$(get_max_loops_for_phase "unknown")
    assert_equal "$result" "10"
}

@test "is_phase_loop_limit_exceeded returns false under limit" {
    init_sprint_state
    set_current_phase "implementation"
    
    run is_phase_loop_limit_exceeded
    assert_failure
}

@test "is_phase_loop_limit_exceeded returns true at limit" {
    init_sprint_state
    set_current_phase "planning"
    update_sprint_state "phase_loop_count" 3
    
    run is_phase_loop_limit_exceeded "planning"
    assert_success
}

@test "is_phase_complete returns true for initialization with backlog" {
    init_sprint_state
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    
    run is_phase_complete "initialization"
    assert_success
}

@test "is_phase_complete returns false for initialization without items" {
    init_sprint_state
    init_backlog "test-project"
    
    run is_phase_complete "initialization"
    assert_failure
}

@test "is_phase_complete returns true for planning with plan file" {
    init_sprint_state
    start_sprint
    mkdir -p "$SPRINTS_DIR/sprint_1"
    touch "$SPRINTS_DIR/sprint_1/plan.md"
    
    run is_phase_complete "planning"
    assert_success
}

@test "is_phase_complete returns false for planning without plan file" {
    init_sprint_state
    start_sprint
    
    run is_phase_complete "planning"
    assert_failure
}

@test "is_phase_complete returns true for implementation with no pending tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "implemented"
    
    run is_phase_complete "implementation"
    assert_success
}

@test "is_phase_complete returns false for implementation with pending tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    
    run is_phase_complete "implementation"
    assert_failure
}

@test "is_phase_complete returns true for qa with no implemented tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "qa_passed"
    
    run is_phase_complete "qa"
    assert_success
}

@test "is_phase_complete returns false for qa with implemented tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "implemented"
    
    run is_phase_complete "qa"
    assert_failure
}

@test "is_phase_complete returns true for review with review file" {
    init_sprint_state
    start_sprint
    mkdir -p "$REVIEWS_DIR"
    touch "$REVIEWS_DIR/sprint_1_review.md"
    
    run is_phase_complete "review"
    assert_success
}

@test "has_tasks_to_rework returns true with qa_failed tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "qa_failed"
    
    run has_tasks_to_rework
    assert_success
}

@test "has_tasks_to_rework returns false without qa_failed tasks" {
    init_sprint_state
    init_backlog "test-project"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "qa_passed"
    
    run has_tasks_to_rework
    assert_failure
}

# ============================================================================
# PROJECT COMPLETION TESTS
# ============================================================================

@test "mark_project_done sets project_done to true" {
    init_sprint_state
    start_sprint
    
    mark_project_done
    
    run is_project_marked_done
    assert_success
}

@test "check_project_completion returns true when all done" {
    init_sprint_state
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    run check_project_completion
    assert_success
}

@test "check_project_completion returns false when tasks pending" {
    init_sprint_state
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    
    run check_project_completion
    assert_failure
}

@test "check_project_completion handles cancelled tasks" {
    init_sprint_state
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "cancelled"
    
    run check_project_completion
    assert_success
}

@test "check_project_completion returns false for empty backlog" {
    init_sprint_state
    init_backlog "test-project"
    
    run check_project_completion
    assert_failure
}

# ============================================================================
# ROLE MAPPING TESTS
# ============================================================================

@test "get_role_for_phase returns product_owner for initialization" {
    result=$(get_role_for_phase "initialization")
    assert_equal "$result" "product_owner"
}

@test "get_role_for_phase returns product_owner for planning" {
    result=$(get_role_for_phase "planning")
    assert_equal "$result" "product_owner"
}

@test "get_role_for_phase returns developer for implementation" {
    result=$(get_role_for_phase "implementation")
    assert_equal "$result" "developer"
}

@test "get_role_for_phase returns qa for qa phase" {
    result=$(get_role_for_phase "qa")
    assert_equal "$result" "qa"
}

@test "get_role_for_phase returns product_owner for review" {
    result=$(get_role_for_phase "review")
    assert_equal "$result" "product_owner"
}

@test "get_role_for_phase returns developer for unknown phase" {
    result=$(get_role_for_phase "unknown")
    assert_equal "$result" "developer"
}
