#!/usr/bin/env bash
# Test runner for status.json functionality
# Runs all unit and integration tests for file-based status tracking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Status.json Functionality Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${YELLOW}⚠ bats is not installed${NC}"
    echo ""
    echo "Please install bats-core:"
    echo "  Ubuntu/Debian: sudo apt-get install bats"
    echo "  macOS: brew install bats-core"
    echo "  From source: https://github.com/bats-core/bats-core"
    echo ""
    exit 1
fi

# Test counters
total_tests=0
passed_tests=0
failed_tests=0

# Run a test file
run_test_file() {
    local test_file=$1
    local test_name=$(basename "$test_file")
    
    echo -e "${BLUE}Running:${NC} $test_name"
    
    if bats "$test_file"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        echo ""
        passed_tests=$((passed_tests + 1))
        return 0
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        echo ""
        failed_tests=$((failed_tests + 1))
        return 1
    fi
}

# Unit tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  UNIT TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

unit_tests=(
    "$PROJECT_ROOT/tests/unit/test_agent_status_management.bats"
    "$PROJECT_ROOT/tests/unit/test_agent_status_parsing.bats"
)

for test_file in "${unit_tests[@]}"; do
    if [[ -f "$test_file" ]]; then
        total_tests=$((total_tests + 1))
        run_test_file "$test_file" || true
    else
        echo -e "${YELLOW}⚠ Test file not found: $test_file${NC}"
        echo ""
    fi
done

# Integration tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INTEGRATION TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

integration_tests=(
    "$PROJECT_ROOT/tests/integration/test_status_json_workflow.bats"
    "$PROJECT_ROOT/tests/integration/test_update_status_preservation.bats"
)

for test_file in "${integration_tests[@]}"; do
    if [[ -f "$test_file" ]]; then
        total_tests=$((total_tests + 1))
        run_test_file "$test_file" || true
    else
        echo -e "${YELLOW}⚠ Test file not found: $test_file${NC}"
        echo ""
    fi
done

# Manual integration test
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MANUAL INTEGRATION TEST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

manual_test="$PROJECT_ROOT/tests/manual_test_file_based_status.sh"
if [[ -f "$manual_test" ]]; then
    total_tests=$((total_tests + 1))
    echo -e "${BLUE}Running:${NC} manual_test_file_based_status.sh"
    
    if bash "$manual_test"; then
        echo -e "${GREEN}✓ Manual integration test passed${NC}"
        echo ""
        passed_tests=$((passed_tests + 1))
    else
        echo -e "${RED}✗ Manual integration test failed${NC}"
        echo ""
        failed_tests=$((failed_tests + 1))
    fi
else
    echo -e "${YELLOW}⚠ Manual test not found: $manual_test${NC}"
    echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total test suites:  $total_tests"
echo -e "Passed:            ${GREEN}$passed_tests${NC}"
echo -e "Failed:            ${RED}$failed_tests${NC}"
echo ""

if [[ $failed_tests -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo ""
    exit 1
fi
