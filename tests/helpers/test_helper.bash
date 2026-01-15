#!/usr/bin/env bash
# Test Helper Utilities for Sprinty Test Suite

# ============================================================================
# ASSERTION FUNCTIONS
# ============================================================================

assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "Expected success but got status $status"
        echo "Output: $output"
        return 1
    fi
}

assert_failure() {
    if [ "$status" -eq 0 ]; then
        echo "Expected failure but got success"
        echo "Output: $output"
        return 1
    fi
}

assert_equal() {
    if [ "$1" != "$2" ]; then
        echo "Expected '$2' but got '$1'"
        return 1
    fi
}

assert_not_equal() {
    if [ "$1" == "$2" ]; then
        echo "Expected not '$2' but got '$1'"
        return 1
    fi
}

assert_output() {
    if [ "$1" == "--partial" ]; then
        local expected="$2"
        if [[ "$output" != *"$expected"* ]]; then
            echo "Expected output to contain: '$expected'"
            echo "Actual output: '$output'"
            return 1
        fi
    else
        local expected="$1"
        if [ "$output" != "$expected" ]; then
            echo "Expected output: '$expected'"
            echo "Actual output: '$output'"
            return 1
        fi
    fi
}

assert_output_contains() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: '$expected'"
        echo "Actual output: '$output'"
        return 1
    fi
}

assert_output_not_contains() {
    local expected="$1"
    if [[ "$output" == *"$expected"* ]]; then
        echo "Expected output NOT to contain: '$expected'"
        echo "Actual output: '$output'"
        return 1
    fi
}

# ============================================================================
# FILE/DIRECTORY ASSERTIONS
# ============================================================================

assert_file_exists() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo "File does not exist: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file=$1
    if [[ -f "$file" ]]; then
        echo "File exists but should not: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        echo "Directory does not exist: $dir"
        return 1
    fi
}

assert_valid_json() {
    local file=$1
    if ! jq empty "$file" 2>/dev/null; then
        echo "Invalid JSON in file: $file"
        cat "$file"
        return 1
    fi
}

# ============================================================================
# JSON HELPERS
# ============================================================================

get_json_field() {
    local file=$1
    local field=$2
    jq -r ".$field" "$file" 2>/dev/null
}

get_json_array_length() {
    local file=$1
    local field=$2
    jq -r ".$field | length" "$file" 2>/dev/null
}

# ============================================================================
# TEST ENVIRONMENT
# ============================================================================

export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-/tmp/bats-sprinty-$$}"

# Get the project root directory
get_project_root() {
    local test_dir
    test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$test_dir/../.." && pwd)"
}

# Setup test environment - called by setup() in tests
setup_test_environment() {
    # Get project root
    export PROJECT_ROOT="$(get_project_root)"
    export SPRINTY_ROOT="$PROJECT_ROOT"
    
    # Create unique temp directory for this test
    export TEST_DIR="$(mktemp -d /tmp/sprinty_test_XXXXXX)"
    export TEST_TEMP_DIR="$TEST_DIR"
    cd "$TEST_DIR"
    
    # Set up test environment variables
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export STATUS_FILE="$SPRINTY_DIR/status.json"
    export SPRINT_STATE_FILE="$SPRINTY_DIR/sprint_state.json"
    export RATE_LIMIT_STATE_FILE="$SPRINTY_DIR/.rate_limit_state"
    export CIRCUIT_BREAKER_STATE_FILE="$SPRINTY_DIR/.circuit_breaker_state"
    export EXIT_SIGNALS_FILE="$SPRINTY_DIR/.exit_signals"
    export PROMPTS_DIR="$SPRINTY_ROOT/prompts"
    
    # Configuration defaults
    export MAX_CALLS_PER_HOUR=100
    export DEFAULT_MAX_SPRINTS=10
    export DEFAULT_CAPACITY=20
    export VERSION="0.1.0"
    
    # Create necessary directories
    mkdir -p "$SPRINTY_DIR" "$TEST_DIR/logs"
}

# Cleanup test environment - called by teardown() in tests
cleanup_test_environment() {
    # Clean up temp directory
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Setup function - runs before each test (for compatibility)
setup() {
    setup_test_environment
}

# Teardown function - runs after each test (for compatibility)
teardown() {
    cleanup_test_environment
}

# ============================================================================
# MOCK HELPERS
# ============================================================================

# Create a mock backlog with items
create_mock_backlog() {
    local project_name=${1:-"test-project"}
    local num_items=${2:-3}
    
    cat > "$BACKLOG_FILE" << EOF
{
  "project": "$project_name",
  "items": [],
  "metadata": {
    "total_items": 0,
    "total_points": 0,
    "created_at": "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')",
    "last_updated": "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
  }
}
EOF
    
    # Add mock items
    for ((i=1; i<=num_items; i++)); do
        local task_id=$(printf "TASK-%03d" $i)
        local status="backlog"
        [[ $i -eq 1 ]] && status="ready"
        [[ $i -eq 2 ]] && status="in_progress"
        
        jq --arg id "$task_id" \
           --arg title "Test Task $i" \
           --arg status "$status" \
           --argjson points $((i * 2)) '
            .items += [{
                "id": $id,
                "title": $title,
                "type": "feature",
                "priority": 1,
                "story_points": $points,
                "status": $status,
                "sprint_id": null,
                "acceptance_criteria": ["AC1", "AC2"],
                "dependencies": [],
                "parent_id": null,
                "subtasks": [],
                "created_at": "2026-01-06T10:00:00Z",
                "updated_at": "2026-01-06T10:00:00Z"
            }] |
            .metadata.total_items = (.items | length) |
            .metadata.total_points = ([.items[].story_points] | add // 0)
        ' "$BACKLOG_FILE" > "${BACKLOG_FILE}.tmp" && mv "${BACKLOG_FILE}.tmp" "$BACKLOG_FILE"
    done
}

# Create mock sprint state
create_mock_sprint_state() {
    local sprint=${1:-1}
    local phase=${2:-"planning"}
    
    mkdir -p "$SPRINTY_DIR"
    cat > "$SPRINT_STATE_FILE" << EOF
{
    "current_sprint": $sprint,
    "current_phase": "$phase",
    "phase_loop_count": 0,
    "rework_count": 0,
    "project_done": false,
    "created_at": "2026-01-06T10:00:00Z",
    "last_updated": "2026-01-06T10:00:00Z"
}
EOF
}

# Create mock config
create_mock_config() {
    mkdir -p "$SPRINTY_DIR"
    cat > "$SPRINTY_DIR/config.json" << 'EOF'
{
    "project": { "name": "test-project" },
    "sprint": {
        "max_sprints": 10,
        "default_capacity": 20,
        "planning_max_loops": 3,
        "implementation_max_loops": 20,
        "qa_max_loops": 5,
        "review_max_loops": 2,
        "max_rework_cycles": 3
    },
    "rate_limiting": {
        "max_calls_per_hour": 100,
        "min_wait_between_calls_sec": 5
    },
    "circuit_breaker": {
        "max_consecutive_failures": 3,
        "max_consecutive_no_progress": 5
    }
}
EOF
}

# Create mock agent output with SPRINTY_STATUS block
create_mock_agent_output() {
    local output_file=${1:-"agent_output.log"}
    local status=${2:-"IN_PROGRESS"}
    local phase_complete=${3:-"false"}
    local project_done=${4:-"false"}
    
    cat > "$output_file" << EOF
Analyzing requirements...
Implementing feature...

Created src/feature.ts with 100 lines of code.
All tests passing.

---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 1
TASKS_COMPLETED: 1
TASKS_REMAINING: 2
BLOCKERS: none
STORY_POINTS_DONE: 5
TESTS_STATUS: PASSING
PHASE_COMPLETE: $phase_complete
PROJECT_DONE: $project_done
NEXT_ACTION: Continue with next task
---END_SPRINTY_STATUS---
EOF
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Strip ANSI color codes from output
strip_colors() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# Skip test if command not available
skip_if_not_installed() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        skip "$cmd is not installed"
    fi
}

# Debug helper - print current state
debug_state() {
    echo "=== DEBUG STATE ===" >&2
    echo "TEST_TEMP_DIR: $TEST_TEMP_DIR" >&2
    echo "BACKLOG_FILE: $BACKLOG_FILE" >&2
    [[ -f "$BACKLOG_FILE" ]] && cat "$BACKLOG_FILE" >&2
    echo "===================" >&2
}
