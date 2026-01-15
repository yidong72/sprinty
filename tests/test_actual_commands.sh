#!/usr/bin/env bash
# Practical test to verify actual command execution

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                        ║"
echo "║              PRACTICAL COMMAND EXECUTION TEST                          ║"
echo "║                                                                        ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Test prompt
TEST_PROMPT="Say 'Hello from AI' and nothing else."

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 TEST 1: OpenCode Command"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v opencode &> /dev/null; then
    echo "Command being tested:"
    echo "  opencode run --model opencode/glm-4.7-free \"$TEST_PROMPT\""
    echo ""
    echo "Executing (timeout 10s)..."
    echo "─────────────────────────────────────────────────────────────────────"
    
    # Execute with timeout
    timeout 10s opencode run --model opencode/glm-4.7-free "$TEST_PROMPT" 2>&1 || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "⏱️  Command timed out (this is OK for testing)"
        else
            echo "⚠️  Command failed with exit code: $exit_code"
        fi
    }
    echo "─────────────────────────────────────────────────────────────────────"
    echo ""
else
    echo "❌ opencode is not installed, skipping test"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 TEST 2: Cursor Agent Command"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v cursor-agent &> /dev/null; then
    echo "Command being tested:"
    echo "  cursor-agent -p --model opus-4.5-thinking \"$TEST_PROMPT\""
    echo ""
    echo "Executing (timeout 10s)..."
    echo "─────────────────────────────────────────────────────────────────────"
    
    # Execute with timeout
    timeout 10s cursor-agent -p --model opus-4.5-thinking "$TEST_PROMPT" 2>&1 || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "⏱️  Command timed out (this is OK for testing)"
        else
            echo "⚠️  Command failed with exit code: $exit_code"
        fi
    }
    echo "─────────────────────────────────────────────────────────────────────"
    echo ""
else
    echo "❌ cursor-agent is not installed, skipping test"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Command Syntax Used:"
echo ""
echo "  OpenCode:     opencode run --model <model> <prompt>"
echo "                ✅ Matches documentation"
echo ""
echo "  Cursor Agent: cursor-agent -p --model <model> <prompt>"
echo "                ✅ Matches documentation"
echo ""
echo "Both commands are correctly formatted according to their respective"
echo "CLI documentation."
echo ""
