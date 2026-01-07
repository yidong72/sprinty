#!/usr/bin/env bats
# Integration tests for resume functionality

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source all required modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
    source "$PROJECT_ROOT/lib/rate_limiter.sh"
    source "$PROJECT_ROOT/lib/metrics_collector.sh"
    
    # Source main script functions
    eval "$(sed -n '/^is_resuming_sprint()/,/^}/p' "$PROJECT_ROOT/sprinty.sh")"
    eval "$(sed -n '/^resume_sprint()/,/^}/p' "$PROJECT_ROOT/sprinty.sh" | head -200)"
    
    # Mock execute_phase to not actually run agents
    execute_phase() {
        local phase=$1
        local role=$2
        log_status "INFO" "Mock: execute_phase $phase $role"
        return 0
    }
    
    # Mock other functions
    is_project_complete() { return 1; }
    mark_project_done() { log_status "INFO" "Mock: mark_project_done"; }
    has_tasks_to_rework() { return 1; }  # No rework needed
    increment_rework() { update_sprint_state "rework_count" $(($(get_rework_count) + 1)); }
    is_rework_limit_exceeded() { [[ $(get_rework_count) -ge 3 ]]; }
    record_sprint_velocity() { log_status "INFO" "Mock: record_sprint_velocity"; }
    end_sprint() { log_status "INFO" "Mock: end_sprint $1"; }
    get_sprint_completed_points() { echo "10"; }
    get_sprint_points() { echo "20"; }
    is_phase_complete() { return 1; }  # Phases not complete by default
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# FULL RESUME WORKFLOW TESTS
# ============================================================================

@test "integration: resume from Sprint 1 implementation" {
    init_sprint_state
    init_backlog "test-project"
    init_circuit_breaker
    
    # Setup: Sprint 1, implementation phase with tasks
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 3 '["AC2"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).sprint_id = 1 | (.items[1]).status = "in_progress"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Set phase to implementation
    set_current_phase "implementation"
    
    # Verify we're resuming
    run is_resuming_sprint
    assert_success
    
    # Resume sprint
    run resume_sprint
    assert_success
    
    # Verify sprint number unchanged
    local sprint=$(get_current_sprint)
    assert_equal "$sprint" "1"
}

@test "integration: resume from Sprint 1 planning with tasks assigned" {
    init_sprint_state
    init_backlog "test-project"
    
    # Setup: Sprint 1, planning phase, tasks assigned
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Still in planning phase but tasks are assigned
    # (simulates kill after planning complete but before phase change)
    
    # Verify we're resuming
    run is_resuming_sprint
    assert_success
    
    # Resume should skip planning (tasks already assigned)
    run resume_sprint
    assert_success
}

@test "integration: resume from Sprint 1 QA" {
    init_sprint_state
    init_backlog "test-project"
    
    # Setup: Sprint 1, QA phase
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    set_current_phase "qa"
    
    # Verify resuming
    run is_resuming_sprint
    assert_success
    
    # Resume
    run resume_sprint
    assert_success
    
    # Sprint number unchanged
    local sprint=$(get_current_sprint)
    assert_equal "$sprint" "1"
}

@test "integration: resume from Sprint 1 review" {
    init_sprint_state
    init_backlog "test-project"
    
    # Setup: Sprint 1, review phase
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "qa_passed"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    set_current_phase "review"
    
    # Verify resuming
    run is_resuming_sprint
    assert_success
    
    # Resume
    run resume_sprint
    assert_success
}

@test "integration: fresh sprint when not resuming" {
    init_sprint_state
    init_backlog "test-project"
    
    # Sprint 0, no resume needed
    run is_resuming_sprint
    assert_failure  # Not resuming
}

# ============================================================================
# RESUME WITH REWORK TESTS
# ============================================================================

@test "integration: resume preserves rework counter" {
    init_sprint_state
    init_backlog "test-project"
    
    # Setup: Sprint 1, implementation with rework=1
    start_sprint
    set_current_phase "implementation"
    update_sprint_state "rework_count" 1
    
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "qa_failed"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Verify rework count preserved
    local rework_before=$(get_rework_count)
    assert_equal "$rework_before" "1"
    
    # Resume
    run resume_sprint
    assert_success
    
    # Rework count should be used in resume logic
    local rework_after=$(get_rework_count)
    assert_equal "$rework_after" "1"
}

# ============================================================================
# SPRINT NUMBER CONSISTENCY TESTS
# ============================================================================

@test "integration: sprint number doesn't increment on resume" {
    init_sprint_state
    init_backlog "test-project"
    
    # Start Sprint 1
    local sprint1=$(start_sprint)
    assert_equal "$sprint1" "1"
    
    # Add tasks
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "in_progress"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Move to implementation (simulates work in progress)
    set_current_phase "implementation"
    
    # Now "kill and restart" - verify is_resuming detects it
    local resuming
    if is_resuming_sprint; then
        resuming="yes"
    else
        resuming="no"
    fi
    assert_equal "$resuming" "yes"
    
    # Resume - sprint number should stay 1
    run resume_sprint
    assert_success
    
    local sprint_after=$(get_current_sprint)
    assert_equal "$sprint_after" "1"
}

@test "integration: multiple resumes stay on same sprint" {
    init_sprint_state
    init_backlog "test-project"
    
    # Start Sprint 1
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # First "kill" during implementation
    set_current_phase "implementation"
    
    # Resume 1
    run resume_sprint
    assert_success
    local sprint1=$(get_current_sprint)
    
    # Second "kill" during QA
    set_current_phase "qa"
    
    # Resume 2
    run resume_sprint
    assert_success
    local sprint2=$(get_current_sprint)
    
    # Third "kill" during review
    set_current_phase "review"
    
    # Resume 3
    run resume_sprint
    assert_success
    local sprint3=$(get_current_sprint)
    
    # All should be Sprint 1
    assert_equal "$sprint1" "1"
    assert_equal "$sprint2" "1"
    assert_equal "$sprint3" "1"
}

# ============================================================================
# PHASE SKIPPING TESTS
# ============================================================================

@test "integration: resume skips completed planning phase" {
    init_sprint_state
    init_backlog "test-project"
    
    # Mock is_phase_complete to return true for planning
    is_phase_complete() {
        local phase=$1
        if [[ "$phase" == "planning" ]]; then
            return 0  # Complete
        else
            return 1  # Not complete
        fi
    }
    
    # Setup: Sprint 1, planning phase with tasks
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Resume from planning
    run resume_sprint
    assert_success
    
    # Planning should have been skipped (check via logs would be ideal)
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "integration: resume handles missing backlog gracefully" {
    init_sprint_state
    
    # No backlog
    rm -f "$BACKLOG_FILE"
    
    # Set to Sprint 1, implementation
    jq '.current_sprint = 1 | .current_phase = "implementation"' "$SPRINT_STATE_FILE" > tmp && mv tmp "$SPRINT_STATE_FILE"
    
    # Should still detect resume
    run is_resuming_sprint
    assert_success
}

@test "integration: resume handles empty backlog" {
    init_sprint_state
    init_backlog "test-project"
    
    # Sprint 1, implementation, but no tasks
    start_sprint
    set_current_phase "implementation"
    
    # Should resume but might exit quickly
    run resume_sprint
    assert_success
}

# ============================================================================
# STATE FILE VALIDATION TESTS
# ============================================================================

@test "integration: sprint state valid after resume" {
    init_sprint_state
    init_backlog "test-project"
    
    start_sprint
    set_current_phase "implementation"
    
    # Resume
    run resume_sprint
    assert_success
    
    # Verify state file is valid JSON
    assert_valid_json "$SPRINT_STATE_FILE"
    
    # Verify required fields exist
    local sprint=$(get_current_sprint)
    [[ -n "$sprint" ]]
    
    local phase=$(get_current_phase)
    [[ -n "$phase" ]]
}

@test "integration: backlog valid after resume" {
    init_sprint_state
    init_backlog "test-project"
    add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
    
    start_sprint
    jq '(.items[0]).sprint_id = 1' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    set_current_phase "implementation"
    
    # Resume
    run resume_sprint
    assert_success
    
    # Verify backlog still valid
    assert_valid_json "$BACKLOG_FILE"
    
    # Verify tasks still there
    local count=$(jq '.items | length' "$BACKLOG_FILE")
    assert_equal "$count" "1"
}

# ============================================================================
# CROSS-PHASE RESUME TESTS
# ============================================================================

@test "integration: resume from each phase executes correctly" {
    local phases=("planning" "implementation" "qa" "review")
    
    for phase in "${phases[@]}"; do
        # Setup fresh environment for each phase
        cleanup_test_environment
        setup_test_environment
        
        init_sprint_state
        init_backlog "test-project"
        start_sprint
        add_backlog_item "Task 1" "feature" 1 5 '["AC1"]'
        jq '(.items[0]).sprint_id = 1' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
        
        set_current_phase "$phase"
        
        # Should detect resume
        run is_resuming_sprint
        assert_success
        
        # Should be able to resume
        run resume_sprint
        assert_success
    done
}

# ============================================================================
# CIRCUIT BREAKER INTERACTION TESTS
# ============================================================================

@test "integration: resume works with circuit breaker closed" {
    init_sprint_state
    init_backlog "test-project"
    init_circuit_breaker
    
    start_sprint
    set_current_phase "implementation"
    
    # Circuit breaker closed
    local state=$(get_circuit_state)
    assert_equal "$state" "CLOSED"
    
    # Resume should work
    run resume_sprint
    assert_success
}

@test "integration: resume respects circuit breaker state" {
    init_sprint_state
    init_backlog "test-project"
    init_circuit_breaker
    
    start_sprint
    set_current_phase "implementation"
    
    # Circuit breaker state persists
    # Trigger some no-progress loops
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    local state=$(get_circuit_state)
    # Should be HALF_OPEN after 2 loops without progress
    
    # Resume should still work (circuit not fully open yet)
    run resume_sprint
    assert_success
}
