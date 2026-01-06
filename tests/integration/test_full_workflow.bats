#!/usr/bin/env bats
# Integration Tests: Full Workflow
# End-to-end tests simulating complete project lifecycle

# Load test helpers
load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-integration-full.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export BACKLOG_FILE="backlog.json"
    export CB_STATE_FILE=".sprinty/.circuit_breaker_state"
    export CB_HISTORY_FILE=".sprinty/.circuit_breaker_history"
    export EXIT_SIGNALS_FILE=".sprinty/.exit_signals"
    export METRICS_FILE=".sprinty/metrics.json"
    export VELOCITY_HISTORY_FILE=".sprinty/velocity_history.json"
    export RATE_LIMIT_DIR=".sprinty"
    export CALL_COUNT_FILE=".sprinty/.call_count"
    export TIMESTAMP_FILE=".sprinty/.last_reset"
    export RATE_LIMIT_STATE_FILE=".sprinty/.rate_limit_state"
    export FIX_PLAN_FILE="@fix_plan.md"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    export AGENT_OUTPUT_DIR="logs/agent_output"
    export PROMPTS_DIR="prompts"
    
    export CB_NO_PROGRESS_THRESHOLD=3
    export MAX_CONSECUTIVE_IDLE_LOOPS=5
    export MAX_CALLS_PER_HOUR=100
    
    mkdir -p .sprinty logs/agent_output sprints reviews prompts
    
    # Create mock prompt files
    echo "# Developer Agent" > prompts/developer.md
    echo "# Product Owner Agent" > prompts/product_owner.md
    echo "# QA Agent" > prompts/qa.md
    
    # Source all modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
    source "$PROJECT_ROOT/lib/done_detector.sh"
    source "$PROJECT_ROOT/lib/metrics_collector.sh"
    source "$PROJECT_ROOT/lib/rate_limiter.sh"
    source "$PROJECT_ROOT/lib/agent_adapter.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# COMPLETE PROJECT LIFECYCLE
# ============================================================================

@test "integration: full project lifecycle from init to completion" {
    # ========================================
    # PHASE 1: Project Initialization
    # ========================================
    
    # Initialize all components
    init_sprint_state
    init_backlog "full-lifecycle-project"
    init_circuit_breaker
    init_exit_signals
    init_velocity_history
    init_rate_limiter
    
    # Verify initialization
    assert_file_exists "$SPRINT_STATE_FILE"
    assert_file_exists "$BACKLOG_FILE"
    assert_file_exists "$CB_STATE_FILE"
    assert_file_exists "$EXIT_SIGNALS_FILE"
    
    # Create backlog items (Product Owner work)
    add_backlog_item "User Authentication" "feature" 1 8
    add_backlog_item "Dashboard UI" "feature" 2 5
    add_backlog_item "API Endpoints" "feature" 1 8
    add_backlog_item "Database Schema" "infra" 1 3
    add_backlog_item "Unit Tests" "chore" 2 5
    
    local total_items=$(jq '.items | length' "$BACKLOG_FILE")
    assert_equal "$total_items" "5"
    
    # Verify initialization phase complete
    run is_phase_complete "initialization"
    assert_success
    
    # ========================================
    # PHASE 2: Sprint 1 - Core Features
    # ========================================
    
    local sprint=$(start_sprint)
    assert_equal "$sprint" "1"
    
    # Plan sprint (assign high priority items)
    assign_to_sprint "TASK-001" 1  # Auth
    assign_to_sprint "TASK-003" 1  # API
    assign_to_sprint "TASK-004" 1  # DB
    
    # Create sprint plan
    mkdir -p "$SPRINTS_DIR/sprint_1"
    cat > "$SPRINTS_DIR/sprint_1/plan.md" << 'EOF'
# Sprint 1 Plan
## Goals
- Implement core authentication
- Set up API endpoints
- Create database schema
EOF
    
    run is_phase_complete "planning"
    assert_success
    
    # Implementation phase
    set_current_phase "implementation"
    
    # Simulate implementation with progress tracking
    record_loop_result 1 5 "false" 1000  # Progress made
    update_item_status "TASK-004" "in_progress"
    update_item_status "TASK-004" "implemented"
    
    record_loop_result 2 8 "false" 1000
    update_item_status "TASK-003" "in_progress"
    update_item_status "TASK-003" "implemented"
    
    record_loop_result 3 10 "false" 1000
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    # Circuit breaker should stay closed
    local cb_state=$(get_circuit_state)
    assert_equal "$cb_state" "CLOSED"
    
    run is_phase_complete "implementation"
    assert_success
    
    # QA phase
    set_current_phase "qa"
    
    # One task fails QA
    update_item_status "TASK-004" "qa_passed"
    update_item_status "TASK-003" "qa_passed"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Missing password validation"
    
    run has_tasks_to_rework
    assert_success
    
    # Rework cycle
    increment_rework
    set_current_phase "implementation"
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    set_current_phase "qa"
    update_item_status "TASK-001" "qa_passed"
    
    run is_phase_complete "qa"
    assert_success
    
    # Complete tasks
    update_item_status "TASK-001" "done"
    update_item_status "TASK-003" "done"
    update_item_status "TASK-004" "done"
    
    # Review phase
    set_current_phase "review"
    cat > "$REVIEWS_DIR/sprint_1_review.md" << 'EOF'
# Sprint 1 Review
## Completed
- User authentication with validation
- API endpoints
- Database schema
## Notes
- One rework cycle for auth validation
EOF
    
    run is_phase_complete "review"
    assert_success
    
    # Record velocity and end sprint
    record_sprint_velocity 1 19 19  # 8 + 8 + 3 points
    end_sprint "completed"
    
    # ========================================
    # PHASE 3: Sprint 2 - Remaining Features
    # ========================================
    
    reset_circuit_breaker "New sprint"
    
    sprint=$(start_sprint)
    assert_equal "$sprint" "2"
    
    assign_to_sprint "TASK-002" 2  # Dashboard
    assign_to_sprint "TASK-005" 2  # Tests
    
    mkdir -p "$SPRINTS_DIR/sprint_2"
    echo "# Sprint 2 Plan" > "$SPRINTS_DIR/sprint_2/plan.md"
    
    set_current_phase "implementation"
    update_item_status "TASK-002" "done"
    update_item_status "TASK-005" "done"
    
    echo "# Sprint 2 Review" > "$REVIEWS_DIR/sprint_2_review.md"
    record_sprint_velocity 2 10 10  # 5 + 5 points
    end_sprint "completed"
    
    # ========================================
    # PHASE 4: Project Completion
    # ========================================
    
    # Verify project complete
    run check_project_completion
    assert_success
    
    # Done detector should recognize completion
    result=$(should_exit_gracefully)
    assert_equal "$result" "backlog_complete"
    
    # Final metrics
    local metrics=$(get_project_metrics)
    local completion=$(echo "$metrics" | jq '.completion_percentage')
    assert_equal "$completion" "100"
    
    local velocity=$(calculate_velocity)
    local avg=$(echo "$velocity" | jq '.average_velocity')
    # (19 + 10) / 2 = 14.5, floors to 14
    assert_equal "$avg" "14"
    
    # Sprint history
    local history=$(jq '.sprints_history | length' "$SPRINT_STATE_FILE")
    assert_equal "$history" "2"
}

@test "integration: project with circuit breaker intervention" {
    init_sprint_state
    init_backlog "cb-intervention-test"
    init_circuit_breaker
    init_exit_signals
    
    add_backlog_item "Complex Feature" "feature" 1 13
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    mkdir -p "$SPRINTS_DIR/sprint_1"
    echo "# Plan" > "$SPRINTS_DIR/sprint_1/plan.md"
    
    set_current_phase "implementation"
    
    # Simulate getting stuck (no progress)
    record_loop_result 1 0 "false" 1000
    record_loop_result 2 0 "false" 1000
    record_loop_result 3 0 "false" 1000 || true
    
    # Circuit breaker should open
    local cb_state=$(get_circuit_state)
    assert_equal "$cb_state" "OPEN"
    
    run can_execute
    assert_failure
    
    # Manual intervention: reset and fix the issue
    reset_circuit_breaker "Fixed blocking issue"
    
    # Now progress can continue
    run can_execute
    assert_success
    
    record_loop_result 4 10 "false" 1000
    update_item_status "TASK-001" "done"
    
    run check_project_completion
    assert_success
}

@test "integration: rate limiting affects loop execution" {
    init_sprint_state
    init_backlog "rate-limit-test"
    init_rate_limiter
    
    add_backlog_item "Task" "feature" 1 5
    start_sprint
    
    # Track API calls
    for i in {1..10}; do
        increment_call_counter > /dev/null
    done
    
    local count=$(get_call_count)
    assert_equal "$count" "10"
    
    local remaining=$(get_remaining_calls)
    assert_equal "$remaining" "90"
    
    run can_make_call
    assert_success
}

@test "integration: all components initialize correctly together" {
    # Initialize all components
    init_sprint_state
    init_backlog "init-test"
    init_circuit_breaker
    init_exit_signals
    init_velocity_history
    init_rate_limiter
    init_cursor_project_config "."
    
    # All state files should exist and be valid JSON
    assert_file_exists "$SPRINT_STATE_FILE"
    assert_valid_json "$SPRINT_STATE_FILE"
    
    assert_file_exists "$BACKLOG_FILE"
    assert_valid_json "$BACKLOG_FILE"
    
    assert_file_exists "$CB_STATE_FILE"
    assert_valid_json "$CB_STATE_FILE"
    
    assert_file_exists "$EXIT_SIGNALS_FILE"
    assert_valid_json "$EXIT_SIGNALS_FILE"
    
    assert_file_exists "$VELOCITY_HISTORY_FILE"
    assert_valid_json "$VELOCITY_HISTORY_FILE"
    
    assert_file_exists "$RATE_LIMIT_STATE_FILE"
    assert_valid_json "$RATE_LIMIT_STATE_FILE"
    
    assert_file_exists ".cursor/cli.json"
    assert_valid_json ".cursor/cli.json"
}

@test "integration: state persists across module reloads" {
    init_sprint_state
    init_backlog "persist-test"
    init_circuit_breaker
    
    add_backlog_item "Task" "feature" 1 5
    start_sprint
    set_current_phase "implementation"
    record_loop_result 1 5 "false" 1000
    
    # Store current state
    local sprint=$(get_current_sprint)
    local phase=$(get_current_phase)
    local cb_state=$(get_circuit_state)
    
    # Re-source all modules (simulating restart)
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/circuit_breaker.sh"
    
    # State should persist
    local new_sprint=$(get_current_sprint)
    local new_phase=$(get_current_phase)
    local new_cb_state=$(get_circuit_state)
    
    assert_equal "$sprint" "$new_sprint"
    assert_equal "$phase" "$new_phase"
    assert_equal "$cb_state" "$new_cb_state"
}

@test "integration: prompt generation uses correct context" {
    init_sprint_state
    init_backlog "prompt-context-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 3
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    set_current_phase "implementation"
    
    # Generate context
    local context=$(generate_context_json)
    
    # Verify context includes sprint info
    local ctx_sprint=$(echo "$context" | jq '.sprint_id')
    assert_equal "$ctx_sprint" "1"
    
    local ctx_phase=$(echo "$context" | jq -r '.phase')
    assert_equal "$ctx_phase" "implementation"
    
    # Generate prompt
    local prompt_file=$(generate_prompt "developer" "implementation" 1 "$context")
    
    assert_file_exists "$prompt_file"
    grep -q "Sprint.*: 1" "$prompt_file"
    grep -q "Phase.*: implementation" "$prompt_file"
    grep -q "Developer Agent" "$prompt_file"
}

@test "integration: metrics reflect real project state" {
    init_sprint_state
    init_velocity_history
    init_backlog "metrics-state-test"
    
    add_backlog_item "Task 1" "feature" 1 5
    add_backlog_item "Task 2" "feature" 1 5
    
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # Initial state
    local burndown=$(calculate_burndown 1)
    local done=$(echo "$burndown" | jq '.points.done')
    assert_equal "$done" "0"
    
    # Progress
    update_item_status "TASK-001" "done"
    
    burndown=$(calculate_burndown 1)
    done=$(echo "$burndown" | jq '.points.done')
    assert_equal "$done" "5"
    
    local pct=$(echo "$burndown" | jq '.completion_percentage')
    assert_equal "$pct" "50"
    
    # Complete
    update_item_status "TASK-002" "done"
    
    local project=$(get_project_metrics)
    local completion=$(echo "$project" | jq '.completion_percentage')
    assert_equal "$completion" "100"
}

@test "integration: error recovery across components" {
    init_sprint_state
    init_backlog "error-recovery-test"
    init_circuit_breaker
    init_exit_signals
    
    add_backlog_item "Task" "feature" 1 5
    start_sprint
    
    # Simulate error scenario
    record_loop_result 1 1 "true" 1000
    record_loop_result 2 1 "true" 1000
    record_idle_loop 3 "error"
    
    # Check signals recorded
    local idle=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$idle" "1"
    
    # Reset for recovery
    reset_circuit_breaker "Error resolved"
    reset_exit_signals
    
    # Should be able to continue
    run can_execute
    assert_success
    
    local cb_state=$(get_circuit_state)
    assert_equal "$cb_state" "CLOSED"
    
    idle=$(jq '.idle_loops | length' "$EXIT_SIGNALS_FILE")
    assert_equal "$idle" "0"
}
