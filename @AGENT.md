# Sprinty Agent Build Instructions

## Project Overview
Sprinty is a sprint-based software development orchestrator that uses cursor-agent to execute different roles (Product Owner, Developer, QA) in phases.

## Project Structure
```
sprinty/
├── sprinty.sh                 # ✅ Main orchestrator (entry point)
├── lib/
│   ├── utils.sh               # ✅ Logging, date functions
│   ├── circuit_breaker.sh     # ✅ Halt on repeated failures
│   ├── rate_limiter.sh        # ✅ API call management
│   ├── backlog_manager.sh     # ✅ Backlog CRUD operations
│   ├── sprint_manager.sh      # ✅ Sprint state management
│   ├── agent_adapter.sh       # ✅ cursor-agent integration
│   ├── done_detector.sh       # ✅ Completion detection
│   └── metrics_collector.sh   # ✅ Burndown, velocity, dashboard
├── prompts/
│   ├── product_owner.md       # ✅ PO agent prompt
│   ├── developer.md           # ✅ Developer agent prompt
│   └── qa.md                  # ✅ QA agent prompt
├── templates/
│   └── config.json            # ✅ Default configuration
└── tests/unit/                # TODO: Unit tests (bats)
```

## Dependencies
- **bash** >= 4.0
- **jq** - JSON processing (required)
- **cursor-agent** - AI agent CLI (for orchestration)
- **bats** - Testing framework (optional, for tests)

## Running Sprinty
```bash
# Initialize a new project
./sprinty.sh init my-project --prd docs/PRD.md

# Run sprint loop
./sprinty.sh run

# Check status
./sprinty.sh status
./sprinty.sh status --check-done

# Backlog management
./sprinty.sh backlog list
./sprinty.sh backlog add "Implement feature" --type feature --points 5

# Show metrics
./sprinty.sh metrics

# Reset circuit breaker (if halted)
./sprinty.sh --reset-circuit

# Show help
./sprinty.sh --help
```

## Running Tests
```bash
# Syntax check all modules
for f in lib/*.sh; do bash -n "$f" && echo "$f OK"; done
for f in sprinty.sh; do bash -n "$f" && echo "$f OK"; done

# Run unit tests (when available)
bats tests/unit/

# Manual smoke test
source lib/utils.sh
source lib/backlog_manager.sh
source lib/sprint_manager.sh
init_backlog "test-project"
add_backlog_item "Test task" "feature" 1 3
list_backlog
```

## Key Modules

### sprinty.sh (Main Orchestrator)
Entry point for Sprinty. Orchestrates the entire sprint workflow.
```bash
# CLI Commands
./sprinty.sh init <project> --prd <file>   # Initialize project
./sprinty.sh run                           # Run sprint loop
./sprinty.sh status [--check-done]         # Show status
./sprinty.sh backlog list                  # List backlog items
./sprinty.sh backlog add <title> [opts]    # Add backlog item
./sprinty.sh metrics                       # Show metrics
./sprinty.sh --reset-circuit               # Reset circuit breaker
./sprinty.sh --help                        # Show help
```

### lib/utils.sh
Core utilities: logging, date functions, JSON helpers.
```bash
source lib/utils.sh
log_status "INFO" "Hello from Sprinty"
get_iso_timestamp  # Returns ISO 8601 timestamp
```

### lib/backlog_manager.sh
Backlog CRUD operations using jq.
```bash
source lib/utils.sh
source lib/backlog_manager.sh
init_backlog "my-project"
task_id=$(add_backlog_item "Implement login" "feature" 1 5)
update_item_status "$task_id" "in_progress"
list_backlog
```

### lib/sprint_manager.sh
Sprint state management.
```bash
source lib/utils.sh
source lib/backlog_manager.sh
source lib/sprint_manager.sh
init_sprint_state
start_sprint
set_current_phase "implementation"
show_sprint_status
```

### lib/circuit_breaker.sh
Prevents runaway execution when no progress is detected.
```bash
source lib/utils.sh
source lib/circuit_breaker.sh
init_circuit_breaker
record_loop_result 1 5 "false" 1000  # files_changed=5, no errors
show_circuit_status
```

### lib/rate_limiter.sh
API call rate limiting.
```bash
source lib/utils.sh
source lib/rate_limiter.sh
init_rate_limiter
can_make_call && increment_call_counter
show_rate_limit_status
```

### lib/agent_adapter.sh
Cursor-agent CLI integration for executing AI agents.
```bash
source lib/utils.sh
source lib/agent_adapter.sh
check_cursor_agent_installed
init_cursor_project_config
print_agent_status

# Generate prompt for a role/phase
prompt_file=$(generate_prompt "developer" "implementation" 1)

# Execute agent
run_agent "developer" "implementation" 1

# Parse response
output=$(get_last_agent_output)
status_json=$(parse_sprinty_status_to_json "$output")
```

### lib/done_detector.sh
Completion detection and graceful exit logic.
```bash
source lib/utils.sh
source lib/backlog_manager.sh
source lib/done_detector.sh
init_exit_signals

# Check if project should exit gracefully
exit_reason=$(should_exit_gracefully)
if [[ -n "$exit_reason" ]]; then
    echo "Ready to exit: $exit_reason"
fi

# Check project completion criteria
if is_project_complete; then
    echo "Project is complete!"
fi

# Record signals from agent execution
record_done_signal 5 "agent_response"
analyze_output_for_completion "$output_file" 5

# Show exit detection status
show_exit_status
```

### lib/metrics_collector.sh
Sprint metrics, burndown charts, and velocity tracking.
```bash
source lib/utils.sh
source lib/backlog_manager.sh
source lib/sprint_manager.sh
source lib/metrics_collector.sh

# Calculate burndown for current sprint
burndown=$(calculate_burndown)
echo "$burndown" | jq '.completion_percentage'

# Calculate team velocity
velocity=$(calculate_velocity 5)  # Last 5 sprints
echo "$velocity" | jq '.average_velocity'

# Get sprint summary
summary=$(get_sprint_summary)
echo "$summary" | jq '.health_score'

# Get overall project metrics
project=$(get_project_metrics)
echo "$project" | jq '.completion_percentage'

# Record sprint velocity after sprint ends
record_sprint_velocity 1 15 20  # sprint 1, 15 done, 20 planned

# Display functions
show_burndown_chart          # ASCII burndown chart
show_velocity_metrics        # Velocity stats
show_metrics_dashboard       # Full dashboard

# Save metrics snapshot
save_metrics_snapshot
```

## Configuration
Default configuration is in `templates/config.json`. Copy to `.sprinty/config.json` for project-specific settings.

Key settings:
- `sprint.max_sprints`: Maximum number of sprints (default: 10)
- `sprint.default_capacity`: Story points per sprint (default: 20)
- `rate_limiting.max_calls_per_hour`: API call limit (default: 100)

## Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 10 | Circuit breaker opened |
| 20 | Project complete |
| 21 | Max sprints reached |

## Development Guidelines
1. **Use jq for JSON** - All data manipulation uses jq
2. **Source dependencies** - Always source utils.sh first
3. **Atomic writes** - Use temp files + mv for JSON updates
4. **Status block required** - All agent responses need SPRINTY_STATUS
5. **Copy patterns** - Follow ralph-cursor-agent patterns

## Key Learnings
- Cross-platform date handling requires checking `uname` for BSD vs GNU
- Circuit breaker prevents infinite loops when agent makes no progress
- Rate limiter uses hourly windows with automatic reset
- Backlog manager validates status transitions
- Sprint manager tracks phase-specific loop counts
- Done detector tracks multiple signals for graceful exit (idle loops, done signals, completion indicators)
- Exit conditions only trigger if no remaining work in @fix_plan.md
- Rework loop allows up to 3 implementation→QA cycles per sprint

## Feature Development Quality Standards

### Testing Requirements
- Syntax validation: `bash -n lib/module.sh`
- Functional tests: Use bats framework
- Integration tests: Test module combinations

### Git Workflow
- Commit after completing each module
- Use conventional commits: `feat:`, `fix:`, `docs:`
- Update @fix_plan.md with progress

## Next Steps
1. ~~Create `lib/agent_adapter.sh` for cursor-agent integration~~ ✅
2. ~~Create agent prompts in `prompts/`~~ ✅
3. ~~Create `lib/done_detector.sh` for completion detection~~ ✅
4. ~~Create main orchestrator `sprinty.sh`~~ ✅
5. ~~Create `lib/metrics_collector.sh` for sprint metrics~~ ✅
6. Add unit tests (bats)
7. Create README.md documentation
