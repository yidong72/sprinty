#!/usr/bin/env bats
# Unit Tests for Done Detector Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-done-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export EXIT_SIGNALS_FILE=".sprinty/.exit_signals"
    export BACKLOG_FILE="backlog.json"
    export FIX_PLAN_FILE="@fix_plan.md"
    
    export MAX_CONSECUTIVE_IDLE_LOOPS=5
    export MAX_CONSECUTIVE_DONE_SIGNALS=3
    export MAX_CONSECUTIVE_TEST_LOOPS=5
    
    mkdir -p .sprinty logs
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/done_detector.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# INITIALIZATION TESTS
# ============================================================================

@test "init_exit_signals creates exit signals file" {
    init_exit_signals
    
    assert_file_exists "$EXIT_SIGNALS_FILE"
}

@test "init_exit_signals creates valid JSON" {
    init_exit_signals
    
    assert_valid_json "$EXIT_SIGNALS_FILE"
}

@test "init_exit_signals has empty arrays" {
    init_exit_signals
    
    local idle_count=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    local done_count=$(jq '.done_signals | length' "$EXIT_SIGNALS_FILE")
    
    assert_equal "$idle_count" "0"
    assert_equal "$done_count" "0"
}

@test "reset_exit_signals clears all signals" {
    init_exit_signals
    record_idle_loop 1 "test"
    record_done_signal 1 "test"
    
    reset_exit_signals
    
    local idle_count=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$idle_count" "0"
}

# ============================================================================
# SIGNAL RECORDING TESTS
# ============================================================================

@test "record_idle_loop adds to idle_loops array" {
    init_exit_signals
    
    record_idle_loop 1 "no_changes"
    
    local count=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$count" "1"
}

@test "record_idle_loop stores loop number" {
    init_exit_signals
    
    record_idle_loop 5 "no_changes"
    
    local loop=$(jq '.idle_loops[0].loop' "$EXIT_SIGNALS_FILE")
    assert_equal "$loop" "5"
}

@test "record_idle_loop stores reason" {
    init_exit_signals
    
    record_idle_loop 1 "custom_reason"
    
    local reason=$(jq -r '.idle_loops[0].reason' "$EXIT_SIGNALS_FILE")
    assert_equal "$reason" "custom_reason"
}

@test "record_idle_loop keeps only last 10 entries" {
    init_exit_signals
    
    for i in {1..15}; do
        record_idle_loop $i "test"
    done
    
    local count=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$count" "10"
}

@test "record_done_signal adds to done_signals array" {
    init_exit_signals
    
    record_done_signal 1 "agent_response"
    
    local count=$(jq '.done_signals | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$count" "1"
}

@test "record_done_signal stores source" {
    init_exit_signals
    
    record_done_signal 1 "sprinty_status_block"
    
    local source=$(jq -r '.done_signals[0].source' "$EXIT_SIGNALS_FILE")
    assert_equal "$source" "sprinty_status_block"
}

@test "record_completion_indicator adds to completion_indicators" {
    init_exit_signals
    
    record_completion_indicator 1 "phase_complete"
    
    local count=$(jq '.completion_indicators | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$count" "1"
}

@test "record_test_only_loop adds to test_only_loops" {
    init_exit_signals
    
    record_test_only_loop 1
    
    local count=$(jq '.test_only_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$count" "1"
}

# ============================================================================
# OUTPUT ANALYSIS TESTS
# ============================================================================

@test "analyze_output_for_completion detects PROJECT_DONE: true" {
    init_exit_signals
    echo "PROJECT_DONE: true" > "output.log"
    
    result=$(analyze_output_for_completion "output.log" 1)
    
    [[ $result -ge 1 ]]
}

@test "analyze_output_for_completion ignores PHASE_COMPLETE (not a project completion signal)" {
    init_exit_signals
    echo "PHASE_COMPLETE: true" > "output.log"
    
    result=$(analyze_output_for_completion "output.log" 1)
    
    # PHASE_COMPLETE is a normal phase transition, not a project completion signal
    # It should NOT count towards completion indicators
    [[ $result -eq 0 ]]
}

@test "analyze_output_for_completion detects completion keywords" {
    init_exit_signals
    echo "🎉 Project complete!" > "output.log"
    
    result=$(analyze_output_for_completion "output.log" 1)
    
    [[ $result -ge 1 ]]
}

@test "analyze_output_for_completion detects TASKS_REMAINING: 0" {
    init_exit_signals
    echo "TASKS_REMAINING: 0" > "output.log"
    
    result=$(analyze_output_for_completion "output.log" 1)
    
    [[ $result -ge 1 ]]
}

@test "analyze_output_for_completion returns 0 for missing file" {
    init_exit_signals
    
    run analyze_output_for_completion "nonexistent.log" 1
    
    assert_failure
}

@test "analyze_output_for_completion returns 0 for empty file" {
    init_exit_signals
    touch "empty.log"
    
    result=$(analyze_output_for_completion "empty.log" 1)
    
    assert_equal "$result" "0"
}

# ============================================================================
# BACKLOG COMPLETION TESTS
# ============================================================================

@test "check_backlog_completion returns failure when not initialized" {
    rm -f "$BACKLOG_FILE"
    
    run check_backlog_completion
    
    assert_failure
}

@test "check_backlog_completion returns failure when items pending" {
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    
    run check_backlog_completion
    
    assert_failure
}

@test "check_backlog_completion returns success when all done" {
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    run check_backlog_completion
    
    assert_success
}

@test "check_backlog_completion handles cancelled tasks" {
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "cancelled"
    
    run check_backlog_completion
    
    assert_success
}

@test "check_backlog_completion fails with P1 bug open" {
    init_backlog "test"
    add_backlog_item "Bug" "bug" 1 3
    
    run check_backlog_completion
    
    assert_failure
}

# ============================================================================
# FIX PLAN COMPLETION TESTS
# ============================================================================

@test "check_fix_plan_completion returns failure when no file" {
    rm -f "$FIX_PLAN_FILE"
    
    run check_fix_plan_completion
    
    assert_failure
}

@test "check_fix_plan_completion returns failure with unchecked items" {
    cat > "$FIX_PLAN_FILE" << 'EOF'
# Fix Plan
- [x] Done item
- [ ] Pending item
EOF
    
    run check_fix_plan_completion
    
    assert_failure
}

@test "check_fix_plan_completion returns success when all checked" {
    cat > "$FIX_PLAN_FILE" << 'EOF'
# Fix Plan
- [x] Done item 1
- [x] Done item 2
EOF
    
    run check_fix_plan_completion
    
    assert_success
}

@test "has_remaining_fix_plan_work returns true with unchecked items" {
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [ ] Pending item
EOF
    
    run has_remaining_fix_plan_work
    
    assert_success
}

@test "has_remaining_fix_plan_work returns false when all done" {
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [x] Done item
EOF
    
    run has_remaining_fix_plan_work
    
    assert_failure
}

@test "has_remaining_fix_plan_work returns false when no file" {
    rm -f "$FIX_PLAN_FILE"
    
    run has_remaining_fix_plan_work
    
    assert_failure
}

# ============================================================================
# EXIT CONDITION TESTS
# ============================================================================

@test "should_exit_gracefully returns 1 when work remains" {
    init_exit_signals
    init_backlog "test"
    add_backlog_item "Task" "feature" 1 5
    
    run should_exit_gracefully
    
    assert_failure
}

@test "should_exit_gracefully exits on backlog complete" {
    init_exit_signals
    init_backlog "test"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    result=$(should_exit_gracefully)
    
    assert_equal "$result" "backlog_complete"
}

@test "should_exit_gracefully exits on fix plan complete" {
    init_exit_signals
    init_backlog "test"
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [x] Done
EOF
    
    result=$(should_exit_gracefully)
    
    assert_equal "$result" "fix_plan_complete"
}

@test "should_exit_gracefully exits after multiple done signals" {
    init_exit_signals
    init_backlog "test"
    
    for i in {1..3}; do
        record_done_signal $i "test"
    done
    
    result=$(should_exit_gracefully)
    
    assert_equal "$result" "done_signals"
}

@test "should_exit_gracefully exits after multiple idle loops" {
    init_exit_signals
    init_backlog "test"
    
    for i in {1..5}; do
        record_idle_loop $i "test"
    done
    
    result=$(should_exit_gracefully)
    
    assert_equal "$result" "idle_loops"
}

@test "should_exit_gracefully ignores soft signals when work remains in fix plan" {
    init_exit_signals
    init_backlog "test"
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [ ] Pending work
EOF
    
    for i in {1..5}; do
        record_idle_loop $i "test"
    done
    
    run should_exit_gracefully
    
    assert_failure
}

# ============================================================================
# PROJECT COMPLETE TESTS
# ============================================================================

@test "is_project_complete returns false without backlog" {
    rm -f "$BACKLOG_FILE"
    
    run is_project_complete
    
    assert_failure
}

@test "is_project_complete returns false with pending items" {
    init_backlog "test"
    add_backlog_item "Task" "feature" 1 5
    
    run is_project_complete
    
    assert_failure
}

@test "is_project_complete returns true when all done" {
    init_backlog "test"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    run is_project_complete
    
    assert_success
}

@test "is_project_complete fails with fix plan work remaining" {
    init_backlog "test"
    add_backlog_item "Task" "feature" 1 5
    update_item_status "TASK-001" "done"
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [ ] Pending
EOF
    
    run is_project_complete
    
    assert_failure
}
