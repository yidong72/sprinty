# Sprinty Development Instructions

## Context
You are an autonomous AI development agent building **Sprinty** - a sprint-based software development orchestrator that uses cursor-agent to execute different roles (Product Owner, Developer, QA) in phases.

## Reference Implementation
**REQUIRED**: Study these files from `../ralph-cursor-agent/` before implementing:
- `ralph_loop.sh` - Main loop pattern (copy this structure)
- `lib/circuit_breaker.sh` - Circuit breaker pattern (copy this)
- `lib/rate_limiter.sh` - Rate limiting pattern (adapt this)
- `templates/AGENT.md` - Prompt template patterns

## Current Objectives
1. Study `specs/requirements.md` to understand the full specification
2. Review `@fix_plan.md` for current priorities
3. Implement the highest priority item using best practices
4. Copy patterns from `../ralph-cursor-agent/` - don't reinvent
5. Use `jq` for all JSON manipulation
6. Run tests after each implementation
7. Update documentation and `@fix_plan.md`

## Key Principles
- **ONE task per loop** - focus on the most important thing
- **Copy, don't reinvent** - Use ralph-cursor-agent as reference
- **Use jq for JSON** - All data is in JSON files (backlog.json, sprint_state.json, config.json)
- **Status block required** - Every response MUST include SPRINTY_STATUS block
- **Commit after each phase** - Track progress with git commits
- **Test as you go** - Write unit tests (bats) for each module

## Sprinty Core Loop
```
Sprint 0 (once): PRD → Backlog creation
Sprint 1-N (repeat):
  Planning → Implementation → QA → Review
  ↓
  PROJECT_DONE or next sprint
```

## Task Status Flow
```
backlog → ready → in_progress → implemented → qa_in_progress
                       ↑                            │
                       │              ┌─────────────┴─────────────┐
                       │              ↓                           ↓
                       │         qa_passed → done            qa_failed
                       │                                          │
                       └──────────────────────────────────────────┘
                                    (rework)
```

## 🧪 Testing Guidelines (CRITICAL)
- LIMIT testing to ~20% of your total effort per loop
- PRIORITIZE: Implementation > Documentation > Tests
- Only write tests for NEW functionality you implement
- Use `bats` framework for bash unit tests
- Focus on CORE functionality first, comprehensive testing later

## Execution Guidelines
- Before making changes: review `../ralph-cursor-agent/` for patterns
- After implementation: run tests for the modified code only
- If tests fail: fix them as part of your current work
- Keep `@AGENT.md` updated with build/run instructions
- Document the WHY behind implementations
- No placeholder implementations - build it properly

## 🎯 Status Reporting (CRITICAL - Sprinty orchestrator needs this!)

**IMPORTANT**: At the end of your response, ALWAYS include this status block:

```
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 0
TASKS_COMPLETED: <number>
TASKS_REMAINING: <number>
BLOCKERS: none | <description>
STORY_POINTS_DONE: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
PHASE_COMPLETE: false | true
PROJECT_DONE: false | true
NEXT_ACTION: <one line summary of what to do next>
---END_SPRINTY_STATUS---
```

### When to set PROJECT_DONE: true
Set PROJECT_DONE to **true** when ALL of these conditions are met:
1. ✅ All items in `@fix_plan.md` are marked [x]
2. ✅ All tests are passing
3. ✅ No errors or warnings in the last execution
4. ✅ All requirements from `specs/requirements.md` are implemented
5. ✅ You have nothing meaningful left to implement

### When to set PHASE_COMPLETE: true
Set PHASE_COMPLETE to **true** when:
- All tasks for the current phase are done
- Ready to move to next phase (planning → implementation → qa → review)

### Examples of proper status reporting:

**Example 1: Foundation work in progress**
```
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 0
TASKS_COMPLETED: 2
TASKS_REMAINING: 5
BLOCKERS: none
STORY_POINTS_DONE: 8
TESTS_STATUS: PASSING
PHASE_COMPLETE: false
PROJECT_DONE: false
NEXT_ACTION: Implement lib/backlog_manager.sh CRUD functions
---END_SPRINTY_STATUS---
```

**Example 2: Phase complete**
```
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 1
TASKS_COMPLETED: 3
TASKS_REMAINING: 0
BLOCKERS: none
STORY_POINTS_DONE: 13
TESTS_STATUS: PASSING
PHASE_COMPLETE: true
PROJECT_DONE: false
NEXT_ACTION: Ready for QA phase
---END_SPRINTY_STATUS---
```

**Example 3: Blocked**
```
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 1
TASKS_COMPLETED: 0
TASKS_REMAINING: 2
BLOCKERS: cursor-agent CLI not installed
STORY_POINTS_DONE: 0
TESTS_STATUS: NOT_RUN
PHASE_COMPLETE: false
PROJECT_DONE: false
NEXT_ACTION: Need cursor-agent CLI installed to continue
---END_SPRINTY_STATUS---
```

### What NOT to do:
- ❌ Do NOT continue with busy work when PROJECT_DONE should be true
- ❌ Do NOT run tests repeatedly without implementing new features
- ❌ Do NOT refactor code that is already working fine
- ❌ Do NOT add features not in the specifications
- ❌ Do NOT forget to include the status block (Sprinty depends on it!)

## File Structure to Create
```
sprinty/
├── sprinty.sh                 # Main orchestrator (entry point)
├── lib/
│   ├── utils.sh               # log_status(), date functions
│   ├── circuit_breaker.sh     # Halt on repeated failures
│   ├── rate_limiter.sh        # API call management
│   ├── backlog_manager.sh     # Backlog CRUD operations
│   ├── sprint_manager.sh      # Sprint state management
│   ├── agent_adapter.sh       # cursor-agent integration
│   ├── metrics_collector.sh   # Burndown, velocity
│   └── done_detector.sh       # Completion detection
├── prompts/
│   ├── product_owner.md       # PO agent prompt
│   ├── developer.md           # Developer agent prompt
│   └── qa.md                  # QA agent prompt
├── templates/
│   └── config.json            # Default configuration
└── tests/
    └── unit/                  # Unit tests (bats)
```

## Exit Codes to Implement
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 10 | Circuit breaker opened |
| 20 | Project complete |
| 21 | Max sprints reached |

## Current Task
Follow `@fix_plan.md` and choose the most important item to implement next.
Use your judgment to prioritize what will have the biggest impact on project progress.
Study `../ralph-cursor-agent/` patterns before implementing.

Remember: Copy patterns, don't reinvent. Build it right the first time. Know when you're done.
