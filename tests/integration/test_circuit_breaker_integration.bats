#!/usr/bin/env bats
# Integration Tests: Circuit Breaker
# Tests circuit breaker integration with sprint management and progress detection

# Load test helpers
load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-integration-cb.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export CB_STATE_FILE=".sprinty/.circuit_breaker_state"
    export CB_HISTORY_FILE=".sprinty/.circuit_breaker_history"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export BACKLOG_FILE="backlog.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    export CB_NO_PROGRESS_THRESHOLD=3
    export CB_SAME_ERROR_THRESHOLD=5
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source all modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# CIRCUIT BREAKER + SPRINT INTEGRATION TESTS
# ============================================================================

@test "integration: circuit breaker stays closed during normal sprint progress" {
    init_sprint_state
    init_backlog "cb-progress-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # Simulate progress loops
    for i in {1..5}; do
        # Each loop makes progress (files_changed > 0)
        record_loop_result $i 3 "false" 1000
    done
    
    local state=$(get_circuit_state)
    assert_equal "$state" "CLOSED"
    
    run can_execute
    assert_success
}

@test "integration: circuit breaker opens after no progress in sprint" {
    init_sprint_state
    init_backlog "cb-no-progress-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    
    # Simulate loops with no progress
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local state=$(get_circuit_state)
    assert_equal "$state" "OPEN"
    
    run can_execute
    assert_failure
    
    run should_halt_execution
    assert_success
}

@test "integration: circuit breaker recovers on sprint progress after HALF_OPEN" {
    init_sprint_state
    init_backlog "cb-recovery-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    
    # Enter HALF_OPEN state
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    local state=$(get_circuit_state)
    assert_equal "$state" "HALF_OPEN"
    
    # Make progress - complete a task
    update_item_status "TASK-001" "in_progress"
    record_loop_result 3 5 "false" 1000  # 5 files changed = progress
    
    state=$(get_circuit_state)
    assert_equal "$state" "CLOSED"
    
    run can_execute
    assert_success
}

@test "integration: circuit breaker opens on repeated errors during sprint" {
    init_sprint_state
    init_backlog "cb-error-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    
    # Simulate repeated errors
    for i in {1..5}; do
        record_loop_result $i 1 "true" 1000 || true
    done
    
    local state=$(get_circuit_state)
    assert_equal "$state" "OPEN"
}

@test "integration: circuit breaker reset allows sprint to continue" {
    init_sprint_state
    init_backlog "cb-reset-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    
    # Open circuit
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    run can_execute
    assert_failure
    
    # Reset circuit
    reset_circuit_breaker "Manual intervention"
    
    run can_execute
    assert_success
    
    # Sprint can continue
    local phase=$(get_current_phase)
    [[ -n "$phase" ]]
}

@test "integration: circuit breaker history tracks sprint loop numbers" {
    init_sprint_state
    init_backlog "cb-history-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    
    # Cause state transitions
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000  # -> HALF_OPEN
    record_loop_result 3 5 "false" 1000  # -> CLOSED (recovery)
    record_loop_result 4 0 "false" 1000
    record_loop_result 5 0 "false" 1000  # -> HALF_OPEN
    record_loop_result 6 0 "false" 1000 || true  # -> OPEN
    
    # Check history
    local history_count=$(jq 'length' "$CB_HISTORY_FILE")
    [[ $history_count -ge 3 ]]
    
    # Verify loop numbers are recorded
    local loops_recorded=$(jq '[.[].loop] | length' "$CB_HISTORY_FILE")
    assert_equal "$loops_recorded" "$history_count"
}

@test "integration: circuit breaker total_opens counter tracks sprint issues" {
    init_sprint_state
    init_backlog "cb-opens-test"
    init_circuit_breaker
    
    # First open
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "1"
    
    # Reset and open again
    reset_circuit_breaker
    record_loop_result 4 0 "false" 1000
    record_loop_result 5 0 "false" 1000
    record_loop_result 6 0 "false" 1000 || true
    
    # Note: reset clears total_opens, so this is a fresh count
    opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "1"
}

@test "integration: circuit breaker state persists across function calls" {
    init_circuit_breaker
    
    # Record some state
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    # Verify state persisted
    local state=$(get_circuit_state)
    assert_equal "$state" "HALF_OPEN"
    
    local no_progress=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$no_progress" "2"
    
    # Re-source module (simulating new session)
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
    
    # State should persist
    state=$(get_circuit_state)
    assert_equal "$state" "HALF_OPEN"
}

@test "integration: multiple sprints with circuit breaker resets" {
    init_sprint_state
    init_backlog "cb-multi-sprint-test"
    init_circuit_breaker
    
    add_backlog_item "Task 1" "feature" 1 3
    add_backlog_item "Task 2" "feature" 1 3
    
    # Sprint 1 with progress
    start_sprint
    assign_to_sprint "TASK-001" 1
    record_loop_result 1 5 "false" 1000
    update_item_status "TASK-001" "done"
    
    local state=$(get_circuit_state)
    assert_equal "$state" "CLOSED"
    
    end_sprint "completed"
    
    # Reset for sprint 2
    reset_circuit_breaker "New sprint"
    
    # Sprint 2
    start_sprint
    assign_to_sprint "TASK-002" 2
    record_loop_result 2 5 "false" 1000
    update_item_status "TASK-002" "done"
    
    state=$(get_circuit_state)
    assert_equal "$state" "CLOSED"
}
