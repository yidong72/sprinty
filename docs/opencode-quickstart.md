# Quick Start: Using OpenCode with Sprinty

## What is OpenCode?

OpenCode is a free, open-source AI agent CLI that provides code generation and execution capabilities. Sprinty now uses OpenCode as the default agent backend, making it accessible to everyone without requiring API keys or subscriptions.

## Installation

### 1. Install OpenCode

```bash
curl -fsSL https://opencode.ai/install | bash
source ~/.bashrc  # or ~/.zshrc
```

### 2. Verify Installation

```bash
opencode --version
```

### 3. Install Sprinty (if not already installed)

```bash
git clone https://github.com/your-username/sprinty.git
cd sprinty
./install.sh
```

## Usage

### Quick Start

```bash
# 1. Create your project directory
mkdir my-awesome-project
cd my-awesome-project

# 2. Create a Product Requirements Document
cat > PRD.md << 'EOF'
# My Awesome Project

## Requirements
- Create a CLI todo list application
- Support add, list, complete, and delete operations
- Store tasks in JSON format
- Include unit tests

## Acceptance Criteria
- All CRUD operations work correctly
- Tests pass with >80% coverage
- Code is well-documented
EOF

# 3. Initialize Sprinty
sprinty init my-awesome-project --prd PRD.md

# 4. Run autonomous development!
sprinty --container --workspace . --monitor run
```

### Configuration

Sprinty is pre-configured to use OpenCode. Your `.sprinty/config.json` will look like:

```json
{
  "agent": {
    "cli_tool": "opencode",
    "model": "opencode/glm-4.7-free",
    "timeout_minutes": 15,
    "output_format": "text"
  }
}
```

## Available Models

### Free Models (No API Key Required)

- `opencode/glm-4.7-free` (default) - Good balance of speed and quality

### Premium Models (Require API Key)

Check [OpenCode documentation](https://opencode.ai/docs) for available premium models.

To use premium models:

```bash
export OPENCODE_API_KEY="your-api-key"
```

Then update `.sprinty/config.json`:

```json
{
  "agent": {
    "cli_tool": "opencode",
    "model": "opencode/premium-model-name"
  }
}
```

## Monitoring Progress

With the `--monitor` flag, you'll see a split-screen tmux dashboard:

```
╔══════════════════════════════════════╗
║  Top: Real-time Status & Metrics     ║  ← Project progress
╠══════════════════════════════════════╣
║  Bottom: Agent Activity & Logs       ║  ← Live OpenCode execution
╚══════════════════════════════════════╝
```

- **Top pane**: Sprint status, burndown charts, velocity
- **Bottom pane**: OpenCode agent output in real-time

### Dashboard Controls

```bash
# Detach from dashboard (keeps running)
Ctrl+B, then D

# Reattach to dashboard
tmux attach

# Kill dashboard (stops execution)
tmux kill-session
```

## Checking Status

```bash
# Quick status check
sprinty status

# Detailed metrics
sprinty metrics

# Backlog view
sprinty backlog list
```

## Troubleshooting

### OpenCode Not Found

```bash
# Reinstall OpenCode
curl -fsSL https://opencode.ai/install | bash
source ~/.bashrc
```

### Model Timeout

If you experience timeouts, increase the timeout in config:

```json
{
  "agent": {
    "timeout_minutes": 30
  }
}
```

### Rate Limiting

OpenCode has built-in rate limiting. If you hit limits:

```bash
# Check status
sprinty status

# Wait for rate limit reset (shown in status)
# Or increase the limit in config
```

## Switching to Cursor Agent

If you prefer Cursor Agent (requires API key):

```bash
# Install Cursor Agent
curl https://cursor.com/install -fsS | bash

# Update your config
cat > .sprinty/config.json << 'EOF'
{
  "project": {...},
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "opus-4.5-thinking"
  },
  ...
}
EOF

# Run
sprinty --container --workspace . --monitor run
```

## Examples

### Web Application

```markdown
# E-commerce Store

## Requirements
- Product listing with search
- Shopping cart functionality
- User authentication
- Payment integration (mock for now)
- Responsive design
```

### CLI Tool

```markdown
# Password Manager CLI

## Requirements
- Encrypt/decrypt passwords
- Store in local database
- Generate strong passwords
- Copy to clipboard
- Master password protection
```

### Data Pipeline

```markdown
# Data ETL Pipeline

## Requirements
- Extract data from CSV files
- Transform with pandas
- Load into SQLite database
- Schedule with cron
- Error handling and logging
```

## Tips for Best Results

1. **Clear Requirements**: Be specific in your PRD
2. **Acceptance Criteria**: Include measurable success criteria
3. **Incremental Complexity**: Start simple, add features iteratively
4. **Monitor Progress**: Use `--monitor` to watch agents work
5. **Container Mode**: Always use `--container` for safety

## Getting Help

- 📖 [Full Documentation](../README.md)
- 🐛 [Report Issues](https://github.com/your-username/sprinty/issues)
- 💬 [Discussions](https://github.com/your-username/sprinty/discussions)
- 🌐 [OpenCode Docs](https://opencode.ai/docs)

---

**Ready to build?** Just create a PRD and let Sprinty + OpenCode handle the rest! 🚀
