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
- [ ] Create `lib/agent_adapter.sh` - cursor-agent wrapper:
  - [ ] `execute_cursor_agent()` - Execute with timeout
  - [ ] `parse_agent_response()` - Extract SPRINTY_STATUS block
  - [ ] `generate_prompt()` - Generate role-specific prompts
- [ ] Create `prompts/product_owner.md` - PO agent prompt:
  - [ ] Sprint 0: Parse PRD, create backlog with acceptance criteria
  - [ ] Planning: Select tasks based on capacity
  - [ ] Review: Accept/reject tasks, calculate metrics
- [ ] Create `prompts/developer.md` - Developer agent prompt:
  - [ ] Pick highest priority ready task
  - [ ] Break down tasks >8 points
  - [ ] Implement with unit tests (85% coverage)
  - [ ] Update status flow
- [ ] Create `prompts/qa.md` - QA agent prompt:
  - [ ] Test each "implemented" task
  - [ ] Verify acceptance criteria
  - [ ] Pass/fail with reasons
  - [ ] Create bug tasks for issues

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
