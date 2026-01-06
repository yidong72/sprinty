#!/usr/bin/env bats
# Integration Tests: Sprint Lifecycle
# Tests the full flow of sprint management with backlog integration

# Load test helpers
load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-integration-sprint.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export BACKLOG_FILE="backlog.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source all modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# COMPLETE SPRINT WORKFLOW TESTS
# ============================================================================

@test "integration: complete sprint workflow from init to done" {
    # Initialize project
    init_sprint_state
    init_backlog "integration-test"
    
    # Create backlog items
    add_backlog_item "Feature A" "feature" 1 5
    add_backlog_item "Feature B" "feature" 2 3
    add_backlog_item "Bug Fix" "bug" 1 2
    
    # Verify initialization phase
    local phase=$(get_current_phase)
    assert_equal "$phase" "initialization"
    
    # Complete initialization by having items
    run is_phase_complete "initialization"
    assert_success
    
    # Start sprint
    local sprint=$(start_sprint)
    assert_equal "$sprint" "1"
    
    # Verify we're in planning phase
    phase=$(get_current_phase)
    assert_equal "$phase" "planning"
    
    # Assign tasks to sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    # Verify sprint backlog
    local sprint_items=$(get_sprint_backlog 1 | jq 'length')
    assert_equal "$sprint_items" "3"
    
    # Create plan to complete planning phase
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "# Sprint 1 Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    run is_phase_complete "planning"
    assert_success
    
    # Move to implementation
    set_current_phase "implementation"
    
    # Implement tasks
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-002" "in_progress"
    update_item_status "TASK-002" "implemented"
    update_item_status "TASK-003" "in_progress"
    update_item_status "TASK-003" "implemented"
    
    run is_phase_complete "implementation"
    assert_success
    
    # Move to QA
    set_current_phase "qa"
    
    # QA passes all tasks
    update_item_status "TASK-001" "qa_in_progress"
    update_item_status "TASK-001" "qa_passed"
    update_item_status "TASK-002" "qa_in_progress"
    update_item_status "TASK-002" "qa_passed"
    update_item_status "TASK-003" "qa_in_progress"
    update_item_status "TASK-003" "qa_passed"
    
    run is_phase_complete "qa"
    assert_success
    
    # Move tasks to done
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    update_item_status "TASK-003" "done"
    
    # Move to review
    set_current_phase "review"
    
    # Create review document
    echo "# Sprint 1 Review" > "$REVIEWS_DIR/sprint_1_review.md"
    run is_phase_complete "review"
    assert_success
    
    # End sprint
    end_sprint "completed"
    
    # Verify sprint completed
    local status=$(jq -r '.sprints_history[0].status' "$SPRINT_STATE_FILE")
    assert_equal "$status" "completed"
    
    # Verify project completion
    run check_project_completion
    assert_success
}

@test "integration: sprint with QA failures triggers rework cycle" {
    # Setup
    init_sprint_state
    init_backlog "rework-test"
    add_backlog_item "Feature" "feature" 1 5
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Create plan
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "# Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    
    # Implement
    set_current_phase "implementation"
    update_item_status "TASK-001" "implemented"
    
    # QA fails
    set_current_phase "qa"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "AC1 not met"
    
    # Check rework needed
    run has_tasks_to_rework
    assert_success
    
    # Increment rework counter
    local rework=$(increment_rework)
    assert_equal "$rework" "1"
    
    # Go back to implementation
    set_current_phase "implementation"
    
    # Re-implement
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    # QA passes this time
    set_current_phase "qa"
    update_item_status "TASK-001" "qa_passed"
    
    run has_tasks_to_rework
    assert_failure
    
    # Complete
    update_item_status "TASK-001" "done"
    run is_sprint_complete 1
    assert_success
}

@test "integration: multiple sprints with proper history tracking" {
    init_sprint_state
    init_backlog "multi-sprint-test"
    
    # Create multiple items
    for i in {1..6}; do
        add_backlog_item "Task $i" "feature" 1 3
    done
    
    # Sprint 1: Complete tasks 1-2
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "# Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    echo "# Review" > "$REVIEWS_DIR/sprint_1_review.md"
    end_sprint "completed"
    
    # Sprint 2: Complete tasks 3-4
    start_sprint
    assign_to_sprint "TASK-003" 2
    assign_to_sprint "TASK-004" 2
    mkdir -p "$SPRINTS_DIR/sprint_2"
    echo "# Plan" > "$SPRINTS_DIR/sprint_2/plan.md"
    update_item_status "TASK-003" "done"
    update_item_status "TASK-004" "done"
    echo "# Review" > "$REVIEWS_DIR/sprint_2_review.md"
    end_sprint "completed"
    
    # Sprint 3: Complete tasks 5-6
    start_sprint
    assign_to_sprint "TASK-005" 3
    assign_to_sprint "TASK-006" 3
    mkdir -p "$SPRINTS_DIR/sprint_3"
    echo "# Plan" > "$SPRINTS_DIR/sprint_3/plan.md"
    update_item_status "TASK-005" "done"
    update_item_status "TASK-006" "done"
    echo "# Review" > "$REVIEWS_DIR/sprint_3_review.md"
    end_sprint "completed"
    
    # Verify history
    local history_count=$(jq '.sprints_history | length' "$SPRINT_STATE_FILE")
    assert_equal "$history_count" "3"
    
    # Verify all sprints completed
    local completed=$(jq '[.sprints_history[] | select(.status == "completed")] | length' "$SPRINT_STATE_FILE")
    assert_equal "$completed" "3"
    
    # Verify project complete
    run check_project_completion
    assert_success
}

@test "integration: sprint backlog points calculation throughout lifecycle" {
    init_sprint_state
    init_backlog "points-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 8
    add_backlog_item "Task 3" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    # Verify total points
    local total=$(get_sprint_points 1)
    assert_equal "$total" "16"
    
    # Initially 0 completed
    local completed=$(get_sprint_completed_points 1)
    assert_equal "$completed" "0"
    
    # Complete first task
    update_item_status "TASK-001" "done"
    completed=$(get_sprint_completed_points 1)
    assert_equal "$completed" "5"
    
    # Complete second task
    update_item_status "TASK-002" "done"
    completed=$(get_sprint_completed_points 1)
    assert_equal "$completed" "13"
    
    # Complete third task
    update_item_status "TASK-003" "done"
    completed=$(get_sprint_completed_points 1)
    assert_equal "$completed" "16"
    
    # Verify sprint complete
    run is_sprint_complete 1
    assert_success
}

@test "integration: phase loop limits enforce progression" {
    init_sprint_state
    init_backlog "loop-limit-test"
    add_backlog_item "Task" "feature" 1 5
    
    start_sprint
    set_current_phase "planning"
    
    # Increment loops up to limit
    local max_loops=$(get_max_loops_for_phase "planning")
    
    for ((i=1; i<max_loops; i++)); do
        increment_phase_loop
        run is_phase_loop_limit_exceeded "planning"
        assert_failure
    done
    
    # One more should exceed
    increment_phase_loop
    run is_phase_loop_limit_exceeded "planning"
    assert_success
}

@test "integration: rework limit prevents infinite loops" {
    init_sprint_state
    init_backlog "rework-limit-test"
    add_backlog_item "Task" "feature" 1 5
    
    start_sprint
    
    # Rework up to limit
    increment_rework
    increment_rework
    run is_rework_limit_exceeded
    assert_failure
    
    increment_rework
    run is_rework_limit_exceeded
    assert_success
}

@test "integration: role transitions match phase transitions" {
    init_sprint_state
    init_backlog "role-test"
    
    # Initialization phase
    local role=$(get_role_for_phase "initialization")
    assert_equal "$role" "product_owner"
    
    start_sprint
    
    # Planning phase
    role=$(get_role_for_phase "planning")
    assert_equal "$role" "product_owner"
    
    set_current_phase "implementation"
    role=$(get_role_for_phase "implementation")
    assert_equal "$role" "developer"
    
    set_current_phase "qa"
    role=$(get_role_for_phase "qa")
    assert_equal "$role" "qa"
    
    set_current_phase "review"
    role=$(get_role_for_phase "review")
    assert_equal "$role" "product_owner"
}
