# Multi-Agent CLI Backend Support - Implementation Summary

## Overview

Sprinty has been successfully refactored to support multiple AI agent CLI backends. The system now supports both **OpenCode** (default, free) and **Cursor Agent** (premium) with an extensible architecture for adding more backends in the future.

## Changes Made

### 1. Configuration Template (`templates/config.json`)

Added `agent.cli_tool` configuration:

```json
{
  "agent": {
    "cli_tool": "opencode",              // "opencode" or "cursor-agent"
    "model": "opencode/glm-4.7-free",    // Model to use
    "timeout_minutes": 15,
    "output_format": "text"
  }
}
```

**Default**: `opencode` with `opencode/glm-4.7-free` model (free, no API key required)

### 2. Agent Adapter Refactoring (`lib/agent_adapter.sh`)

#### Architecture

The agent adapter now uses a **3-layer architecture**:

```
┌─────────────────────────────────────────────────────┐
│  Abstraction Layer (public API)                     │
│  - check_agent_installed()                          │
│  - get_agent_version()                              │
│  - execute_agent()                                  │
│  - init_agent_project_config()                      │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
┌───────▼──────────┐  ┌──────▼────────────┐
│  Cursor Agent    │  │  OpenCode         │
│  Backend         │  │  Backend          │
│  - check_cursor  │  │  - check_opencode │
│  - execute_cursor│  │  - execute_opencode│
└──────────────────┘  └───────────────────┘
```

#### New Functions

**Abstraction Layer:**
- `detect_agent_cli_tool()` - Auto-detect from config
- `get_agent_model()` - Get model from config with smart defaults
- `get_agent_timeout()` - Get timeout from config
- `check_agent_installed()` - Check if configured agent is installed
- `get_agent_version()` - Get version of configured agent
- `check_agent_auth()` - Check authentication status
- `init_agent_project_config()` - Initialize project config
- `execute_agent()` - Execute agent with prompt file
- `execute_agent_raw()` - Execute agent with raw prompt string

**OpenCode Backend:**
- `check_opencode_installed()` - Check if opencode CLI is installed
- `get_opencode_version()` - Get opencode version
- `check_opencode_auth()` - Check opencode authentication
- `init_opencode_project_config()` - Initialize opencode project
- `execute_opencode()` - Execute opencode with prompt file
- `execute_opencode_raw()` - Execute opencode with raw prompt

**Cursor Agent Backend:**
- All existing cursor-agent functions preserved for backward compatibility

### 3. Main Script Update (`sprinty.sh`)

Changed from:
```bash
init_cursor_project_config "."
```

To:
```bash
init_agent_project_config "."
```

This automatically uses the correct backend based on configuration.

### 4. Documentation (`README.md`)

#### Added Sections:

1. **Prerequisites** - Updated to show both OpenCode and Cursor Agent options
2. **Choosing Your AI Agent Backend** - Complete guide with:
   - OpenCode setup (free, default)
   - Cursor Agent setup (premium)
   - Comparison table
   - Configuration examples
3. **Environment Variables** - Added agent-related variables:
   - `AGENT_CLI_TOOL`
   - `AGENT_MODEL`
   - `AGENT_TIMEOUT_MINUTES`
   - `OPENCODE_API_KEY`
   - `CURSOR_API_KEY`

### 5. Testing (`tests/unit/test_agent_backend_selection.bats`)

Created comprehensive test suite covering:
- Configuration detection
- Abstraction layer routing
- OpenCode backend functions
- Cursor Agent backward compatibility
- Integration tests

## Usage Examples

### Using OpenCode (Default)

```bash
# Install OpenCode
curl -fsSL https://opencode.ai/install | bash

# Initialize project (uses opencode by default)
sprinty init my-project --prd requirements.md

# Run
sprinty --container --workspace . --monitor run
```

### Using Cursor Agent

```bash
# Install Cursor Agent
npm install -g @anthropic/cursor-agent

# Initialize project
sprinty init my-project --prd requirements.md

# Update config to use cursor-agent
cat > .sprinty/config.json << 'EOF'
{
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

### Using Environment Variables

```bash
# Override agent backend temporarily
export AGENT_CLI_TOOL=cursor-agent
export AGENT_MODEL=sonnet-4.5

sprinty --monitor run
```

## Backward Compatibility

✅ **100% backward compatible** with existing installations:

1. **No config file**: Defaults to `cursor-agent` (previous behavior)
2. **Existing cursor-agent functions**: All preserved and exported
3. **Environment variables**: `CURSOR_*` variables still work
4. **Project configs**: `.cursor/cli.json` still created when needed

## Testing Results

All tests passed:

- ✅ Configuration detection (3 scenarios)
- ✅ Abstraction layer routing (both backends)
- ✅ OpenCode backend functions
- ✅ Cursor Agent backward compatibility
- ✅ Function exports (21 functions)
- ✅ Full initialization with opencode
- ✅ Manual cursor-agent configuration
- ✅ Main script loads without errors

## Benefits

1. **Free tier option**: OpenCode provides free AI agent execution
2. **Flexibility**: Easy to switch backends via config
3. **Extensibility**: Simple to add more backends (e.g., aider, gpt-engineer)
4. **No breaking changes**: Existing users unaffected
5. **Smart defaults**: Auto-detects correct models per backend

## Future Enhancements

Potential additions:
- Support for `aider` CLI
- Support for `gpt-engineer`
- Per-agent role configuration (different models for PO, Dev, QA)
- Model performance metrics and recommendations
- Auto-selection based on task complexity

## Files Modified

1. ✅ `templates/config.json` - Added agent configuration
2. ✅ `lib/agent_adapter.sh` - Complete refactor with abstraction layer
3. ✅ `sprinty.sh` - Updated to use abstracted functions
4. ✅ `README.md` - Comprehensive documentation update
5. ✅ `tests/unit/test_agent_backend_selection.bats` - New test suite

## Configuration Reference

### OpenCode (Default)

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

**Installation**: `curl -fsSL https://opencode.ai/install | bash`

### Cursor Agent

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

**Installation**: `npm install -g @anthropic/cursor-agent`

## Comparison

| Feature | OpenCode | Cursor Agent |
|---------|----------|--------------|
| **Cost** | ✅ Free | 💰 Requires API key |
| **Installation** | curl script | npm package |
| **Default Model** | `opencode/glm-4.7-free` | `opus-4.5-thinking` |
| **Speed** | Fast | Very fast |
| **API Key Required** | No (for free model) | Yes |
| **Best For** | Testing, learning, personal projects | Production, enterprise |

---

**Status**: ✅ Complete and tested
**Date**: 2026-01-06
**Version**: Sprinty 0.1.0
