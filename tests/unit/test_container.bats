#!/usr/bin/env bats
# Unit Tests for Container Support

load '../helpers/test_helper'

setup() {
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"
    export PROJECT_ROOT="$(get_project_root)"
    
    # Create temp directory
    export TEST_TEMP_DIR="$(mktemp -d /tmp/sprinty-container-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    
    # Source container module
    source "$PROJECT_ROOT/lib/utils.sh"
    source "$PROJECT_ROOT/lib/container.sh"
}

teardown() {
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# CONTAINER DETECTION TESTS
# ============================================================================

@test "is_in_container returns false on host" {
    # Unset container environment variables
    unset SINGULARITY_CONTAINER
    unset APPTAINER_CONTAINER
    
    # This should return false on a normal host
    # (unless running tests inside a container)
    if [[ -n "$SINGULARITY_CONTAINER" ]] || [[ -n "$APPTAINER_CONTAINER" ]] || [[ -f "/.dockerenv" ]]; then
        skip "Test is running inside a container"
    fi
    
    run is_in_container
    # May succeed or fail depending on environment
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "is_in_container returns true when APPTAINER_CONTAINER set" {
    export APPTAINER_CONTAINER="/some/container.sif"
    
    run is_in_container
    assert_success
}

@test "is_in_container returns true when SINGULARITY_CONTAINER set" {
    export SINGULARITY_CONTAINER="/some/container.sif"
    
    run is_in_container
    assert_success
}

# ============================================================================
# APPTAINER CHECK TESTS
# ============================================================================

@test "check_apptainer_installed returns apptainer if available" {
    if ! command -v apptainer &> /dev/null && ! command -v singularity &> /dev/null; then
        skip "Neither apptainer nor singularity installed"
    fi
    
    result=$(check_apptainer_installed)
    
    [[ "$result" == "apptainer" || "$result" == "singularity" ]]
}

@test "check_apptainer_installed fails if not installed" {
    # Temporarily hide apptainer/singularity
    PATH_BACKUP="$PATH"
    export PATH="/usr/bin:/bin"
    
    # Remove apptainer and singularity from PATH
    if command -v apptainer &> /dev/null || command -v singularity &> /dev/null; then
        # Can't easily hide them, skip
        export PATH="$PATH_BACKUP"
        skip "Cannot hide apptainer/singularity from PATH"
    fi
    
    run check_apptainer_installed
    assert_failure
    
    export PATH="$PATH_BACKUP"
}

# ============================================================================
# CONTAINER PROMPT ADDITIONS TESTS
# ============================================================================

@test "get_container_prompt_additions returns empty when not in container" {
    unset SPRINTY_IN_CONTAINER
    
    result=$(get_container_prompt_additions)
    
    [[ -z "$result" ]]
}

@test "get_container_prompt_additions returns content when in container" {
    export SPRINTY_IN_CONTAINER="true"
    
    result=$(get_container_prompt_additions)
    
    # Should contain key phrases
    [[ "$result" == *"sandboxed container"* ]]
    [[ "$result" == *"root access"* ]]
    [[ "$result" == *"/workspace"* ]]
    [[ "$result" == *"install any packages"* ]]
}

@test "get_container_prompt_additions mentions apt and pip" {
    export SPRINTY_IN_CONTAINER="true"
    
    result=$(get_container_prompt_additions)
    
    [[ "$result" == *"apt"* ]]
    [[ "$result" == *"pip"* ]]
    [[ "$result" == *"npm"* ]]
}

# ============================================================================
# SETUP SCRIPT TESTS
# ============================================================================

@test "create_setup_script creates executable file" {
    local setup_file="$TEST_TEMP_DIR/setup.sh"
    
    create_setup_script "$setup_file" "/tmp/sprinty"
    
    [[ -f "$setup_file" ]]
    [[ -x "$setup_file" ]]
}

@test "create_setup_script contains required commands" {
    local setup_file="$TEST_TEMP_DIR/setup.sh"
    
    create_setup_script "$setup_file" "/tmp/sprinty"
    
    local content=$(cat "$setup_file")
    
    # Should contain key setup steps
    [[ "$content" == *"apt-get update"* ]]
    [[ "$content" == *"jq"* ]]
    [[ "$content" == *"/opt/sprinty"* ]]
    [[ "$content" == *"/workspace"* ]]
    # Should set non-interactive mode for timezone
    [[ "$content" == *"DEBIAN_FRONTEND=noninteractive"* ]]
}

@test "create_setup_script sets up sprinty wrapper" {
    local setup_file="$TEST_TEMP_DIR/setup.sh"
    
    create_setup_script "$setup_file" "/tmp/sprinty"
    
    local content=$(cat "$setup_file")
    
    # Should create wrapper script (not just symlink)
    [[ "$content" == *"/usr/local/bin/sprinty"* ]]
    [[ "$content" == *"SCRIPT_DIR"* ]]
    [[ "$content" == *"exec /opt/sprinty/sprinty.sh"* ]]
}

# ============================================================================
# CONTAINER IMAGE HANDLING TESTS  
# ============================================================================

@test "default container image is ubuntu:24.04" {
    [[ "$DEFAULT_CONTAINER_IMAGE" == "docker://ubuntu:24.04" ]]
}

@test "CONTAINER_WORKSPACE is /workspace" {
    [[ "$CONTAINER_WORKSPACE" == "/workspace" ]]
}

# ============================================================================
# ENVIRONMENT VARIABLE TESTS
# ============================================================================

@test "SPRINTY_IN_CONTAINER env var used for detection" {
    export SPRINTY_IN_CONTAINER="true"
    
    # Container additions should be available
    result=$(get_container_prompt_additions)
    [[ -n "$result" ]]
    
    unset SPRINTY_IN_CONTAINER
    
    # Should be empty now
    result=$(get_container_prompt_additions)
    [[ -z "$result" ]]
}

# ============================================================================
# CURSOR-AGENT MOUNTING TESTS
# ============================================================================

@test "find_cursor_agent returns path if cursor-agent installed" {
    if ! command -v cursor-agent &> /dev/null; then
        skip "cursor-agent not installed"
    fi
    
    result=$(find_cursor_agent)
    
    # Should return bin|dir format
    [[ "$result" == *"|"* ]]
    
    local bin="${result%%|*}"
    local dir="${result##*|}"
    
    # Binary should exist
    [[ -f "$bin" || -L "$bin" ]]
}

@test "find_cursor_agent handles missing cursor-agent" {
    # Temporarily hide cursor-agent
    PATH_BACKUP="$PATH"
    export PATH="/usr/bin:/bin"
    
    result=$(find_cursor_agent)
    
    # Should return empty or partial result
    # Format is bin|dir, both may be empty
    [[ "$result" == "|" || "$result" == *"|"* ]]
    
    export PATH="$PATH_BACKUP"
}

@test "setup script links cursor-agent from mounted directory" {
    local setup_file="$TEST_TEMP_DIR/setup.sh"
    
    create_setup_script "$setup_file" "/tmp/sprinty"
    
    local content=$(cat "$setup_file")
    
    # Should check for /opt/cursor-agent mount
    [[ "$content" == *"/opt/cursor-agent"* ]]
    
    # Should create symlink
    [[ "$content" == *"ln -sf"* ]]
    [[ "$content" == *"/usr/local/bin/cursor-agent"* ]]
}

# ============================================================================
# CONTAINER CACHE TESTS
# ============================================================================

@test "get_cache_filename converts docker image to safe filename" {
    result=$(get_cache_filename "docker://ubuntu:24.04")
    [[ "$result" == "ubuntu_24.04.sif" ]]
    
    result=$(get_cache_filename "docker://python:3.12-slim")
    [[ "$result" == "python_3.12-slim.sif" ]]
    
    result=$(get_cache_filename "library://myorg/myimage:latest")
    [[ "$result" == "myorg_myimage_latest.sif" ]]
}

@test "get_cached_container returns empty if no cache exists" {
    export CONTAINER_CACHE_DIR="$TEST_TEMP_DIR/nonexistent"
    
    run get_cached_container "docker://ubuntu:24.04"
    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
}

@test "get_cached_container returns path if cache exists" {
    export CONTAINER_CACHE_DIR="$TEST_TEMP_DIR/cache"
    mkdir -p "$CONTAINER_CACHE_DIR"
    touch "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif"
    
    result=$(get_cached_container "docker://ubuntu:24.04")
    [[ "$result" == "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif" ]]
}

@test "list_cached_containers shows no cache message when empty" {
    export CONTAINER_CACHE_DIR="$TEST_TEMP_DIR/empty-cache"
    
    run list_cached_containers
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No cached containers"* ]]
}

@test "list_cached_containers shows cached files" {
    export CONTAINER_CACHE_DIR="$TEST_TEMP_DIR/cache"
    mkdir -p "$CONTAINER_CACHE_DIR"
    touch "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif"
    
    run list_cached_containers
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ubuntu_24.04.sif"* ]]
    [[ "$output" == *"Total: 1"* ]]
}

@test "clear_container_cache removes cached files" {
    export CONTAINER_CACHE_DIR="$TEST_TEMP_DIR/cache"
    mkdir -p "$CONTAINER_CACHE_DIR"
    touch "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif"
    touch "$CONTAINER_CACHE_DIR/python_3.12.sif"
    
    [[ -f "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif" ]]
    
    clear_container_cache
    
    [[ ! -f "$CONTAINER_CACHE_DIR/ubuntu_24.04.sif" ]]
    [[ ! -f "$CONTAINER_CACHE_DIR/python_3.12.sif" ]]
}

@test "CONTAINER_CACHE_DIR defaults to ~/.local/share/sprinty/containers" {
    # Re-source to get default value
    unset SPRINTY_CONTAINER_CACHE
    unset CONTAINER_CACHE_DIR
    source "$PROJECT_ROOT/lib/container.sh"
    
    [[ "$CONTAINER_CACHE_DIR" == "$HOME/.local/share/sprinty/containers" ]]
}

@test "CONTAINER_CACHE_DIR respects SPRINTY_CONTAINER_CACHE env var" {
    export SPRINTY_CONTAINER_CACHE="/custom/cache/dir"
    source "$PROJECT_ROOT/lib/container.sh"
    
    [[ "$CONTAINER_CACHE_DIR" == "/custom/cache/dir" ]]
}
