#!/usr/bin/env bash
# Manual integration test for file-based status tracking
# This demonstrates that status.json tracking works end-to-end

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/backlog_manager.sh"
source "$PROJECT_ROOT/lib/agent_adapter.sh"
source "$PROJECT_ROOT/lib/done_detector.sh"

# Setup test environment
TEST_DIR="/tmp/sprinty_test_$$"
export SPRINTY_DIR="$TEST_DIR/.sprinty"
export BACKLOG_FILE="$TEST_DIR/backlog.json"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "======================================================================"
echo "File-Based Status Tracking Integration Test"
echo "======================================================================"

# Test 1: Initialize
echo ""
echo "=== Test 1: Initialize backlog and status ==="
init_backlog "test_project"
mkdir -p "$SPRINTY_DIR"

cat > "$SPRINTY_DIR/status.json" << 'EOF'
{
    "version": "0.1.0",
    "timestamp": "2026-01-07T12:00:00+00:00",
    "status": "running"
}
EOF

init_agent_status
echo "✓ Backlog and status initialized"
cat "$SPRINTY_DIR/status.json" | jq .agent_status

# Test 2: Add tasks
echo ""
echo "=== Test 2: Add tasks to backlog ==="
add_backlog_item "Implement login" "feature" 1 5 '["User can log in", "Password validation works"]'
add_backlog_item "Add tests" "chore" 1 3 '["Tests pass"]'
add_backlog_item "Deploy app" "infra" 2 2 '["App is live"]'
echo "✓ Added 3 tasks"
cat backlog.json | jq -r '.items[] | "\(.id): \(.title) - \(.status)"'

# Test 3: Simulate Developer updating status.json
echo ""
echo "=== Test 3: Developer marks task in_progress and updates status.json ==="
jq '(.items[] | select(.id == "TASK-001")).status = "in_progress"' backlog.json > tmp.json && mv tmp.json backlog.json

update_agent_status \
    "role" "developer" \
    "phase" "implementation" \
    "sprint" "1" \
    "tasks_completed" "0" \
    "tasks_remaining" "3" \
    "blockers" "none" \
    "phase_complete" "false" \
    "project_done" "false" \
    "next_action" "Started TASK-001"

echo "✓ Developer updated status.json"
echo "Backlog status:"
cat backlog.json | jq -r '.items[] | "\(.id): \(.status)"'
echo "Agent status:"
cat "$SPRINTY_DIR/status.json" | jq .agent_status | head -5

# Test 4: Check phase NOT complete
echo ""
echo "=== Test 4: Check phase complete (should be false) ==="
if is_phase_complete_from_status; then
    echo "✗ ERROR: Phase should NOT be complete"
    exit 1
else
    echo "✓ Phase is not complete (correct)"
fi

# Test 5: Developer completes task
echo ""
echo "=== Test 5: Developer completes task and updates status.json ==="
jq '(.items[] | select(.id == "TASK-001")).status = "implemented"' backlog.json > tmp.json && mv tmp.json backlog.json
jq '(.items[] | select(.id == "TASK-002")).status = "implemented"' backlog.json > tmp.json && mv tmp.json backlog.json
jq '(.items[] | select(.id == "TASK-003")).status = "implemented"' backlog.json > tmp.json && mv tmp.json backlog.json

update_agent_status \
    "role" "developer" \
    "phase" "implementation" \
    "sprint" "1" \
    "tasks_completed" "3" \
    "tasks_remaining" "0" \
    "blockers" "none" \
    "phase_complete" "true" \
    "project_done" "false" \
    "next_action" "All tasks implemented"

echo "✓ Developer completed all tasks"
echo "Backlog status:"
cat backlog.json | jq -r '.items[] | "\(.id): \(.status)"'

# Test 6: Check phase IS complete
echo ""
echo "=== Test 6: Check phase complete (should be true) ==="
if is_phase_complete_from_status; then
    echo "✓ Phase is complete (correct)"
else
    echo "✗ ERROR: Phase should be complete"
    exit 1
fi

# Test 7: QA phase
echo ""
echo "=== Test 7: QA marks tasks as qa_passed ==="
jq '(.items[] | select(.id == "TASK-001")).status = "qa_passed"' backlog.json > tmp.json && mv tmp.json backlog.json
jq '(.items[] | select(.id == "TASK-002")).status = "qa_passed"' backlog.json > tmp.json && mv tmp.json backlog.json
jq '(.items[] | select(.id == "TASK-003")).status = "qa_passed"' backlog.json > tmp.json && mv tmp.json backlog.json

update_agent_status \
    "role" "qa" \
    "phase" "qa" \
    "sprint" "1" \
    "tasks_completed" "3" \
    "tasks_remaining" "0" \
    "blockers" "none" \
    "phase_complete" "true" \
    "project_done" "false" \
    "next_action" "All tasks passed QA"

echo "✓ QA completed"

# Test 8: Product Owner marks project done
echo ""
echo "=== Test 8: Product Owner marks all tasks done ==="
jq '(.items[] | select(.status == "qa_passed")).status = "done"' backlog.json > tmp.json && mv tmp.json backlog.json

update_agent_status \
    "role" "product_owner" \
    "phase" "review" \
    "sprint" "1" \
    "tasks_completed" "3" \
    "tasks_remaining" "0" \
    "blockers" "none" \
    "phase_complete" "true" \
    "project_done" "true" \
    "next_action" "Project complete"

echo "✓ Product Owner marked project done"
echo "Final backlog status:"
cat backlog.json | jq -r '.items[] | "\(.id): \(.status)"'

# Test 9: Check project IS done
echo ""
echo "=== Test 9: Check project done (should be true) ==="
if is_project_done_from_status; then
    echo "✓ Project is done (correct)"
else
    echo "✗ ERROR: Project should be done"
    exit 1
fi

# Test 10: Enhanced parse (file-based priority)
echo ""
echo "=== Test 10: Test strict requirement - NO fallback to text ==="

# Create output with status in text but NOT in file
cat > /tmp/test_output.log << 'EOF'
Some agent output
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
PHASE_COMPLETE: true
PROJECT_DONE: false
---END_SPRINTY_STATUS---
EOF

# Clear status.json agent_status to empty values
jq '.agent_status = {
  "role": "",
  "phase": "",
  "phase_complete": false,
  "project_done": false
}' "$SPRINTY_DIR/status.json" > "$SPRINTY_DIR/status.json.tmp" && mv "$SPRINTY_DIR/status.json.tmp" "$SPRINTY_DIR/status.json"

# This should FAIL because role is empty (agent didn't update file)
set +e  # Allow command to fail
parsed=$(parse_agent_status_enhanced /tmp/test_output.log 2>&1)
parse_result=$?
set -e

if [[ $parse_result -ne 0 ]]; then
    echo "✓ Correctly REJECTS status when agent doesn't update status.json (strict mode)"
else
    echo "✗ ERROR: Should reject when status.json not updated by agent"
    echo "   No text-based fallback (strict mode)"
    exit 1
fi

# Test 11: Verify file MUST be updated
echo ""
echo "=== Test 11: Verify strict status.json requirement ==="

# Now properly update status.json
update_agent_status \
    "role" "developer" \
    "phase" "implementation" \
    "sprint" "1" \
    "phase_complete" "true" \
    "project_done" "false"

# Check directly from status file (bypass parse function for test)
role=$(cat "$SPRINTY_DIR/status.json" | jq -r '.agent_status.role')
phase_complete=$(cat "$SPRINTY_DIR/status.json" | jq -r '.agent_status.phase_complete')

if [[ "$role" == "developer" && "$phase_complete" == "true" ]]; then
    echo "✓ status.json properly updated with correct values"
else
    echo "✗ ERROR: status.json not properly updated"
    echo "   Got role='$role', phase_complete='$phase_complete'"
    exit 1
fi

# Now test that parse function reads it correctly
if check_phase_complete_enhanced /tmp/test_output.log 2>/dev/null; then
    echo "✓ Phase complete check works with updated status.json"
else
    echo "✗ ERROR: Phase complete check failed"
    exit 1
fi

echo ""
echo "======================================================================"
echo "✅ ALL TESTS PASSED!"
echo "======================================================================"
echo ""
echo "Summary:"
echo "  ✓ Status.json tracking works"
echo "  ✓ Phase completion detection works"
echo "  ✓ Project completion detection works"
echo "  ✓ Strict file-based requirement enforced (no fallback)"
echo "  ✓ Errors when agent doesn't update status.json"
echo ""
echo "File-based status tracking is working correctly with STRICT enforcement!"
