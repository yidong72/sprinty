# Sprinty Fix Plan

## High Priority (Phase 1: Foundation - MVP)
- [x] Create `lib/utils.sh` - Copy `log_status()` from ralph-cursor-agent, add date functions
- [x] Create `lib/circuit_breaker.sh` - Copy from `../ralph-cursor-agent/lib/circuit_breaker.sh`
- [x] Create `lib/rate_limiter.sh` - Copy/adapt from ralph-cursor-agent pattern
- [x] Create `lib/backlog_manager.sh` - Implement CRUD functions:
  - [x] `add_backlog_item()` - Add item to backlog.json
  - [x] `update_item_status()` - Update task status using jq
  - [x] `get_sprint_backlog()` - Get tasks for a sprint
  - [x] `get_next_task_id()` - Generate TASK-XXX IDs
- [x] Create `lib/sprint_manager.sh` - Implement state functions:
  - [x] `start_sprint()` - Initialize new sprint
  - [x] `is_phase_complete()` - Check phase completion
  - [x] `has_qa_failed_tasks()` - Check for QA failures (via has_tasks_to_rework)
  - [x] `is_project_done()` - Check project completion (check_project_completion)
  - [x] `get_sprint_state()` / `update_sprint_state()` - State CRUD
- [x] Create `templates/config.json` - Default configuration template

## High Priority (Phase 2: Agent Integration)
- [x] Create `lib/agent_adapter.sh` - cursor-agent wrapper:
  - [x] `execute_cursor_agent()` - Execute with timeout
  - [x] `parse_agent_response()` - Extract SPRINTY_STATUS block (via parse_sprinty_status_to_json)
  - [x] `generate_prompt()` - Generate role-specific prompts
- [x] Create `prompts/product_owner.md` - PO agent prompt:
  - [x] Sprint 0: Parse PRD, create backlog with acceptance criteria
  - [x] Planning: Select tasks based on capacity
  - [x] Review: Accept/reject tasks, calculate metrics
- [x] Create `prompts/developer.md` - Developer agent prompt:
  - [x] Pick highest priority ready task
  - [x] Break down tasks >8 points
  - [x] Implement with unit tests (85% coverage)
  - [x] Update status flow
- [x] Create `prompts/qa.md` - QA agent prompt:
  - [x] Test each "implemented" task
  - [x] Verify acceptance criteria
  - [x] Pass/fail with reasons
  - [x] Create bug tasks for issues

## Medium Priority (Phase 3: Orchestration)
- [ ] Create `lib/done_detector.sh` - Completion detection logic
- [ ] Create `sprinty.sh` - Main orchestrator:
  - [ ] `main()` - Main loop with sprint phases
  - [ ] `init_sprinty()` - Initialize project
  - [ ] `execute_phase()` - Run agent for a phase
  - [ ] Implement rework loop (max 3 cycles)
  - [ ] Handle exit codes (0, 1, 10, 20, 21)
- [ ] Create `.sprinty/` directory structure:
  - [ ] `config.json` - Project configuration
  - [ ] `sprint_state.json` - Current sprint state

## Medium Priority (Phase 4: Metrics)
- [ ] Create `lib/metrics_collector.sh`:
  - [ ] `calculate_burndown()` - Sprint burndown data
  - [ ] `calculate_velocity()` - Team velocity metrics
  - [ ] `get_sprint_summary()` - Sprint statistics
- [ ] Add CLI dashboard output:
  - [ ] `sprinty status` - Show current state
  - [ ] `sprinty metrics` - Show burndown/velocity

## Low Priority (Phase 5: Polish)
- [ ] Add CLI commands to `sprinty.sh`:
  - [ ] `sprinty init <project> --prd <file>` - Initialize project
  - [ ] `sprinty run` - Run sprint loop
  - [ ] `sprinty status [--check-done]` - Show status
  - [ ] `sprinty backlog list` - List backlog items
  - [ ] `sprinty backlog add` - Add backlog item
- [ ] Create unit tests in `tests/unit/`:
  - [ ] `test_backlog_manager.bats`
  - [ ] `test_sprint_manager.bats`
  - [ ] `test_agent_adapter.bats`
  - [ ] `test_circuit_breaker.bats`
- [ ] Create `README.md` with usage documentation
- [ ] Create `@AGENT.md` with build/test instructions

## Completed
- [x] Project directory structure created
- [x] Created PROMPT.md for Ralph agent
- [x] Created @fix_plan.md task list
- [x] Created specs/requirements.md
- [x] Phase 1 Foundation - All lib modules created (utils, circuit_breaker, rate_limiter, backlog_manager, sprint_manager)
- [x] templates/config.json with default configuration
- [x] Phase 2 Agent Integration - agent_adapter.sh and all role prompts created

## Notes
- **Copy patterns from `../ralph-cursor-agent/`** - Don't reinvent
- **Use jq for all JSON operations** - backlog.json, config.json, sprint_state.json
- **Commit after each phase** - Track progress with git
- **Test as you go** - bats framework for bash tests
- **Status block required** - Every agent needs SPRINTY_STATUS output

## Implementation Order
1. Foundation (lib/*.sh) → commit
2. Agent Integration (prompts/*.md, adapter) → commit
3. Orchestration (sprinty.sh, done_detector) → commit
4. Metrics (metrics_collector) → commit
5. Polish (CLI, tests, docs) → commit
