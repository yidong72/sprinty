# Sprinty

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-bash%204.0%2B-lightgrey)

> **Sprint-based Software Development Orchestrator for Cursor Agent CLI**

Sprinty is an autonomous development orchestrator that uses AI agents (via cursor-agent) to execute different roles (Product Owner, Developer, QA) through structured sprint cycles. It manages the complete software development lifecycle from requirements to delivery.

## 🎯 What is Sprinty?

Sprinty automates the agile development process by orchestrating AI agents through:

- **Sprint 0**: Product Owner parses PRD → Creates prioritized backlog with acceptance criteria
- **Sprint 1-N**: 
  - **Planning** → Product Owner selects tasks for sprint
  - **Implementation** → Developer implements features with tests
  - **QA** → QA agent verifies acceptance criteria
  - **Review** → Product Owner accepts/rejects completed work

The loop continues until all tasks are done or max sprints are reached.

## 📦 Features

- **🔄 Sprint-based Workflow** - Structured phases: Planning → Implementation → QA → Review
- **🤖 Multi-Agent Orchestration** - Product Owner, Developer, and QA roles
- **📋 Backlog Management** - Full CRUD operations with JSON storage
- **⚡ Rate Limiting** - Built-in API call management (default 100/hour)
- **🛡️ Circuit Breaker** - Prevents runaway loops with stagnation detection
- **📊 Metrics Dashboard** - Burndown charts, velocity tracking, health scores
- **🎯 Completion Detection** - Automatically detects when project is done
- **🔁 Rework Cycles** - QA failures trigger implementation rework (up to 3 cycles)

## 🚀 Quick Start

### Prerequisites

1. **Bash** >= 4.0
2. **jq** - JSON processor (required)
3. **cursor-agent** - Cursor Agent CLI
4. **git** - Version control

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/sprinty.git
cd sprinty

# Make executable
chmod +x sprinty.sh

# Optional: Add to PATH
ln -s "$(pwd)/sprinty.sh" /usr/local/bin/sprinty
```

### Basic Usage

```bash
# Initialize a new project
./sprinty.sh init my-project --prd docs/PRD.md

# Run the sprint loop
./sprinty.sh run

# Check current status
./sprinty.sh status

# View metrics dashboard
./sprinty.sh metrics
```

## 📖 CLI Commands

### Project Initialization

```bash
# Initialize with PRD
sprinty init <project-name> --prd <prd-file>

# Example
sprinty init shopping-cart --prd specs/PRD.md
```

### Sprint Execution

```bash
# Run in container sandbox (RECOMMENDED for safety)
sprinty --container --workspace . --monitor run

# Or with custom container image
sprinty --container python:3.12 --workspace ~/myproject --monitor run

# Run without container (use with caution)
sprinty --monitor run

# Check status
sprinty status
sprinty status --check-done   # Returns exit code 20 if done
```

### Container Mode (Recommended)

Running Sprinty in a container sandbox protects your host system:

```bash
# Basic containerized execution
sprinty --container --workspace /path/to/project run

# With custom Ubuntu version
sprinty --container ubuntu:22.04 --workspace . run

# With Python environment
sprinty --container python:3.12 --workspace . --monitor run

# With Node.js environment
sprinty --container node:20 --workspace . run
```

**Benefits of container mode:**
- 🛡️ Host system protected from destructive operations
- 🔧 AI agents can install any packages (apt, pip, npm)
- 🗑️ Agents can safely delete/modify files
- 🔄 Container resets on restart (only /workspace persists)

**Requirements:** Apptainer (`sudo apt install apptainer`)

### Backlog Management

```bash
# List all backlog items
sprinty backlog list

# Add new item
sprinty backlog add "Implement user login" --type feature --points 5

# Options:
#   --type       feature|bug|spike|infra|chore (default: feature)
#   --priority   1-5 (default: 1, lower = higher priority)
#   --points     Story points (default: 3)

# Show summary
sprinty backlog summary
```

### Metrics & Monitoring

```bash
# Full metrics dashboard
sprinty metrics

# Shows:
# - Sprint burndown (ASCII chart)
# - Velocity metrics
# - Project progress
# - Health score
```

### Troubleshooting

```bash
# Reset circuit breaker (if halted)
sprinty --reset-circuit

# Reset rate limiter
sprinty --reset-rate-limit

# Show help
sprinty --help

# Show version
sprinty --version
```

## 📁 Project Structure

```
my-project/
├── .sprinty/                   # Sprinty state (auto-created)
│   ├── config.json             # Project configuration
│   ├── sprint_state.json       # Current sprint state
│   └── status.json             # Execution status
├── backlog.json                # Product backlog
├── sprints/                    # Sprint plans (auto-created)
│   └── sprint_1_plan.md
├── reviews/                    # Sprint reviews (auto-created)
│   └── sprint_1_review.md
├── logs/                       # Execution logs
│   └── agent_output/
└── specs/
    └── PRD.md                  # Your product requirements
```

## 📊 Data Schemas

### backlog.json

```json
{
  "project": "my-project",
  "items": [
    {
      "id": "TASK-001",
      "title": "Implement feature X",
      "type": "feature",
      "priority": 1,
      "story_points": 5,
      "status": "backlog",
      "sprint_id": null,
      "acceptance_criteria": ["AC1", "AC2"],
      "dependencies": [],
      "created_at": "2026-01-06T10:00:00Z",
      "updated_at": "2026-01-06T10:00:00Z"
    }
  ],
  "metadata": {
    "total_items": 1,
    "total_points": 5
  }
}
```

### Task Status Flow

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

## ⚙️ Configuration

### .sprinty/config.json

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
  "rate_limiting": {
    "max_calls_per_hour": 100,
    "min_wait_between_calls_sec": 5
  },
  "circuit_breaker": {
    "max_consecutive_failures": 3,
    "max_consecutive_no_progress": 5
  }
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_CALLS_PER_HOUR` | 100 | API rate limit |
| `SPRINTY_DIR` | `.sprinty` | State directory |
| `BACKLOG_FILE` | `backlog.json` | Backlog location |

## 🚦 Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Normal completion |
| 1 | Error | General error |
| 10 | Circuit Breaker | Halted due to no progress |
| 20 | Project Done | All tasks completed |
| 21 | Max Sprints | Reached sprint limit |

## 🤖 Agent Prompts

Sprinty uses role-specific prompts in the `prompts/` directory:

- **product_owner.md** - PRD parsing, planning, review
- **developer.md** - Implementation with tests
- **qa.md** - Acceptance criteria verification

Each agent must output a status block:

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

## 🧪 Testing

```bash
# Run unit tests (requires bats)
bats tests/unit/

# Run specific test file
bats tests/unit/test_backlog_manager.bats

# Manual smoke test
source lib/utils.sh
source lib/backlog_manager.sh
init_backlog "test-project"
add_backlog_item "Test task" "feature" 1 3
list_backlog
```

## 📚 Modules

| Module | Description |
|--------|-------------|
| `lib/utils.sh` | Logging, date functions, JSON helpers |
| `lib/backlog_manager.sh` | Backlog CRUD operations |
| `lib/sprint_manager.sh` | Sprint state management |
| `lib/agent_adapter.sh` | cursor-agent integration |
| `lib/circuit_breaker.sh` | Runaway loop prevention |
| `lib/rate_limiter.sh` | API call rate limiting |
| `lib/done_detector.sh` | Completion detection |
| `lib/metrics_collector.sh` | Burndown, velocity metrics |

## 🔧 Development

### Adding New Features

1. Create/modify module in `lib/`
2. Export new functions
3. Source in `sprinty.sh`
4. Add tests in `tests/unit/`
5. Update documentation

### Conventions

- Use `jq` for all JSON operations
- Atomic writes: `file.tmp` + `mv`
- Always source `utils.sh` first
- Export functions that need to be accessible

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Inspired by [Ralph](https://ghuntley.com/ralph/) autonomous development technique
- Reference implementation: [ralph-cursor-agent](../ralph-cursor-agent)
- Built for [Cursor](https://cursor.com) Agent CLI

---

**Ready to start?** Run `sprinty init my-project --prd your-requirements.md` and let Sprinty handle the rest!
