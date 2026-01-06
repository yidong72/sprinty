#!/usr/bin/env bats
# Unit Tests for Agent Adapter Module

# Load test helpers
load '../helpers/test_helper'

setup() {
    # Source test helper (sets up temp directory and env vars)
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-adapter-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    export SPRINTY_DIR=".sprinty"
    export CURSOR_CONFIG_DIR=".cursor"
    export PROMPTS_DIR="prompts"
    export AGENT_OUTPUT_DIR="logs/agent_output"
    
    mkdir -p .sprinty logs/agent_output prompts
    
    # Create mock sprint state
    cat > ".sprinty/sprint_state.json" << 'EOF'
{
    "current_sprint": 1,
    "current_phase": "implementation"
}
EOF
    
    # Create mock backlog
    cat > "backlog.json" << 'EOF'
{
    "project": "test-project",
    "items": [
        {"id": "TASK-001", "title": "Task 1", "status": "ready", "story_points": 5, "sprint_id": 1}
    ]
}
EOF
    
    # Create mock prompt files
    cat > "prompts/developer.md" << 'EOF'
# Developer Agent

You are a developer agent.

## Instructions
Implement the assigned tasks.
EOF
    
    cat > "prompts/product_owner.md" << 'EOF'
# Product Owner Agent

You are a product owner agent.
EOF
    
    cat > "prompts/qa.md" << 'EOF'
# QA Agent

You are a QA agent.
EOF
    
    # Source the modules under test
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/agent_adapter.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# PROJECT CONFIGURATION TESTS
# ============================================================================

@test "init_cursor_project_config creates config file" {
    init_cursor_project_config "."
    
    assert_file_exists "$CURSOR_CONFIG_DIR/cli.json"
}

@test "init_cursor_project_config creates valid JSON" {
    init_cursor_project_config "."
    
    assert_valid_json "$CURSOR_CONFIG_DIR/cli.json"
}

@test "init_cursor_project_config includes permissions" {
    init_cursor_project_config "."
    
    local has_perms=$(jq 'has("permissions")' "$CURSOR_CONFIG_DIR/cli.json")
    assert_equal "$has_perms" "true"
}

@test "init_cursor_project_config includes allow list" {
    init_cursor_project_config "."
    
    local allow_count=$(jq '.permissions.allow | length' "$CURSOR_CONFIG_DIR/cli.json")
    [[ $allow_count -gt 0 ]]
}

@test "init_cursor_project_config includes deny list" {
    init_cursor_project_config "."
    
    local deny_count=$(jq '.permissions.deny | length' "$CURSOR_CONFIG_DIR/cli.json")
    [[ $deny_count -gt 0 ]]
}

@test "init_cursor_project_config does not overwrite existing config" {
    mkdir -p "$CURSOR_CONFIG_DIR"
    echo '{"custom": "config"}' > "$CURSOR_CONFIG_DIR/cli.json"
    
    init_cursor_project_config "."
    
    local custom=$(jq -r '.custom' "$CURSOR_CONFIG_DIR/cli.json")
    assert_equal "$custom" "config"
}

# ============================================================================
# PROMPT GENERATION TESTS
# ============================================================================

@test "generate_prompt creates output file" {
    result=$(generate_prompt "developer" "implementation" 1)
    
    assert_file_exists "$result"
}

@test "generate_prompt includes base prompt content" {
    result=$(generate_prompt "developer" "implementation" 1)
    
    grep -q "Developer Agent" "$result"
}

@test "generate_prompt includes sprint context" {
    result=$(generate_prompt "developer" "implementation" 1)
    
    grep -q "Sprint.*: 1" "$result"
}

@test "generate_prompt includes phase context" {
    result=$(generate_prompt "developer" "qa" 2)
    
    grep -q "Phase.*: qa" "$result"
}

@test "generate_prompt includes role context" {
    result=$(generate_prompt "qa" "qa" 1)
    
    grep -q "Role.*: qa" "$result"
}

@test "generate_prompt includes timestamp" {
    result=$(generate_prompt "developer" "implementation" 1)
    
    grep -q "Timestamp" "$result"
}

@test "generate_prompt includes SPRINTY_STATUS reminder" {
    result=$(generate_prompt "developer" "implementation" 1)
    
    grep -q "SPRINTY_STATUS" "$result"
}

@test "generate_prompt fails for missing base prompt" {
    rm -f "prompts/developer.md"
    
    run generate_prompt "developer" "implementation" 1
    assert_failure
}

@test "generate_prompt works with JSON context" {
    result=$(generate_prompt "developer" "implementation" 1 '{"key": "value"}')
    
    grep -q '"key"' "$result"
}

# ============================================================================
# CONTEXT GENERATION TESTS
# ============================================================================

@test "generate_context_json returns valid JSON" {
    result=$(generate_context_json)
    
    echo "$result" | jq . >/dev/null
}

@test "generate_context_json includes sprint_id" {
    result=$(generate_context_json)
    
    local sprint=$(echo "$result" | jq -r '.sprint_id')
    assert_equal "$sprint" "1"
}

@test "generate_context_json includes phase" {
    result=$(generate_context_json)
    
    local phase=$(echo "$result" | jq -r '.phase')
    assert_equal "$phase" "implementation"
}

@test "generate_context_json includes backlog stats" {
    result=$(generate_context_json)
    
    local has_backlog=$(echo "$result" | jq 'has("backlog")')
    assert_equal "$has_backlog" "true"
}

@test "generate_context_json includes sprint stats" {
    result=$(generate_context_json)
    
    local has_sprint=$(echo "$result" | jq 'has("sprint_stats")')
    assert_equal "$has_sprint" "true"
}

# ============================================================================
# SPRINTY_STATUS PARSING TESTS
# ============================================================================

@test "extract_sprinty_status extracts status block" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(extract_sprinty_status "test_output.log")
    
    echo "$result" | grep -q "ROLE: developer"
}

@test "extract_sprinty_status returns empty for missing block" {
    echo "No status block here" > "test_output.log"
    
    result=$(extract_sprinty_status "test_output.log")
    
    [[ -z "$result" ]]
}

@test "get_sprinty_status_field extracts role" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(get_sprinty_status_field "test_output.log" "ROLE")
    
    assert_equal "$result" "developer"
}

@test "get_sprinty_status_field extracts phase" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(get_sprinty_status_field "test_output.log" "PHASE")
    
    assert_equal "$result" "implementation"
}

@test "get_sprinty_status_field extracts sprint" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(get_sprinty_status_field "test_output.log" "SPRINT")
    
    assert_equal "$result" "1"
}

@test "get_sprinty_status_field extracts tasks_completed" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(get_sprinty_status_field "test_output.log" "TASKS_COMPLETED")
    
    assert_equal "$result" "1"
}

@test "get_sprinty_status_field extracts phase_complete" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "false"
    
    result=$(get_sprinty_status_field "test_output.log" "PHASE_COMPLETE")
    
    assert_equal "$result" "true"
}

@test "parse_sprinty_status_to_json returns valid JSON" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(parse_sprinty_status_to_json "test_output.log")
    
    echo "$result" | jq . >/dev/null
}

@test "parse_sprinty_status_to_json extracts all fields" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    result=$(parse_sprinty_status_to_json "test_output.log")
    
    local role=$(echo "$result" | jq -r '.role')
    local phase=$(echo "$result" | jq -r '.phase')
    local sprint=$(echo "$result" | jq -r '.sprint')
    
    assert_equal "$role" "developer"
    assert_equal "$phase" "implementation"
    assert_equal "$sprint" "1"
}

@test "parse_sprinty_status_to_json converts phase_complete to boolean" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "false"
    
    result=$(parse_sprinty_status_to_json "test_output.log")
    
    local complete=$(echo "$result" | jq -r '.phase_complete')
    assert_equal "$complete" "true"
}

@test "parse_sprinty_status_to_json converts project_done to boolean" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "true"
    
    result=$(parse_sprinty_status_to_json "test_output.log")
    
    local done=$(echo "$result" | jq -r '.project_done')
    assert_equal "$done" "true"
}

@test "parse_sprinty_status_to_json returns empty object for missing block" {
    echo "No status block" > "test_output.log"
    
    result=$(parse_sprinty_status_to_json "test_output.log")
    
    assert_equal "$result" "{}"
}

# ============================================================================
# PHASE/PROJECT COMPLETION CHECKS
# ============================================================================

@test "check_phase_complete_from_response returns true for complete" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "false"
    
    run check_phase_complete_from_response "test_output.log"
    assert_success
}

@test "check_phase_complete_from_response returns false for incomplete" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    run check_phase_complete_from_response "test_output.log"
    assert_failure
}

@test "check_project_done_from_response returns true for done" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "true"
    
    run check_project_done_from_response "test_output.log"
    assert_success
}

@test "check_project_done_from_response returns false for not done" {
    create_mock_agent_output "test_output.log" "SUCCESS" "true" "false"
    
    run check_project_done_from_response "test_output.log"
    assert_failure
}

# ============================================================================
# ERROR DETECTION TESTS
# ============================================================================

@test "detect_rate_limit_error detects rate limit" {
    echo "Error: rate limit exceeded" > "test_output.log"
    
    run detect_rate_limit_error "test_output.log"
    assert_success
}

@test "detect_rate_limit_error detects too many requests" {
    echo "Error: too many requests" > "test_output.log"
    
    run detect_rate_limit_error "test_output.log"
    assert_success
}

@test "detect_rate_limit_error returns false for normal output" {
    echo "Success: task completed" > "test_output.log"
    
    run detect_rate_limit_error "test_output.log"
    assert_failure
}

@test "detect_auth_error detects unauthorized" {
    echo "Error: unauthorized access" > "test_output.log"
    
    run detect_auth_error "test_output.log"
    assert_success
}

@test "detect_auth_error detects authentication failed" {
    echo "authentication failed" > "test_output.log"
    
    run detect_auth_error "test_output.log"
    assert_success
}

@test "detect_auth_error returns false for normal output" {
    echo "Success: authenticated" > "test_output.log"
    
    run detect_auth_error "test_output.log"
    assert_failure
}

@test "detect_permission_error detects permission denied" {
    echo "Error: permission denied for file.txt" > "test_output.log"
    
    run detect_permission_error "test_output.log"
    assert_success
}

@test "detect_permission_error returns false for normal output" {
    echo "Success: file created" > "test_output.log"
    
    run detect_permission_error "test_output.log"
    assert_failure
}

@test "detect_timeout detects timeout marker" {
    echo "TIMEOUT: cursor-agent execution timed out" > "test_output.log"
    
    run detect_timeout "test_output.log"
    assert_success
}

@test "detect_timeout returns false for normal output" {
    echo "Success: completed" > "test_output.log"
    
    run detect_timeout "test_output.log"
    assert_failure
}

# ============================================================================
# BLOCKER DETECTION TESTS
# ============================================================================

@test "detect_blockers detects actual blockers" {
    cat > "test_output.log" << 'EOF'
---SPRINTY_STATUS---
ROLE: developer
BLOCKERS: Missing API credentials
---END_SPRINTY_STATUS---
EOF
    
    result=$(detect_blockers "test_output.log")
    
    [[ "$result" == *"Missing API credentials"* ]]
}

@test "detect_blockers returns failure for 'none'" {
    create_mock_agent_output "test_output.log" "SUCCESS" "false" "false"
    
    run detect_blockers "test_output.log"
    assert_failure
}

# ============================================================================
# OUTPUT FILE TRACKING
# ============================================================================

@test "get_last_agent_output returns stored path" {
    mkdir -p "$AGENT_OUTPUT_DIR"
    echo "/path/to/output.log" > "$AGENT_OUTPUT_DIR/.last_output"
    
    result=$(get_last_agent_output)
    
    assert_equal "$result" "/path/to/output.log"
}

@test "get_last_agent_output returns empty when no output" {
    rm -f "$AGENT_OUTPUT_DIR/.last_output"
    
    result=$(get_last_agent_output)
    
    [[ -z "$result" ]]
}

# ============================================================================
# VERSION/INSTALLATION CHECKS
# ============================================================================

@test "get_cursor_agent_version returns 'not installed' when missing" {
    # Mock cursor-agent as missing
    export CURSOR_AGENT_CMD="nonexistent_cmd_12345"
    
    result=$(get_cursor_agent_version)
    
    assert_equal "$result" "not installed"
}
