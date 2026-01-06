#!/usr/bin/env bats
# Unit Tests for Metrics Collector Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-metrics-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export METRICS_FILE=".sprinty/metrics.json"
    export VELOCITY_HISTORY_FILE=".sprinty/velocity_history.json"
    export BACKLOG_FILE="backlog.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    mkdir -p .sprinty logs sprints reviews
    
    # Source the modules under test
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
# BURNDOWN TESTS
# ============================================================================

@test "calculate_burndown returns valid JSON" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(calculate_burndown 1)
    
    echo "$result" | jq '.' > /dev/null
}

@test "calculate_burndown includes sprint id" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(calculate_burndown 1)
    
    local sprint=$(echo "$result" | jq '.sprint')
    assert_equal "$sprint" "1"
}

@test "calculate_burndown calculates total items" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    result=$(calculate_burndown 1)
    
    local total=$(echo "$result" | jq '.items.total')
    assert_equal "$total" "2"
}

@test "calculate_burndown calculates total points" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    result=$(calculate_burndown 1)
    
    local total=$(echo "$result" | jq '.points.total')
    assert_equal "$total" "8"
}

@test "calculate_burndown calculates done items" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    
    result=$(calculate_burndown 1)
    
    local done=$(echo "$result" | jq '.items.done')
    assert_equal "$done" "1"
}

@test "calculate_burndown calculates done points" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    
    result=$(calculate_burndown 1)
    
    local done=$(echo "$result" | jq '.points.done')
    assert_equal "$done" "5"
}

@test "calculate_burndown calculates remaining points" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    
    result=$(calculate_burndown 1)
    
    local remaining=$(echo "$result" | jq '.points.remaining')
    assert_equal "$remaining" "3"
}

@test "calculate_burndown calculates completion percentage" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    update_item_status "TASK-001" "done"
    
    result=$(calculate_burndown 1)
    
    local pct=$(echo "$result" | jq '.completion_percentage')
    assert_equal "$pct" "50"
}

@test "calculate_burndown tracks in_progress items" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "in_progress"
    
    result=$(calculate_burndown 1)
    
    local in_progress=$(echo "$result" | jq '.items.in_progress')
    assert_equal "$in_progress" "1"
}

@test "calculate_burndown tracks qa_failed items" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "qa_failed"
    
    result=$(calculate_burndown 1)
    
    local failed=$(echo "$result" | jq '.items.qa_failed')
    assert_equal "$failed" "1"
}

@test "calculate_burndown fails without backlog" {
    init_sprint_state
    rm -f "$BACKLOG_FILE"
    
    run calculate_burndown 1
    
    assert_failure
}

# ============================================================================
# VELOCITY TESTS
# ============================================================================

@test "init_velocity_history creates history file" {
    init_velocity_history
    
    assert_file_exists "$VELOCITY_HISTORY_FILE"
}

@test "init_velocity_history creates valid JSON" {
    init_velocity_history
    
    assert_valid_json "$VELOCITY_HISTORY_FILE"
}

@test "init_velocity_history has empty sprints array" {
    init_velocity_history
    
    local count=$(jq '.sprints | length' "$VELOCITY_HISTORY_FILE")
    assert_equal "$count" "0"
}

@test "record_sprint_velocity adds sprint to history" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    
    local count=$(jq '.sprints | length' "$VELOCITY_HISTORY_FILE")
    assert_equal "$count" "1"
}

@test "record_sprint_velocity stores points completed" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    
    local completed=$(jq '.sprints[0].points_completed' "$VELOCITY_HISTORY_FILE")
    assert_equal "$completed" "10"
}

@test "record_sprint_velocity stores points planned" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    
    local planned=$(jq '.sprints[0].points_planned' "$VELOCITY_HISTORY_FILE")
    assert_equal "$planned" "12"
}

@test "record_sprint_velocity updates average velocity" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    record_sprint_velocity 2 14 15
    
    local avg=$(jq '.average_velocity' "$VELOCITY_HISTORY_FILE")
    assert_equal "$avg" "12"
}

@test "record_sprint_velocity updates total points completed" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    record_sprint_velocity 2 14 15
    
    local total=$(jq '.total_points_completed' "$VELOCITY_HISTORY_FILE")
    assert_equal "$total" "24"
}

@test "record_sprint_velocity updates existing sprint" {
    init_velocity_history
    
    record_sprint_velocity 1 10 12
    record_sprint_velocity 1 15 12
    
    local count=$(jq '.sprints | length' "$VELOCITY_HISTORY_FILE")
    local completed=$(jq '.sprints[0].points_completed' "$VELOCITY_HISTORY_FILE")
    
    assert_equal "$count" "1"
    assert_equal "$completed" "15"
}

@test "calculate_velocity returns valid JSON" {
    init_velocity_history
    
    result=$(calculate_velocity)
    
    echo "$result" | jq '.' > /dev/null
}

@test "calculate_velocity includes average_velocity" {
    init_velocity_history
    record_sprint_velocity 1 10 12
    record_sprint_velocity 2 14 15
    
    result=$(calculate_velocity)
    
    local avg=$(echo "$result" | jq '.average_velocity')
    assert_equal "$avg" "12"
}

@test "calculate_velocity includes recent_velocity" {
    init_velocity_history
    record_sprint_velocity 1 10 12
    record_sprint_velocity 2 14 15
    
    result=$(calculate_velocity 2)
    
    local recent=$(echo "$result" | jq '.recent_velocity')
    assert_equal "$recent" "12"
}

@test "calculate_velocity calculates velocity trend" {
    init_velocity_history
    record_sprint_velocity 1 10 12
    record_sprint_velocity 2 14 15
    
    result=$(calculate_velocity)
    
    local trend=$(echo "$result" | jq '.velocity_trend')
    assert_equal "$trend" "4"
}

@test "calculate_velocity includes sprint history" {
    init_velocity_history
    record_sprint_velocity 1 10 12
    
    result=$(calculate_velocity)
    
    local count=$(echo "$result" | jq '.sprint_history | length')
    assert_equal "$count" "1"
}

# ============================================================================
# SPRINT SUMMARY TESTS
# ============================================================================

@test "get_sprint_summary returns valid JSON" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_sprint_summary 1)
    
    echo "$result" | jq '.' > /dev/null
}

@test "get_sprint_summary includes phase info" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_sprint_summary 1)
    
    local phase=$(echo "$result" | jq -r '.phase')
    assert_equal "$phase" "planning"
}

@test "get_sprint_summary includes burndown data" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_sprint_summary 1)
    
    local has_burndown=$(echo "$result" | jq 'has("burndown")')
    assert_equal "$has_burndown" "true"
}

@test "get_sprint_summary includes health score" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_sprint_summary 1)
    
    local health=$(echo "$result" | jq '.health_score')
    [[ $health -ge 0 && $health -le 100 ]]
}

@test "get_sprint_summary health score decreases with QA failures" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    add_backlog_item "Task 1" "feature" 1 5
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "qa_failed"
    
    result=$(get_sprint_summary 1)
    
    local health=$(echo "$result" | jq '.health_score')
    [[ $health -lt 100 ]]
}

@test "get_sprint_summary includes status breakdown" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_sprint_summary 1)
    
    local has_status=$(echo "$result" | jq 'has("status_breakdown")')
    assert_equal "$has_status" "true"
}

# ============================================================================
# PROJECT METRICS TESTS
# ============================================================================

@test "get_project_metrics returns valid JSON" {
    init_sprint_state
    init_backlog "test"
    
    result=$(get_project_metrics)
    
    echo "$result" | jq '.' > /dev/null
}

@test "get_project_metrics includes total items" {
    init_sprint_state
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    result=$(get_project_metrics)
    
    local total=$(echo "$result" | jq '.items.total')
    assert_equal "$total" "2"
}

@test "get_project_metrics includes total points" {
    init_sprint_state
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    result=$(get_project_metrics)
    
    local total=$(echo "$result" | jq '.points.total')
    assert_equal "$total" "8"
}

@test "get_project_metrics calculates completion percentage" {
    init_sprint_state
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 5
    update_item_status "TASK-001" "done"
    
    result=$(get_project_metrics)
    
    local pct=$(echo "$result" | jq '.completion_percentage')
    assert_equal "$pct" "50"
}

@test "get_project_metrics includes current sprint" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    result=$(get_project_metrics)
    
    local sprint=$(echo "$result" | jq '.sprints.current')
    assert_equal "$sprint" "1"
}

@test "get_project_metrics estimates remaining sprints" {
    init_sprint_state
    init_velocity_history
    record_sprint_velocity 1 10 12
    init_backlog "test"
    add_backlog_item "Task 1" "feature" 1 20
    
    result=$(get_project_metrics)
    
    local estimated=$(echo "$result" | jq '.sprints.estimated_remaining')
    [[ $estimated -ge 1 ]]
}

@test "get_project_metrics fails without backlog" {
    init_sprint_state
    rm -f "$BACKLOG_FILE"
    
    run get_project_metrics
    
    assert_failure
}

# ============================================================================
# SAVE METRICS TESTS
# ============================================================================

@test "save_metrics_snapshot creates metrics file" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    assert_file_exists "$METRICS_FILE"
}

@test "save_metrics_snapshot creates valid JSON" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    assert_valid_json "$METRICS_FILE"
}

@test "save_metrics_snapshot includes timestamp" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    local has_ts=$(jq 'has("timestamp")' "$METRICS_FILE")
    assert_equal "$has_ts" "true"
}

@test "save_metrics_snapshot includes burndown" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    local has_burndown=$(jq 'has("burndown")' "$METRICS_FILE")
    assert_equal "$has_burndown" "true"
}

@test "save_metrics_snapshot includes velocity" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    local has_velocity=$(jq 'has("velocity")' "$METRICS_FILE")
    assert_equal "$has_velocity" "true"
}

@test "save_metrics_snapshot includes project metrics" {
    init_sprint_state
    init_backlog "test"
    start_sprint
    
    save_metrics_snapshot
    
    local has_project=$(jq 'has("project")' "$METRICS_FILE")
    assert_equal "$has_project" "true"
}
