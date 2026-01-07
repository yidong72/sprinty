#!/usr/bin/env bats
# Unit tests for resume functionality

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source required modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    
    # Source the main script to get resume functions
    # Extract just the resume functions
    eval "$(sed -n '/^is_resuming_sprint()/,/^}/p' "$PROJECT_ROOT/sprinty.sh")"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# is_resuming_sprint() TESTS
# ============================================================================

@test "resume: not resuming on Sprint 0" {
    init_sprint_state
    
    # Sprint 0 (initialization)
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "false"
}

@test "resume: not resuming on fresh Sprint 1 planning" {
    init_sprint_state
    init_backlog "test-project"
    
    # Start Sprint 1, no tasks assigned yet
    start_sprint
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "false"
}

@test "resume: resuming on Sprint 1 planning with tasks assigned" {
    init_sprint_state
    init_backlog "test-project"
    
    # Start Sprint 1
    start_sprint
    
    # Assign tasks to sprint 1
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

@test "resume: resuming on Sprint 1 implementation" {
    init_sprint_state
    init_backlog "test-project"
    
    # Set state to Sprint 1, implementation
    jq '.current_sprint = 1 | .current_phase = "implementation"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

@test "resume: resuming on Sprint 1 QA" {
    init_sprint_state
    init_backlog "test-project"
    
    # Set state to Sprint 1, QA
    jq '.current_sprint = 1 | .current_phase = "qa"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

@test "resume: resuming on Sprint 1 review" {
    init_sprint_state
    init_backlog "test-project"
    
    # Set state to Sprint 1, review
    jq '.current_sprint = 1 | .current_phase = "review"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

@test "resume: resuming on Sprint 2 implementation" {
    init_sprint_state
    init_backlog "test-project"
    
    # Set state to Sprint 2, implementation
    jq '.current_sprint = 2 | .current_phase = "implementation"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

# ============================================================================
# RESUME STATE VERIFICATION
# ============================================================================

@test "resume: state preserved after sprint increment" {
    init_sprint_state
    init_backlog "test-project"
    
    # Start Sprint 1
    local sprint_id=$(start_sprint)
    
    assert_equal "$sprint_id" "1"
    
    # Verify state
    local current=$(get_current_sprint)
    assert_equal "$current" "1"
    
    local phase=$(get_current_phase)
    assert_equal "$phase" "planning"
}

@test "resume: rework counter preserved" {
    init_sprint_state
    
    # Set rework count
    update_sprint_state "rework_count" 2
    
    local rework=$(get_rework_count)
    assert_equal "$rework" "2"
}

@test "resume: phase loop counter preserved" {
    init_sprint_state
    
    # Set phase loop count
    update_sprint_state "phase_loop_count" 5
    
    local loop=$(get_phase_loop_count)
    assert_equal "$loop" "5"
}

# ============================================================================
# BACKLOG STATE PRESERVATION
# ============================================================================

@test "resume: task status preserved across restart" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 3 '["AC2"]'
    
    # Update statuses
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-002" "in_progress"
    
    # Verify preserved
    local status1=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status1" "implemented"
    
    local status2=$(jq -r '.items[1].status' "$BACKLOG_FILE")
    assert_equal "$status2" "in_progress"
}

@test "resume: sprint assignments preserved" {
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 3 '["AC2"]'
    
    # Assign to Sprint 1
    jq '(.items[0]).sprint_id = 1 | (.items[1]).sprint_id = 1' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Verify preserved
    local sprint1=$(jq -r '.items[0].sprint_id' "$BACKLOG_FILE")
    assert_equal "$sprint1" "1"
    
    local sprint2=$(jq -r '.items[1].sprint_id' "$BACKLOG_FILE")
    assert_equal "$sprint2" "1"
}

# ============================================================================
# EDGE CASES
# ============================================================================

@test "resume: handles missing backlog file gracefully" {
    init_sprint_state
    
    # No backlog file
    rm -f "$BACKLOG_FILE"
    
    # Set to Sprint 1, implementation
    jq '.current_sprint = 1 | .current_phase = "implementation"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    # Should still detect resume (not dependent on backlog)
    local result
    if is_resuming_sprint; then
        result="true"
    else
        result="false"
    fi
    
    assert_equal "$result" "true"
}

@test "resume: handles corrupted sprint state gracefully" {
    # Create invalid JSON
    echo "invalid json" > "$SPRINT_STATE_FILE"
    
    # init_sprint_state should recreate it
    init_sprint_state
    
    # Should be valid now
    assert_valid_json "$SPRINT_STATE_FILE"
}

@test "resume: handles null values in sprint state" {
    init_sprint_state
    
    # Set null phase
    jq '.current_phase = null' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    # get_current_phase should return empty string, not crash
    local phase=$(get_current_phase)
    [[ -z "$phase" || "$phase" == "null" ]]
}
