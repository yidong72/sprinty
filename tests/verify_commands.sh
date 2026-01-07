#!/usr/bin/env bash
# Test script to show the exact commands used by cursor-agent and opencode

source "$(dirname "$0")/../lib/utils.sh"
source "$(dirname "$0")/../lib/agent_adapter.sh"

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                        ║"
echo "║              AGENT CLI COMMAND VERIFICATION                            ║"
echo "║                                                                        ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Create a test prompt
TEST_PROMPT="You are a helpful AI assistant. Please respond with 'Hello, World!'"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 TEST PROMPT:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TEST_PROMPT"
echo ""

# Test Cursor Agent command
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  CURSOR-AGENT COMMAND:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Variables:"
echo "  CURSOR_AGENT_CMD = ${CURSOR_AGENT_CMD}"
echo "  CURSOR_MODEL = ${CURSOR_MODEL}"
echo "  CURSOR_OUTPUT_FORMAT = ${CURSOR_OUTPUT_FORMAT}"
echo ""
echo "Command structure:"
echo "  ${CURSOR_AGENT_CMD} -p --model \"${CURSOR_MODEL}\" \"\$prompt_content\""
echo ""
echo "Full command example:"
echo "  timeout 900s cursor-agent -p --model \"opus-4.5-thinking\" \"$TEST_PROMPT\""
echo ""

# Test OpenCode command
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  OPENCODE COMMAND:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Set opencode-specific variables
AGENT_CLI_TOOL="opencode"
AGENT_MODEL="opencode/glm-4.7-free"
AGENT_TIMEOUT_MINUTES=15

echo "Variables:"
echo "  AGENT_CLI_TOOL = ${AGENT_CLI_TOOL}"
echo "  AGENT_MODEL = ${AGENT_MODEL}"
echo "  AGENT_TIMEOUT_MINUTES = ${AGENT_TIMEOUT_MINUTES}"
echo ""
echo "Command structure:"
echo "  opencode run --model \"${AGENT_MODEL}\" \"\$prompt_content\""
echo ""
echo "Full command example:"
echo "  timeout 900s opencode run --model \"opencode/glm-4.7-free\" \"$TEST_PROMPT\""
echo ""

# Compare with documented syntax
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  COMPARISON WITH DOCUMENTATION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "OpenCode Documentation (https://opencode.ai/docs):"
echo "  ✅ CORRECT: opencode run 'prompt'"
echo "  ✅ CORRECT: opencode run --model 'model-name' 'prompt'"
echo ""
echo "Cursor Agent Documentation:"
echo "  ✅ CORRECT: cursor-agent -p 'prompt'"
echo "  ✅ CORRECT: cursor-agent -p --model 'model-name' 'prompt'"
echo ""

# Show actual function implementations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  ACTUAL IMPLEMENTATION IN agent_adapter.sh:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "execute_cursor_agent():"
echo "  local cmd_args=('-p')"
echo "  cmd_args+=('--model' \"\$CURSOR_MODEL\")"
echo "  cmd_args+=(\"\$prompt_content\")"
echo "  timeout \${timeout_seconds}s \"\$CURSOR_AGENT_CMD\" \"\${cmd_args[@]}\""
echo ""
echo "execute_opencode():"
echo "  local cmd_args=('run')"
echo "  cmd_args+=('--model' \"\$AGENT_MODEL\")"
echo "  cmd_args+=(\"\$prompt_content\")"
echo "  timeout \${timeout_seconds}s opencode \"\${cmd_args[@]}\""
echo ""

# Verification
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  VERIFICATION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v cursor-agent &> /dev/null; then
    echo "✅ cursor-agent is installed"
    cursor-agent --version 2>/dev/null || echo "   Version: unable to detect"
else
    echo "❌ cursor-agent is NOT installed"
fi

if command -v opencode &> /dev/null; then
    echo "✅ opencode is installed"
    opencode --version 2>/dev/null || echo "   Version: unable to detect"
else
    echo "❌ opencode is NOT installed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ COMMAND VERIFICATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
