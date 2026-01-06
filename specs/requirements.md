# Sprinty Technical Requirements

> **Version**: 2.1.0  
> **Target**: Bash shell script with cursor-agent integration

---

## 1. Overview

Sprinty is a sprint-based software development orchestrator that uses cursor-agent to execute different roles (Product Owner, Developer, QA) in phases.

### Core Loop
```
Sprint 0 (once): PRD → Backlog creation
Sprint 1-N (repeat):
  Planning → Implementation → QA → Review
  ↓
  PROJECT_DONE or next sprint
```

---

## 2. Data Schemas

### 2.1 backlog.json

```json
{
  "project": "project-name",
  "items": [
    {
      "id": "TASK-001",
      "title": "Task title",
      "type": "feature|bug|spike|infra",
      "priority": 1,
      "story_points": 5,
      "status": "backlog|ready|in_progress|implemented|qa_in_progress|qa_passed|qa_failed|done",
      "sprint_id": null,
      "acceptance_criteria": ["AC1", "AC2"],
      "dependencies": [],
      "parent_id": null,
      "subtasks": []
    }
  ],
  "metadata": {
    "total_items": 1,
    "total_points": 5
  }
}
```

### 2.2 .sprinty/config.json

```json
{
  "project": { "name": "my-project" },
  "sprint": {
    "max_sprints": 10,
    "default_capacity": 20,
    "planning_max_loops": 3,
    "implementation_max_loops": 20,
    "qa_max_loops": 5,
    "review_max_loops": 2,
    "max_rework_cycles": 3
  },
  "testing": {
    "unit_test_command": "npm test",
    "coverage_command": "npm run coverage"
  }
}
```

### 2.3 .sprinty/sprint_state.json

```json
{
  "current_sprint": 1,
  "current_phase": "implementation",
  "phase_loop_count": 0,
  "project_done": false
}
```

---

## 3. Task Status Flow

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

### Valid Status Transitions
- `backlog` → `ready` (selected for sprint)
- `ready` → `in_progress` (developer starts work)
- `in_progress` → `implemented` (code complete with tests)
- `implemented` → `qa_in_progress` (QA starts testing)
- `qa_in_progress` → `qa_passed` (all AC verified)
- `qa_in_progress` → `qa_failed` (AC not met)
- `qa_passed` → `done` (accepted in review)
- `qa_failed` → `in_progress` (rework cycle)

---

## 4. Agent Response Format

All agents MUST output this status block:

```
---SPRINTY_STATUS---
ROLE: developer
PHASE: implementation
SPRINT: 1
TASKS_COMPLETED: 1
TASKS_REMAINING: 2
BLOCKERS: none
STORY_POINTS_DONE: 5
TESTS_STATUS: PASSING
PHASE_COMPLETE: false
PROJECT_DONE: false
NEXT_ACTION: Continue with TASK-002
---END_SPRINTY_STATUS---
```

### Status Block Fields
| Field | Type | Description |
|-------|------|-------------|
| ROLE | string | Current role: product_owner, developer, qa |
| PHASE | string | Current phase: initialization, planning, implementation, qa, review |
| SPRINT | integer | Current sprint number (0 for initialization) |
| TASKS_COMPLETED | integer | Tasks completed this loop |
| TASKS_REMAINING | integer | Tasks still to be done |
| BLOCKERS | string | "none" or description of blocker |
| STORY_POINTS_DONE | integer | Story points completed this sprint |
| TESTS_STATUS | string | PASSING, FAILING, or NOT_RUN |
| PHASE_COMPLETE | boolean | true if phase is complete |
| PROJECT_DONE | boolean | true if all work is complete |
| NEXT_ACTION | string | Recommended next action |

---

## 5. Key Functions

### 5.1 Main Orchestrator (sprinty.sh)

```bash
main() {
    init_sprinty
    
    # Sprint 0: Create backlog from PRD
    if ! is_backlog_initialized; then
        execute_phase "initialization" "product_owner"
    fi
    
    # Sprint loop
    while ! is_project_done && [[ $sprint_count -lt $max_sprints ]]; do
        start_sprint
        execute_phase "planning" "product_owner"
        
        # Implementation + QA with rework loop
        while [[ $rework_count -lt $max_rework ]]; do
            execute_phase "implementation" "developer"
            execute_phase "qa" "qa"
            if ! has_qa_failed_tasks; then break; fi
            ((rework_count++))
        done
        
        execute_phase "review" "product_owner"
    done
}

execute_phase() {
    local phase=$1 role=$2
    while [[ $loop_count -lt $max_loops ]]; do
        if should_halt_execution; then return 1; fi
        if ! can_make_call; then wait_for_reset; continue; fi
        
        execute_agent "$(generate_prompt $role $phase)" "$role"
        
        if is_phase_complete "$phase"; then break; fi
        ((loop_count++))
    done
}
```

### 5.2 Backlog Manager (lib/backlog_manager.sh)

```bash
add_backlog_item() {
    # Add item to backlog.json using jq
}

update_item_status() {
    local id=$1 new_status=$2
    jq --arg id "$id" --arg status "$new_status" \
       '(.items[] | select(.id == $id)).status = $status' \
       backlog.json > tmp && mv tmp backlog.json
}

get_sprint_backlog() {
    local sprint_id=$1
    jq --argjson s "$sprint_id" '[.items[] | select(.sprint_id == $s)]' backlog.json
}

get_next_task_id() {
    local max=$(jq '[.items[].id | capture("TASK-(?<n>[0-9]+)").n | tonumber] | max // 0' backlog.json)
    printf "TASK-%03d" $((max + 1))
}
```

### 5.3 Sprint Manager (lib/sprint_manager.sh)

```bash
start_sprint() {
    local sprint_id=$(($(get_sprint_state current_sprint) + 1))
    update_sprint_state "current_sprint" "$sprint_id"
    update_sprint_state "current_phase" "planning"
    reset_circuit_breaker
}

is_phase_complete() {
    case "$1" in
        planning) [[ -f "sprints/sprint_${sprint_id}_plan.md" ]] ;;
        implementation)
            local remaining=$(jq '[.items[] | select(.sprint_id == '$sprint_id' and (.status == "ready" or .status == "in_progress"))] | length' backlog.json)
            [[ $remaining -eq 0 ]] ;;
        qa)
            local untested=$(jq '[.items[] | select(.sprint_id == '$sprint_id' and .status == "implemented")] | length' backlog.json)
            [[ $untested -eq 0 ]] ;;
        review) [[ -f "reviews/sprint_${sprint_id}_review.md" ]] ;;
    esac
}

has_qa_failed_tasks() {
    local count=$(jq '[.items[] | select(.status == "qa_failed")] | length' backlog.json)
    [[ $count -gt 0 ]]
}

is_project_done() {
    local undone=$(jq '[.items[] | select(.status != "done" and .status != "cancelled")] | length' backlog.json)
    local bugs=$(jq '[.items[] | select(.type == "bug" and .severity == "P1" and .status != "done")] | length' backlog.json)
    [[ $undone -eq 0 ]] && [[ $bugs -eq 0 ]]
}
```

### 5.4 Agent Adapter (lib/agent_adapter.sh)

```bash
execute_cursor_agent() {
    local prompt_file=$1 output_file=$2 timeout=${3:-900}
    timeout "$timeout" cursor-agent --prompt "$prompt_file" --output "$output_file"
}

parse_agent_response() {
    local output_file=$1
    sed -n '/---SPRINTY_STATUS---/,/---END_SPRINTY_STATUS---/p' "$output_file"
}
```

---

## 6. Agent Prompts

### 6.1 Product Owner (`prompts/product_owner.md`)
**Sprint 0 (Initialization)**:
- Parse PRD document
- Create backlog items with acceptance criteria
- Estimate story points
- Set priorities

**Planning Phase**:
- Select tasks for sprint based on capacity
- Move tasks from `backlog` to `ready`
- Create sprint plan document

**Review Phase**:
- Accept/reject completed tasks
- Move `qa_passed` to `done`
- Calculate sprint metrics
- Create review document

### 6.2 Developer (`prompts/developer.md`)
- Pick highest priority `ready` task
- Break down tasks >8 points into subtasks
- Implement with unit tests (85% coverage minimum)
- Update status: `ready` → `in_progress` → `implemented`

### 6.3 QA (`prompts/qa.md`)
- Test each `implemented` task
- Verify ALL acceptance criteria
- Pass: status → `qa_passed`
- Fail: status → `qa_failed`, set `failure_reason`
- Create bug tasks for new issues found

---

## 7. Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 10 | Circuit breaker opened |
| 20 | Project complete |
| 21 | Max sprints reached |

---

## 8. CLI Commands

```bash
# Initialize project
sprinty init my-project --prd specs/PRD.md

# Run sprints
sprinty run

# Check status
sprinty status
sprinty status --check-done

# Backlog management
sprinty backlog list
sprinty backlog add "Title" --type feature --points 5

# Metrics
sprinty metrics
```

---

## 9. Definition of Done

### Task Done
- [ ] Code implemented
- [ ] Unit tests pass (85%+ coverage)
- [ ] Acceptance criteria verified by QA
- [ ] Status = "done"

### Project Done
- [ ] All tasks status = "done"
- [ ] All tests pass
- [ ] No P1/P2 bugs open

---

## 10. Project Structure

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

---

## 11. Dependencies

- **bash** >= 4.0
- **jq** - JSON processing
- **cursor-agent** - AI agent CLI
- **bats** - Testing framework (optional)

---

## 12. Configuration Defaults

| Setting | Default | Description |
|---------|---------|-------------|
| max_sprints | 10 | Maximum sprints before forced exit |
| default_capacity | 20 | Story points per sprint |
| planning_max_loops | 3 | Max agent loops for planning |
| implementation_max_loops | 20 | Max agent loops for implementation |
| qa_max_loops | 5 | Max agent loops for QA |
| review_max_loops | 2 | Max agent loops for review |
| max_rework_cycles | 3 | Max implementation→QA rework cycles |
