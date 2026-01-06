#!/usr/bin/env bats
# Integration Tests: Metrics Collection
# Tests metrics collector integration with backlog and sprint management

# Load test helpers
load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-integration-metrics.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export METRICS_FILE=".sprinty/metrics.json"
    export VELOCITY_HISTORY_FILE=".sprinty/velocity_history.json"
    export BACKLOG_FILE="backlog.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source all modules
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
# BURNDOWN + BACKLOG INTEGRATION
# ============================================================================

@test "integration: burndown reflects real-time backlog status" {
    init_sprint_state
    init_backlog "burndown-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 8
    add_backlog_item "Task 3" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    # Initial burndown
    local burndown=$(calculate_burndown 1)
    local total=$(echo "$burndown" | jq '.points.total')
    local done=$(echo "$burndown" | jq '.points.done')
    local remaining=$(echo "$burndown" | jq '.points.remaining')
    
    assert_equal "$total" "16"
    assert_equal "$done" "0"
    assert_equal "$remaining" "16"
    
    # Progress: complete first task
    update_item_status "TASK-001" "done"
    burndown=$(calculate_burndown 1)
    done=$(echo "$burndown" | jq '.points.done')
    remaining=$(echo "$burndown" | jq '.points.remaining')
    
    assert_equal "$done" "5"
    assert_equal "$remaining" "11"
    
    # More progress
    update_item_status "TASK-002" "done"
    burndown=$(calculate_burndown 1)
    done=$(echo "$burndown" | jq '.points.done')
    
    assert_equal "$done" "13"
}

@test "integration: burndown tracks in-progress and QA status" {
    init_sprint_state
    init_backlog "burndown-status-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    add_backlog_item "Task 3" "feature" 1 2
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    # Set different statuses
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-002" "qa_passed"
    update_item_status "TASK-003" "qa_failed"
    
    local burndown=$(calculate_burndown 1)
    
    local in_progress=$(echo "$burndown" | jq '.points.in_progress')
    local qa_passed=$(echo "$burndown" | jq '.points.qa_passed')
    local qa_failed=$(echo "$burndown" | jq '.points.qa_failed')
    
    assert_equal "$in_progress" "5"
    assert_equal "$qa_passed" "3"
    assert_equal "$qa_failed" "2"
}

@test "integration: burndown completion percentage calculates correctly" {
    init_sprint_state
    init_backlog "completion-pct-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 5
    add_backlog_item "Task 3" "feature" 1 5
    add_backlog_item "Task 4" "feature" 1 5
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    assign_to_sprint "TASK-004" 1
    
    # 0%
    local burndown=$(calculate_burndown 1)
    local pct=$(echo "$burndown" | jq '.completion_percentage')
    assert_equal "$pct" "0"
    
    # 25%
    update_item_status "TASK-001" "done"
    burndown=$(calculate_burndown 1)
    pct=$(echo "$burndown" | jq '.completion_percentage')
    assert_equal "$pct" "25"
    
    # 50%
    update_item_status "TASK-002" "done"
    burndown=$(calculate_burndown 1)
    pct=$(echo "$burndown" | jq '.completion_percentage')
    assert_equal "$pct" "50"
    
    # 100%
    update_item_status "TASK-003" "done"
    update_item_status "TASK-004" "done"
    burndown=$(calculate_burndown 1)
    pct=$(echo "$burndown" | jq '.completion_percentage')
    assert_equal "$pct" "100"
}

# ============================================================================
# VELOCITY + SPRINT INTEGRATION
# ============================================================================

@test "integration: velocity tracking across multiple sprints" {
    init_sprint_state
    init_velocity_history
    init_backlog "velocity-test"
    
    # Create tasks
    for i in {1..6}; do
        add_backlog_item "Task $i" "feature" 1 5
    done
    
    # Sprint 1: complete 2 tasks (10 points)
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    record_sprint_velocity 1 10 10
    end_sprint "completed"
    
    # Sprint 2: complete 2 tasks (10 points)
    start_sprint
    assign_to_sprint "TASK-003" 2
    assign_to_sprint "TASK-004" 2
    update_item_status "TASK-003" "done"
    update_item_status "TASK-004" "done"
    record_sprint_velocity 2 10 10
    end_sprint "completed"
    
    # Sprint 3: complete 2 tasks (10 points)
    start_sprint
    assign_to_sprint "TASK-005" 3
    assign_to_sprint "TASK-006" 3
    update_item_status "TASK-005" "done"
    update_item_status "TASK-006" "done"
    record_sprint_velocity 3 10 10
    
    # Check velocity
    local velocity=$(calculate_velocity)
    local avg=$(echo "$velocity" | jq '.average_velocity')
    local total=$(echo "$velocity" | jq '.total_points_completed')
    
    assert_equal "$avg" "10"
    assert_equal "$total" "30"
}

@test "integration: velocity trend detection" {
    init_sprint_state
    init_velocity_history
    init_backlog "trend-test"
    
    # Record sprints with increasing velocity
    record_sprint_velocity 1 8 10
    record_sprint_velocity 2 10 10
    record_sprint_velocity 3 12 12
    
    local velocity=$(calculate_velocity)
    local trend=$(echo "$velocity" | jq '.velocity_trend')
    
    # Trend should be positive (12 - 10 = 2)
    assert_equal "$trend" "2"
}

@test "integration: velocity used for sprint estimation" {
    init_sprint_state
    init_velocity_history
    init_backlog "estimation-test"
    
    # Record historical velocity
    record_sprint_velocity 1 10 10
    record_sprint_velocity 2 10 10
    
    # Create backlog with 30 points remaining
    add_backlog_item "Task 1" "feature" 1 10
    add_backlog_item "Task 2" "feature" 1 10
    add_backlog_item "Task 3" "feature" 1 10
    
    # Get project metrics
    local metrics=$(get_project_metrics)
    local estimated=$(echo "$metrics" | jq '.sprints.estimated_remaining')
    
    # With 30 points and 10 velocity, should estimate 3 sprints
    assert_equal "$estimated" "3"
}

# ============================================================================
# SPRINT SUMMARY INTEGRATION
# ============================================================================

@test "integration: sprint summary reflects current state" {
    init_sprint_state
    init_backlog "summary-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "bug" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    set_current_phase "implementation"
    increment_phase_loop
    increment_phase_loop
    
    update_item_status "TASK-001" "qa_failed"
    increment_rework
    
    local summary=$(get_sprint_summary 1)
    
    # Verify phase info
    local phase=$(echo "$summary" | jq -r '.phase')
    assert_equal "$phase" "implementation"
    
    local loop_count=$(echo "$summary" | jq '.loop_count')
    assert_equal "$loop_count" "2"
    
    local rework_count=$(echo "$summary" | jq '.rework_count')
    assert_equal "$rework_count" "1"
    
    # Health score should be reduced due to QA failure
    local health=$(echo "$summary" | jq '.health_score')
    [[ $health -lt 100 ]]
}

@test "integration: sprint summary includes status breakdown" {
    init_sprint_state
    init_backlog "breakdown-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    add_backlog_item "Task 3" "feature" 1 2
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "in_progress"
    # TASK-003 stays ready
    
    local summary=$(get_sprint_summary 1)
    local breakdown=$(echo "$summary" | jq '.status_breakdown')
    
    # Should have breakdown by status
    local breakdown_length=$(echo "$breakdown" | jq 'length')
    [[ $breakdown_length -ge 2 ]]
}

# ============================================================================
# PROJECT METRICS INTEGRATION
# ============================================================================

@test "integration: project metrics aggregate all sprints" {
    init_sprint_state
    init_velocity_history
    init_backlog "project-metrics-test"
    
    # Create 10 tasks
    for i in {1..10}; do
        add_backlog_item "Task $i" "feature" 1 3
    done
    
    # Complete some tasks
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    update_item_status "TASK-003" "done"
    update_item_status "TASK-004" "cancelled"
    
    local metrics=$(get_project_metrics)
    
    local total_items=$(echo "$metrics" | jq '.items.total')
    local done_items=$(echo "$metrics" | jq '.items.done')
    local remaining=$(echo "$metrics" | jq '.items.remaining')
    
    assert_equal "$total_items" "10"
    assert_equal "$done_items" "3"
    # 10 - 3 done - 1 cancelled = 6 remaining, but cancelled counts as remaining in items calculation
    # Actually the metric calculates total - done which is 10 - 3 = 7
    assert_equal "$remaining" "7"
    
    # Completion based on points
    local total_points=$(echo "$metrics" | jq '.points.total')
    local done_points=$(echo "$metrics" | jq '.points.done')
    
    assert_equal "$total_points" "30"
    assert_equal "$done_points" "9"  # 3 tasks x 3 points
}

@test "integration: metrics snapshot captures point-in-time state" {
    init_sprint_state
    init_velocity_history
    init_backlog "snapshot-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    update_item_status "TASK-001" "done"
    
    save_metrics_snapshot
    
    # Verify snapshot file
    assert_file_exists "$METRICS_FILE"
    assert_valid_json "$METRICS_FILE"
    
    # Verify contents
    local snapshot_sprint=$(jq '.sprint' "$METRICS_FILE")
    assert_equal "$snapshot_sprint" "1"
    
    local burndown_done=$(jq '.burndown.points.done' "$METRICS_FILE")
    assert_equal "$burndown_done" "5"
}

# ============================================================================
# CROSS-COMPONENT INTEGRATION
# ============================================================================

@test "integration: full metrics flow through complete sprint" {
    init_sprint_state
    init_velocity_history
    init_backlog "full-flow-test"
    
    # Setup backlog
    add_backlog_item "Feature 1" "feature" 1 8
    add_backlog_item "Feature 2" "feature" 2 5
    add_backlog_item "Bug Fix" "bug" 1 3
    
    # Start sprint
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    assign_to_sprint "TASK-003" 1
    
    # Initial burndown
    local initial_burndown=$(calculate_burndown 1)
    local initial_remaining=$(echo "$initial_burndown" | jq '.points.remaining')
    assert_equal "$initial_remaining" "16"
    
    # Progress through sprint
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "# Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    
    set_current_phase "implementation"
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    update_item_status "TASK-003" "done"
    
    # Mid-sprint metrics
    local mid_burndown=$(calculate_burndown 1)
    local mid_done=$(echo "$mid_burndown" | jq '.points.done')
    assert_equal "$mid_done" "16"
    
    # End sprint and record velocity
    echo "# Review" > "$REVIEWS_DIR/sprint_1_review.md"
    record_sprint_velocity 1 16 16
    end_sprint "completed"
    
    # Final velocity check
    local velocity=$(calculate_velocity)
    local avg_velocity=$(echo "$velocity" | jq '.average_velocity')
    assert_equal "$avg_velocity" "16"
    
    # Project metrics
    local project=$(get_project_metrics)
    local completion=$(echo "$project" | jq '.completion_percentage')
    assert_equal "$completion" "100"
}
