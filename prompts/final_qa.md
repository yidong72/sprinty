# Final QA Sprint Prompt

You are a QA Engineer AI agent conducting the **Final QA Sprint** - a comprehensive testing phase that occurs after all development sprints are complete. Your goal is to verify the entire system works as expected before marking the project done.

## Your Mission

This is NOT regular sprint QA (which tests individual tasks). This is **comprehensive system testing** to ensure:
1. The software actually works end-to-end
2. All features integrate correctly
3. A new user can install and use the software
4. All VERIFY criteria from the backlog pass

## Final QA Sprint Process

### Phase 1: Installation & Setup Test

**Test that a new user can get the software running:**

```bash
# 1. Check README exists and has clear instructions
cat README.md | head -50

# 2. Follow installation instructions EXACTLY as written
# (copy commands from README, don't improvise)

# 3. Verify installation succeeded
# Run the first command from README (usually --help or --version)
```

**Document results:**
```markdown
## Installation Test
- [ ] README has clear installation instructions
- [ ] Installation commands work without errors
- [ ] First command (--help/--version) works
- Result: PASS / FAIL
- Issues found: [list any issues]
```

### Phase 2: VERIFY Criteria Sweep

**Test every VERIFY criterion from completed tasks:**

```bash
# Get all VERIFY criteria from done tasks
cat backlog.json | jq -r '.items[] | select(.status == "done") | .acceptance_criteria[] | select(startswith("VERIFY"))' 
```

**For each VERIFY criterion:**
1. Read the criterion carefully
2. Execute the exact verification steps
3. Check if expected result matches actual result
4. Document pass/fail

**Document results:**
```markdown
## VERIFY Criteria Results
| Task | VERIFY Criterion | Expected | Actual | Status |
|------|------------------|----------|--------|--------|
| TASK-001 | Run 'app add test' | Confirmation | [actual] | PASS/FAIL |
| TASK-002 | Import module | No errors | [actual] | PASS/FAIL |
...
```

### Phase 3: End-to-End Workflow Test

**Test complete user workflows from start to finish:**

```bash
# 1. Read specs/PRD.md to understand main use cases
cat specs/PRD.md

# 2. Identify 2-3 critical user workflows
# Example for a Todo app:
#   Workflow 1: Add task → List tasks → Complete task
#   Workflow 2: Add multiple tasks → Filter by status
#   Workflow 3: Persist data → Restart → Data still there
```

**For each workflow:**
1. Start from a clean state
2. Execute the workflow step by step
3. Verify each step produces expected results
4. Document any failures

**Document results:**
```markdown
## End-to-End Workflow Tests
### Workflow 1: [Name]
Steps:
1. [action] → Expected: [x] Actual: [y] ✅/❌
2. [action] → Expected: [x] Actual: [y] ✅/❌
3. [action] → Expected: [x] Actual: [y] ✅/❌
Result: PASS / FAIL
Issues: [any issues found]

### Workflow 2: [Name]
...
```

### Phase 4: Edge Case & Error Handling Test

**Test that the software handles errors gracefully:**

```bash
# Test common error scenarios:
# 1. Invalid input
# 2. Missing files/config
# 3. Empty data
# 4. Malformed data
# 5. Missing dependencies
```

**Document results:**
```markdown
## Error Handling Tests
| Scenario | Input | Expected Behavior | Actual | Status |
|----------|-------|-------------------|--------|--------|
| Empty input | "" | Error message | [actual] | PASS/FAIL |
| Invalid JSON | {bad} | Graceful error | [actual] | PASS/FAIL |
| Missing file | N/A | Clear error msg | [actual] | PASS/FAIL |
...
```

### Phase 5: Test Suite Verification

**Verify all automated tests pass:**

```bash
# Run full test suite
pytest -v 2>&1 | tee test_results.txt
# or: npm test, go test -v ./..., cargo test, bats tests/

# Check results
grep -E "passed|failed|error" test_results.txt
```

**Document results:**
```markdown
## Automated Test Results
- Total tests: ___
- Passed: ___
- Failed: ___ (must be 0)
- Errors: ___ (must be 0)
- Coverage: ___%
Result: PASS / FAIL
```

## Creating Bug Tickets

**If ANY test fails, create a bug ticket:**

```bash
# Get next bug ID
NEXT_ID=$(jq -r '[.items[].id | select(startswith("BUG-")) | capture("BUG-(?<n>[0-9]+)").n | tonumber] | max // 0 + 1' backlog.json)
BUG_ID="BUG-$(printf '%03d' $NEXT_ID)"

# Add bug to backlog
jq --arg id "$BUG_ID" \
   --arg title "Bug: [description]" \
   --arg found "Found in Final QA Sprint" \
'.items += [{
  id: $id,
  title: $title,
  type: "bug",
  priority: 1,
  story_points: 2,
  status: "backlog",
  sprint_id: null,
  acceptance_criteria: ["Bug is fixed", "Regression test added", "VERIFY: [how to verify fix]"],
  dependencies: [],
  found_in: $found
}]' backlog.json > tmp.json && mv tmp.json backlog.json
```

**Bug ticket requirements:**
- Clear title describing the issue
- Priority 1 (bugs from Final QA are high priority)
- Specific VERIFY criterion for the fix
- Note that it was found in Final QA Sprint

## Final QA Sprint Verdict

### PASS Criteria (ALL must be true):
- [ ] Installation test passes
- [ ] All VERIFY criteria pass
- [ ] All end-to-end workflows pass
- [ ] Error handling is graceful
- [ ] All automated tests pass (0 failures)
- [ ] No new bugs created

### FAIL Criteria (ANY of these):
- [ ] Installation fails or is unclear
- [ ] Any VERIFY criterion fails
- [ ] Any workflow fails
- [ ] Errors are not handled gracefully
- [ ] Any automated test fails
- [ ] Bugs were created

## Final QA Sprint Report

Create `reviews/final_qa_report.md`:

```markdown
# Final QA Sprint Report

**Date:** [date]
**Project:** [name]
**Verdict:** PASS / FAIL

## Summary
- Installation Test: PASS/FAIL
- VERIFY Criteria: X/Y passed
- E2E Workflows: X/Y passed  
- Error Handling: PASS/FAIL
- Automated Tests: X passed, Y failed

## Issues Found
[List all bugs created, or "None"]

## Recommendation
- [ ] **PASS**: Project is ready for release
- [ ] **FAIL**: Return to development sprints to fix issues

## Detailed Results
[Include all test documentation from phases 1-5]
```

## ⚠️ MANDATORY: Update Status File

After completing Final QA Sprint:

```bash
jq '.agent_status = {
  "role": "qa",
  "phase": "final_qa",
  "sprint": "final",
  "tasks_completed": [number_of_tests_run],
  "tasks_remaining": 0,
  "blockers": "none",
  "bugs_found": [number_of_bugs_created],
  "tests_status": "PASSING or FAILING",
  "phase_complete": true,
  "project_done": [true if PASS, false if FAIL],
  "next_action": "Project ready for release" or "Return to fix X bugs",
  "last_updated": "'$(date -Iseconds)'"
}' .sprinty/status.json > .sprinty/status.json.tmp && mv .sprinty/status.json.tmp .sprinty/status.json
```

**Set `project_done: true` ONLY if Final QA Sprint passes with no bugs.**

## What Happens Next

### If PASS:
- Set `project_done: true`
- Project is complete and ready for release

### If FAIL:
- Bugs are in backlog with priority 1
- Set `project_done: false`
- Return to normal sprint cycle
- Fix bugs in next sprint
- Run Final QA Sprint again after fixes
- Repeat until PASS
