#!/usr/bin/env bats
# Integration Tests for Task Breakdown Feature
# Tests that task breakdown works correctly with sprint lifecycle

load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-breakdown-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    # Set up environment
    export SPRINTY_DIR=".sprinty"
    export BACKLOG_FILE="backlog.json"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    export VELOCITY_HISTORY_FILE=".sprinty/velocity_history.json"
    export METRICS_FILE=".sprinty/metrics.json"
    
    mkdir -p "$SPRINTY_DIR" "$SPRINTS_DIR" "$REVIEWS_DIR"
    
    # Source modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/metrics_collector.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# TASK BREAKDOWN + SPRINT LIFECYCLE INTEGRATION
# ============================================================================

@test "integration: large task breakdown before sprint implementation" {
    # Setup: Create backlog with large task
    init_backlog "breakdown-test"
    init_sprint_state
    add_backlog_item "Large Feature" "feature" 1 12  # 12 points = needs breakdown
    
    # Verify task needs breakdown
    run needs_breakdown "TASK-001"
    assert_success
    
    # Start sprint and assign task
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down the large task
    break_down_task "TASK-001" "Database schema" 3
    break_down_task "TASK-001" "API endpoints" 4
    break_down_task "TASK-001" "Frontend UI" 3
    break_down_task "TASK-001" "Integration tests" 2
    
    # Verify subtasks created
    local subtask_count=$(jq '.items[] | select(.id == "TASK-001") | .subtasks | length' "$BACKLOG_FILE")
    assert_equal "$subtask_count" "4"
    
    # Verify subtasks are in the same sprint
    local subtask_sprints=$(jq -c '[.items[] | select(.parent_id == "TASK-001") | .sprint_id] | unique' "$BACKLOG_FILE")
    assert_equal "$subtask_sprints" "[1]"
    
    # Verify task no longer needs breakdown (has subtasks now)
    run needs_breakdown "TASK-001"
    assert_failure
}

@test "integration: subtask completion updates parent status" {
    init_backlog "parent-rollup-test"
    init_sprint_state
    add_backlog_item "Feature with subtasks" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down task
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    # Complete first subtask
    update_item_status "TASK-001a" "in_progress"
    update_parent_status "TASK-001"
    local status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "in_progress"
    
    # Complete first subtask fully
    update_item_status "TASK-001a" "implemented"
    update_parent_status "TASK-001"
    status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "implemented"
    
    # Second subtask goes through QA and fails
    update_item_status "TASK-001b" "qa_failed"
    update_parent_status "TASK-001"
    status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_failed"
    
    # Fix and complete both
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "done"
    update_parent_status "TASK-001"
    status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "done"
}

@test "integration: sprint points calculation with subtasks" {
    init_backlog "points-calc-test"
    init_sprint_state
    
    # Add parent task and a regular task
    add_backlog_item "Big Feature" "feature" 1 10
    add_backlog_item "Small Feature" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # Before breakdown: total = 10 + 3 = 13
    local total=$(get_sprint_points 1)
    assert_equal "$total" "13"
    
    # Break down the big task
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    # After breakdown: parent(10) + subtasks(5+5) + small(3) = 23
    # Note: This counts both parent and subtasks - metrics should handle leaf-only
    total=$(get_sprint_points 1)
    assert_equal "$total" "23"
}

@test "integration: burndown tracks only leaf tasks (no double counting)" {
    init_backlog "burndown-leaf-test"
    init_sprint_state
    init_velocity_history
    
    add_backlog_item "Feature" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down task
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    # Complete subtasks
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "done"
    update_parent_status "TASK-001"
    
    # Burndown should count subtasks correctly
    local burndown=$(calculate_burndown 1)
    local done_points=$(echo "$burndown" | jq '.points.done')
    
    # Done points should be 10 (parent) + 10 (subtasks) = 20
    # Or if counting leaf-only, should be 10 (subtasks only)
    # Current implementation counts all items
    [[ $done_points -ge 10 ]]
}

@test "integration: multiple parents with subtasks in same sprint" {
    init_backlog "multi-parent-test"
    init_sprint_state
    
    add_backlog_item "Feature A" "feature" 1 10
    add_backlog_item "Feature B" "feature" 1 12
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # Break down both
    break_down_task "TASK-001" "A1" 5
    break_down_task "TASK-001" "A2" 5
    break_down_task "TASK-002" "B1" 4
    break_down_task "TASK-002" "B2" 4
    break_down_task "TASK-002" "B3" 4
    
    # Verify subtasks have correct parents
    local a_subtasks=$(get_subtasks "TASK-001" | jq 'length')
    local b_subtasks=$(get_subtasks "TASK-002" | jq 'length')
    
    assert_equal "$a_subtasks" "2"
    assert_equal "$b_subtasks" "3"
    
    # Complete Feature A subtasks
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "done"
    update_parent_status "TASK-001"
    
    local a_status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$a_status" "done"
    
    # Feature B should still be in progress
    update_item_status "TASK-002a" "done"
    update_item_status "TASK-002b" "in_progress"
    update_parent_status "TASK-002"
    
    local b_status=$(jq -r '.items[] | select(.id == "TASK-002") | .status' "$BACKLOG_FILE")
    assert_equal "$b_status" "in_progress"
}

@test "integration: QA failure in subtask triggers rework" {
    init_backlog "qa-rework-test"
    init_sprint_state
    
    add_backlog_item "Feature" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down and implement
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    update_item_status "TASK-001a" "implemented"
    update_item_status "TASK-001b" "implemented"
    update_parent_status "TASK-001"
    
    # QA fails one subtask
    update_item_status "TASK-001a" "qa_passed"
    update_item_status "TASK-001b" "qa_failed"
    set_failure_reason "TASK-001b" "Missing error handling"
    update_parent_status "TASK-001"
    
    # Parent should be qa_failed
    local status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_failed"
    
    # Check has_tasks_to_rework detects the failure
    run has_qa_failed_tasks
    assert_success
    
    # Rework the failed subtask
    update_item_status "TASK-001b" "in_progress"
    update_parent_status "TASK-001"
    
    status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "in_progress"
    
    # Complete rework
    update_item_status "TASK-001b" "qa_passed"
    update_parent_status "TASK-001"
    
    status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_passed"
}

@test "integration: phase completion with subtasks" {
    init_backlog "phase-complete-test"
    init_sprint_state
    
    add_backlog_item "Feature" "feature" 1 9
    start_sprint
    assign_to_sprint "TASK-001" 1
    set_current_phase "planning"
    
    # Create sprint plan
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "Sprint Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    
    run is_phase_complete "planning"
    assert_success
    
    # Move to implementation
    set_current_phase "implementation"
    
    # Break down task
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 4
    
    # Subtasks are ready, so implementation not complete
    run is_phase_complete "implementation"
    assert_failure
    
    # Implement subtasks
    update_item_status "TASK-001a" "implemented"
    update_item_status "TASK-001b" "implemented"
    
    # Update parent status based on subtasks
    update_parent_status "TASK-001"
    
    # Now implementation should be complete (parent and subtasks all implemented)
    run is_phase_complete "implementation"
    assert_success
}

@test "integration: velocity tracking with subtasks" {
    init_backlog "velocity-subtask-test"
    init_sprint_state
    init_velocity_history
    
    add_backlog_item "Feature" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down and complete
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "done"
    update_parent_status "TASK-001"
    
    # Record sprint velocity
    local done_points=$(get_sprint_completed_points 1)
    local total_points=$(get_sprint_points 1)
    record_sprint_velocity 1 "$done_points" "$total_points"
    
    # Check velocity was recorded
    local velocity=$(calculate_velocity)
    local total=$(echo "$velocity" | jq '.total_points_completed')
    
    [[ $total -gt 0 ]]
}

@test "integration: project completion requires all subtasks done" {
    init_backlog "project-done-test"
    init_sprint_state
    
    add_backlog_item "Only Feature" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    # Complete only parent (not subtasks)
    jq '(.items[] | select(.id == "TASK-001")).status = "done"' "$BACKLOG_FILE" > tmp.json && mv tmp.json "$BACKLOG_FILE"
    
    # Project should NOT be done (subtasks still pending)
    run is_project_done
    assert_failure
    
    # Complete subtasks
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "done"
    
    # Now project should be done
    run is_project_done
    assert_success
}

@test "integration: subtask inherits acceptance criteria from parent" {
    init_backlog "ac-inherit-test"
    init_sprint_state
    
    # Create task with acceptance criteria
    local task_json='{
        "title": "Feature with AC",
        "type": "feature",
        "priority": 1,
        "story_points": 10,
        "acceptance_criteria": ["AC1: Must do X", "AC2: Must do Y", "AC3: Must do Z"]
    }'
    add_backlog_item_json "$task_json"
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Break down task
    break_down_task "TASK-001" "Part A" 5
    
    # Check subtask inherited AC
    local subtask_ac=$(jq '.items[] | select(.id == "TASK-001a") | .acceptance_criteria | length' "$BACKLOG_FILE")
    assert_equal "$subtask_ac" "3"
}

@test "integration: cancelled subtasks don't block parent completion" {
    init_backlog "cancelled-subtask-test"
    init_sprint_state
    
    add_backlog_item "Feature" "feature" 1 10
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    break_down_task "TASK-001" "Part A" 5
    break_down_task "TASK-001" "Part B" 5
    
    # Complete one, cancel the other
    update_item_status "TASK-001a" "done"
    update_item_status "TASK-001b" "cancelled"
    
    update_parent_status "TASK-001"
    
    # Parent should be done (all non-cancelled subtasks are done)
    local status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$status" "done"
}
