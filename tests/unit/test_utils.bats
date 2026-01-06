#!/usr/bin/env bats
# Unit Tests for Utils Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-utils-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINTY_LOG_DIR="logs"
    export SPRINTY_LOG_FILE="logs/sprinty.log"
    
    mkdir -p .sprinty logs
    
    # Source the module under test
    source "$PROJECT_ROOT/lib/utils.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# TIMESTAMP FUNCTION TESTS
# ============================================================================

@test "get_iso_timestamp returns ISO 8601 format" {
    result=$(get_iso_timestamp)
    
    # Should match YYYY-MM-DDTHH:MM:SS pattern
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "get_basic_timestamp returns basic format" {
    result=$(get_basic_timestamp)
    
    # Should match YYYY-MM-DD HH:MM:SS pattern
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "get_unix_timestamp returns numeric value" {
    result=$(get_unix_timestamp)
    
    # Should be a number
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "get_unix_timestamp returns current time" {
    result=$(get_unix_timestamp)
    current=$(date +%s)
    
    # Should be within 2 seconds of current time
    diff=$((current - result))
    [[ $diff -ge -2 && $diff -le 2 ]]
}

@test "get_next_hour_time returns time format" {
    result=$(get_next_hour_time)
    
    # Should match HH:MM:SS pattern
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

# ============================================================================
# LOG DIRECTORY TESTS
# ============================================================================

@test "ensure_log_dir creates log directory" {
    rm -rf "$SPRINTY_LOG_DIR"
    
    ensure_log_dir
    
    assert_dir_exists "$SPRINTY_LOG_DIR"
}

@test "ensure_log_dir is idempotent" {
    ensure_log_dir
    ensure_log_dir
    
    assert_dir_exists "$SPRINTY_LOG_DIR"
}

# ============================================================================
# LOGGING TESTS
# ============================================================================

@test "log_status writes to log file" {
    log_status "INFO" "Test message"
    
    grep -q "Test message" "$SPRINTY_LOG_FILE"
}

@test "log_status includes timestamp in log file" {
    log_status "INFO" "Test message"
    
    grep -qE "\[[0-9]{4}-[0-9]{2}-[0-9]{2}" "$SPRINTY_LOG_FILE"
}

@test "log_status includes level in log file" {
    log_status "ERROR" "Error message"
    
    grep -q "\[ERROR\]" "$SPRINTY_LOG_FILE"
}

@test "log_status handles all levels" {
    log_status "INFO" "Info test"
    log_status "WARN" "Warn test"
    log_status "ERROR" "Error test"
    log_status "SUCCESS" "Success test"
    log_status "DEBUG" "Debug test"
    
    grep -q "\[INFO\]" "$SPRINTY_LOG_FILE"
    grep -q "\[WARN\]" "$SPRINTY_LOG_FILE"
    grep -q "\[ERROR\]" "$SPRINTY_LOG_FILE"
    grep -q "\[SUCCESS\]" "$SPRINTY_LOG_FILE"
    grep -q "\[DEBUG\]" "$SPRINTY_LOG_FILE"
}

@test "log_debug does not log when SPRINTY_DEBUG is false" {
    export SPRINTY_DEBUG="false"
    
    log_debug "Debug message"
    
    ! grep -q "Debug message" "$SPRINTY_LOG_FILE" 2>/dev/null || [[ ! -f "$SPRINTY_LOG_FILE" ]]
}

@test "log_debug logs when SPRINTY_DEBUG is true" {
    export SPRINTY_DEBUG="true"
    
    log_debug "Debug message"
    
    grep -q "Debug message" "$SPRINTY_LOG_FILE"
}

# ============================================================================
# JSON FILE UTILITIES TESTS
# ============================================================================

@test "safe_write_json creates valid JSON file" {
    safe_write_json "test.json" '{"key": "value"}'
    
    assert_file_exists "test.json"
    assert_valid_json "test.json"
}

@test "safe_write_json rejects invalid JSON" {
    run safe_write_json "test.json" 'not valid json'
    
    assert_failure
}

@test "safe_write_json overwrites existing file" {
    echo '{"old": "data"}' > "test.json"
    
    safe_write_json "test.json" '{"new": "data"}'
    
    local value=$(jq -r '.new' "test.json")
    assert_equal "$value" "data"
}

@test "read_json_file returns file contents" {
    echo '{"key": "value"}' > "test.json"
    
    result=$(read_json_file "test.json")
    
    echo "$result" | jq '.' > /dev/null
}

@test "read_json_file fails for missing file" {
    run read_json_file "nonexistent.json"
    
    assert_failure
}

@test "read_json_file fails for invalid JSON" {
    echo "not json" > "invalid.json"
    
    run read_json_file "invalid.json"
    
    assert_failure
}

# ============================================================================
# SPRINTY DIRECTORY UTILITIES TESTS
# ============================================================================

@test "ensure_sprinty_dir creates .sprinty directory" {
    rm -rf "$SPRINTY_DIR"
    
    ensure_sprinty_dir
    
    assert_dir_exists "$SPRINTY_DIR"
}

@test "ensure_sprinty_dir creates logs directory" {
    rm -rf logs
    
    ensure_sprinty_dir
    
    assert_dir_exists "logs"
}

@test "ensure_sprinty_dir creates sprints directory" {
    rm -rf sprints
    
    ensure_sprinty_dir
    
    assert_dir_exists "sprints"
}

@test "ensure_sprinty_dir creates reviews directory" {
    rm -rf reviews
    
    ensure_sprinty_dir
    
    assert_dir_exists "reviews"
}

@test "sprinty_path returns correct path" {
    result=$(sprinty_path "config.json")
    
    assert_equal "$result" "$SPRINTY_DIR/config.json"
}

@test "is_sprinty_initialized returns false when not initialized" {
    rm -rf "$SPRINTY_DIR"
    
    run is_sprinty_initialized
    
    assert_failure
}

@test "is_sprinty_initialized returns true when config exists" {
    mkdir -p "$SPRINTY_DIR"
    echo '{}' > "$SPRINTY_DIR/config.json"
    
    run is_sprinty_initialized
    
    assert_success
}

# ============================================================================
# JSON HELPERS TESTS
# ============================================================================

@test "json_get extracts value from file" {
    echo '{"name": "test", "count": 42}' > "test.json"
    
    result=$(json_get "test.json" ".name")
    
    assert_equal "$result" "test"
}

@test "json_get extracts nested value" {
    echo '{"outer": {"inner": "value"}}' > "test.json"
    
    result=$(json_get "test.json" ".outer.inner")
    
    assert_equal "$result" "value"
}

@test "json_get returns null for missing key" {
    echo '{"name": "test"}' > "test.json"
    
    result=$(json_get "test.json" ".missing")
    
    assert_equal "$result" "null"
}

@test "json_set updates value in file" {
    echo '{"count": 1}' > "test.json"
    
    json_set "test.json" ".count" "42"
    
    result=$(jq -r '.count' "test.json")
    assert_equal "$result" "42"
}

@test "json_set updates string value" {
    echo '{"name": "old"}' > "test.json"
    
    json_set "test.json" ".name" '"new"'
    
    result=$(jq -r '.name' "test.json")
    assert_equal "$result" "new"
}

# ============================================================================
# DEPENDENCY CHECK TESTS
# ============================================================================

@test "check_jq_installed returns success when jq available" {
    run check_jq_installed
    
    assert_success
}

@test "check_dependencies returns success with all dependencies" {
    run check_dependencies
    
    assert_success
}
