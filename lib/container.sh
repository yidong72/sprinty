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
CONTAINER_CACHE_DIR="${SPRINTY_CONTAINER_CACHE:-$HOME/.local/share/sprinty/containers}"

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

# Check if running under WSL
is_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

# Check if NVIDIA GPU is available
has_nvidia_gpu() {
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        return 0
    fi
    return 1
}

# Check if nvidia-container-cli is available
has_nvidia_container_cli() {
    command -v nvidia-container-cli &> /dev/null
}

# Get appropriate GPU flag for Apptainer
# Returns: --nvccli for WSL (if available), --nv for native Linux, empty if no GPU
# Return codes: 0 = GPU available, 1 = no GPU, 2 = GPU found but missing nvidia-container-cli (WSL)
get_gpu_flag() {
    if ! has_nvidia_gpu; then
        echo ""
        return 1
    fi
    
    if is_wsl; then
        # WSL2 requires --nvccli for proper NVIDIA GPU support
        if has_nvidia_container_cli; then
            echo "--nvccli"
            return 0
        else
            # nvidia-container-cli not installed, GPU cannot be used
            echo ""
            return 2
        fi
    else
        # Native Linux uses --nv
        echo "--nv"
        return 0
    fi
}

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

# Get cache filename for an image
get_cache_filename() {
    local image=$1
    # Convert image name to safe filename
    # docker://ubuntu:24.04 -> ubuntu_24.04.sif
    local safe_name=$(echo "$image" | sed 's|docker://||; s|library://||; s|shub://||; s|[/:]|_|g')
    echo "${safe_name}.sif"
}

# Check if cached container exists
get_cached_container() {
    local image=$1
    local cache_file="$CONTAINER_CACHE_DIR/$(get_cache_filename "$image")"
    
    if [[ -f "$cache_file" ]]; then
        echo "$cache_file"
        return 0
    fi
    return 1
}

# Build cached container with pre-installed packages
build_cached_container() {
    local image=$1
    local container_cmd=$2
    local cache_file="$CONTAINER_CACHE_DIR/$(get_cache_filename "$image")"
    
    mkdir -p "$CONTAINER_CACHE_DIR"
    
    log_status "INFO" "Building cached container: $cache_file"
    log_status "INFO" "This may take a few minutes (one-time setup)..."
    
    # Create definition file
    local def_file=$(mktemp /tmp/sprinty-container.XXXXXX.def)
    
    cat > "$def_file" << DEFEOF
Bootstrap: docker
From: ${image#docker://}

%post
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    export TZ=UTC
    ln -snf /usr/share/zoneinfo/\$TZ /etc/localtime
    echo \$TZ > /etc/timezone
    
    # Update and install packages
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \\
        curl \\
        git \\
        jq \\
        tmux \\
        python3 \\
        python3-pip \\
        python3-venv \\
        build-essential \\
        ca-certificates \\
        locales
    
    # Setup locale
    locale-gen en_US.UTF-8
    
    # Cleanup to reduce image size
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    
    # Create directories
    mkdir -p /workspace /opt/sprinty /root/.config/cursor

%environment
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export DEBIAN_FRONTEND=noninteractive

%labels
    Author Sprinty
    Version 1.0
    Description Sprinty container with pre-installed packages
DEFEOF
    
    # Build the container
    "$container_cmd" build --fakeroot "$cache_file" "$def_file" 2>&1 | while read line; do
        echo "  $line"
    done
    
    local build_status=${PIPESTATUS[0]}
    rm -f "$def_file"
    
    if [[ $build_status -eq 0 && -f "$cache_file" ]]; then
        log_status "SUCCESS" "Container cached: $cache_file"
        echo "$cache_file"
        return 0
    else
        log_status "ERROR" "Failed to build cached container"
        rm -f "$cache_file"
        return 1
    fi
}

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
    tmux \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    2>/dev/null || true

# Setup opencode from mounted host installation or install it
if [[ -d "/host-bin" && -f "/host-bin/opencode" ]]; then
    echo "Using opencode from host bin..."
    ln -sf /host-bin/opencode /usr/local/bin/opencode
    echo "✓ Linked opencode from /host-bin"
elif command -v opencode &> /dev/null; then
    echo "✓ opencode already available: $(which opencode)"
else
    echo "Installing opencode..."
    # Install opencode in container
    if curl -fsSL https://opencode.ai/install | bash 2>&1 | grep -v "^$"; then
        # Source the shell config to get opencode in PATH
        if [[ -f "/root/.bashrc" ]]; then
            source /root/.bashrc 2>/dev/null || true
        fi
        if command -v opencode &> /dev/null; then
            echo "✓ opencode installed: $(which opencode)"
        else
            # Try to find it manually
            if [[ -f "/root/.local/bin/opencode" ]]; then
                ln -sf /root/.local/bin/opencode /usr/local/bin/opencode
                echo "✓ opencode installed: /usr/local/bin/opencode"
            else
                echo "⚠ opencode installation may have failed"
            fi
        fi
    else
        echo "⚠ Failed to install opencode - will try to use from host mount"
    fi
fi

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
        echo "✓ Linked cursor-agent: $CURSOR_BIN → /usr/local/bin/cursor-agent"
    fi
elif [[ -d "/host-bin" && -f "/host-bin/cursor-agent" ]]; then
    echo "Using cursor-agent from host bin..."
    ln -sf /host-bin/cursor-agent /usr/local/bin/cursor-agent
    echo "✓ Linked cursor-agent from /host-bin"
fi

# Setup cursor auth credentials
if [[ -f "/root/.config/cursor/auth.json" ]]; then
    echo "✓ Cursor credentials mounted from host"
else
    # Create config directory for potential manual auth
    mkdir -p /root/.config/cursor
    echo "⚠ No cursor credentials found - may need to run: cursor-agent auth login"
fi

# Verify both agents are available
echo ""
echo "Agent CLI availability:"
if command -v opencode &> /dev/null; then
    echo "  ✓ opencode: $(which opencode)"
else
    echo "  ✗ opencode: not found"
fi

if command -v cursor-agent &> /dev/null; then
    echo "  ✓ cursor-agent: $(which cursor-agent)"
else
    echo "  ✗ cursor-agent: not found"
    echo "    (Install on host: curl https://cursor.com/install -fsS | bash)"
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

# Find opencode installation on host
find_opencode() {
    local opencode_bin=""
    local opencode_dir=""
    
    # Find opencode binary
    if command -v opencode &> /dev/null; then
        opencode_bin=$(command -v opencode)
        # Resolve symlink to find actual installation
        if [[ -L "$opencode_bin" ]]; then
            local real_path=$(readlink -f "$opencode_bin" 2>/dev/null || realpath "$opencode_bin" 2>/dev/null)
            opencode_dir=$(dirname "$real_path")
        else
            opencode_dir=$(dirname "$opencode_bin")
        fi
    fi
    
    # Also check common locations
    if [[ -z "$opencode_dir" ]]; then
        local search_paths=(
            "$HOME/.local/bin"
            "$HOME/.opencode"
            "/usr/local/bin"
            "/opt/opencode"
        )
        for path in "${search_paths[@]}"; do
            if [[ -f "$path/opencode" ]]; then
                opencode_bin="$path/opencode"
                opencode_dir="$path"
                break
            fi
        done
    fi
    
    echo "$opencode_bin|$opencode_dir"
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
    local use_image
    
    # Get container command
    container_cmd=$(prepare_container "$image") || return 1
    
    # Check for cached container
    local cached_image=$(get_cached_container "$image")
    if [[ -n "$cached_image" ]]; then
        log_status "INFO" "Using cached container: $cached_image"
        use_image="$cached_image"
    else
        log_status "INFO" "No cached container found for: $image"
        log_status "INFO" "Building cached container (one-time setup)..."
        
        cached_image=$(build_cached_container "$image" "$container_cmd")
        if [[ -n "$cached_image" && -f "$cached_image" ]]; then
            use_image="$cached_image"
        else
            log_status "WARN" "Cache build failed, using image directly (slower)"
            use_image="$image"
        fi
    fi
    
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
    
    # Find opencode
    local opencode_info=$(find_opencode)
    local opencode_bin="${opencode_info%%|*}"
    local opencode_dir="${opencode_info##*|}"
    
    # Find cursor-agent
    local cursor_info=$(find_cursor_agent)
    local cursor_agent_bin="${cursor_info%%|*}"
    local cursor_agent_dir="${cursor_info##*|}"
    
    log_status "INFO" "Launching container..."
    log_status "INFO" "  Image: $use_image"
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
    
    # Mount opencode if found (check opencode_bin first to avoid mounting empty directories)
    if [[ -n "$opencode_bin" && -f "$opencode_bin" ]]; then
        local bin_dir=$(dirname "$opencode_bin")
        # Create a combined host-bin directory if not already mounting one
        if [[ -d "$bin_dir" ]]; then
            # Check if we're already mounting this directory
            local already_mounted=false
            for opt in "${bind_opts[@]}"; do
                if [[ "$opt" == *"$bin_dir"* ]]; then
                    already_mounted=true
                    break
                fi
            done
            
            if [[ "$already_mounted" == "false" ]]; then
                bind_opts+=("--bind" "$bin_dir:/host-bin:ro")
                log_status "INFO" "  OpenCode: $opencode_bin → /host-bin/opencode"
            fi
        fi
    fi
    
    # Mount cursor-agent if found
    if [[ -n "$cursor_agent_dir" && -d "$cursor_agent_dir" ]]; then
        # Mount the entire cursor-agent installation directory
        bind_opts+=("--bind" "$cursor_agent_dir:/opt/cursor-agent:ro")
        log_status "INFO" "  Cursor-agent: $cursor_agent_dir → /opt/cursor-agent"
    fi
    
    # Also mount the cursor-agent binary symlink location if different and not already mounted
    if [[ -n "$cursor_agent_bin" && -f "$cursor_agent_bin" ]]; then
        local bin_dir=$(dirname "$cursor_agent_bin")
        # Check if already mounted
        local already_mounted=false
        for opt in "${bind_opts[@]}"; do
            if [[ "$opt" == *"$bin_dir"* && "$opt" == *"/host-bin"* ]]; then
                already_mounted=true
                break
            fi
        done
        
        if [[ "$already_mounted" == "false" && -d "$bin_dir" ]]; then
            bind_opts+=("--bind" "$bin_dir:/host-bin:ro")
            log_status "INFO" "  Host bin: $bin_dir → /host-bin"
        fi
    fi
    
    # Mount opencode auth/config if they exist
    local opencode_auth_file="$HOME/.local/share/opencode/auth.json"
    if [[ -f "$opencode_auth_file" ]]; then
        bind_opts+=("--bind" "$opencode_auth_file:/root/.local/share/opencode/auth.json:ro")
        log_status "INFO" "  OpenCode auth: $opencode_auth_file → /root/.local/share/opencode/auth.json"
    fi
    
    local opencode_config_dir="$HOME/.config/opencode"
    if [[ -d "$opencode_config_dir" ]]; then
        bind_opts+=("--bind" "$opencode_config_dir:/root/.config/opencode:ro")
        log_status "INFO" "  OpenCode config: $opencode_config_dir → /root/.config/opencode"
    fi
    
    # Mount cursor auth credentials if they exist
    local cursor_auth_file="$HOME/.config/cursor/auth.json"
    if [[ -f "$cursor_auth_file" ]]; then
        # Create the config directory structure in container
        bind_opts+=("--bind" "$cursor_auth_file:/root/.config/cursor/auth.json:ro")
        log_status "INFO" "  Cursor auth: $cursor_auth_file → /root/.config/cursor/auth.json"
    fi
    
    # Also mount cursor-server data for additional auth tokens
    local cursor_server_dir="$HOME/.cursor-server"
    if [[ -d "$cursor_server_dir" ]]; then
        bind_opts+=("--bind" "$cursor_server_dir:/root/.cursor-server:ro")
        log_status "INFO" "  Cursor server: $cursor_server_dir → /root/.cursor-server"
    fi
    
    # Mount user config files if they exist
    if [[ -f "$HOME/.gitconfig" ]]; then
        bind_opts+=("--bind" "$HOME/.gitconfig:/root/.gitconfig:ro")
        log_status "INFO" "  Git config: ~/.gitconfig → /root/.gitconfig"
    fi
    
    if [[ -f "$HOME/.tmux.conf" ]]; then
        bind_opts+=("--bind" "$HOME/.tmux.conf:/root/.tmux.conf:ro")
        log_status "INFO" "  Tmux config: ~/.tmux.conf → /root/.tmux.conf"
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
    
    # Run container with isolation options:
    # --writable-tmpfs: Allow writes to container filesystem (temporary)
    # --fakeroot: Run as fake root inside container
    # --pid: Isolate process namespace
    # --no-mount home,cwd: Don't auto-mount host directories (we mount explicitly)
    # --nv/--nvccli: Enable NVIDIA GPU support
    
    # Create a temporary directory for container's /tmp
    local container_tmp=$(mktemp -d /tmp/sprinty-container-tmp.XXXXXX)
    chmod 1777 "$container_tmp"
    
    # Add /tmp bind mount
    bind_opts+=("--bind" "$container_tmp:/tmp")
    
    # Check for GPU support and get appropriate flag
    local gpu_opts=()
    local gpu_flag
    gpu_flag=$(get_gpu_flag)
    local gpu_status=$?
    
    if [[ $gpu_status -eq 0 && -n "$gpu_flag" ]]; then
        gpu_opts+=("$gpu_flag")
        if is_wsl; then
            log_status "INFO" "  GPU: NVIDIA (WSL2 with nvidia-container-cli)"
        else
            log_status "INFO" "  GPU: NVIDIA (native Linux, using $gpu_flag)"
        fi
        # Add NVIDIA environment variables
        env_opts+=("--env" "NVIDIA_VISIBLE_DEVICES=all")
        env_opts+=("--env" "NVIDIA_DRIVER_CAPABILITIES=compute,utility")
    elif [[ $gpu_status -eq 2 ]]; then
        # WSL with GPU but missing nvidia-container-cli
        log_status "WARN" "  GPU: NVIDIA detected but not available in container"
        log_status "WARN" "       Please install nvidia-container-cli for GPU support:"
        log_status "WARN" "       sudo apt-get install -y nvidia-container-toolkit"
    else
        log_status "INFO" "  GPU: Not available or not detected"
    fi
    
    if [[ ${#sprinty_args[@]} -gt 0 ]]; then
        # Run with specific command
        "$container_cmd" exec \
            --writable-tmpfs \
            --fakeroot \
            --pid \
            --no-mount home,cwd \
            "${gpu_opts[@]}" \
            "${bind_opts[@]}" \
            "${env_opts[@]}" \
            --pwd "$CONTAINER_WORKSPACE" \
            "$use_image" \
            /bin/bash /tmp/setup.sh "${sprinty_args[@]}"
    else
        # Interactive shell
        "$container_cmd" exec \
            --writable-tmpfs \
            --fakeroot \
            --pid \
            --no-mount home,cwd \
            "${gpu_opts[@]}" \
            "${bind_opts[@]}" \
            "${env_opts[@]}" \
            --pwd "$CONTAINER_WORKSPACE" \
            "$use_image" \
            /bin/bash /tmp/setup.sh
    fi
    
    # Cleanup container temp directory
    rm -rf "$container_tmp"
    
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
- You can **install any packages** needed (apt, pip, npm, cargo, etc.)
- You can **modify or delete any files** in /workspace
- You can run **any commands** without restriction
- Changes outside /workspace are temporary (reset on container restart)

### Workspace
- Your working directory is `/workspace`
- This is mounted from the host system
- All project files should be here
- Changes here persist to the host

### Installing Dependencies

**Feel free to install ANY dependency libraries needed to make your code work and tests pass.**

```bash
# System packages (build tools, libraries, etc.)
apt-get update && apt-get install -y build-essential curl git jq

# Python: Install packages and test tools
pip install pytest pytest-cov requests flask numpy pandas

# Node.js: Install packages
npm install           # Install from package.json
npm install jest --save-dev

# Rust: Add crates
cargo add serde tokio

# Go: Get modules
go mod tidy
go get github.com/stretchr/testify
```

### Example: Setting Up a Python Project
```bash
apt-get update && apt-get install -y python3-pip python3-venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt  # If exists
pip install pytest pytest-cov    # For testing
pytest -v                        # Run tests
```

### Example: Setting Up a Node.js Project
```bash
apt-get update && apt-get install -y nodejs npm
npm install                      # Install dependencies
npm install --save-dev jest      # Add test framework
npm test                         # Run tests
```

### No Restrictions
Since you're in a sandbox:
- Feel free to experiment and install any tools
- Delete files if needed for cleanup
- Install whatever helps get the job done
- Run any commands necessary
- No need to worry about system safety
EOF
    fi
}

# ============================================================================
# CONTAINER CACHE MANAGEMENT
# ============================================================================

# List cached containers
list_cached_containers() {
    if [[ ! -d "$CONTAINER_CACHE_DIR" ]]; then
        echo "No cached containers found."
        return 0
    fi
    
    echo "Cached containers in: $CONTAINER_CACHE_DIR"
    echo ""
    
    local count=0
    for sif in "$CONTAINER_CACHE_DIR"/*.sif; do
        if [[ -f "$sif" ]]; then
            local size=$(du -h "$sif" | cut -f1)
            local name=$(basename "$sif")
            local modified=$(stat -c %y "$sif" 2>/dev/null | cut -d. -f1 || stat -f %Sm "$sif" 2>/dev/null)
            echo "  $name ($size) - $modified"
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    fi
    echo ""
    echo "Total: $count container(s)"
}

# Rebuild cached container
rebuild_cached_container() {
    local image=${1:-$DEFAULT_CONTAINER_IMAGE}
    local container_cmd
    
    container_cmd=$(check_apptainer_installed) || {
        log_status "ERROR" "Apptainer/Singularity not installed"
        return 1
    }
    
    local cache_file="$CONTAINER_CACHE_DIR/$(get_cache_filename "$image")"
    
    # Remove existing cache
    if [[ -f "$cache_file" ]]; then
        log_status "INFO" "Removing existing cache: $cache_file"
        rm -f "$cache_file"
    fi
    
    # Rebuild
    build_cached_container "$image" "$container_cmd"
}

# Clear all cached containers
clear_container_cache() {
    if [[ -d "$CONTAINER_CACHE_DIR" ]]; then
        log_status "INFO" "Clearing container cache: $CONTAINER_CACHE_DIR"
        rm -rf "$CONTAINER_CACHE_DIR"/*.sif
        log_status "SUCCESS" "Container cache cleared"
    else
        log_status "INFO" "No container cache to clear"
    fi
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f is_in_container
export -f check_apptainer_installed
export -f is_wsl
export -f has_nvidia_gpu
export -f has_nvidia_container_cli
export -f get_gpu_flag
export -f prepare_container
export -f find_opencode
export -f find_cursor_agent
export -f launch_container
export -f get_container_prompt_additions
export -f get_cache_filename
export -f get_cached_container
export -f build_cached_container
export -f list_cached_containers
export -f rebuild_cached_container
export -f clear_container_cache
