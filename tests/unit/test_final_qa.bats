#!/usr/bin/env bats

# Unit tests for Final QA Sprint functionality

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    
    # Source the libraries
    source "$SPRINTY_ROOT/lib/utils.sh"
    source "$SPRINTY_ROOT/lib/done_detector.sh"
    source "$SPRINTY_ROOT/lib/backlog_manager.sh"
    source "$SPRINTY_ROOT/lib/sprint_manager.sh"
    
    # Create test directories
    mkdir -p "$TEST_DIR/.sprinty"
    mkdir -p "$TEST_DIR/reviews"
    
    # Initialize sprint state
    cat > "$TEST_DIR/.sprinty/sprint_state.json" << 'EOF'
{
  "current_sprint": 1,
  "current_phase": "review",
  "project_done": false
}
EOF
    
    # Initialize backlog
    cat > "$TEST_DIR/backlog.json" << 'EOF'
{
  "project": "test-project",
  "items": []
}
EOF
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    
    cd "$TEST_DIR"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# has_final_qa_passed() tests
# ============================================================================

@test "has_final_qa_passed: returns false when final_qa_status not set" {
    run has_final_qa_passed
    [ "$status" -eq 1 ]
}

@test "has_final_qa_passed: returns false when final_qa_status is 'not_run'" {
    jq '.final_qa_status = "not_run"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run has_final_qa_passed
    [ "$status" -eq 1 ]
}

@test "has_final_qa_passed: returns false when final_qa_status is 'failed'" {
    jq '.final_qa_status = "failed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run has_final_qa_passed
    [ "$status" -eq 1 ]
}

@test "has_final_qa_passed: returns false when final_qa_status is 'in_progress'" {
    jq '.final_qa_status = "in_progress"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run has_final_qa_passed
    [ "$status" -eq 1 ]
}

@test "has_final_qa_passed: returns true when final_qa_status is 'passed'" {
    jq '.final_qa_status = "passed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run has_final_qa_passed
    [ "$status" -eq 0 ]
}

@test "has_final_qa_passed: returns false when state file doesn't exist" {
    rm -f "$SPRINTY_DIR/sprint_state.json"
    
    run has_final_qa_passed
    [ "$status" -eq 1 ]
}

# ============================================================================
# needs_final_qa_sprint() tests
# ============================================================================

@test "needs_final_qa_sprint: returns false when backlog not initialized" {
    rm -f "$BACKLOG_FILE"
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "needs_final_qa_sprint: returns false when tasks still incomplete" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "in_progress"}
  ]
}
EOF
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "needs_final_qa_sprint: returns false when Final QA already passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    jq '.final_qa_status = "passed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "needs_final_qa_sprint: returns true when all tasks done and Final QA not passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

@test "needs_final_qa_sprint: returns true when all tasks done/cancelled and Final QA not passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "cancelled"}
  ]
}
EOF
    
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

@test "needs_final_qa_sprint: returns true when Final QA previously failed (needs retry)" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    jq '.final_qa_status = "failed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

@test "needs_final_qa_sprint: returns false when backlog has ready tasks" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "ready"}
  ]
}
EOF
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "needs_final_qa_sprint: returns false when backlog has qa_failed tasks" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "qa_failed"}
  ]
}
EOF
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

# ============================================================================
# mark_final_qa_status() tests
# ============================================================================

@test "mark_final_qa_status: sets status to 'passed'" {
    mark_final_qa_status "passed"
    
    local status=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$status" = "passed" ]
}

@test "mark_final_qa_status: sets status to 'failed'" {
    mark_final_qa_status "failed"
    
    local status=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$status" = "failed" ]
}

@test "mark_final_qa_status: sets status to 'in_progress'" {
    mark_final_qa_status "in_progress"
    
    local status=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$status" = "in_progress" ]
}

@test "mark_final_qa_status: sets status to 'not_run'" {
    # First set to something else
    mark_final_qa_status "passed"
    # Then reset
    mark_final_qa_status "not_run"
    
    local status=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$status" = "not_run" ]
}

@test "mark_final_qa_status: updates timestamp" {
    mark_final_qa_status "passed"
    
    local updated=$(jq -r '.final_qa_updated' "$SPRINTY_DIR/sprint_state.json")
    [ "$updated" != "null" ]
    [ -n "$updated" ]
}

@test "mark_final_qa_status: preserves other state fields" {
    mark_final_qa_status "passed"
    
    local sprint=$(jq -r '.current_sprint' "$SPRINTY_DIR/sprint_state.json")
    local phase=$(jq -r '.current_phase' "$SPRINTY_DIR/sprint_state.json")
    
    [ "$sprint" = "1" ]
    [ "$phase" = "review" ]
}

# ============================================================================
# is_project_complete() tests (with Final QA requirement)
# ============================================================================

@test "is_project_complete: returns false when backlog incomplete" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "ready"}
  ]
}
EOF
    
    run is_project_complete
    [ "$status" -eq 1 ]
}

@test "is_project_complete: returns false when backlog complete but Final QA not passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    run is_project_complete
    [ "$status" -eq 1 ]
}

@test "is_project_complete: returns false when Final QA failed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    jq '.final_qa_status = "failed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run is_project_complete
    [ "$status" -eq 1 ]
}

@test "is_project_complete: returns true when backlog complete AND Final QA passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    jq '.final_qa_status = "passed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run is_project_complete
    [ "$status" -eq 0 ]
}

@test "is_project_complete: returns true with done and cancelled tasks AND Final QA passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "cancelled"},
    {"id": "TASK-003", "status": "done"}
  ]
}
EOF
    jq '.final_qa_status = "passed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run is_project_complete
    [ "$status" -eq 0 ]
}

# ============================================================================
# Final QA Retry Limit Tests
# ============================================================================

@test "get_final_qa_attempts: returns 0 when not set" {
    run get_final_qa_attempts
    [ "$output" = "0" ]
}

@test "increment_final_qa_attempts: increments counter" {
    increment_final_qa_attempts
    local count=$(get_final_qa_attempts)
    [ "$count" = "1" ]
    
    increment_final_qa_attempts
    count=$(get_final_qa_attempts)
    [ "$count" = "2" ]
}

@test "reset_final_qa_attempts: resets counter to 0" {
    increment_final_qa_attempts
    increment_final_qa_attempts
    local count=$(get_final_qa_attempts)
    [ "$count" = "2" ]
    
    reset_final_qa_attempts
    count=$(get_final_qa_attempts)
    [ "$count" = "0" ]
}

@test "needs_final_qa_sprint: returns false when max attempts reached" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    # Set attempts to max (3)
    jq '.final_qa_attempts = 3' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]  # Should return false (max attempts reached)
}

@test "needs_final_qa_sprint: returns true when under max attempts" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    # Set attempts to 2 (under max of 3)
    jq '.final_qa_attempts = 2' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]  # Should return true (under max attempts)
}

# ============================================================================
# should_exit_gracefully with Final QA Tests
# ============================================================================

@test "should_exit_gracefully: does not exit when backlog complete but Final QA not passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    # Final QA not passed (default)
    run should_exit_gracefully
    [ "$status" -eq 1 ]  # Should NOT exit (Final QA not passed)
}

@test "should_exit_gracefully: exits when backlog complete AND Final QA passed" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    # Mark Final QA as passed
    jq '.final_qa_status = "passed"' "$SPRINTY_DIR/sprint_state.json" > tmp.json && mv tmp.json "$SPRINTY_DIR/sprint_state.json"
    
    run should_exit_gracefully
    [ "$status" -eq 0 ]  # Should exit
    [[ "$output" == *"backlog_complete"* ]]  # Output contains the exit reason
}
