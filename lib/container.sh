#!/usr/bin/env bash
# ============================================================================
# Sprinty Container Support (Apptainer/Singularity)
# ============================================================================
# 
# Provides sandboxed execution environment for safe AI agent operations.
# Uses Apptainer (formerly Singularity) with Docker images.
#
# ============================================================================

set -e

# Source utilities
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

DEFAULT_CONTAINER_IMAGE="${SPRINTY_CONTAINER_IMAGE:-docker://ubuntu:24.04}"
CONTAINER_WORKSPACE="/workspace"
SPRINTY_INSTALL_PATH="/opt/sprinty"

# ============================================================================
# CONTAINER DETECTION
# ============================================================================

# Check if running inside a container
is_in_container() {
    # Check for Apptainer/Singularity environment
    if [[ -n "$SINGULARITY_CONTAINER" ]] || [[ -n "$APPTAINER_CONTAINER" ]]; then
        return 0
    fi
    # Check for Docker
    if [[ -f "/.dockerenv" ]]; then
        return 0
    fi
    # Check for container cgroup
    if grep -q "docker\|lxc\|singularity\|apptainer" /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if Apptainer is installed
check_apptainer_installed() {
    if command -v apptainer &> /dev/null; then
        echo "apptainer"
        return 0
    elif command -v singularity &> /dev/null; then
        echo "singularity"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

# Build or pull container image
prepare_container() {
    local image=$1
    local container_cmd
    
    container_cmd=$(check_apptainer_installed) || {
        log_status "ERROR" "Apptainer/Singularity not installed"
        echo ""
        echo "Install Apptainer:"
        echo "  Ubuntu/Debian: sudo apt install apptainer"
        echo "  Or see: https://apptainer.org/docs/admin/main/installation.html"
        return 1
    }
    
    log_status "INFO" "Using container runtime: $container_cmd"
    log_status "INFO" "Container image: $image"
    
    echo "$container_cmd"
}

# Create the container setup script
create_setup_script() {
    local setup_script="$1"
    local sprinty_source="$2"
    
    cat > "$setup_script" << 'SETUP_SCRIPT'
#!/usr/bin/env bash
# Sprinty Container Setup Script
set -e

echo "=== Setting up Sprinty in container ==="

# Set non-interactive mode to avoid timezone and other prompts
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# Pre-configure timezone to avoid interactive prompt
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime 2>/dev/null || true
echo $TZ > /etc/timezone 2>/dev/null || true

# Update package lists (suppress output)
apt-get update -qq 2>/dev/null || true

# Install essential tools (non-interactive)
apt-get install -y -qq --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    2>/dev/null || true

# Setup cursor-agent from mounted host installation
if [[ -d "/opt/cursor-agent" ]]; then
    echo "Using cursor-agent from host mount..."
    
    # Find the cursor-agent binary in the mounted directory
    CURSOR_BIN=""
    if [[ -f "/opt/cursor-agent/cursor-agent" ]]; then
        CURSOR_BIN="/opt/cursor-agent/cursor-agent"
    else
        # Look in versions subdirectory
        CURSOR_BIN=$(find /opt/cursor-agent -name "cursor-agent" -type f 2>/dev/null | head -1)
    fi
    
    if [[ -n "$CURSOR_BIN" && -f "$CURSOR_BIN" ]]; then
        ln -sf "$CURSOR_BIN" /usr/local/bin/cursor-agent
        chmod +x /usr/local/bin/cursor-agent 2>/dev/null || true
        echo "Linked cursor-agent: $CURSOR_BIN → /usr/local/bin/cursor-agent"
    fi
elif [[ -d "/host-bin" && -f "/host-bin/cursor-agent" ]]; then
    echo "Using cursor-agent from host bin..."
    ln -sf /host-bin/cursor-agent /usr/local/bin/cursor-agent
    echo "Linked cursor-agent from /host-bin"
fi

# Verify cursor-agent is available
if command -v cursor-agent &> /dev/null; then
    echo "✓ cursor-agent available: $(which cursor-agent)"
else
    echo "⚠ cursor-agent not found - some features may not work"
    echo "  Install on host: npm install -g @anthropic/cursor-agent"
fi

# Copy sprinty to install location
if [[ -d "/tmp/sprinty-source" ]]; then
    mkdir -p /opt/sprinty
    cp -r /tmp/sprinty-source/* /opt/sprinty/
    chmod +x /opt/sprinty/sprinty.sh
    
    # Create wrapper script that properly sets SCRIPT_DIR
    # (Direct symlink breaks SCRIPT_DIR resolution)
    cat > /usr/local/bin/sprinty << 'WRAPPER'
#!/usr/bin/env bash
export SCRIPT_DIR="/opt/sprinty"
exec /opt/sprinty/sprinty.sh "$@"
WRAPPER
    chmod +x /usr/local/bin/sprinty
    echo "✓ Sprinty installed to /opt/sprinty"
fi

# Setup workspace
mkdir -p /workspace
cd /workspace

echo ""
echo "=== Container setup complete ==="
echo "Working directory: /workspace"
echo "Sprinty: $(which sprinty 2>/dev/null || echo 'not found')"
echo "Cursor-agent: $(which cursor-agent 2>/dev/null || echo 'not found')"
echo ""

# If arguments provided, run sprinty
if [[ $# -gt 0 ]]; then
    exec sprinty "$@"
else
    exec bash
fi
SETUP_SCRIPT
    
    chmod +x "$setup_script"
}

# Find cursor-agent installation on host
find_cursor_agent() {
    local cursor_agent_bin=""
    local cursor_agent_dir=""
    
    # Find cursor-agent binary
    if command -v cursor-agent &> /dev/null; then
        cursor_agent_bin=$(command -v cursor-agent)
        # Resolve symlink to find actual installation
        if [[ -L "$cursor_agent_bin" ]]; then
            local real_path=$(readlink -f "$cursor_agent_bin" 2>/dev/null || realpath "$cursor_agent_bin" 2>/dev/null)
            cursor_agent_dir=$(dirname "$real_path")
        else
            cursor_agent_dir=$(dirname "$cursor_agent_bin")
        fi
    fi
    
    # Also check common locations
    if [[ -z "$cursor_agent_dir" ]]; then
        local search_paths=(
            "$HOME/.local/share/cursor-agent"
            "$HOME/.cursor-agent"
            "/usr/local/share/cursor-agent"
            "/opt/cursor-agent"
        )
        for path in "${search_paths[@]}"; do
            if [[ -d "$path" ]]; then
                cursor_agent_dir="$path"
                break
            fi
        done
    fi
    
    echo "$cursor_agent_bin|$cursor_agent_dir"
}

# Launch sprinty in container
launch_container() {
    local image=$1
    local workspace=$2
    local sprinty_args=("${@:3}")
    local container_cmd
    local sprinty_source
    
    # Get container command
    container_cmd=$(prepare_container "$image") || return 1
    
    # Get sprinty source directory
    sprinty_source="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Create temp setup script
    local setup_script=$(mktemp /tmp/sprinty-setup.XXXXXX.sh)
    create_setup_script "$setup_script" "$sprinty_source"
    
    # Resolve workspace to absolute path
    workspace=$(cd "$workspace" 2>/dev/null && pwd) || {
        log_status "ERROR" "Workspace directory not found: $workspace"
        return 1
    }
    
    # Find cursor-agent
    local cursor_info=$(find_cursor_agent)
    local cursor_agent_bin="${cursor_info%%|*}"
    local cursor_agent_dir="${cursor_info##*|}"
    
    log_status "INFO" "Launching container..."
    log_status "INFO" "  Image: $image"
    log_status "INFO" "  Workspace: $workspace → $CONTAINER_WORKSPACE"
    log_status "INFO" "  Sprinty source: $sprinty_source"
    
    # Build apptainer/singularity command
    # --writable-tmpfs: Allow writes to container filesystem
    # --fakeroot: Run as fake root inside container
    # --bind: Mount directories
    # --pwd: Set working directory
    # --env: Pass environment variables
    
    local bind_opts=(
        "--bind" "$workspace:$CONTAINER_WORKSPACE"
        "--bind" "$sprinty_source:/tmp/sprinty-source:ro"
        "--bind" "$setup_script:/tmp/setup.sh:ro"
    )
    
    # Mount cursor-agent if found
    if [[ -n "$cursor_agent_dir" && -d "$cursor_agent_dir" ]]; then
        # Mount the entire cursor-agent installation directory
        bind_opts+=("--bind" "$cursor_agent_dir:/opt/cursor-agent:ro")
        log_status "INFO" "  Cursor-agent: $cursor_agent_dir → /opt/cursor-agent"
    fi
    
    # Also mount the binary symlink location if different
    if [[ -n "$cursor_agent_bin" && -f "$cursor_agent_bin" ]]; then
        local bin_dir=$(dirname "$cursor_agent_bin")
        # Mount entire .local/bin if that's where it is
        if [[ "$bin_dir" == *".local/bin"* && -d "$bin_dir" ]]; then
            bind_opts+=("--bind" "$bin_dir:/host-bin:ro")
            log_status "INFO" "  Host bin: $bin_dir → /host-bin"
        fi
    fi
    
    # Pass through important environment variables
    local env_opts=(
        "--env" "CURSOR_MODEL=${CURSOR_MODEL:-opus-4.5-thinking}"
        "--env" "SPRINTY_IN_CONTAINER=true"
        "--env" "SPRINTY_CONTAINER_MODE=sandbox"
        "--env" "HOME=/root"
    )
    
    # Pass cursor auth if available
    if [[ -n "$CURSOR_API_KEY" ]]; then
        env_opts+=("--env" "CURSOR_API_KEY=$CURSOR_API_KEY")
    fi
    
    echo ""
    log_status "SUCCESS" "Starting sandboxed Sprinty environment"
    echo ""
    
    # Run container
    if [[ ${#sprinty_args[@]} -gt 0 ]]; then
        # Run with specific command
        "$container_cmd" exec \
            --writable-tmpfs \
            --fakeroot \
            "${bind_opts[@]}" \
            "${env_opts[@]}" \
            --pwd "$CONTAINER_WORKSPACE" \
            "$image" \
            /bin/bash /tmp/setup.sh "${sprinty_args[@]}"
    else
        # Interactive shell
        "$container_cmd" exec \
            --writable-tmpfs \
            --fakeroot \
            "${bind_opts[@]}" \
            "${env_opts[@]}" \
            --pwd "$CONTAINER_WORKSPACE" \
            "$image" \
            /bin/bash /tmp/setup.sh
    fi
    
    local exit_code=$?
    
    # Cleanup
    rm -f "$setup_script"
    
    return $exit_code
}

# ============================================================================
# CONTAINER-SPECIFIC PROMPT MODIFICATIONS
# ============================================================================

# Get container-aware prompt additions
get_container_prompt_additions() {
    if [[ "$SPRINTY_IN_CONTAINER" == "true" ]]; then
        cat << 'EOF'

## Container Environment

You are running in a **sandboxed container environment**. This means:

### Full System Access
- You have **root access** inside the container
- You can **install any packages** needed (apt, pip, npm, etc.)
- You can **modify or delete any files** in /workspace
- You can run **any commands** without restriction
- Changes outside /workspace are temporary (reset on container restart)

### Workspace
- Your working directory is `/workspace`
- This is mounted from the host system
- All project files should be here
- Changes here persist to the host

### Installing Dependencies
```bash
# System packages
apt-get update && apt-get install -y <package>

# Python packages
pip install <package>

# Node packages
npm install -g <package>
```

### No Restrictions
Since you're in a sandbox:
- Feel free to experiment
- Delete files if needed for cleanup
- Install whatever tools help get the job done
- Run any commands necessary
- No need to worry about system safety
EOF
    fi
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f is_in_container
export -f check_apptainer_installed
export -f prepare_container
export -f find_cursor_agent
export -f launch_container
export -f get_container_prompt_additions
