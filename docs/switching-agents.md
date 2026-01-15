# How to Switch to Cursor Agent

There are multiple ways to switch from OpenCode to Cursor Agent in Sprinty.

---

## Method 1: Edit Configuration File (Recommended)

### Step 1: Install Cursor Agent

```bash
curl https://cursor.com/install -fsS | bash
```

Verify installation:
```bash
cursor-agent --version
```

### Step 2: Edit Your Project Configuration

Open your project's `.sprinty/config.json` file:

```bash
cd /path/to/your/project
nano .sprinty/config.json
```

Or use any text editor:
```bash
code .sprinty/config.json
vim .sprinty/config.json
```

### Step 3: Update the Agent Configuration

Change the `agent` section from:

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

To:

```json
{
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "opus-4.5-thinking",
    "timeout_minutes": 15,
    "output_format": "text"
  }
}
```

### Step 4: Save and Run

```bash
sprinty --container --workspace . --monitor run
```

---

## Method 2: Use Environment Variables (Temporary)

For a one-time switch without modifying the config file:

```bash
# Set the agent CLI tool
export AGENT_CLI_TOOL=cursor-agent
export AGENT_MODEL=opus-4.5-thinking

# Run sprinty
sprinty --container --workspace . --monitor run
```

This method is useful for:
- Testing cursor-agent before permanently switching
- Running one-off sprints with a different backend
- Keeping your config file unchanged

---

## Method 3: Quick Config Script

Create a helper script to switch quickly:

```bash
#!/bin/bash
# switch-to-cursor.sh

cat > .sprinty/config.json << 'EOF'
{
  "project": {
    "name": "$(jq -r '.project.name' .sprinty/config.json)",
    "description": "",
    "version": "1.0.0"
  },
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "opus-4.5-thinking",
    "timeout_minutes": 15,
    "output_format": "text"
  },
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
    "wait_between_calls_seconds": 5
  },
  "circuit_breaker": {
    "no_progress_threshold": 3,
    "same_error_threshold": 5,
    "output_decline_threshold": 70
  }
}
EOF

echo "✅ Switched to cursor-agent!"
```

Make it executable and run:
```bash
chmod +x switch-to-cursor.sh
./switch-to-cursor.sh
```

---

## Available Cursor Agent Models

When using cursor-agent, you can choose from these models:

```json
{
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "opus-4.5-thinking"     // Most capable (default)
  }
}
```

Or:

```json
{
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "sonnet-4.5"            // Faster, still very capable
  }
}
```

Or:

```json
{
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "haiku-4.0"             // Fastest, good for simple tasks
  }
}
```

---

## Verification

After switching, verify the configuration:

```bash
# Check which agent is configured
cat .sprinty/config.json | jq '.agent'
```

Expected output:
```json
{
  "cli_tool": "cursor-agent",
  "model": "opus-4.5-thinking",
  "timeout_minutes": 15,
  "output_format": "text"
}
```

---

## Testing the Switch

Test that cursor-agent is working:

```bash
# Quick test
cursor-agent -p --model opus-4.5-thinking "Say hello"

# Full sprinty test
cd your-project
sprinty status
sprinty --monitor run
```

---

## Switching Back to OpenCode

To switch back to OpenCode, simply reverse the process:

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

---

## Comparison: When to Use Each

### Use OpenCode When:
- ✅ Learning and experimenting
- ✅ No budget for API costs
- ✅ Personal projects
- ✅ Testing Sprinty features

### Use Cursor Agent When:
- ✅ Production projects
- ✅ Need highest quality output
- ✅ Faster response times required
- ✅ Have Cursor subscription or API budget

---

## Troubleshooting

### "cursor-agent: command not found"

Install cursor-agent:
```bash
curl https://cursor.com/install -fsS | bash
source ~/.bashrc  # or ~/.zshrc
```

### "Authentication failed"

Cursor Agent requires authentication. Options:
1. Use Cursor IDE (automatic authentication)
2. Set API key: `export CURSOR_API_KEY=your-key`

### Config file not updating

Make sure you're editing the right file:
```bash
# From project root
ls -la .sprinty/config.json

# If missing, reinitialize
sprinty init your-project --prd your-prd.md
```

---

## Example: Complete Switch

```bash
# 1. Install cursor-agent (if not installed)
curl https://cursor.com/install -fsS | bash

# 2. Navigate to your project
cd ~/projects/my-sprinty-project

# 3. Backup current config
cp .sprinty/config.json .sprinty/config.json.backup

# 4. Edit config
nano .sprinty/config.json
# Change "cli_tool": "opencode" to "cursor-agent"
# Change model to "opus-4.5-thinking"

# 5. Verify
cat .sprinty/config.json | jq '.agent'

# 6. Run
sprinty --container --workspace . --monitor run
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| **Edit config** | `nano .sprinty/config.json` |
| **View current agent** | `cat .sprinty/config.json \| jq '.agent'` |
| **Temporary switch** | `export AGENT_CLI_TOOL=cursor-agent` |
| **Test cursor-agent** | `cursor-agent --version` |
| **Run with cursor-agent** | `sprinty --monitor run` |

---

That's it! You can now easily switch between OpenCode and Cursor Agent based on your needs. 🚀
