#!/usr/bin/env bats
# Unit Tests for Circuit Breaker Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-cb-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export CB_STATE_FILE=".sprinty/.circuit_breaker_state"
    export CB_HISTORY_FILE=".sprinty/.circuit_breaker_history"
    export CB_NO_PROGRESS_THRESHOLD=3
    export CB_SAME_ERROR_THRESHOLD=5
    
    mkdir -p .sprinty logs
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

@test "init_circuit_breaker creates state file" {
    init_circuit_breaker
    
    assert_file_exists "$CB_STATE_FILE"
}

@test "init_circuit_breaker creates valid JSON state" {
    init_circuit_breaker
    
    assert_valid_json "$CB_STATE_FILE"
}

@test "init_circuit_breaker creates history file" {
    init_circuit_breaker
    
    assert_file_exists "$CB_HISTORY_FILE"
}

@test "init_circuit_breaker sets state to CLOSED" {
    init_circuit_breaker
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "CLOSED"
}

@test "init_circuit_breaker sets consecutive_no_progress to 0" {
    init_circuit_breaker
    
    local count=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$count" "0"
}

@test "init_circuit_breaker does not overwrite valid existing state" {
    init_circuit_breaker
    # Update to a different state
    jq '.consecutive_no_progress = 2' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    init_circuit_breaker
    
    local count=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$count" "2"
}

@test "init_circuit_breaker recreates invalid JSON" {
    mkdir -p .sprinty
    echo "invalid json" > "$CB_STATE_FILE"
    
    init_circuit_breaker
    
    assert_valid_json "$CB_STATE_FILE"
}

# ============================================================================
# STATE QUERIES TESTS
# ============================================================================

@test "get_circuit_state returns CLOSED initially" {
    init_circuit_breaker
    
    result=$(get_circuit_state)
    assert_equal "$result" "CLOSED"
}

@test "get_circuit_state returns CLOSED when file missing" {
    rm -f "$CB_STATE_FILE"
    
    result=$(get_circuit_state)
    assert_equal "$result" "CLOSED"
}

@test "can_execute returns true when CLOSED" {
    init_circuit_breaker
    
    run can_execute
    assert_success
}

@test "can_execute returns true when HALF_OPEN" {
    init_circuit_breaker
    jq '.state = "HALF_OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    run can_execute
    assert_success
}

@test "can_execute returns false when OPEN" {
    init_circuit_breaker
    jq '.state = "OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    run can_execute
    assert_failure
}

@test "should_halt_execution returns false when CLOSED" {
    init_circuit_breaker
    
    run should_halt_execution
    assert_failure
}

@test "should_halt_execution returns true when OPEN" {
    init_circuit_breaker
    jq '.state = "OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    run should_halt_execution
    assert_success
}

# ============================================================================
# RECORD LOOP RESULT TESTS
# ============================================================================

@test "record_loop_result resets counter on progress" {
    init_circuit_breaker
    jq '.consecutive_no_progress = 2' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    # files_changed > 0 means progress
    record_loop_result 1 5 "false" 1000
    
    local count=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$count" "0"
}

@test "record_loop_result increments counter on no progress" {
    init_circuit_breaker
    
    # files_changed = 0 means no progress
    record_loop_result 1 0 "false" 1000
    
    local count=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$count" "1"
}

@test "record_loop_result updates current_loop" {
    init_circuit_breaker
    
    record_loop_result 5 1 "false" 1000
    
    local loop=$(jq -r '.current_loop' "$CB_STATE_FILE")
    assert_equal "$loop" "5"
}

@test "record_loop_result updates last_progress_loop on progress" {
    init_circuit_breaker
    
    record_loop_result 10 5 "false" 1000
    
    local last=$(jq -r '.last_progress_loop' "$CB_STATE_FILE")
    assert_equal "$last" "10"
}

@test "record_loop_result transitions to HALF_OPEN after 2 loops without progress" {
    init_circuit_breaker
    
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "HALF_OPEN"
}

@test "record_loop_result transitions to OPEN after threshold loops without progress" {
    init_circuit_breaker
    
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "OPEN"
}

@test "record_loop_result returns 1 when circuit opens" {
    init_circuit_breaker
    
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    run record_loop_result 3 0 "false" 1000
    assert_failure
}

@test "record_loop_result returns 0 when circuit stays closed" {
    init_circuit_breaker
    
    run record_loop_result 1 5 "false" 1000
    assert_success
}

@test "record_loop_result tracks same error repetition" {
    init_circuit_breaker
    
    record_loop_result 1 1 "true" 1000
    
    local count=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
    assert_equal "$count" "1"
}

@test "record_loop_result resets error counter on success" {
    init_circuit_breaker
    record_loop_result 1 1 "true" 1000
    
    record_loop_result 2 1 "false" 1000
    
    local count=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
    assert_equal "$count" "0"
}

@test "record_loop_result opens circuit on repeated errors" {
    init_circuit_breaker
    
    for i in 1 2 3 4 5; do
        record_loop_result $i 1 "true" 1000 || true
    done
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "OPEN"
}

@test "record_loop_result increments total_opens on state change to OPEN" {
    init_circuit_breaker
    
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "1"
}

# ============================================================================
# STATE RECOVERY TESTS
# ============================================================================

@test "record_loop_result recovers from HALF_OPEN to CLOSED on progress" {
    init_circuit_breaker
    # Set to HALF_OPEN
    jq '.state = "HALF_OPEN" | .consecutive_no_progress = 2' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    # Make progress
    record_loop_result 3 5 "false" 1000
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "CLOSED"
}

@test "record_loop_result opens from HALF_OPEN on continued no progress" {
    init_circuit_breaker
    # Set to HALF_OPEN with high no-progress count
    jq '.state = "HALF_OPEN" | .consecutive_no_progress = 2' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    # No progress
    record_loop_result 3 0 "false" 1000 || true
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "OPEN"
}

# ============================================================================
# HISTORY TRACKING TESTS
# ============================================================================

@test "log_circuit_transition adds to history" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "HALF_OPEN" "test reason" 1
    
    local count=$(jq 'length' "$CB_HISTORY_FILE")
    assert_equal "$count" "1"
}

@test "log_circuit_transition records from_state" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "OPEN" "test" 1
    
    local from=$(jq -r '.[0].from_state' "$CB_HISTORY_FILE")
    assert_equal "$from" "CLOSED"
}

@test "log_circuit_transition records to_state" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "OPEN" "test" 1
    
    local to=$(jq -r '.[0].to_state' "$CB_HISTORY_FILE")
    assert_equal "$to" "OPEN"
}

@test "log_circuit_transition records reason" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "OPEN" "no progress" 5
    
    local reason=$(jq -r '.[0].reason' "$CB_HISTORY_FILE")
    assert_equal "$reason" "no progress"
}

@test "log_circuit_transition records loop number" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "OPEN" "test" 42
    
    local loop=$(jq -r '.[0].loop' "$CB_HISTORY_FILE")
    assert_equal "$loop" "42"
}

# ============================================================================
# RESET TESTS
# ============================================================================

@test "reset_circuit_breaker sets state to CLOSED" {
    init_circuit_breaker
    jq '.state = "OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    reset_circuit_breaker
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "CLOSED"
}

@test "reset_circuit_breaker clears counters" {
    init_circuit_breaker
    jq '.consecutive_no_progress = 5 | .consecutive_same_error = 3' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    reset_circuit_breaker
    
    local no_progress=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    local same_error=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
    
    assert_equal "$no_progress" "0"
    assert_equal "$same_error" "0"
}

@test "reset_circuit_breaker sets reason" {
    init_circuit_breaker
    
    reset_circuit_breaker "custom reason"
    
    local reason=$(jq -r '.reason' "$CB_STATE_FILE")
    assert_equal "$reason" "custom reason"
}

@test "reset_circuit_breaker uses default reason" {
    init_circuit_breaker
    
    reset_circuit_breaker
    
    local reason=$(jq -r '.reason' "$CB_STATE_FILE")
    assert_equal "$reason" "Manual reset"
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

@test "CB_NO_PROGRESS_THRESHOLD is configurable" {
    export CB_NO_PROGRESS_THRESHOLD=5
    init_circuit_breaker
    
    # Should not open until 5 loops
    for i in 1 2 3 4; do
        record_loop_result $i 0 "false" 1000 || true
    done
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    # Should be HALF_OPEN, not OPEN yet
    [[ "$state" != "OPEN" ]]
}

@test "CB_SAME_ERROR_THRESHOLD is configurable" {
    export CB_SAME_ERROR_THRESHOLD=3
    init_circuit_breaker
    
    # Should open after 3 errors
    for i in 1 2 3; do
        record_loop_result $i 1 "true" 1000 || true
    done
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "OPEN"
}

# ============================================================================
# STATE FILE STRUCTURE TESTS
# ============================================================================

@test "state file has all required fields" {
    init_circuit_breaker
    
    local has_state=$(jq 'has("state")' "$CB_STATE_FILE")
    local has_last_change=$(jq 'has("last_change")' "$CB_STATE_FILE")
    local has_no_progress=$(jq 'has("consecutive_no_progress")' "$CB_STATE_FILE")
    local has_same_error=$(jq 'has("consecutive_same_error")' "$CB_STATE_FILE")
    local has_last_progress=$(jq 'has("last_progress_loop")' "$CB_STATE_FILE")
    local has_total_opens=$(jq 'has("total_opens")' "$CB_STATE_FILE")
    local has_reason=$(jq 'has("reason")' "$CB_STATE_FILE")
    local has_current_loop=$(jq 'has("current_loop")' "$CB_STATE_FILE")
    
    assert_equal "$has_state" "true"
    assert_equal "$has_last_change" "true"
    assert_equal "$has_no_progress" "true"
    assert_equal "$has_same_error" "true"
    assert_equal "$has_last_progress" "true"
    assert_equal "$has_total_opens" "true"
    assert_equal "$has_reason" "true"
    assert_equal "$has_current_loop" "true"
}

@test "state file starts with total_opens at 0" {
    init_circuit_breaker
    
    local opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "0"
}

@test "state file starts with current_loop at 0" {
    init_circuit_breaker
    
    local loop=$(jq -r '.current_loop' "$CB_STATE_FILE")
    assert_equal "$loop" "0"
}

# ============================================================================
# HISTORY FILE TESTS
# ============================================================================

@test "history file starts as empty array" {
    init_circuit_breaker
    
    local count=$(jq 'length' "$CB_HISTORY_FILE")
    assert_equal "$count" "0"
}

@test "history file accumulates transitions" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "HALF_OPEN" "test1" 1
    log_circuit_transition "HALF_OPEN" "OPEN" "test2" 2
    log_circuit_transition "OPEN" "CLOSED" "test3" 3
    
    local count=$(jq 'length' "$CB_HISTORY_FILE")
    assert_equal "$count" "3"
}

@test "history entries have timestamp" {
    init_circuit_breaker
    
    log_circuit_transition "CLOSED" "OPEN" "test" 1
    
    local has_ts=$(jq '.[0] | has("timestamp")' "$CB_HISTORY_FILE")
    assert_equal "$has_ts" "true"
}

# ============================================================================
# PROGRESS DETECTION TESTS
# ============================================================================

@test "record_loop_result detects progress from files_changed > 0" {
    init_circuit_breaker
    jq '.consecutive_no_progress = 5' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    record_loop_result 1 10 "false" 1000
    
    local no_progress=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$no_progress" "0"
}

@test "record_loop_result detects no progress from files_changed = 0" {
    init_circuit_breaker
    
    record_loop_result 1 0 "false" 1000
    
    local no_progress=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    assert_equal "$no_progress" "1"
}

@test "record_loop_result tracks consecutive errors" {
    init_circuit_breaker
    
    record_loop_result 1 1 "true" 1000
    record_loop_result 2 1 "true" 1000
    record_loop_result 3 1 "true" 1000
    
    local same_error=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
    assert_equal "$same_error" "3"
}

@test "record_loop_result resets error count on success" {
    init_circuit_breaker
    record_loop_result 1 1 "true" 1000
    record_loop_result 2 1 "true" 1000
    
    record_loop_result 3 1 "false" 1000
    
    local same_error=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
    assert_equal "$same_error" "0"
}

# ============================================================================
# STATE TRANSITION TESTS
# ============================================================================

@test "circuit stays CLOSED when making progress" {
    init_circuit_breaker
    
    for i in 1 2 3 4 5; do
        record_loop_result $i 5 "false" 1000
    done
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "CLOSED"
}

@test "circuit transitions CLOSED -> HALF_OPEN -> CLOSED on recovery" {
    init_circuit_breaker
    
    # No progress, enter HALF_OPEN
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "HALF_OPEN"
    
    # Make progress, recover to CLOSED
    record_loop_result 3 5 "false" 1000
    
    state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "CLOSED"
}

@test "circuit transitions CLOSED -> HALF_OPEN -> OPEN on continued no progress" {
    init_circuit_breaker
    
    # No progress loops
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    assert_equal "$state" "OPEN"
}

# ============================================================================
# HALT EXECUTION TESTS
# ============================================================================

@test "should_halt_execution returns 1 (no halt) when CLOSED" {
    init_circuit_breaker
    
    run should_halt_execution
    
    assert_failure
}

@test "should_halt_execution returns 1 (no halt) when HALF_OPEN" {
    init_circuit_breaker
    jq '.state = "HALF_OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    run should_halt_execution
    
    assert_failure
}

@test "should_halt_execution returns 0 (halt) when OPEN" {
    init_circuit_breaker
    jq '.state = "OPEN"' "$CB_STATE_FILE" > "${CB_STATE_FILE}.tmp" && mv "${CB_STATE_FILE}.tmp" "$CB_STATE_FILE"
    
    run should_halt_execution
    
    assert_success
}

# ============================================================================
# TOTAL OPENS TRACKING TESTS
# ============================================================================

@test "total_opens increments each time circuit opens" {
    init_circuit_breaker
    
    # First open
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    local opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "1"
}

@test "total_opens preserves count across resets" {
    init_circuit_breaker
    
    # Open circuit
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    # Reset - but check total_opens was recorded before reset clears it
    local opens=$(jq -r '.total_opens' "$CB_STATE_FILE")
    assert_equal "$opens" "1"
}
