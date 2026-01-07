#!/usr/bin/env bats
# Unit tests for agent status management functions in backlog_manager.sh

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source the module
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    mkdir -p "$SPRINTY_DIR"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# init_agent_status tests
# ============================================================================

@test "init_agent_status creates agent_status section when missing" {
    # Create status.json without agent_status
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "status": "running"
}
EOF
    
    run init_agent_status
    assert_success
    
    # Check agent_status was added
    run jq -e '.agent_status' "$SPRINTY_DIR/status.json"
    assert_success
    
    # Verify default values
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" ""
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$SPRINTY_DIR/status.json")
    assert_equal "$phase_complete" "false"
}

@test "init_agent_status skips if agent_status already exists" {
    # Create status.json with agent_status
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "developer",
    "phase_complete": true
  }
}
EOF
    
    run init_agent_status
    assert_success
    
    # Verify existing values preserved
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
}

@test "init_agent_status handles missing status.json file" {
    run init_agent_status
    assert_success
    
    # File should be created by subsequent operations
}

# ============================================================================
# update_agent_status tests
# ============================================================================

@test "update_agent_status updates single field" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    run update_agent_status "role" "developer"
    assert_success
    
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "developer"
}

@test "update_agent_status updates multiple fields" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "",
    "phase_complete": false,
    "tasks_completed": 0
  }
}
EOF
    
    run update_agent_status "role" "qa" "phase_complete" "true" "tasks_completed" "3"
    assert_success
    
    role=$(jq -r '.agent_status.role' "$SPRINTY_DIR/status.json")
    assert_equal "$role" "qa"
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$SPRINTY_DIR/status.json")
    assert_equal "$phase_complete" "true"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$SPRINTY_DIR/status.json")
    assert_equal "$tasks" "3"
}

@test "update_agent_status handles boolean values correctly" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "phase_complete": false,
    "project_done": false
  }
}
EOF
    
    run update_agent_status "phase_complete" "true" "project_done" "false"
    assert_success
    
    # Verify as actual booleans, not strings
    phase_complete=$(jq -r '.agent_status.phase_complete' "$SPRINTY_DIR/status.json")
    assert_equal "$phase_complete" "true"
    
    # Verify it's a boolean in JSON
    is_bool=$(jq '.agent_status.phase_complete | type' "$SPRINTY_DIR/status.json")
    assert_equal "$is_bool" '"boolean"'
}

@test "update_agent_status handles numeric values correctly" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "sprint": 0,
    "tasks_completed": 0
  }
}
EOF
    
    run update_agent_status "sprint" "2" "tasks_completed" "5"
    assert_success
    
    sprint=$(jq -r '.agent_status.sprint' "$SPRINTY_DIR/status.json")
    assert_equal "$sprint" "2"
    
    # Verify it's a number in JSON
    is_number=$(jq '.agent_status.sprint | type' "$SPRINTY_DIR/status.json")
    assert_equal "$is_number" '"number"'
}

@test "update_agent_status updates last_updated timestamp" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "",
    "last_updated": "2020-01-01T00:00:00+00:00"
  }
}
EOF
    
    old_timestamp=$(jq -r '.agent_status.last_updated' "$SPRINTY_DIR/status.json")
    
    sleep 1
    run update_agent_status "role" "developer"
    assert_success
    
    new_timestamp=$(jq -r '.agent_status.last_updated' "$SPRINTY_DIR/status.json")
    
    # Timestamps should be different
    assert_not_equal "$old_timestamp" "$new_timestamp"
}

# ============================================================================
# get_agent_status_field tests
# ============================================================================

@test "get_agent_status_field returns correct value" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer",
    "phase": "implementation",
    "sprint": 1
  }
}
EOF
    
    run get_agent_status_field "role"
    assert_success
    assert_output "developer"
    
    run get_agent_status_field "phase"
    assert_success
    assert_output "implementation"
}

@test "get_agent_status_field returns empty for missing field" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer"
  }
}
EOF
    
    run get_agent_status_field "nonexistent"
    assert_success
    assert_output ""
}

@test "get_agent_status_field handles missing status file" {
    rm -f "$SPRINTY_DIR/status.json"
    
    run get_agent_status_field "role"
    assert_failure
    assert_output ""
}

# ============================================================================
# get_agent_status_json tests
# ============================================================================

@test "get_agent_status_json returns full agent_status object" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "developer",
    "phase_complete": true,
    "tasks_completed": 3
  }
}
EOF
    
    run get_agent_status_json
    assert_success
    
    # Parse output as JSON and verify
    role=$(echo "$output" | jq -r '.role')
    assert_equal "$role" "developer"
    
    phase_complete=$(echo "$output" | jq -r '.phase_complete')
    assert_equal "$phase_complete" "true"
}

@test "get_agent_status_json returns empty object for missing agent_status" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0"
}
EOF
    
    run get_agent_status_json
    assert_success
    assert_output "{}"
}

# ============================================================================
# is_phase_complete_from_status tests
# ============================================================================

@test "is_phase_complete_from_status returns true when phase_complete is true" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "phase_complete": true
  }
}
EOF
    
    run is_phase_complete_from_status
    assert_success
}

@test "is_phase_complete_from_status returns false when phase_complete is false" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "phase_complete": false
  }
}
EOF
    
    run is_phase_complete_from_status
    assert_failure
}

@test "is_phase_complete_from_status returns false for missing field" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "role": "developer"
  }
}
EOF
    
    run is_phase_complete_from_status
    assert_failure
}

# ============================================================================
# is_project_done_from_status tests
# ============================================================================

@test "is_project_done_from_status returns true when project_done is true" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "project_done": true
  }
}
EOF
    
    run is_project_done_from_status
    assert_success
}

@test "is_project_done_from_status returns false when project_done is false" {
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "agent_status": {
    "project_done": false
  }
}
EOF
    
    run is_project_done_from_status
    assert_failure
}

@test "is_project_done_from_status handles missing status file" {
    rm -f "$SPRINTY_DIR/status.json"
    
    run is_project_done_from_status
    assert_failure
}

# ============================================================================
# Integration with backlog
# ============================================================================

@test "agent_status functions work with backlog operations" {
    # Initialize backlog
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    run init_backlog "test-project"
    assert_success
    
    # Initialize agent status
    cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {
    "role": "",
    "phase_complete": false
  }
}
EOF
    
    # Update agent status
    run update_agent_status "role" "product_owner" "phase_complete" "true"
    assert_success
    
    # Verify both files exist and are valid
    assert_file_exists "$BACKLOG_FILE"
    assert_file_exists "$SPRINTY_DIR/status.json"
    
    # Verify phase complete
    run is_phase_complete_from_status
    assert_success
}
