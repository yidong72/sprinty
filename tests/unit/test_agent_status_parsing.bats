#!/usr/bin/env bats
# Unit tests for enhanced status parsing functions in agent_adapter.sh

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/agent_adapter.sh"
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    mkdir -p "$SPRINTY_DIR"
    
    # Create minimal backlog
    init_backlog "test"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# parse_agent_status_enhanced tests
# ============================================================================

@test "parse_agent_status_enhanced succeeds with valid agent_status" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase": "implementation",
    "sprint": 1,
    "phase_complete": true,
    "project_done": false,
    "last_updated": "2026-01-07T12:00:00Z"
  }
}
EOF
    
    # Create dummy output file
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Verify it returns valid JSON
    role=$(echo "$output" | tail -1 | jq -r '.role')
    assert_equal "$role" "developer"
}

@test "parse_agent_status_enhanced fails when role is empty" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    
    # Should output error message
    assert_output --partial "Agent did not update status.json"
}

@test "parse_agent_status_enhanced fails when status.json missing" {
    rm -f "$SPRINTY_DIR/status.json"
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    assert_output --partial "status.json not found"
}

@test "parse_agent_status_enhanced fails when agent_status section missing" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "status": "running"
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    assert_output --partial "agent_status section missing"
}

@test "parse_agent_status_enhanced warns about missing last_updated" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Should contain warning about last_updated
    assert_output --partial "last_updated field is empty"
}

@test "parse_agent_status_enhanced returns correct JSON structure" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "qa",
    "phase": "qa",
    "sprint": 2,
    "tasks_completed": 5,
    "tasks_remaining": 0,
    "blockers": "none",
    "story_points_done": 13,
    "tests_status": "PASSING",
    "phase_complete": true,
    "project_done": false,
    "next_action": "All tests passed",
    "last_updated": "2026-01-07T12:00:00Z"
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Extract last line (JSON output)
    json_output=$(echo "$output" | tail -1)
    
    # Verify all fields
    assert_equal "$(echo "$json_output" | jq -r '.role')" "qa"
    assert_equal "$(echo "$json_output" | jq -r '.phase')" "qa"
    assert_equal "$(echo "$json_output" | jq -r '.sprint')" "2"
    assert_equal "$(echo "$json_output" | jq -r '.tasks_completed')" "5"
    assert_equal "$(echo "$json_output" | jq -r '.phase_complete')" "true"
}

# ============================================================================
# check_phase_complete_enhanced tests
# ============================================================================

@test "check_phase_complete_enhanced returns true when phase_complete is true" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase_complete": true
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
}

@test "check_phase_complete_enhanced returns false when phase_complete is false" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_failure
}

@test "check_phase_complete_enhanced logs appropriate message" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase_complete": true
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
    assert_output --partial "Phase complete detected from status.json"
}

# ============================================================================
# check_project_done_enhanced tests
# ============================================================================

@test "check_project_done_enhanced returns true when project_done is true" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "product_owner",
    "project_done": true
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run check_project_done_enhanced "$TEST_DIR/output.log"
    assert_success
}

@test "check_project_done_enhanced returns false when project_done is false" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "product_owner",
    "project_done": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run check_project_done_enhanced "$TEST_DIR/output.log"
    assert_failure
}

@test "check_project_done_enhanced checks backlog completion as safety" {
    # status.json says not done
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "project_done": false
  }
}
EOF
    
    # But backlog is actually complete
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    # Should return true because backlog is complete (safety check)
    run check_project_done_enhanced "$TEST_DIR/output.log"
    assert_success
    assert_output --partial "backlog completion"
}

# ============================================================================
# Strict mode enforcement tests
# ============================================================================

@test "strict mode rejects null role" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": null,
    "phase_complete": false
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    assert_output --partial "role field is empty"
}

@test "strict mode requires status.json file to exist" {
    rm -f "$SPRINTY_DIR/status.json"
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    assert_output --partial "not found"
}

@test "strict mode validates agent_status section exists" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0"
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
}

# ============================================================================
# Error handling tests
# ============================================================================

@test "parse handles malformed JSON gracefully" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer"
    MISSING COMMA
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
}

@test "parse returns empty JSON on failure" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": ""
  }
}
EOF
    
    touch "$TEST_DIR/output.log"
    
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_failure
    
    # Check last line is empty JSON
    last_line=$(echo "$output" | tail -1)
    assert_equal "$last_line" "{}"
}

# ============================================================================
# Integration scenarios
# ============================================================================

@test "complete workflow: agent updates, orchestrator reads" {
    # 1. Initial state (orchestrator creates)
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "loop_count": 1,
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    # 2. Agent updates status.json
    update_agent_status "role" "developer" "phase" "implementation" "sprint" "1" \
                       "tasks_completed" "2" "tasks_remaining" "1" \
                       "phase_complete" "false" "project_done" "false"
    
    # 3. Orchestrator parses
    touch "$TEST_DIR/output.log"
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # 4. Verify correct data
    json=$(echo "$output" | tail -1)
    assert_equal "$(echo "$json" | jq -r '.role')" "developer"
    assert_equal "$(echo "$json" | jq -r '.tasks_completed')" "2"
    
    # 5. Check phase not complete
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_failure
    
    # 6. Agent marks phase complete
    update_agent_status "phase_complete" "true"
    
    # 7. Check phase complete now
    run check_phase_complete_enhanced "$TEST_DIR/output.log"
    assert_success
}

@test "multiple agents in sequence preserve status" {
    touch "$TEST_DIR/output.log"
    
    # Product Owner initializes
    update_agent_status "role" "product_owner" "phase" "planning" "phase_complete" "true"
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    
    # Developer takes over
    update_agent_status "role" "developer" "phase" "implementation" "phase_complete" "false"
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    json=$(echo "$output" | tail -1)
    assert_equal "$(echo "$json" | jq -r '.role')" "developer"
    
    # QA takes over
    update_agent_status "role" "qa" "phase" "qa" "phase_complete" "true"
    run parse_agent_status_enhanced "$TEST_DIR/output.log"
    assert_success
    json=$(echo "$output" | tail -1)
    assert_equal "$(echo "$json" | jq -r '.role')" "qa"
}
