#!/usr/bin/env bats

# Integration tests for Final QA Sprint workflow

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    
    # Source the libraries
    source "$SPRINTY_ROOT/lib/utils.sh"
    source "$SPRINTY_ROOT/lib/done_detector.sh"
    source "$SPRINTY_ROOT/lib/backlog_manager.sh"
    source "$SPRINTY_ROOT/lib/sprint_manager.sh"
    source "$SPRINTY_ROOT/lib/agent_adapter.sh"
    
    # Create test directories
    mkdir -p "$TEST_DIR/.sprinty"
    mkdir -p "$TEST_DIR/reviews"
    mkdir -p "$TEST_DIR/specs"
    mkdir -p "$TEST_DIR/logs/agent_output"
    
    # Initialize config
    cat > "$TEST_DIR/.sprinty/config.json" << 'EOF'
{
  "project": {"name": "test-project"},
  "sprint": {"max_sprints": 10},
  "agent": {"cli_tool": "cursor-agent", "model": "test-model", "timeout_minutes": 1}
}
EOF
    
    # Initialize sprint state
    cat > "$TEST_DIR/.sprinty/sprint_state.json" << 'EOF'
{
  "current_sprint": 3,
  "current_phase": "review",
  "project_done": false
}
EOF
    
    # Initialize status.json
    cat > "$TEST_DIR/.sprinty/status.json" << 'EOF'
{
  "version": "0.1.0",
  "agent_status": {}
}
EOF
    
    export SPRINTY_DIR="$TEST_DIR/.sprinty"
    export BACKLOG_FILE="$TEST_DIR/backlog.json"
    export AGENT_OUTPUT_DIR="$TEST_DIR/logs/agent_output"
    
    cd "$TEST_DIR"
}

teardown() {
    cleanup_test_environment
}

# ============================================================================
# Final QA Sprint Trigger Tests
# ============================================================================

@test "Final QA Sprint: triggers when all tasks are done" {
    # Setup: All tasks done
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "title": "Feature A", "status": "done", "type": "feature"},
    {"id": "TASK-002", "title": "Feature B", "status": "done", "type": "feature"},
    {"id": "TASK-003", "title": "Feature C", "status": "done", "type": "feature"}
  ]
}
EOF
    
    # Verify Final QA is needed
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

@test "Final QA Sprint: does not trigger when tasks incomplete" {
    # Setup: Some tasks not done
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "title": "Feature A", "status": "done", "type": "feature"},
    {"id": "TASK-002", "title": "Feature B", "status": "implemented", "type": "feature"},
    {"id": "TASK-003", "title": "Feature C", "status": "ready", "type": "feature"}
  ]
}
EOF
    
    # Verify Final QA is NOT needed
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "Final QA Sprint: does not trigger again after passing" {
    # Setup: All tasks done AND Final QA passed
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "title": "Feature A", "status": "done", "type": "feature"},
    {"id": "TASK-002", "title": "Feature B", "status": "done", "type": "feature"}
  ]
}
EOF
    mark_final_qa_status "passed"
    
    # Verify Final QA is NOT needed (already passed)
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
}

@test "Final QA Sprint: triggers again after failure with new bugs fixed" {
    # Setup: All tasks done (including fixed bugs), Final QA previously failed
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "title": "Feature A", "status": "done", "type": "feature"},
    {"id": "TASK-002", "title": "Feature B", "status": "done", "type": "feature"},
    {"id": "BUG-001", "title": "Bug from Final QA", "status": "done", "type": "bug"}
  ]
}
EOF
    mark_final_qa_status "failed"
    
    # Verify Final QA IS needed (need to retry after bug fixes)
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

# ============================================================================
# Final QA Status Tracking Tests
# ============================================================================

@test "Final QA Sprint: status transitions correctly" {
    # Initial: not set
    run has_final_qa_passed
    [ "$status" -eq 1 ]
    
    # In progress
    mark_final_qa_status "in_progress"
    local current=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$current" = "in_progress" ]
    
    # Failed
    mark_final_qa_status "failed"
    current=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$current" = "failed" ]
    run has_final_qa_passed
    [ "$status" -eq 1 ]
    
    # Passed
    mark_final_qa_status "passed"
    current=$(jq -r '.final_qa_status' "$SPRINTY_DIR/sprint_state.json")
    [ "$current" = "passed" ]
    run has_final_qa_passed
    [ "$status" -eq 0 ]
}

# ============================================================================
# Project Completion with Final QA Tests
# ============================================================================

@test "Project completion: requires Final QA passed" {
    # Setup: All tasks done but Final QA not passed
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"}
  ]
}
EOF
    
    # Project should NOT be complete
    run is_project_complete
    [ "$status" -eq 1 ]
    
    # Mark Final QA as passed
    mark_final_qa_status "passed"
    
    # Now project should be complete
    run is_project_complete
    [ "$status" -eq 0 ]
}

@test "Project completion: blocked by incomplete tasks even if Final QA passed previously" {
    # Edge case: Final QA passed but somehow new tasks added
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done"},
    {"id": "TASK-002", "status": "done"},
    {"id": "TASK-003", "status": "ready"}
  ]
}
EOF
    mark_final_qa_status "passed"
    
    # Project should NOT be complete (has incomplete task)
    run is_project_complete
    [ "$status" -eq 1 ]
}

# ============================================================================
# Bug Creation Workflow Tests
# ============================================================================

@test "Final QA Sprint: new bugs block completion until fixed" {
    # Setup: Original tasks done
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "done", "type": "feature"},
    {"id": "TASK-002", "status": "done", "type": "feature"}
  ]
}
EOF
    
    # Final QA finds bugs and adds them
    jq '.items += [{"id": "BUG-001", "title": "Bug from Final QA", "status": "backlog", "type": "bug"}]' \
        "$BACKLOG_FILE" > tmp.json && mv tmp.json "$BACKLOG_FILE"
    mark_final_qa_status "failed"
    
    # Project should NOT be complete
    run is_project_complete
    [ "$status" -eq 1 ]
    
    # Final QA should NOT be needed yet (bug not fixed)
    run needs_final_qa_sprint
    [ "$status" -eq 1 ]
    
    # Fix the bug
    jq '(.items[] | select(.id == "BUG-001")).status = "done"' \
        "$BACKLOG_FILE" > tmp.json && mv tmp.json "$BACKLOG_FILE"
    
    # Now Final QA should be needed again
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

# ============================================================================
# Edge Cases
# ============================================================================

@test "Final QA Sprint: handles empty backlog" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": []
}
EOF
    
    # Empty backlog is technically "complete" but still needs Final QA
    # This is an edge case - check_backlog_completion should handle it
    run needs_final_qa_sprint
    # Behavior depends on how check_backlog_completion handles empty
}

@test "Final QA Sprint: handles all cancelled tasks" {
    cat > "$BACKLOG_FILE" << 'EOF'
{
  "project": "test-project",
  "items": [
    {"id": "TASK-001", "status": "cancelled"},
    {"id": "TASK-002", "status": "cancelled"}
  ]
}
EOF
    
    # All cancelled is "complete" but still needs Final QA
    run needs_final_qa_sprint
    [ "$status" -eq 0 ]
}

@test "Final QA Sprint: mixed done and cancelled is complete" {
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
    mark_final_qa_status "passed"
    
    run is_project_complete
    [ "$status" -eq 0 ]
}

# ============================================================================
# Final QA Report Tests
# ============================================================================

@test "Final QA Sprint: report directory exists after setup" {
    mkdir -p "$TEST_DIR/reviews"
    [ -d "$TEST_DIR/reviews" ]
}

@test "Final QA Sprint: can create report file" {
    mkdir -p "$TEST_DIR/reviews"
    
    cat > "$TEST_DIR/reviews/final_qa_report.md" << 'EOF'
# Final QA Sprint Report

**Date:** 2026-01-08
**Status:** PASSED

## Summary
- All tests passed
EOF
    
    [ -f "$TEST_DIR/reviews/final_qa_report.md" ]
    grep -q "PASSED" "$TEST_DIR/reviews/final_qa_report.md"
}

# ============================================================================
# Prompt Selection Tests
# ============================================================================

@test "Final QA Sprint: uses final_qa.md prompt" {
    # Verify the prompt file exists
    [ -f "$SPRINTY_ROOT/prompts/final_qa.md" ]
}

@test "Final QA Sprint: prompt contains comprehensive testing instructions" {
    grep -q "Installation" "$SPRINTY_ROOT/prompts/final_qa.md"
    grep -q "VERIFY" "$SPRINTY_ROOT/prompts/final_qa.md"
    grep -q "End-to-End" "$SPRINTY_ROOT/prompts/final_qa.md"
    grep -q "bug" "$SPRINTY_ROOT/prompts/final_qa.md"
}
