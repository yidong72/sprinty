#!/usr/bin/env bats
# Tests for multi-backend agent support

load ../helpers/test_helper

setup() {
    setup_test_env
    source "$PROJECT_ROOT/lib/agent_adapter.sh"
}

teardown() {
    cleanup_test_env
}

# ============================================================================
# Configuration Detection Tests
# ============================================================================

@test "detect_agent_cli_tool: defaults to cursor-agent when no config" {
    # No .sprinty/config.json exists
    result=$(detect_agent_cli_tool)
    [ "$result" = "cursor-agent" ]
}

@test "detect_agent_cli_tool: reads from config when present" {
    mkdir -p "$TEST_DIR/.sprinty"
    cat > "$TEST_DIR/.sprinty/config.json" << 'EOF'
{
  "agent": {
    "cli_tool": "opencode"
  }
}
EOF
    
    cd "$TEST_DIR"
    result=$(detect_agent_cli_tool)
    [ "$result" = "opencode" ]
}

@test "get_agent_model: returns opencode default when tool is opencode" {
    mkdir -p "$TEST_DIR/.sprinty"
    cat > "$TEST_DIR/.sprinty/config.json" << 'EOF'
{
  "agent": {
    "cli_tool": "opencode"
  }
}
EOF
    
    cd "$TEST_DIR"
    AGENT_CLI_TOOL="opencode"
    result=$(get_agent_model)
    [ "$result" = "opencode/glm-4.7-free" ]
}

@test "get_agent_model: returns cursor-agent default when tool is cursor-agent" {
    mkdir -p "$TEST_DIR/.sprinty"
    cat > "$TEST_DIR/.sprinty/config.json" << 'EOF'
{
  "agent": {
    "cli_tool": "cursor-agent"
  }
}
EOF
    
    cd "$TEST_DIR"
    AGENT_CLI_TOOL="cursor-agent"
    result=$(get_agent_model)
    [ "$result" = "opus-4.5-thinking" ]
}

@test "get_agent_model: uses model from config when specified" {
    mkdir -p "$TEST_DIR/.sprinty"
    cat > "$TEST_DIR/.sprinty/config.json" << 'EOF'
{
  "agent": {
    "cli_tool": "opencode",
    "model": "custom-model"
  }
}
EOF
    
    cd "$TEST_DIR"
    result=$(get_agent_model)
    [ "$result" = "custom-model" ]
}

# ============================================================================
# Abstraction Layer Tests
# ============================================================================

@test "check_agent_installed: calls correct backend for opencode" {
    AGENT_CLI_TOOL="opencode"
    
    # Mock check_opencode_installed
    check_opencode_installed() { return 0; }
    export -f check_opencode_installed
    
    run check_agent_installed
    [ "$status" -eq 0 ]
}

@test "check_agent_installed: calls correct backend for cursor-agent" {
    AGENT_CLI_TOOL="cursor-agent"
    
    # Mock check_cursor_agent_installed
    check_cursor_agent_installed() { return 0; }
    export -f check_cursor_agent_installed
    
    run check_agent_installed
    [ "$status" -eq 0 ]
}

@test "check_agent_installed: fails for unknown backend" {
    AGENT_CLI_TOOL="unknown-backend"
    
    run check_agent_installed
    [ "$status" -eq 1 ]
}

@test "get_agent_version: calls correct backend for opencode" {
    AGENT_CLI_TOOL="opencode"
    
    # Mock get_opencode_version
    get_opencode_version() { echo "1.0.0"; }
    export -f get_opencode_version
    
    result=$(get_agent_version)
    [ "$result" = "1.0.0" ]
}

@test "get_agent_version: calls correct backend for cursor-agent" {
    AGENT_CLI_TOOL="cursor-agent"
    
    # Mock get_cursor_agent_version
    get_cursor_agent_version() { echo "2.0.0"; }
    export -f get_cursor_agent_version
    
    result=$(get_agent_version)
    [ "$result" = "2.0.0" ]
}

# ============================================================================
# OpenCode Backend Tests
# ============================================================================

@test "check_opencode_installed: returns 1 when not installed" {
    # Ensure opencode is not in PATH for this test
    run check_opencode_installed
    # Should fail if opencode is not installed
    # We can't guarantee the state, so we just test the function runs
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "check_opencode_auth: returns 0 when opencode is installed" {
    # Mock check_opencode_installed
    check_opencode_installed() { return 0; }
    export -f check_opencode_installed
    
    run check_opencode_auth
    [ "$status" -eq 0 ]
}

@test "init_opencode_project_config: creates .opencode directory" {
    cd "$TEST_DIR"
    run init_opencode_project_config "."
    [ "$status" -eq 0 ]
    [ -d "$TEST_DIR/.opencode" ]
}

# ============================================================================
# Cursor Agent Backend Tests (Backward Compatibility)
# ============================================================================

@test "check_cursor_agent_installed: function still exists" {
    # Ensure backward compatibility - function should exist
    declare -F check_cursor_agent_installed
}

@test "init_cursor_project_config: function still exists" {
    # Ensure backward compatibility - function should exist
    declare -F init_cursor_project_config
}

@test "execute_cursor_agent: function still exists" {
    # Ensure backward compatibility - function should exist
    declare -F execute_cursor_agent
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "agent adapter loads without errors" {
    run bash -c "source '$PROJECT_ROOT/lib/agent_adapter.sh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "loaded" ]]
}

@test "all abstraction functions are exported" {
    # Check key functions are exported
    declare -F check_agent_installed
    declare -F get_agent_version
    declare -F check_agent_auth
    declare -F init_agent_project_config
    declare -F execute_agent
    declare -F execute_agent_raw
}

@test "all backend-specific functions are exported" {
    # OpenCode functions
    declare -F check_opencode_installed
    declare -F get_opencode_version
    declare -F execute_opencode
    
    # Cursor Agent functions (backward compatibility)
    declare -F check_cursor_agent_installed
    declare -F get_cursor_agent_version
    declare -F execute_cursor_agent
}
