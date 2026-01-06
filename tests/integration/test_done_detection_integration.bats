#!/usr/bin/env bats
# Integration Tests: Done Detection
# Tests done detector integration with backlog, sprint, and exit signals

# Load test helpers
load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-integration-done.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export EXIT_SIGNALS_FILE=".sprinty/.exit_signals"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export BACKLOG_FILE="backlog.json"
    export FIX_PLAN_FILE="@fix_plan.md"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    export MAX_CONSECUTIVE_IDLE_LOOPS=5
    export MAX_CONSECUTIVE_DONE_SIGNALS=3
    export MAX_CONSECUTIVE_TEST_LOOPS=5
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source all modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/done_detector.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# DONE DETECTION + BACKLOG INTEGRATION
# ============================================================================

@test "integration: done detector recognizes completed backlog" {
    init_exit_signals
    init_sprint_state
    init_backlog "done-backlog-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    # Not complete yet
    run should_exit_gracefully
    assert_failure
    
    # Complete all tasks
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    # Now should exit
    result=$(should_exit_gracefully)
    assert_equal "$result" "backlog_complete"
}

@test "integration: done detector respects fix plan over backlog completion" {
    init_exit_signals
    init_sprint_state
    init_backlog "fix-plan-priority-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    # Create fix plan with unchecked items
    cat > "$FIX_PLAN_FILE" << 'EOF'
# Fix Plan
- [x] Done item
- [ ] Pending item
EOF
    
    # Backlog complete but fix plan has work
    run check_backlog_completion
    assert_success
    
    run has_remaining_fix_plan_work
    assert_success
    
    # Should NOT exit because fix plan has work
    run should_exit_gracefully
    assert_failure
}

@test "integration: done detector exits when both backlog and fix plan complete" {
    init_exit_signals
    init_sprint_state
    init_backlog "both-complete-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    # Create completed fix plan
    cat > "$FIX_PLAN_FILE" << 'EOF'
# Fix Plan
- [x] Done item 1
- [x] Done item 2
EOF
    
    result=$(should_exit_gracefully)
    # Should exit on either backlog_complete or fix_plan_complete
    [[ "$result" == "backlog_complete" || "$result" == "fix_plan_complete" ]]
}

@test "integration: done detector tracks signals during sprint execution" {
    init_exit_signals
    init_sprint_state
    init_backlog "signal-track-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Simulate agent output analysis
    cat > "output1.log" << 'EOF'
Implementing feature...
---SPRINTY_STATUS---
PHASE_COMPLETE: true
---END_SPRINTY_STATUS---
EOF
    
    analyze_output_for_completion "output1.log" 1
    
    local indicators=$(jq '.completion_indicators | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$indicators" "1"
}

@test "integration: done detector accumulates multiple signal types" {
    init_exit_signals
    init_sprint_state
    init_backlog "multi-signal-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    
    # Record different signal types
    record_idle_loop 1 "no_changes"
    record_idle_loop 2 "no_changes"
    record_done_signal 3 "agent_response"
    record_completion_indicator 4 "phase_complete"
    record_test_only_loop 5
    
    # All should be tracked
    local idle=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    local done=$(jq '.done_signals | length' "$EXIT_SIGNALS_FILE")
    local completion=$(jq '.completion_indicators | length' "$EXIT_SIGNALS_FILE")
    local test_only=$(jq '.test_only_loops | length' "$EXIT_SIGNALS_FILE")
    
    assert_equal "$idle" "2"
    assert_equal "$done" "1"
    assert_equal "$completion" "1"
    assert_equal "$test_only" "1"
}

# ============================================================================
# DONE DETECTION + SPRINT INTEGRATION
# ============================================================================

@test "integration: is_project_complete checks all criteria" {
    init_exit_signals
    init_sprint_state
    init_backlog "project-complete-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "bug" 1 3  # P1 bug
    
    # Not complete with pending items
    run is_project_complete
    assert_failure
    
    # Complete tasks
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    # Now complete
    run is_project_complete
    assert_success
}

@test "integration: cancelled tasks don't block project completion" {
    init_exit_signals
    init_sprint_state
    init_backlog "cancelled-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    add_backlog_item "Task 3" "feature" 1 2
    
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "cancelled"
    update_item_status "TASK-003" "done"
    
    run is_project_complete
    assert_success
    
    result=$(should_exit_gracefully)
    assert_equal "$result" "backlog_complete"
}

@test "integration: P1 bugs block project completion" {
    init_exit_signals
    init_sprint_state
    init_backlog "p1-bug-test"
    
    add_backlog_item "Feature" "feature" 1 5
    add_backlog_item "Critical Bug" "bug" 1 3  # P1 bug
    
    update_item_status "TASK-001" "done"
    # Bug still open
    
    run is_project_complete
    assert_failure
    
    run should_exit_gracefully
    assert_failure
}

# ============================================================================
# SIGNAL THRESHOLDS INTEGRATION
# ============================================================================

@test "integration: idle loop threshold triggers exit" {
    init_exit_signals
    init_sprint_state
    init_backlog "idle-threshold-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    
    # Record idle loops below threshold
    for i in {1..4}; do
        record_idle_loop $i "no_changes"
    done
    
    run should_exit_gracefully
    assert_failure
    
    # One more to hit threshold
    record_idle_loop 5 "no_changes"
    
    result=$(should_exit_gracefully)
    assert_equal "$result" "idle_loops"
}

@test "integration: done signal threshold triggers exit" {
    init_exit_signals
    init_sprint_state
    init_backlog "done-signal-threshold-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    
    # Record done signals below threshold
    record_done_signal 1 "agent"
    record_done_signal 2 "agent"
    
    run should_exit_gracefully
    assert_failure
    
    # One more to hit threshold
    record_done_signal 3 "agent"
    
    result=$(should_exit_gracefully)
    assert_equal "$result" "done_signals"
}

@test "integration: soft signals ignored when fix plan has work" {
    init_exit_signals
    init_sprint_state
    init_backlog "soft-signal-ignore-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    
    # Create fix plan with pending work
    cat > "$FIX_PLAN_FILE" << 'EOF'
- [ ] Pending work
EOF
    
    # Record many idle loops
    for i in {1..10}; do
        record_idle_loop $i "no_changes"
    done
    
    # Should NOT exit because fix plan has work
    run should_exit_gracefully
    assert_failure
}

# ============================================================================
# OUTPUT ANALYSIS INTEGRATION
# ============================================================================

@test "integration: analyze_output_for_completion detects all patterns" {
    init_exit_signals
    
    # Create output with multiple patterns
    cat > "multi_pattern.log" << 'EOF'
Working on implementation...

---SPRINTY_STATUS---
PROJECT_DONE: true
PHASE_COMPLETE: true
TASKS_REMAINING: 0
---END_SPRINTY_STATUS---

🎉 Project complete! All tasks done.
EOF
    
    result=$(analyze_output_for_completion "multi_pattern.log" 1)
    
    # Should detect multiple signals
    [[ $result -ge 3 ]]
    
    # Check signals were recorded
    local done_count=$(jq '.done_signals | length' "$EXIT_SIGNALS_FILE")
    local indicator_count=$(jq '.completion_indicators | length' "$EXIT_SIGNALS_FILE")
    
    [[ $done_count -ge 1 ]]
    [[ $indicator_count -ge 1 ]]
}

@test "integration: reset signals allows fresh detection" {
    init_exit_signals
    
    # Record signals
    for i in {1..5}; do
        record_idle_loop $i "test"
    done
    
    result=$(should_exit_gracefully)
    assert_equal "$result" "idle_loops"
    
    # Reset
    reset_exit_signals
    
    # Should not exit anymore
    run should_exit_gracefully
    assert_failure
    
    # Verify signals cleared
    local idle_count=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$idle_count" "0"
}

@test "integration: signal persistence across function calls" {
    init_exit_signals
    
    # Record signals
    record_idle_loop 1 "test"
    record_done_signal 2 "test"
    record_completion_indicator 3 "test"
    
    # Re-source module (simulating new call)
    source "$PROJECT_ROOT/lib/done_detector.sh"
    
    # Signals should persist
    local idle=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    local done=$(jq '.done_signals | length' "$EXIT_SIGNALS_FILE")
    local indicators=$(jq '.completion_indicators | length' "$EXIT_SIGNALS_FILE")
    
    assert_equal "$idle" "1"
    assert_equal "$done" "1"
    assert_equal "$indicators" "1"
}
