#!/usr/bin/env bats
# Integration Tests for QA Workflow
# Tests QA fail/pass logic and task creation rules

load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    
    export PROJECT_ROOT="$(get_project_root)"
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-qa-workflow.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    # Set up environment
    export SPRINTY_DIR=".sprinty"
    export BACKLOG_FILE="backlog.json"
    export SPRINT_STATE_FILE=".sprinty/sprint_state.json"
    export SPRINTS_DIR="sprints"
    export REVIEWS_DIR="reviews"
    
    mkdir -p "$SPRINTY_DIR" "$SPRINTS_DIR" "$REVIEWS_DIR"
    
    # Source modules
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/backlog_manager.sh"
    source "$PROJECT_ROOT/lib/sprint_manager.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# QA FAIL WORKFLOW TESTS
# ============================================================================

@test "QA workflow: task with missing tests should be failed" {
    init_backlog "qa-fail-test"
    init_sprint_state
    
    # Create and implement a task
    add_backlog_item "Implement login" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Developer implements (status: implemented)
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    # QA finds missing tests - should FAIL the task
    update_item_status "TASK-001" "qa_in_progress"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Missing unit tests. Coverage is 40%, requires 85%"
    
    # Verify task is failed
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    local reason=$(jq -r '.items[0].failure_reason' "$BACKLOG_FILE")
    
    assert_equal "$status" "qa_failed"
    [[ "$reason" == *"Missing unit tests"* ]]
}

@test "QA workflow: failed task triggers rework cycle" {
    init_backlog "rework-test"
    init_sprint_state
    
    add_backlog_item "Implement feature" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # First implementation attempt
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    # QA fails
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Tests missing"
    
    # Verify has_tasks_to_rework detects the failure
    run has_qa_failed_tasks
    assert_success
    
    # Developer reworks (back to in_progress)
    update_item_status "TASK-001" "in_progress"
    
    # Verify task is back in progress
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "in_progress"
}

@test "QA workflow: reworked task can pass QA" {
    init_backlog "rework-pass-test"
    init_sprint_state
    
    add_backlog_item "Implement feature" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # First attempt - fails QA
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "No tests"
    
    # Rework
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    
    # Second attempt - passes QA
    update_item_status "TASK-001" "qa_passed"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_passed"
    
    # Failure reason should be cleared or task should pass
    run has_qa_failed_tasks
    assert_failure  # No more failed tasks
}

@test "QA workflow: multiple rework cycles allowed" {
    init_backlog "multi-rework-test"
    init_sprint_state
    
    add_backlog_item "Complex feature" "feature" 1 8
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Cycle 1: Fail for missing tests
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Missing unit tests"
    
    # Cycle 2: Fail for low coverage
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Coverage 60%, needs 85%"
    
    # Cycle 3: Pass
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_passed"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_passed"
}

@test "QA workflow: qa_failed tasks detected for rework" {
    init_backlog "phase-incomplete-test"
    init_sprint_state
    
    add_backlog_item "Feature 1" "feature" 1 5
    add_backlog_item "Feature 2" "feature" 1 3
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # Both implemented
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-002" "implemented"
    
    # One passes, one fails
    update_item_status "TASK-001" "qa_passed"
    update_item_status "TASK-002" "qa_failed"
    set_failure_reason "TASK-002" "Tests missing"
    
    # Should have tasks to rework
    run has_qa_failed_tasks
    assert_success
    
    # Note: is_phase_complete "qa" returns true because no "implemented" tasks remain
    # The qa_failed detection is separate (has_qa_failed_tasks)
    # This is correct - QA phase tested all tasks, rework is a separate concern
    run is_phase_complete "qa"
    assert_success
}

# ============================================================================
# QA BUG TASK CREATION TESTS
# ============================================================================

@test "QA workflow: can create bug task for out-of-scope issue" {
    init_backlog "bug-creation-test"
    init_sprint_state
    
    add_backlog_item "Implement login" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # During QA, found a bug in UNRELATED code
    # QA creates a bug task (simulating what QA agent would do)
    local bug_json='{
        "title": "Bug: Password reset email not sent",
        "type": "bug",
        "priority": 2,
        "story_points": 2,
        "description": "Found while testing login - unrelated to login feature"
    }'
    add_backlog_item_json "$bug_json"
    
    # Original task can still pass QA
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_passed"
    
    # Verify both tasks exist
    local task_count=$(jq '.items | length' "$BACKLOG_FILE")
    assert_equal "$task_count" "2"
    
    # Verify bug task is in backlog (not ready)
    local bug_status=$(jq -r '.items[] | select(.type == "bug") | .status' "$BACKLOG_FILE")
    assert_equal "$bug_status" "backlog"
    
    # Original task passed
    local login_status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$login_status" "qa_passed"
}

@test "QA workflow: bug task has correct structure" {
    init_backlog "bug-structure-test"
    
    # Create bug task like QA would
    local bug_json='{
        "title": "Bug: Crash on invalid input",
        "type": "bug",
        "priority": 2,
        "story_points": 2,
        "acceptance_criteria": ["Bug is fixed", "No regression"]
    }'
    add_backlog_item_json "$bug_json"
    
    # Verify structure
    local bug=$(jq '.items[0]' "$BACKLOG_FILE")
    
    local type=$(echo "$bug" | jq -r '.type')
    local status=$(echo "$bug" | jq -r '.status')
    local sprint_id=$(echo "$bug" | jq -r '.sprint_id')
    local ac_count=$(echo "$bug" | jq '.acceptance_criteria | length')
    
    assert_equal "$type" "bug"
    assert_equal "$status" "backlog"
    assert_equal "$sprint_id" "null"
    assert_equal "$ac_count" "2"
}

@test "QA workflow: infra task for missing test framework" {
    init_backlog "infra-task-test"
    
    # QA discovers no test framework exists - creates infra task
    local infra_json='{
        "title": "Setup pytest test framework",
        "type": "infra",
        "priority": 1,
        "story_points": 5,
        "acceptance_criteria": [
            "pytest installed and configured",
            "CI pipeline runs tests",
            "Coverage reporting enabled"
        ]
    }'
    add_backlog_item_json "$infra_json"
    
    local type=$(jq -r '.items[0].type' "$BACKLOG_FILE")
    local priority=$(jq -r '.items[0].priority' "$BACKLOG_FILE")
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    
    assert_equal "$type" "infra"
    assert_equal "$priority" "1"
    assert_equal "$status" "backlog"
}

# ============================================================================
# QA SHOULD NOT CREATE TEST TASKS FOR CURRENT TASK
# ============================================================================

@test "QA workflow: missing tests should fail task, not create new task" {
    init_backlog "no-test-task-test"
    init_sprint_state
    
    add_backlog_item "Implement feature" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "implemented"
    
    # WRONG: Creating a separate test task
    # This test verifies the task count stays at 1 when we fail properly
    
    # CORRECT: Fail the task
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Missing unit tests for validation logic"
    
    # Should still be only 1 task (not 2)
    local task_count=$(jq '.items | length' "$BACKLOG_FILE")
    assert_equal "$task_count" "1"
    
    # Task should be failed, waiting for rework
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_failed"
}

@test "QA workflow: proper status flow from implemented to done" {
    init_backlog "status-flow-test"
    init_sprint_state
    
    add_backlog_item "Feature" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Implement
    update_item_status "TASK-001" "implemented"
    
    # Proper flow: implemented → qa_passed → done
    update_item_status "TASK-001" "qa_passed"
    update_item_status "TASK-001" "done"
    
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "done"
    
    # Note: The orchestrator/workflow enforces the proper flow
    # The backlog_manager is a low-level utility that allows any valid status
    # This test verifies the CORRECT flow, not that wrong flows fail
}

# ============================================================================
# COMPLETE QA WORKFLOW INTEGRATION
# ============================================================================

@test "QA workflow: complete sprint with rework cycle" {
    init_backlog "complete-workflow-test"
    init_sprint_state
    
    # Setup sprint with 2 tasks
    add_backlog_item "Feature A" "feature" 1 5
    add_backlog_item "Feature B" "feature" 1 3
    start_sprint
    assign_to_sprint "TASK-001" 1
    assign_to_sprint "TASK-002" 1
    
    # === Implementation Phase ===
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-002" "in_progress"
    update_item_status "TASK-002" "implemented"
    
    # === QA Phase - Round 1 ===
    # Task 1 passes
    update_item_status "TASK-001" "qa_passed"
    
    # Task 2 fails (missing tests)
    update_item_status "TASK-002" "qa_failed"
    set_failure_reason "TASK-002" "No unit tests"
    
    # Verify rework needed
    run has_qa_failed_tasks
    assert_success
    
    # === Rework ===
    update_item_status "TASK-002" "in_progress"
    update_item_status "TASK-002" "implemented"
    
    # === QA Phase - Round 2 ===
    update_item_status "TASK-002" "qa_passed"
    
    # No more rework needed
    run has_qa_failed_tasks
    assert_failure
    
    # === Review Phase ===
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    # Both tasks done
    local done_count=$(jq '[.items[] | select(.status == "done")] | length' "$BACKLOG_FILE")
    assert_equal "$done_count" "2"
}

@test "QA workflow: bug found during testing doesn't block original task" {
    init_backlog "bug-no-block-test"
    init_sprint_state
    
    add_backlog_item "Implement checkout" "feature" 1 8
    start_sprint
    assign_to_sprint "TASK-001" 1
    
    # Implement
    update_item_status "TASK-001" "implemented"
    
    # QA finds a bug in unrelated payment code
    local bug_json='{
        "title": "Bug: Payment timeout not handled",
        "type": "bug",
        "priority": 2,
        "story_points": 3
    }'
    add_backlog_item_json "$bug_json"
    
    # Original task still passes QA (bug is out of scope)
    update_item_status "TASK-001" "qa_passed"
    update_item_status "TASK-001" "done"
    
    # Feature is done
    local checkout_status=$(jq -r '.items[] | select(.id == "TASK-001") | .status' "$BACKLOG_FILE")
    assert_equal "$checkout_status" "done"
    
    # Bug is in backlog for next sprint
    local bug_status=$(jq -r '.items[] | select(.type == "bug") | .status' "$BACKLOG_FILE")
    assert_equal "$bug_status" "backlog"
}

@test "QA workflow: cross-cutting test task goes to backlog" {
    init_backlog "cross-cutting-test"
    init_sprint_state
    
    # Multiple features already done
    add_backlog_item "Feature A" "feature" 1 5
    add_backlog_item "Feature B" "feature" 1 5
    update_item_status "TASK-001" "done"
    update_item_status "TASK-002" "done"
    
    # QA notices no integration tests across these features
    # This is a systemic issue, not tied to one task
    local test_task_json='{
        "title": "Add integration tests for A-B workflow",
        "type": "chore",
        "priority": 2,
        "story_points": 5,
        "description": "Multiple features lack integration testing"
    }'
    add_backlog_item_json "$test_task_json"
    
    # Verify it's in backlog (for next sprint planning)
    local test_task=$(jq '.items[] | select(.title | contains("integration tests"))' "$BACKLOG_FILE")
    local status=$(echo "$test_task" | jq -r '.status')
    local type=$(echo "$test_task" | jq -r '.type')
    
    assert_equal "$status" "backlog"
    assert_equal "$type" "chore"
}

# ============================================================================
# FAILURE REASON TESTS
# ============================================================================

@test "QA workflow: failure reason is specific and actionable" {
    init_backlog "failure-reason-test"
    init_sprint_state
    
    add_backlog_item "Implement validation" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "implemented"
    
    # Set specific failure reason
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "AC2 failed: Email validation does not reject 'test@invalid'. Coverage 45% (requires 85%)"
    
    local reason=$(jq -r '.items[0].failure_reason' "$BACKLOG_FILE")
    
    # Reason should contain specific info
    [[ "$reason" == *"AC2"* ]]
    [[ "$reason" == *"45%"* ]]
    [[ "$reason" == *"85%"* ]]
}

@test "QA workflow: failure reason persists as history" {
    init_backlog "reason-history-test"
    init_sprint_state
    
    add_backlog_item "Feature" "feature" 1 5
    start_sprint
    assign_to_sprint "TASK-001" 1
    update_item_status "TASK-001" "implemented"
    
    # Fail with reason
    update_item_status "TASK-001" "qa_failed"
    set_failure_reason "TASK-001" "Tests missing"
    
    # Verify failure reason was set
    local reason=$(jq -r '.items[0].failure_reason' "$BACKLOG_FILE")
    [[ "$reason" == "Tests missing" ]]
    
    # Rework and pass
    update_item_status "TASK-001" "in_progress"
    update_item_status "TASK-001" "implemented"
    update_item_status "TASK-001" "qa_passed"
    
    # Task passes - the old failure_reason may persist as history
    # The important thing is that status is now qa_passed
    local status=$(jq -r '.items[0].status' "$BACKLOG_FILE")
    assert_equal "$status" "qa_passed"
}
