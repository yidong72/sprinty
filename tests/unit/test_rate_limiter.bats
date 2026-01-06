#!/usr/bin/env bats
# Unit Tests for Rate Limiter Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-rate-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export RATE_LIMIT_DIR=".sprinty"
    export CALL_COUNT_FILE=".sprinty/.call_count"
    export TIMESTAMP_FILE=".sprinty/.last_reset"
    export RATE_LIMIT_STATE_FILE=".sprinty/.rate_limit_state"
    
    export MAX_CALLS_PER_HOUR=100
    
    mkdir -p .sprinty logs
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/rate_limiter.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

@test "init_rate_limiter creates call count file" {
    init_rate_limiter
    
    assert_file_exists "$CALL_COUNT_FILE"
}

@test "init_rate_limiter creates timestamp file" {
    init_rate_limiter
    
    assert_file_exists "$TIMESTAMP_FILE"
}

@test "init_rate_limiter creates state file" {
    init_rate_limiter
    
    assert_file_exists "$RATE_LIMIT_STATE_FILE"
}

@test "init_rate_limiter creates valid JSON state" {
    init_rate_limiter
    
    assert_valid_json "$RATE_LIMIT_STATE_FILE"
}

@test "init_rate_limiter initializes call count to 0" {
    init_rate_limiter
    
    local count=$(cat "$CALL_COUNT_FILE")
    assert_equal "$count" "0"
}

@test "init_rate_limiter stores current hour" {
    init_rate_limiter
    
    local stored_hour=$(cat "$TIMESTAMP_FILE")
    local current_hour=$(date +%Y%m%d%H)
    
    assert_equal "$stored_hour" "$current_hour"
}

@test "init_rate_limiter resets counter for new hour" {
    init_rate_limiter
    echo "50" > "$CALL_COUNT_FILE"
    echo "2020010100" > "$TIMESTAMP_FILE"  # Old hour
    
    init_rate_limiter
    
    local count=$(cat "$CALL_COUNT_FILE")
    assert_equal "$count" "0"
}

@test "init_rate_limiter preserves counter for same hour" {
    init_rate_limiter
    echo "50" > "$CALL_COUNT_FILE"
    
    init_rate_limiter
    
    local count=$(cat "$CALL_COUNT_FILE")
    assert_equal "$count" "50"
}

# ============================================================================
# RATE LIMIT CHECK TESTS
# ============================================================================

@test "can_make_call returns success when under limit" {
    init_rate_limiter
    echo "10" > "$CALL_COUNT_FILE"
    
    run can_make_call
    
    assert_success
}

@test "can_make_call returns failure when at limit" {
    init_rate_limiter
    echo "100" > "$CALL_COUNT_FILE"
    
    run can_make_call
    
    assert_failure
}

@test "can_make_call returns failure when over limit" {
    init_rate_limiter
    echo "150" > "$CALL_COUNT_FILE"
    
    run can_make_call
    
    assert_failure
}

@test "can_make_call respects MAX_CALLS_PER_HOUR" {
    export MAX_CALLS_PER_HOUR=50
    init_rate_limiter
    echo "50" > "$CALL_COUNT_FILE"
    
    run can_make_call
    
    assert_failure
}

@test "can_make_call initializes if files missing" {
    rm -f "$CALL_COUNT_FILE" "$TIMESTAMP_FILE"
    
    run can_make_call
    
    assert_success
    assert_file_exists "$CALL_COUNT_FILE"
}

# ============================================================================
# CALL COUNT TESTS
# ============================================================================

@test "get_call_count returns 0 when no file" {
    rm -f "$CALL_COUNT_FILE"
    
    result=$(get_call_count)
    
    assert_equal "$result" "0"
}

@test "get_call_count returns stored value" {
    init_rate_limiter
    echo "42" > "$CALL_COUNT_FILE"
    
    result=$(get_call_count)
    
    assert_equal "$result" "42"
}

@test "get_remaining_calls calculates correctly" {
    init_rate_limiter
    echo "30" > "$CALL_COUNT_FILE"
    
    result=$(get_remaining_calls)
    
    assert_equal "$result" "70"
}

@test "get_remaining_calls returns 0 when at limit" {
    init_rate_limiter
    echo "100" > "$CALL_COUNT_FILE"
    
    result=$(get_remaining_calls)
    
    assert_equal "$result" "0"
}

@test "get_remaining_calls returns 0 when over limit" {
    init_rate_limiter
    echo "150" > "$CALL_COUNT_FILE"
    
    result=$(get_remaining_calls)
    
    assert_equal "$result" "0"
}

# ============================================================================
# CALL TRACKING TESTS
# ============================================================================

@test "increment_call_counter increases count" {
    init_rate_limiter
    
    result=$(increment_call_counter)
    
    assert_equal "$result" "1"
}

@test "increment_call_counter returns new count" {
    init_rate_limiter
    echo "10" > "$CALL_COUNT_FILE"
    
    result=$(increment_call_counter)
    
    assert_equal "$result" "11"
}

@test "increment_call_counter persists to file" {
    init_rate_limiter
    
    increment_call_counter
    
    local stored=$(cat "$CALL_COUNT_FILE")
    assert_equal "$stored" "1"
}

@test "increment_call_counter updates state file" {
    init_rate_limiter
    
    increment_call_counter
    
    local current=$(jq -r '.current_calls' "$RATE_LIMIT_STATE_FILE")
    assert_equal "$current" "1"
}

@test "increment_call_counter tracks total session calls" {
    init_rate_limiter
    
    increment_call_counter
    increment_call_counter
    
    local total=$(jq -r '.total_calls_session' "$RATE_LIMIT_STATE_FILE")
    assert_equal "$total" "2"
}

@test "record_rate_limit_hit increments hit counter" {
    init_rate_limiter
    
    record_rate_limit_hit
    
    local hits=$(jq -r '.rate_limit_hits' "$RATE_LIMIT_STATE_FILE")
    assert_equal "$hits" "1"
}

@test "record_rate_limit_hit accumulates hits" {
    init_rate_limiter
    
    record_rate_limit_hit
    record_rate_limit_hit
    record_rate_limit_hit
    
    local hits=$(jq -r '.rate_limit_hits' "$RATE_LIMIT_STATE_FILE")
    assert_equal "$hits" "3"
}

# ============================================================================
# WAIT FUNCTIONS TESTS
# ============================================================================

@test "wait_between_calls completes without error" {
    # Just verify the function runs without error
    run wait_between_calls 0
    
    # Should succeed (sleep 0 is instant)
    assert_success
}

@test "wait_between_calls defaults to 5 seconds" {
    # We won't actually wait 5 seconds in test, just verify it's called
    # This is a smoke test
    run timeout 1 bash -c 'source "$PROJECT_ROOT/lib/utils.sh"; source "$PROJECT_ROOT/lib/rate_limiter.sh"; wait_between_calls' || true
    
    # Should timeout because default is 5 seconds
    [[ $status -eq 124 ]] || [[ $status -eq 0 ]]
}

# ============================================================================
# RESET TESTS
# ============================================================================

@test "reset_rate_limiter clears call count" {
    init_rate_limiter
    echo "50" > "$CALL_COUNT_FILE"
    
    reset_rate_limiter
    
    local count=$(cat "$CALL_COUNT_FILE")
    assert_equal "$count" "0"
}

@test "reset_rate_limiter updates timestamp" {
    init_rate_limiter
    echo "2020010100" > "$TIMESTAMP_FILE"
    
    reset_rate_limiter
    
    local stored=$(cat "$TIMESTAMP_FILE")
    local current=$(date +%Y%m%d%H)
    assert_equal "$stored" "$current"
}

@test "reset_rate_limiter clears state file" {
    init_rate_limiter
    increment_call_counter
    increment_call_counter
    record_rate_limit_hit
    
    reset_rate_limiter
    
    local current=$(jq -r '.current_calls' "$RATE_LIMIT_STATE_FILE")
    local total=$(jq -r '.total_calls_session' "$RATE_LIMIT_STATE_FILE")
    local hits=$(jq -r '.rate_limit_hits' "$RATE_LIMIT_STATE_FILE")
    
    assert_equal "$current" "0"
    assert_equal "$total" "0"
    assert_equal "$hits" "0"
}

@test "reset_rate_limiter preserves max_calls_per_hour" {
    init_rate_limiter
    
    reset_rate_limiter
    
    local max=$(jq -r '.max_calls_per_hour' "$RATE_LIMIT_STATE_FILE")
    assert_equal "$max" "$MAX_CALLS_PER_HOUR"
}

# ============================================================================
# STATE FILE TESTS
# ============================================================================

@test "state file has max_calls_per_hour" {
    init_rate_limiter
    
    local max=$(jq -r '.max_calls_per_hour' "$RATE_LIMIT_STATE_FILE")
    
    assert_equal "$max" "$MAX_CALLS_PER_HOUR"
}

@test "state file has last_reset timestamp" {
    init_rate_limiter
    
    local has_reset=$(jq 'has("last_reset")' "$RATE_LIMIT_STATE_FILE")
    
    assert_equal "$has_reset" "true"
}

@test "state file tracks all required fields" {
    init_rate_limiter
    
    local has_max=$(jq 'has("max_calls_per_hour")' "$RATE_LIMIT_STATE_FILE")
    local has_current=$(jq 'has("current_calls")' "$RATE_LIMIT_STATE_FILE")
    local has_total=$(jq 'has("total_calls_session")' "$RATE_LIMIT_STATE_FILE")
    local has_hits=$(jq 'has("rate_limit_hits")' "$RATE_LIMIT_STATE_FILE")
    
    assert_equal "$has_max" "true"
    assert_equal "$has_current" "true"
    assert_equal "$has_total" "true"
    assert_equal "$has_hits" "true"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

@test "full workflow: init, increment, check, reset" {
    # Initialize
    init_rate_limiter
    run can_make_call
    assert_success
    
    # Increment to limit
    for i in {1..100}; do
        increment_call_counter > /dev/null
    done
    
    # Should be at limit
    run can_make_call
    assert_failure
    
    # Reset
    reset_rate_limiter
    
    # Should be able to make calls again
    run can_make_call
    assert_success
}

@test "rate limiter respects custom MAX_CALLS_PER_HOUR" {
    export MAX_CALLS_PER_HOUR=10
    init_rate_limiter
    
    for i in {1..10}; do
        increment_call_counter > /dev/null
    done
    
    run can_make_call
    assert_failure
    
    local remaining=$(get_remaining_calls)
    assert_equal "$remaining" "0"
}
