#!/usr/bin/env bash
# Test runner for resume functionality tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Sprinty Resume Tests - Test Runner                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error: bats is not installed${NC}"
    echo ""
    echo "Install bats:"
    echo "  git clone https://github.com/bats-core/bats-core.git /tmp/bats"
    echo "  cd /tmp/bats"
    echo "  ./install.sh ~/.local"
    echo ""
    exit 1
fi

# Track results
total_tests=0
passed_tests=0
failed_tests=0

# Run unit tests
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Running Unit Tests${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

if [[ -f "$SCRIPT_DIR/unit/test_resume.bats" ]]; then
    if bats "$SCRIPT_DIR/unit/test_resume.bats"; then
        echo -e "${GREEN}✓ Unit tests passed${NC}"
        ((passed_tests++))
    else
        echo -e "${RED}✗ Unit tests failed${NC}"
        ((failed_tests++))
    fi
    ((total_tests++))
else
    echo -e "${YELLOW}⚠ Unit test file not found: test_resume.bats${NC}"
fi

echo ""

# Run integration tests
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Running Integration Tests${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

if [[ -f "$SCRIPT_DIR/integration/test_resume_workflow.bats" ]]; then
    if bats "$SCRIPT_DIR/integration/test_resume_workflow.bats"; then
        echo -e "${GREEN}✓ Integration tests passed${NC}"
        ((passed_tests++))
    else
        echo -e "${RED}✗ Integration tests failed${NC}"
        ((failed_tests++))
    fi
    ((total_tests++))
else
    echo -e "${YELLOW}⚠ Integration test file not found: test_resume_workflow.bats${NC}"
fi

echo ""

# Run manual test (optional)
if [[ "$1" == "--manual" || "$1" == "-m" ]]; then
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Running Manual Integration Test${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ -f "$SCRIPT_DIR/manual_test_resume.sh" ]]; then
        if bash "$SCRIPT_DIR/manual_test_resume.sh"; then
            echo -e "${GREEN}✓ Manual test passed${NC}"
            ((passed_tests++))
        else
            echo -e "${RED}✗ Manual test failed${NC}"
            ((failed_tests++))
        fi
        ((total_tests++))
    else
        echo -e "${YELLOW}⚠ Manual test file not found${NC}"
    fi
    
    echo ""
fi

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   TEST SUMMARY                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "Total test suites: $total_tests"
echo -e "Passed: ${GREEN}$passed_tests${NC}"
echo -e "Failed: ${RED}$failed_tests${NC}"
echo ""

if [[ $failed_tests -eq 0 ]]; then
    echo -e "${GREEN}✓ All resume tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    exit 1
fi
