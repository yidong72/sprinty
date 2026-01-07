#!/usr/bin/env bats
# Integration test for update_status() agent_status preservation

load '../helpers/test_helper'

setup() {
    setup_test_environment
    
    # Source modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/rate_limiter.sh"
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export STATUS_FILE="$SPRINTY_DIR/status.json"
    export RATE_LIMIT_STATE_FILE="$SPRINTY_DIR/.rate_limit_state"
    export MAX_CALLS_PER_HOUR=100
    export VERSION="0.1.0"
    
    mkdir -p "$SPRINTY_DIR"
    
    # Initialize rate limiter
    init_rate_limiter
    
    # Source update_status function from sprinty.sh
    # Extract just the function for testing
    eval "$(sed -n '/^update_status()/,/^}/p' "$PROJECT_ROOT/sprinty.sh")"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# update_status preservation tests
# ============================================================================

@test "update_status creates status.json with default agent_status on first call" {
    run update_status 1 "planning" 1 "executing"
    assert_success
    
    # Verify file exists
    assert_file_exists "$STATUS_FILE"
    
    # Verify agent_status exists with defaults
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" ""
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")
    assert_equal "$phase_complete" "false"
}

@test "update_status preserves agent_status when it has been updated" {
    # Initial call
    update_status 1 "planning" 1 "executing"
    
    # Agent updates status.json
    update_agent_status \
        "role" "developer" \
        "phase" "implementation" \
        "sprint" "1" \
        "tasks_completed" "2" \
        "phase_complete" "true"
    
    # Verify agent update
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" "developer"
    
    # Orchestrator calls update_status again (next loop)
    run update_status 2 "planning" 1 "executing"
    assert_success
    
    # Agent status should be preserved
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" "developer"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$STATUS_FILE")
    assert_equal "$tasks" "2"
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")
    assert_equal "$phase_complete" "true"
    
    # But orchestrator fields should be updated
    loop_count=$(jq -r '.loop_count' "$STATUS_FILE")
    assert_equal "$loop_count" "2"
}

@test "update_status preserves all agent_status fields" {
    update_status 1 "implementation" 1 "executing"
    
    # Agent sets all fields
    update_agent_status \
        "role" "developer" \
        "phase" "implementation" \
        "sprint" "1" \
        "tasks_completed" "5" \
        "tasks_remaining" "3" \
        "blockers" "API rate limit" \
        "story_points_done" "13" \
        "tests_status" "PASSING" \
        "phase_complete" "false" \
        "project_done" "false" \
        "next_action" "Continue with TASK-006"
    
    # Orchestrator updates
    update_status 2 "implementation" 1 "executing"
    
    # Verify ALL fields preserved
    assert_equal "$(jq -r '.agent_status.role' "$STATUS_FILE")" "developer"
    assert_equal "$(jq -r '.agent_status.phase' "$STATUS_FILE")" "implementation"
    assert_equal "$(jq -r '.agent_status.sprint' "$STATUS_FILE")" "1"
    assert_equal "$(jq -r '.agent_status.tasks_completed' "$STATUS_FILE")" "5"
    assert_equal "$(jq -r '.agent_status.tasks_remaining' "$STATUS_FILE")" "3"
    assert_equal "$(jq -r '.agent_status.blockers' "$STATUS_FILE")" "API rate limit"
    assert_equal "$(jq -r '.agent_status.story_points_done' "$STATUS_FILE")" "13"
    assert_equal "$(jq -r '.agent_status.tests_status' "$STATUS_FILE")" "PASSING"
    assert_equal "$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")" "false"
    assert_equal "$(jq -r '.agent_status.project_done' "$STATUS_FILE")" "false"
    assert_equal "$(jq -r '.agent_status.next_action' "$STATUS_FILE")" "Continue with TASK-006"
}

@test "update_status handles multiple sequential updates" {
    # Loop 1
    update_status 1 "implementation" 1 "executing"
    update_agent_status "role" "developer" "tasks_completed" "1"
    
    # Loop 2
    update_status 2 "implementation" 1 "executing"
    update_agent_status "tasks_completed" "2"
    
    # Loop 3
    update_status 3 "implementation" 1 "executing"
    update_agent_status "tasks_completed" "3" "phase_complete" "true"
    
    # Loop 4
    update_status 4 "implementation" 1 "executing"
    
    # Final verification
    assert_equal "$(jq -r '.loop_count' "$STATUS_FILE")" "4"
    assert_equal "$(jq -r '.agent_status.role' "$STATUS_FILE")" "developer"
    assert_equal "$(jq -r '.agent_status.tasks_completed' "$STATUS_FILE")" "3"
    assert_equal "$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")" "true"
}

@test "update_status preserves agent_status across phase changes" {
    # Planning phase
    update_status 1 "planning" 1 "executing"
    update_agent_status "role" "product_owner" "phase" "planning" "phase_complete" "true"
    
    # Move to implementation phase
    update_status 2 "implementation" 1 "executing"
    
    # Previous agent data should be preserved
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" "product_owner"
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")
    assert_equal "$phase_complete" "true"
    
    # But current_phase updated
    current_phase=$(jq -r '.current_phase' "$STATUS_FILE")
    assert_equal "$current_phase" "implementation"
}

@test "update_status handles empty agent_status gracefully" {
    # Create status with missing agent_status
    cat > "$STATUS_FILE" << 'EOF'
{
  "version": "0.1.0",
  "loop_count": 1,
  "status": "running"
}
EOF
    
    # update_status should handle this
    run update_status 2 "planning" 1 "executing"
    assert_success
    
    # Should create default agent_status
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" ""
    
    phase_complete=$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")
    assert_equal "$phase_complete" "false"
}

@test "update_status preserves agent_status with complex nested data" {
    update_status 1 "qa" 1 "executing"
    
    # Agent updates with various data types
    jq '.agent_status = {
      "role": "qa",
      "phase": "qa",
      "sprint": 1,
      "tasks_completed": 5,
      "tasks_remaining": 0,
      "blockers": "none",
      "story_points_done": 21,
      "tests_status": "PASSING",
      "phase_complete": true,
      "project_done": false,
      "next_action": "All tests passed",
      "last_updated": "2026-01-07T12:00:00Z",
      "custom_field": "custom_value"
    }' "$STATUS_FILE" > tmp && mv tmp "$STATUS_FILE"
    
    # Orchestrator updates
    update_status 2 "qa" 1 "executing"
    
    # All fields should be preserved including custom ones
    assert_equal "$(jq -r '.agent_status.role' "$STATUS_FILE")" "qa"
    assert_equal "$(jq -r '.agent_status.story_points_done' "$STATUS_FILE")" "21"
    assert_equal "$(jq -r '.agent_status.phase_complete' "$STATUS_FILE")" "true"
    assert_equal "$(jq -r '.agent_status.custom_field' "$STATUS_FILE")" "custom_value"
}

# ============================================================================
# Race condition and timing tests
# ============================================================================

@test "update_status reads before writing (no race condition)" {
    update_status 1 "implementation" 1 "executing"
    
    # Simulate rapid updates (agent then orchestrator)
    update_agent_status "role" "developer" "tasks_completed" "1"
    update_status 2 "implementation" 1 "executing"
    
    # Agent data should survive
    role=$(jq -r '.agent_status.role' "$STATUS_FILE")
    assert_equal "$role" "developer"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$STATUS_FILE")
    assert_equal "$tasks" "1"
}

@test "update_status handles concurrent-like updates" {
    update_status 1 "implementation" 1 "executing"
    
    # Multiple rapid updates
    update_agent_status "role" "developer" "tasks_completed" "1"
    update_status 2 "implementation" 1 "executing"
    
    update_agent_status "tasks_completed" "2"
    update_status 3 "implementation" 1 "executing"
    
    update_agent_status "tasks_completed" "3"
    update_status 4 "implementation" 1 "executing"
    
    # Final state should be consistent
    loop_count=$(jq -r '.loop_count' "$STATUS_FILE")
    assert_equal "$loop_count" "4"
    
    tasks=$(jq -r '.agent_status.tasks_completed' "$STATUS_FILE")
    assert_equal "$tasks" "3"
}

# ============================================================================
# Error recovery tests
# ============================================================================

@test "update_status creates valid JSON even if previous is corrupted" {
    # Create corrupted status.json
    echo "{ INVALID JSON" > "$STATUS_FILE"
    
    # update_status should handle this
    run update_status 1 "planning" 1 "executing"
    
    # Should create valid JSON (defaults for agent_status)
    run jq '.' "$STATUS_FILE"
    assert_success
}

@test "update_status handles missing STATUS_FILE directory" {
    rm -rf "$SPRINTY_DIR"
    
    # Should create directory and file
    run update_status 1 "planning" 1 "executing"
    assert_success
    
    assert_file_exists "$STATUS_FILE"
}

# ============================================================================
# Validation tests
# ============================================================================

@test "update_status creates valid JSON structure" {
    run update_status 1 "planning" 1 "executing"
    assert_success
    
    # Validate JSON structure
    run jq -e '.version' "$STATUS_FILE"
    assert_success
    
    run jq -e '.loop_count' "$STATUS_FILE"
    assert_success
    
    run jq -e '.current_phase' "$STATUS_FILE"
    assert_success
    
    run jq -e '.agent_status' "$STATUS_FILE"
    assert_success
    
    run jq -e '.agent_status.role' "$STATUS_FILE"
    assert_success
    
    run jq -e '.agent_status.phase_complete' "$STATUS_FILE"
    assert_success
}

@test "update_status updates orchestrator fields correctly" {
    update_status 5 "qa" 2 "completed" "test_complete"
    
    assert_equal "$(jq -r '.loop_count' "$STATUS_FILE")" "5"
    assert_equal "$(jq -r '.current_phase' "$STATUS_FILE")" "qa"
    assert_equal "$(jq -r '.current_sprint' "$STATUS_FILE")" "2"
    assert_equal "$(jq -r '.status' "$STATUS_FILE")" "completed"
    assert_equal "$(jq -r '.exit_reason' "$STATUS_FILE")" "test_complete"
}

@test "update_status maintains type correctness" {
    update_status 1 "planning" 1 "executing"
    
    # Verify types
    assert_equal "$(jq '.loop_count | type' "$STATUS_FILE")" '"number"'
    assert_equal "$(jq '.current_sprint | type' "$STATUS_FILE")" '"number"'
    assert_equal "$(jq '.current_phase | type' "$STATUS_FILE")" '"string"'
    assert_equal "$(jq '.agent_status | type' "$STATUS_FILE")" '"object"'
    assert_equal "$(jq '.agent_status.phase_complete | type' "$STATUS_FILE")" '"boolean"'
}
