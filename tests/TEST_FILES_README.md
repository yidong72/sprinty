# Status.json Test Files Quick Reference

## Test Files Overview

```
tests/
├── unit/
│   ├── test_agent_status_management.bats     ← 29 tests: Status management API
│   └── test_agent_status_parsing.bats        ← 28 tests: Enhanced parsing
│
├── integration/
│   ├── test_status_json_workflow.bats        ← 18 tests: Full workflows
│   └── test_update_status_preservation.bats  ← 20 tests: Preservation logic
│
├── manual_test_file_based_status.sh          ← 11 tests: End-to-end
└── run_status_json_tests.sh                  ← Test runner (all tests)
```

## Quick Commands

### Run All Tests
```bash
./tests/run_status_json_tests.sh
```

### Run Specific Test File
```bash
# Unit tests
bats tests/unit/test_agent_status_management.bats
bats tests/unit/test_agent_status_parsing.bats

# Integration tests  
bats tests/integration/test_status_json_workflow.bats
bats tests/integration/test_update_status_preservation.bats

# Manual test
bash tests/manual_test_file_based_status.sh
```

### Run Single Test
```bash
# Run specific test by name
bats -f "update_agent_status updates single field" tests/unit/test_agent_status_management.bats
```

## Test File Details

### test_agent_status_management.bats (29 tests)

Tests functions in `lib/backlog_manager.sh`:
- init_agent_status (3)
- update_agent_status (6)
- get_agent_status_field (3)
- get_agent_status_json (2)
- is_phase_complete_from_status (3)
- is_project_done_from_status (3)
- Integration (9)

**Key Tests:**
- ✅ Creates agent_status when missing
- ✅ Updates single/multiple fields
- ✅ Handles booleans/numbers correctly
- ✅ Returns correct values
- ✅ Checks phase/project completion

### test_agent_status_parsing.bats (28 tests)

Tests functions in `lib/agent_adapter.sh`:
- parse_agent_status_enhanced (7)
- check_phase_complete_enhanced (3)
- check_project_done_enhanced (3)
- Strict mode enforcement (3)
- Error handling (2)
- Workflow scenarios (10)

**Key Tests:**
- ✅ Strict validation (role required)
- ✅ Fails when agent doesn't update
- ✅ Returns proper JSON structure
- ✅ Safety checks on backlog

### test_status_json_workflow.bats (18 tests)

Full workflow integration tests:
- Phase completions (5)
- Status preservation (1)
- Agent failures (2)
- Multi-agent (1)
- Edge cases (9)

**Key Tests:**
- ✅ All 5 phases complete correctly
- ✅ Multi-agent handoffs work
- ✅ Strict mode enforced
- ✅ Recovery from errors

### test_update_status_preservation.bats (20 tests)

Critical preservation logic tests:
- Preservation (7)
- Race conditions (2)
- Error recovery (2)
- Validation (3)
- Sequential updates (6)

**Key Tests:**
- ✅ Preserves all fields
- ✅ Survives multiple updates
- ✅ No race conditions
- ✅ Handles corrupted data

### manual_test_file_based_status.sh (11 tests)

End-to-end workflow test:
- Complete workflow (9)
- Strict mode (2)

**Key Tests:**
- ✅ Full agent workflow
- ✅ Status preservation
- ✅ Rejects empty role
- ✅ Accepts proper updates

## Test Results Expected

When all tests pass, you should see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TEST SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total test suites:  5
Passed:            5
Failed:            0

✅ ALL TESTS PASSED!
```

## Common Issues

### "bats: command not found"
```bash
# Install bats-core
sudo apt-get install bats      # Ubuntu/Debian
brew install bats-core          # macOS
```

### Tests fail with "function not found"
```bash
# Ensure test_helper.bash exists
ls tests/helpers/test_helper.bash

# Check it defines required functions
grep "setup_test_environment" tests/helpers/test_helper.bash
```

### JSON parse errors
```bash
# Verify jq is installed
jq --version

# Should be 1.6 or higher
```

## Test Development

### Adding New Tests

1. Choose appropriate file:
   - Unit test for single function → `test_agent_status_*.bats`
   - Integration test for workflow → `test_status_json_workflow.bats`

2. Follow naming convention:
   ```bash
   @test "function_name does what when condition" {
       # Arrange
       setup_data
       
       # Act
       run function_name args
       
       # Assert
       assert_success
       assert_output "expected"
   }
   ```

3. Use helpers:
   - `assert_success` / `assert_failure`
   - `assert_equal`
   - `assert_output`
   - `assert_file_exists`

## Continuous Integration

### Pre-commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit
./tests/run_status_json_tests.sh || exit 1
```

### GitHub Actions
```yaml
- name: Run Status.json Tests
  run: |
    sudo apt-get install -y bats
    ./tests/run_status_json_tests.sh
```

## Documentation

Full documentation: `docs/test-suite-documentation.md`

## Summary

**106 comprehensive tests** validate that status.json tracking works correctly from beginning to end with no logical flaws. All tests are ready to run with bats-core.
