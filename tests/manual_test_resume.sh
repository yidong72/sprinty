#!/usr/bin/env bash
# Manual integration test for resume functionality
# This script simulates kill and resume scenarios

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="/tmp/sprinty_resume_manual_test_$$"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Sprinty Resume Functionality - Manual Test            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test directory...${NC}"
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# Create test directory
echo -e "${BLUE}Setting up test environment...${NC}"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Create a simple PRD
cat > test.prd << 'EOF'
# Simple Todo CLI

Build a command-line todo list manager with the following features:
- Add tasks
- List tasks
- Mark tasks complete
- Remove tasks

Technology: Python 3
Testing: pytest with 85%+ coverage
EOF

# Test 1: Kill during implementation, resume
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST 1: Kill during implementation, verify resume${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

# Initialize
echo -e "${YELLOW}1. Initializing project...${NC}"
"$PROJECT_ROOT/sprinty.sh" init test-resume --prd test.prd

# Check initialization
if [[ -d .sprinty && -f backlog.json ]]; then
    echo -e "${GREEN}✓ Project initialized${NC}"
else
    echo -e "${RED}✗ Initialization failed${NC}"
    exit 1
fi

# Manually setup state to simulate mid-implementation
echo -e "${YELLOW}2. Simulating Sprint 1 mid-implementation state...${NC}"

# Create sprint state as if Sprint 1 implementation started
cat > .sprinty/sprint_state.json << 'SPRINT_EOF'
{
    "current_sprint": 1,
    "current_phase": "implementation",
    "phase_loop_count": 3,
    "rework_count": 0,
    "project_done": false,
    "sprints_history": [
        {
            "sprint": 0,
            "started_at": "2026-01-07T10:00:00Z",
            "ended_at": "2026-01-07T10:05:00Z",
            "status": "completed"
        },
        {
            "sprint": 1,
            "started_at": "2026-01-07T10:05:00Z",
            "status": "in_progress"
        }
    ],
    "created_at": "2026-01-07T10:00:00Z",
    "last_updated": "2026-01-07T10:15:00Z"
}
SPRINT_EOF

# Update backlog to simulate partial work
if [[ -f backlog.json ]]; then
    # Assign first 3 tasks to Sprint 1, mark some as implemented
    jq '
        (.items[0]).sprint_id = 1 | (.items[0]).status = "implemented" |
        (.items[1]).sprint_id = 1 | (.items[1]).status = "implemented" |
        (.items[2]).sprint_id = 1 | (.items[2]).status = "in_progress" |
        (.items[3]).sprint_id = 1 | (.items[3]).status = "ready"
    ' backlog.json > tmp.json && mv tmp.json backlog.json
fi

# Check state
echo -e "${YELLOW}3. Checking state files...${NC}"
echo -e "   Sprint: $(jq -r '.current_sprint' .sprinty/sprint_state.json)"
echo -e "   Phase: $(jq -r '.current_phase' .sprinty/sprint_state.json)"

# Count tasks by status
local implemented=$(jq '[.items[] | select(.status == "implemented")] | length' backlog.json)
local in_progress=$(jq '[.items[] | select(.status == "in_progress")] | length' backlog.json)
local ready=$(jq '[.items[] | select(.sprint_id == 1 and .status == "ready")] | length' backlog.json)

echo -e "   Tasks: ${implemented} implemented, ${in_progress} in progress, ${ready} ready"
echo -e "${GREEN}✓ State simulated${NC}"

# Test resume detection
echo -e "${YELLOW}4. Testing resume detection...${NC}"

# Source the resume function
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/backlog_manager.sh"
source "$PROJECT_ROOT/lib/sprint_manager.sh"
eval "$(sed -n '/^is_resuming_sprint()/,/^}/p' "$PROJECT_ROOT/sprinty.sh")"

export SPRINTY_DIR=".sprinty"
export BACKLOG_FILE="backlog.json"

if is_resuming_sprint; then
    echo -e "${GREEN}✓ Resume correctly detected!${NC}"
else
    echo -e "${RED}✗ Resume not detected (should be TRUE)${NC}"
    exit 1
fi

# Test 2: Fresh sprint detection
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST 2: Fresh sprint (no resume) detection${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

# Reset to Sprint 0 state
cat > .sprinty/sprint_state.json << 'SPRINT_EOF'
{
    "current_sprint": 0,
    "current_phase": "initialization",
    "phase_loop_count": 0,
    "rework_count": 0,
    "project_done": false,
    "created_at": "2026-01-07T10:00:00Z",
    "last_updated": "2026-01-07T10:00:00Z"
}
SPRINT_EOF

if is_resuming_sprint; then
    echo -e "${RED}✗ Resume detected (should be FALSE for Sprint 0)${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Fresh sprint correctly detected (no resume)${NC}"
fi

# Test 3: Planning with tasks (edge case)
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST 3: Planning phase with tasks assigned (edge case)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

# Set to Sprint 1 planning, but tasks already assigned
cat > .sprinty/sprint_state.json << 'SPRINT_EOF'
{
    "current_sprint": 1,
    "current_phase": "planning",
    "phase_loop_count": 0,
    "rework_count": 0,
    "project_done": false,
    "sprints_history": [
        {
            "sprint": 1,
            "started_at": "2026-01-07T10:05:00Z",
            "status": "in_progress"
        }
    ],
    "created_at": "2026-01-07T10:00:00Z",
    "last_updated": "2026-01-07T10:05:00Z"
}
SPRINT_EOF

# Ensure tasks are assigned to Sprint 1
jq '
    (.items[0]).sprint_id = 1 | (.items[0]).status = "ready" |
    (.items[1]).sprint_id = 1 | (.items[1]).status = "ready"
' backlog.json > tmp.json && mv tmp.json backlog.json

if is_resuming_sprint; then
    echo -e "${GREEN}✓ Resume detected (planning with tasks assigned)${NC}"
else
    echo -e "${RED}✗ Resume not detected (should be TRUE when tasks assigned)${NC}"
    exit 1
fi

# Test 4: All phases
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST 4: Resume detection for all phases${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

phases=("planning" "implementation" "qa" "review")
for phase in "${phases[@]}"; do
    # Set to Sprint 1, specific phase
    jq --arg phase "$phase" '.current_sprint = 1 | .current_phase = $phase' .sprinty/sprint_state.json > tmp && mv tmp .sprinty/sprint_state.json
    
    # Ensure tasks assigned (so planning phase with tasks is detected as resume)
    jq '(.items[0]).sprint_id = 1 | (.items[0]).status = "ready"' backlog.json > tmp.json && mv tmp.json backlog.json
    
    if is_resuming_sprint; then
        echo -e "${GREEN}✓ Resume detected for phase: $phase${NC}"
    else
        echo -e "${RED}✗ Resume not detected for phase: $phase${NC}"
        exit 1
    fi
done

# Test 5: State file validation
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST 5: State file integrity${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

# Verify all state files are valid JSON
files=(".sprinty/sprint_state.json" "backlog.json")
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        if jq empty "$file" 2>/dev/null; then
            echo -e "${GREEN}✓ Valid JSON: $file${NC}"
        else
            echo -e "${RED}✗ Invalid JSON: $file${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗ File missing: $file${NC}"
        exit 1
    fi
done

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   TEST SUMMARY                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ All tests passed!${NC}"
echo ""
echo "Tests executed:"
echo "  1. Mid-implementation resume detection"
echo "  2. Fresh sprint (no resume) detection"
echo "  3. Planning with tasks edge case"
echo "  4. Resume detection for all phases"
echo "  5. State file integrity validation"
echo ""
echo -e "${GREEN}Resume functionality is working correctly!${NC}"
echo ""

# Optional: Show how to use in real scenario
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}How to test with real execution:${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Start a real run:"
echo "   sprinty init my-project --prd my.prd"
echo "   sprinty run"
echo ""
echo "2. Kill it (Ctrl+C or kill) during implementation"
echo ""
echo "3. Check state:"
echo "   cat .sprinty/sprint_state.json | jq"
echo "   cat .sprinty/status.json | jq '.agent_status'"
echo ""
echo "4. Resume:"
echo "   sprinty run"
echo ""
echo "5. Check logs for:"
echo "   grep 'Resuming Sprint' logs/sprinty.log"
echo "   # Should see: 'Resuming Sprint N from phase: ...'"
echo ""
echo "6. Verify sprint number didn't change:"
echo "   cat .sprinty/sprint_state.json | jq '.current_sprint'"
echo ""
