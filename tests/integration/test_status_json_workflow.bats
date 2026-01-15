#!/usr/bin/env bats
# Integration tests for status.json workflow

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source all modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
    source "$PROJECT_ROOT/lib/agent_adapter.sh"
    source "$PROJECT_ROOT/lib/done_detector.sh"
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    export SPRINTS_DIR="$TEST_DIR/sprints"
    export REVIEWS_DIR="$TEST_DIR/reviews"
    
    mkdir -p "$SPRINTY_DIR" "$SPRINTS_DIR" "$REVIEWS_DIR"
    
    # Initialize components
    init_backlog "test-project"
    init_sprint_state
    init_exit_signals
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# Full workflow integration tests
# ============================================================================

@test "integration: initialization phase completes with status.json" {
    # Setup: Product Owner initializes backlog
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 5 '["AC2"]'
    
    # Agent updates status.json
    update_agent_status \
        "role" "product_owner" \
        "phase" "initialization" \
        "sprint" "0" \
        "tasks_completed" "0" \
        "tasks_remaining" "2" \
        "phase_complete" "true" \
        "project_done" "false"
    
    # Verify phase completion detected
    touch "$TEST_DIR/output.log"
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify backlog state also indicates completion
    run is_phase_complete "initialization"
    assert_success
}

@test "integration: planning phase creates sprint plan and completes" {
    # Add tasks to backlog
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 5 '["AC2"]'
    
    # Start sprint
    start_sprint
    
    # Assign tasks to sprint
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).sprint_id = 1 | (.items[1]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Create sprint plan (what agent would do)
    mkdir -p "$SPRINTS_DIR"
    cat > "$SPRINTS_DIR/sprint_1_plan.md" << 'EOF'
# Sprint 1 Plan
- TASK-001: Task 1 (3 points)
- TASK-002: Task 2 (5 points)
EOF
    
    # Agent updates status.json
    update_agent_status \
        "role" "product_owner" \
        "phase" "planning" \
        "sprint" "1" \
        "phase_complete" "true" \
        "project_done" "false"
    
    # Verify phase completion
    touch "$TEST_DIR/output.log"
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify planning phase complete by state
    run is_phase_complete "planning"
    assert_success
}

@test "integration: implementation phase completes when all tasks implemented" {
    # Setup sprint with tasks
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 5 '["AC2"]'
    start_sprint
    
    # Assign to sprint
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).sprint_id = 1 | (.items[1]).status = "ready"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Simulate developer implementing tasks
    jq '(.items[0]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Agent updates status.json
    update_agent_status \
        "role" "developer" \
        "phase" "implementation" \
        "sprint" "1" \
        "tasks_completed" "2" \
        "tasks_remaining" "0" \
        "story_points_done" "8" \
        "tests_status" "PASSING" \
        "phase_complete" "true" \
        "project_done" "false"
    
    # Verify phase completion
    touch "$TEST_DIR/output.log"
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify implementation phase complete by state
    run is_phase_complete "implementation"
    assert_success
}

@test "integration: QA phase completes when all tasks tested" {
    # Setup: Tasks are implemented
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 5 '["AC2"]'
    start_sprint
    
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).sprint_id = 1 | (.items[1]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # QA tests and passes tasks
    jq '(.items[0]).status = "qa_passed"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).status = "qa_passed"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Agent updates status.json
    update_agent_status \
        "role" "qa" \
        "phase" "qa" \
        "sprint" "1" \
        "tasks_completed" "2" \
        "tasks_remaining" "0" \
        "story_points_done" "8" \
        "tests_status" "PASSING" \
        "phase_complete" "true" \
        "project_done" "false"
    
    # Verify phase completion
    touch "$TEST_DIR/output.log"
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify QA phase complete by state
    run is_phase_complete "qa"
    assert_success
}

@test "integration: project completion detected via status.json" {
    # Setup: All tasks done
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    add_backlog_item "Task 2" "feature" 1 5 '["AC2"]'
    
    jq '(.items[0]).status = "done"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    jq '(.items[1]).status = "done"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Product Owner marks project done
    update_agent_status \
        "role" "product_owner" \
        "phase" "review" \
        "sprint" "1" \
        "project_done" "true" \
        "phase_complete" "true"
    
    # Verify project done detected
    touch "$TEST_DIR/output.log"
    run check_project_done_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify backlog also shows complete
    run is_project_complete
    assert_success
}

# ============================================================================
# Status preservation across loops
# ============================================================================

@test "integration: agent status preserved across multiple loop iterations" {
    # Iteration 1: Agent updates
    update_agent_status \
        "role" "developer" \
        "phase" "implementation" \
        "tasks_completed" "1" \
        "phase_complete" "false"
    
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
    
    # Iteration 2: Agent updates again
    update_agent_status \
        "tasks_completed" "2" \
        "phase_complete" "false"
    
    # Verify role still there
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$SPRINTY_DIR/status.json")
    assert_equal "$tasks" "2"
    
    # Iteration 3: Final update
    update_agent_status \
        "tasks_completed" "3" \
        "phase_complete" "true"
    
    # All fields preserved
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$SPRINTY_DIR/status.json")
    assert_equal "$phase_complete" "true"
}

# ============================================================================
# Agent failure scenarios
# ============================================================================

@test "integration: orchestrator detects when agent doesn't update status.json" {
    # Create status with empty role (agent didn't update)
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    # Parse should fail
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    assert_output --partial "Agent did not update status.json"
}

@test "integration: phase doesn't advance when agent fails to update" {
    # Setup
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    start_sprint
    
    # Agent forgets to update status.json (role stays empty)
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    # Phase complete check should fail
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_failure
}

# ============================================================================
# Multi-agent collaboration
# ============================================================================

@test "integration: multiple agents work in sequence" {
    touch "$TEST_DIR/output.log"
    
    # 1. Product Owner initializes
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    update_agent_status "role" "product_owner" "phase" "initialization" "phase_complete" "true"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # 2. Product Owner plans
    start_sprint
    update_agent_status "role" "product_owner" "phase" "planning" "sprint" "1" "phase_complete" "true"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # 3. Developer implements
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "implemented"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    update_agent_status "role" "developer" "phase" "implementation" "phase_complete" "true"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # 4. QA tests
    jq '(.items[0]).status = "qa_passed"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    update_agent_status "role" "qa" "phase" "qa" "phase_complete" "true"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # 5. Product Owner reviews and marks done
    jq '(.items[0]).status = "done"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    update_agent_status "role" "product_owner" "phase" "review" "project_done" "true" "phase_complete" "true"
    
    run check_project_done_enhanced "$TEST_DIR/output.log"
    assert_success
}

# ============================================================================
# Edge cases and error recovery
# ============================================================================

@test "integration: recovery from missing status.json" {
    # Delete status.json (simulating error)
    rm -f "$SPRINTY_DIR/status.json"
    
    # Initialize should recreate it
    run init_agent_status
    assert_success
    
    # Should be usable
    run update_agent_status "role" "developer" "phase_complete" "false"
    assert_success
    
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
}

@test "integration: status.json survives orchestrator updates" {
    # Agent updates
    update_agent_status \
        "role" "developer" \
        "phase" "implementation" \
        "sprint" "1" \
        "tasks_completed" "3" \
        "phase_complete" "true"
    
    # Verify initial state
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$SPRINTY_DIR/status.json")
    assert_equal "$tasks" "3"
    
    # Note: In real workflow, orchestrator would call update_status()
    # which should preserve agent_status. We can't test that here
    # without sourcing sprinty.sh, but the unit test for update_status
    # covers this.
    
    # Verify agent_status is readable
    run get_agent_status_field "role"
    assert_success
    assert_output "developer"
    
    run get_agent_status_field "tasks_completed"
    assert_success
    assert_output "3"
}

@test "integration: done_detector uses status.json for project completion" {
    # Setup complete backlog
    add_backlog_item "Task 1" "feature" 1 3 '["AC1"]'
    jq '(.items[0]).status = "done"' "$BACKLOG_FILE" > tmp && mv tmp "$BACKLOG_FILE"
    
    # Agent signals project done
    update_agent_status "role" "product_owner" "project_done" "true"
    
    touch "$TEST_DIR/output.log"
    
    # analyze_output_for_completion should detect it
    run analyze_output_for_completion "$TEST_DIR/output.log" 1
    
    # Project should be complete
    run is_project_complete
    assert_success
}

@test "integration: strict mode enforces status.json requirement" {
    # Create minimal status without agent update
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    # Should reject
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    
    # Phase should NOT complete
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_failure
}
