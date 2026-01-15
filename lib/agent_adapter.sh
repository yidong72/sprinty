#!/usr/bin/env bash
# Sprinty Agent Adapter
# Multi-backend CLI integration for Sprinty orchestrator
# Supports: cursor-agent, opencode
# Adapted from ralph-cursor-agent/lib/cursor_adapter.sh

set -e

# Source utilities (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Detect agent CLI tool from config, fallback to cursor-agent for backward compatibility
detect_agent_cli_tool() {
    local config_file="${SPRINTY_DIR:-.sprinty}/config.json"
    if [[ -f "$config_file" ]]; then
        jq -r '.agent.cli_tool // "cursor-agent"' "$config_file" 2>/dev/null || echo "cursor-agent"
    else
        echo "cursor-agent"
    fi
}

# Get agent model from config
get_agent_model() {
    local config_file="${SPRINTY_DIR:-.sprinty}/config.json"
    local cli_tool="${AGENT_CLI_TOOL:-$(detect_agent_cli_tool)}"
    
    if [[ -f "$config_file" ]]; then
        local model=$(jq -r '.agent.model // ""' "$config_file" 2>/dev/null || echo "")
        if [[ -n "$model" ]]; then
            echo "$model"
            return
        fi
    fi
    
    # Default models based on CLI tool
    case "$cli_tool" in
        opencode)
            echo "opencode/minimax-m2.1-free"
            ;;
        cursor-agent)
            echo "opus-4.5-thinking"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get agent timeout from config
get_agent_timeout() {
    local config_file="${SPRINTY_DIR:-.sprinty}/config.json"
    if [[ -f "$config_file" ]]; then
        jq -r '.agent.timeout_minutes // 15' "$config_file" 2>/dev/null || echo "15"
    else
        echo "15"
    fi
}

# Set agent configuration from config file or environment
AGENT_CLI_TOOL="${AGENT_CLI_TOOL:-$(detect_agent_cli_tool)}"
AGENT_MODEL="${AGENT_MODEL:-$(get_agent_model)}"
AGENT_TIMEOUT_MINUTES="${AGENT_TIMEOUT_MINUTES:-$(get_agent_timeout)}"
AGENT_OUTPUT_FORMAT="${AGENT_OUTPUT_FORMAT:-text}"

# Legacy cursor-agent variables (for backward compatibility)
CURSOR_AGENT_CMD="${CURSOR_AGENT_CMD:-cursor-agent}"
CURSOR_OUTPUT_FORMAT="${CURSOR_OUTPUT_FORMAT:-$AGENT_OUTPUT_FORMAT}"
CURSOR_MODEL="${CURSOR_MODEL:-$AGENT_MODEL}"
CURSOR_CONFIG_DIR=".cursor"
CURSOR_TIMEOUT_MINUTES="${CURSOR_TIMEOUT_MINUTES:-$AGENT_TIMEOUT_MINUTES}"

# Prompts directory
PROMPTS_DIR="${PROMPTS_DIR:-prompts}"

# Output directory for agent responses
AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-logs/agent_output}"

# ============================================================================
# AGENT CLI ABSTRACTION LAYER
# ============================================================================

# Check if the configured agent CLI is installed
check_agent_installed() {
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            check_cursor_agent_installed
            ;;
        opencode)
            check_opencode_installed
            ;;
        *)
            log_status "ERROR" "Unknown agent CLI tool: $AGENT_CLI_TOOL"
            return 1
            ;;
    esac
}

# Get agent version
get_agent_version() {
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            get_cursor_agent_version
            ;;
        opencode)
            get_opencode_version
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check agent authentication
check_agent_auth() {
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            check_cursor_auth
            ;;
        opencode)
            check_opencode_auth
            ;;
        *)
            return 1
            ;;
    esac
}

# Initialize project configuration
init_agent_project_config() {
    local project_dir=${1:-.}
    
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            init_cursor_project_config "$project_dir"
            ;;
        opencode)
            init_opencode_project_config "$project_dir"
            ;;
        *)
            log_status "WARN" "No project config initialization for: $AGENT_CLI_TOOL"
            return 0
            ;;
    esac
}

# Execute agent with prompt
execute_agent() {
    local prompt_file=$1
    local output_file=$2
    local timeout_seconds=${3:-$((AGENT_TIMEOUT_MINUTES * 60))}
    
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            execute_cursor_agent "$prompt_file" "$output_file" "$timeout_seconds"
            ;;
        opencode)
            execute_opencode "$prompt_file" "$output_file" "$timeout_seconds"
            ;;
        *)
            log_status "ERROR" "Unknown agent CLI tool: $AGENT_CLI_TOOL"
            return 1
            ;;
    esac
}

# Execute agent with raw prompt string
execute_agent_raw() {
    local prompt_string=$1
    local output_file=$2
    local timeout_seconds=${3:-$((AGENT_TIMEOUT_MINUTES * 60))}
    
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            execute_cursor_agent_raw "$prompt_string" "$output_file" "$timeout_seconds"
            ;;
        opencode)
            execute_opencode_raw "$prompt_string" "$output_file" "$timeout_seconds"
            ;;
        *)
            log_status "ERROR" "Unknown agent CLI tool: $AGENT_CLI_TOOL"
            return 1
            ;;
    esac
}

# ============================================================================
# CURSOR-AGENT IMPLEMENTATION
# ============================================================================

# Check if cursor-agent CLI is installed
check_cursor_agent_installed() {
    if ! command -v "$CURSOR_AGENT_CMD" &> /dev/null; then
        log_status "ERROR" "cursor-agent CLI not found"
        echo "" >&2
        echo "Install cursor-agent with:" >&2
        echo "  curl https://cursor.com/install -fsS | bash" >&2
        echo "" >&2
        echo "After installation, restart your terminal or run:" >&2
        echo "  source ~/.bashrc  # or ~/.zshrc" >&2
        return 1
    fi
    return 0
}

# Get cursor-agent version
get_cursor_agent_version() {
    if check_cursor_agent_installed 2>/dev/null; then
        "$CURSOR_AGENT_CMD" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Check if authentication is configured
check_cursor_auth() {
    # Check for API key environment variable
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        return 0
    fi
    
    # cursor-agent may have its own auth mechanism via the IDE
    if check_cursor_agent_installed 2>/dev/null; then
        return 0
    fi
    
    log_status "WARN" "cursor-agent authentication status unknown"
    return 1
}

# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

# Initialize project cursor configuration
init_cursor_project_config() {
    local project_dir=${1:-.}
    local config_file="$project_dir/$CURSOR_CONFIG_DIR/cli.json"
    
    mkdir -p "$project_dir/$CURSOR_CONFIG_DIR"
    
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" << 'EOF'
{
  "permissions": {
    "allow": [
      "Shell(git)",
      "Shell(git status)",
      "Shell(git diff)",
      "Shell(git diff --name-only)",
      "Shell(git add)",
      "Shell(git add .)",
      "Shell(git commit)",
      "Shell(git log)",
      "Shell(npm)",
      "Shell(npm test)",
      "Shell(npm install)",
      "Shell(npm run)",
      "Shell(npx)",
      "Shell(bats)",
      "Shell(pytest)",
      "Shell(go test)",
      "Shell(cargo test)",
      "Shell(make)",
      "Shell(make test)",
      "Shell(ls)",
      "Shell(ls -la)",
      "Shell(cat)",
      "Shell(head)",
      "Shell(tail)",
      "Shell(grep)",
      "Shell(find)",
      "Shell(mkdir)",
      "Shell(mkdir -p)",
      "Shell(touch)",
      "Shell(cp)",
      "Shell(mv)",
      "Shell(echo)",
      "Shell(wc)",
      "Shell(sort)",
      "Shell(uniq)",
      "Shell(jq)",
      "Read(**/*)",
      "Write(src/**/*)",
      "Write(lib/**/*)",
      "Write(tests/**/*)",
      "Write(test/**/*)",
      "Write(docs/**/*)",
      "Write(examples/**/*)",
      "Write(specs/**/*)",
      "Write(logs/**/*)",
      "Write(sprints/**/*)",
      "Write(reviews/**/*)",
      "Write(prompts/**/*)",
      "Write(@fix_plan.md)",
      "Write(@AGENT.md)",
      "Write(PROMPT.md)",
      "Write(README.md)",
      "Write(backlog.json)",
      "Write(.sprinty/**/*)",
      "Write(*.md)",
      "Write(*.json)",
      "Write(*.yaml)",
      "Write(*.yml)",
      "Write(*.ts)",
      "Write(*.tsx)",
      "Write(*.js)",
      "Write(*.jsx)",
      "Write(*.py)",
      "Write(*.go)",
      "Write(*.rs)",
      "Write(*.sh)",
      "Write(*.bash)",
      "Write(Makefile)",
      "Write(Dockerfile)",
      "Write(.gitignore)"
    ],
    "deny": [
      "Shell(rm -rf /)",
      "Shell(rm -rf /*)",
      "Shell(rm -rf ~)",
      "Shell(rm -rf $HOME)",
      "Shell(sudo)",
      "Shell(su)",
      "Shell(chmod 777)",
      "Shell(chown)",
      "Shell(curl | bash)",
      "Shell(wget | bash)",
      "Read(.env)",
      "Read(.env.*)",
      "Read(.env.local)",
      "Read(.env.production)",
      "Read(**/*.key)",
      "Read(**/*.pem)",
      "Read(**/*.p12)",
      "Read(**/*secret*)",
      "Read(**/*password*)",
      "Read(**/*credentials*)",
      "Read(**/id_rsa)",
      "Read(**/id_ed25519)",
      "Read(**/.ssh/*)",
      "Write(.env)",
      "Write(.env.*)",
      "Write(**/*.key)",
      "Write(**/*.pem)",
      "Write(**/*.p12)"
    ]
  }
}
EOF
        log_status "SUCCESS" "Created cursor configuration: $config_file"
        return 0
    else
        log_debug "Cursor configuration already exists: $config_file"
        return 0
    fi
}

# ============================================================================
# PROMPT GENERATION
# ============================================================================

# Generate prompt file for a given role and phase
# Usage: generate_prompt <role> <phase> <sprint_id> [context_json]
generate_prompt() {
    local role=$1
    local phase=$2
    local sprint_id=$3
    local context=${4:-"{}"}
    
    # Ensure output directory exists
    mkdir -p "$AGENT_OUTPUT_DIR"
    
    # Determine base prompt file - use special prompt for final_qa phase
    local base_prompt_file
    if [[ "$phase" == "final_qa" ]]; then
        base_prompt_file="$PROMPTS_DIR/final_qa.md"
    else
        base_prompt_file="$PROMPTS_DIR/${role}.md"
    fi
    local output_prompt_file="$AGENT_OUTPUT_DIR/prompt_${role}_${phase}_sprint${sprint_id}.md"
    
    if [[ ! -f "$base_prompt_file" ]]; then
        log_status "ERROR" "Prompt file not found: $base_prompt_file"
        return 1
    fi
    
    # Read base prompt
    local base_prompt
    base_prompt=$(cat "$base_prompt_file")
    
    # Get container additions if in container mode
    local container_additions=""
    if [[ "$SPRINTY_IN_CONTAINER" == "true" ]]; then
        container_additions=$(get_container_prompt_additions 2>/dev/null || echo "")
    fi
    
    # Add dynamic context
    cat > "$output_prompt_file" << EOF
$base_prompt
$container_additions

---

## Current Context

- **Sprint**: $sprint_id
- **Phase**: $phase
- **Role**: $role
- **Timestamp**: $(get_iso_timestamp)
- **Environment**: ${SPRINTY_IN_CONTAINER:+Container (sandbox mode)}${SPRINTY_IN_CONTAINER:-Host}

### Session Context
\`\`\`json
$context
\`\`\`

---

**IMPORTANT**: Your response MUST end with a SPRINTY_STATUS block. See the prompt above for the required format.
EOF
    
    echo "$output_prompt_file"
}

# Generate context JSON for prompt
# Usage: generate_context_json
generate_context_json() {
    local sprint_id=$(jq -r '.current_sprint // 0' "${SPRINTY_DIR:-.sprinty}/sprint_state.json" 2>/dev/null || echo "0")
    local phase=$(jq -r '.current_phase // "initialization"' "${SPRINTY_DIR:-.sprinty}/sprint_state.json" 2>/dev/null || echo "initialization")
    
    # Get backlog stats
    local backlog_stats="{}"
    if [[ -f "backlog.json" ]]; then
        backlog_stats=$(jq '{
            total_items: (.items | length),
            total_points: ([.items[].story_points] | add // 0),
            by_status: (reduce .items[] as $item ({}; .[$item.status] += 1))
        }' backlog.json 2>/dev/null || echo "{}")
    fi
    
    # Get sprint-specific stats
    local sprint_stats="{}"
    if [[ -f "backlog.json" ]] && [[ $sprint_id -gt 0 ]]; then
        sprint_stats=$(jq --argjson s "$sprint_id" '{
            sprint_items: ([.items[] | select(.sprint_id == $s)] | length),
            sprint_points: ([.items[] | select(.sprint_id == $s) | .story_points] | add // 0),
            completed_points: ([.items[] | select(.sprint_id == $s and .status == "done") | .story_points] | add // 0)
        }' backlog.json 2>/dev/null || echo "{}")
    fi
    
    # Build context
    jq -n \
        --argjson sprint "$sprint_id" \
        --arg phase "$phase" \
        --argjson backlog "$backlog_stats" \
        --argjson sprint_stats "$sprint_stats" \
        '{
            sprint_id: $sprint,
            phase: $phase,
            backlog: $backlog,
            sprint_stats: $sprint_stats
        }'
}

# ============================================================================
# CURSOR-AGENT EXECUTION
# ============================================================================

# Execute cursor-agent with prompt file
# Usage: execute_cursor_agent <prompt_file> <output_file> [timeout_seconds]
# Returns: 0 on success, 1 on error, 124 on timeout
# ERROR-PROOF: This function will NOT cause script exit due to set -e
execute_cursor_agent() {
    local prompt_file=$1
    local output_file=$2
    local timeout_seconds=${3:-$((CURSOR_TIMEOUT_MINUTES * 60))}
    local max_retries=${CURSOR_AGENT_MAX_RETRIES:-3}
    local retry_delay=${CURSOR_AGENT_RETRY_DELAY:-10}
    
    # Validate prompt file exists
    if [[ ! -f "$prompt_file" ]]; then
        log_status "ERROR" "Prompt file not found: $prompt_file"
        echo "ERROR: Prompt file not found: $prompt_file" > "$output_file"
        return 1
    fi
    
    # Read prompt content (with error handling for set -e)
    local prompt_content=""
    prompt_content=$(cat "$prompt_file" 2>/dev/null) || {
        log_status "ERROR" "Failed to read prompt file: $prompt_file"
        echo "ERROR: Failed to read prompt file: $prompt_file" > "$output_file"
        return 1
    }
    
    # Build cursor-agent command arguments
    local cmd_args=("-p")
    
    # Add model if specified
    if [[ -n "$CURSOR_MODEL" ]]; then
        cmd_args+=("--model" "$CURSOR_MODEL")
    fi
    
    # Add output format if specified
    if [[ -n "$CURSOR_OUTPUT_FORMAT" && "$CURSOR_OUTPUT_FORMAT" != "text" ]]; then
        cmd_args+=("--output-format" "$CURSOR_OUTPUT_FORMAT")
    fi
    
    # Add the prompt as the final argument
    cmd_args+=("$prompt_content")
    
    # Retry loop for transient failures
    local attempt=0
    local exit_code=0
    
    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        
        if [[ $attempt -gt 1 ]]; then
            log_status "WARN" "Retry attempt $attempt/$max_retries after ${retry_delay}s delay..."
            sleep "$retry_delay"
        fi
        
        log_status "INFO" "Executing cursor-agent (timeout: ${timeout_seconds}s, attempt: $attempt/$max_retries)..."
        
        # Execute with timeout - USE || true TO PREVENT set -e EXIT
        # The || true ensures the command always "succeeds" for set -e purposes
        # We capture the actual exit code separately
        exit_code=0
        timeout --kill-after=30s ${timeout_seconds}s "$CURSOR_AGENT_CMD" "${cmd_args[@]}" > "$output_file" 2>&1 || exit_code=$?
        
        # Log what happened
        log_debug "cursor-agent exited with code: $exit_code"
        
        # Check output file size
        local output_size=0
        if [[ -f "$output_file" ]]; then
            output_size=$(wc -c < "$output_file" 2>/dev/null || echo "0")
        fi
        
        # Handle different exit scenarios
        case $exit_code in
            0)
                # Success
                if [[ $output_size -gt 0 ]]; then
                    log_status "SUCCESS" "cursor-agent completed (output: ${output_size} bytes)"
                    return 0
                else
                    log_status "WARN" "cursor-agent returned 0 but produced no output"
                    echo "WARNING: cursor-agent returned success but produced no output" >> "$output_file"
                    # Don't retry for this - might be valid empty response
                    return 0
                fi
                ;;
            124)
                # Timeout
                echo "TIMEOUT: cursor-agent execution timed out after ${timeout_seconds}s" >> "$output_file"
                log_status "WARN" "cursor-agent execution timed out (attempt $attempt)"
                # Don't retry timeouts - they're too expensive
                return 124
                ;;
            137|143)
                # Killed by signal (SIGKILL=137, SIGTERM=143)
                echo "ERROR: cursor-agent was killed (signal $exit_code)" >> "$output_file"
                log_status "ERROR" "cursor-agent was killed by signal (exit code: $exit_code)"
                # Retry - might be transient resource issue
                ;;
            *)
                # Other errors
                log_status "WARN" "cursor-agent failed (exit code: $exit_code, output: ${output_size} bytes)"
                
                # Check if output contains specific error types
                if [[ $output_size -gt 0 ]]; then
                    # Check for connection errors (should retry)
                    if grep -qiE "ConnectError|connection.*refused|unavailable|ECONNREFUSED|network" "$output_file" 2>/dev/null; then
                        log_status "WARN" "Connection error detected - will retry"
                        continue
                    fi
                    
                    # Check for rate limit (should retry with longer delay)
                    if grep -qiE "rate.?limit|too many requests|429|throttl" "$output_file" 2>/dev/null; then
                        log_status "WARN" "Rate limit detected - will retry with longer delay"
                        retry_delay=$((retry_delay * 2))
                        continue
                    fi
                    
                    # Check for auth errors (don't retry)
                    if grep -qiE "unauthorized|authentication|invalid.*key|forbidden" "$output_file" 2>/dev/null; then
                        log_status "ERROR" "Authentication error - not retrying"
                        return 1
                    fi
                fi
                
                # Unknown error - retry anyway
                echo "ERROR: cursor-agent failed with exit code $exit_code" >> "$output_file"
                ;;
        esac
    done
    
    # All retries exhausted
    log_status "ERROR" "cursor-agent failed after $max_retries attempts (last exit code: $exit_code)"
    echo "ERROR: All $max_retries retry attempts failed" >> "$output_file"
    return $exit_code
}

# Execute cursor-agent with raw prompt string (not from file)
# ERROR-PROOF: This function will NOT cause script exit due to set -e
execute_cursor_agent_raw() {
    local prompt_string=$1
    local output_file=$2
    local timeout_seconds=${3:-$((CURSOR_TIMEOUT_MINUTES * 60))}
    
    local cmd_args=("-p")
    
    if [[ -n "$CURSOR_MODEL" ]]; then
        cmd_args+=("--model" "$CURSOR_MODEL")
    fi
    
    cmd_args+=("$prompt_string")
    
    # Use || to prevent set -e from exiting the script
    local exit_code=0
    timeout --kill-after=30s ${timeout_seconds}s "$CURSOR_AGENT_CMD" "${cmd_args[@]}" > "$output_file" 2>&1 || exit_code=$?
    
    return $exit_code
}

# ============================================================================
# OPENCODE IMPLEMENTATION
# ============================================================================

# Check if opencode CLI is installed
check_opencode_installed() {
    if ! command -v opencode &> /dev/null; then
        log_status "ERROR" "opencode CLI not found"
        echo "" >&2
        echo "Install opencode with:" >&2
        echo "  curl -fsSL https://opencode.ai/install | bash" >&2
        echo "" >&2
        echo "After installation, restart your terminal or run:" >&2
        echo "  source ~/.bashrc  # or ~/.zshrc" >&2
        return 1
    fi
    return 0
}

# Get opencode version
get_opencode_version() {
    if check_opencode_installed 2>/dev/null; then
        opencode --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Check if opencode authentication is configured
check_opencode_auth() {
    # opencode typically works without explicit auth for free models
    # but may require API key for certain models
    if [[ -n "${OPENCODE_API_KEY:-}" ]]; then
        return 0
    fi
    
    # Check if opencode is installed and can run
    if check_opencode_installed 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Initialize project opencode configuration
init_opencode_project_config() {
    local project_dir=${1:-.}
    
    # opencode doesn't require a project-specific config file like cursor
    # but we can create a .opencode directory for any future config needs
    mkdir -p "$project_dir/.opencode"
    
    log_status "SUCCESS" "opencode project directory initialized"
    return 0
}

# Execute opencode with prompt file
# Usage: execute_opencode <prompt_file> <output_file> [timeout_seconds]
execute_opencode() {
    local prompt_file=$1
    local output_file=$2
    local timeout_seconds=${3:-$((AGENT_TIMEOUT_MINUTES * 60))}
    
    # Validate prompt file exists
    if [[ ! -f "$prompt_file" ]]; then
        log_status "ERROR" "Prompt file not found: $prompt_file"
        return 1
    fi
    
    # Read prompt content
    local prompt_content
    prompt_content=$(cat "$prompt_file") || {
        log_status "ERROR" "Failed to read prompt file: $prompt_file"
        return 1
    }
    
    # Build opencode command arguments
    local cmd_args=("run")
    
    # Add model if specified
    if [[ -n "$AGENT_MODEL" ]]; then
        cmd_args+=("--model" "$AGENT_MODEL")
    fi
    
    # Add the prompt as the final argument
    cmd_args+=("$prompt_content")
    
    log_status "INFO" "Executing opencode (timeout: ${timeout_seconds}s)..."
    log_debug "Using model: ${AGENT_MODEL}"
    log_debug "Command: opencode ${cmd_args[*]:0:2} <prompt-content>"
    
    # Execute with timeout (--kill-after ensures SIGKILL if SIGTERM fails)
    # Redirect stderr to /dev/null to avoid noise/progress indicators in output
    timeout --kill-after=30s ${timeout_seconds}s opencode "${cmd_args[@]}" 2>/dev/null > "$output_file"
    local exit_code=$?
    
    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        echo "TIMEOUT: opencode execution timed out after ${timeout_seconds}s" >> "$output_file"
        log_status "WARN" "opencode execution timed out"
    fi
    
    return $exit_code
}

# Execute opencode with raw prompt string (not from file)
execute_opencode_raw() {
    local prompt_string=$1
    local output_file=$2
    local timeout_seconds=${3:-$((AGENT_TIMEOUT_MINUTES * 60))}
    
    local cmd_args=("run")
    
    if [[ -n "$AGENT_MODEL" ]]; then
        cmd_args+=("--model" "$AGENT_MODEL")
    fi
    
    cmd_args+=("$prompt_string")
    
    # Redirect stderr to /dev/null to avoid noise/progress indicators
    timeout --kill-after=30s ${timeout_seconds}s opencode "${cmd_args[@]}" 2>/dev/null > "$output_file"
    return $?
}

# ============================================================================
# OUTPUT PARSING - SPRINTY_STATUS BLOCK
# ============================================================================

# Extract SPRINTY_STATUS block from output
extract_sprinty_status() {
    local output_file=$1
    
    if grep -q -- "---SPRINTY_STATUS---" "$output_file" 2>/dev/null; then
        sed -n '/---SPRINTY_STATUS---/,/---END_SPRINTY_STATUS---/p' "$output_file" | \
            sed '/---SPRINTY_STATUS---/d' | sed '/---END_SPRINTY_STATUS---/d'
    fi
}

# Get specific field from SPRINTY_STATUS block
# Usage: get_sprinty_status_field <output_file> <field_name>
get_sprinty_status_field() {
    local output_file=$1
    local field_name=$2
    
    extract_sprinty_status "$output_file" | grep "^${field_name}:" | cut -d: -f2- | xargs
}

# Parse full SPRINTY_STATUS block to JSON
parse_sprinty_status_to_json() {
    local output_file=$1
    
    local status_block
    status_block=$(extract_sprinty_status "$output_file")
    
    if [[ -z "$status_block" ]]; then
        echo "{}"
        return 0
    fi
    
    # Parse each field
    local role=$(echo "$status_block" | grep "^ROLE:" | cut -d: -f2 | xargs)
    local phase=$(echo "$status_block" | grep "^PHASE:" | cut -d: -f2 | xargs)
    local sprint=$(echo "$status_block" | grep "^SPRINT:" | cut -d: -f2 | xargs)
    local tasks_completed=$(echo "$status_block" | grep "^TASKS_COMPLETED:" | cut -d: -f2 | xargs)
    local tasks_remaining=$(echo "$status_block" | grep "^TASKS_REMAINING:" | cut -d: -f2 | xargs)
    local blockers=$(echo "$status_block" | grep "^BLOCKERS:" | cut -d: -f2- | xargs)
    local story_points=$(echo "$status_block" | grep "^STORY_POINTS_DONE:" | cut -d: -f2 | xargs)
    local tests_status=$(echo "$status_block" | grep "^TESTS_STATUS:" | cut -d: -f2 | xargs)
    local phase_complete=$(echo "$status_block" | grep "^PHASE_COMPLETE:" | cut -d: -f2 | xargs)
    local project_done=$(echo "$status_block" | grep "^PROJECT_DONE:" | cut -d: -f2 | xargs)
    local next_action=$(echo "$status_block" | grep "^NEXT_ACTION:" | cut -d: -f2- | xargs)
    
    # Build JSON
    jq -n \
        --arg role "${role:-unknown}" \
        --arg phase "${phase:-unknown}" \
        --arg sprint "${sprint:-0}" \
        --arg tasks_completed "${tasks_completed:-0}" \
        --arg tasks_remaining "${tasks_remaining:-0}" \
        --arg blockers "${blockers:-none}" \
        --arg story_points "${story_points:-0}" \
        --arg tests_status "${tests_status:-NOT_RUN}" \
        --arg phase_complete "${phase_complete:-false}" \
        --arg project_done "${project_done:-false}" \
        --arg next_action "${next_action:-}" \
        '{
            role: $role,
            phase: $phase,
            sprint: ($sprint | tonumber),
            tasks_completed: ($tasks_completed | tonumber),
            tasks_remaining: ($tasks_remaining | tonumber),
            blockers: $blockers,
            story_points_done: ($story_points | tonumber),
            tests_status: $tests_status,
            phase_complete: ($phase_complete == "true"),
            project_done: ($project_done == "true"),
            next_action: $next_action
        }'
}

# Check if phase is complete based on agent response
check_phase_complete_from_response() {
    local output_file=$1
    
    local phase_complete=$(get_sprinty_status_field "$output_file" "PHASE_COMPLETE")
    [[ "$phase_complete" == "true" ]]
}

# Check if project is done based on agent response
check_project_done_from_response() {
    local output_file=$1
    
    local project_done=$(get_sprinty_status_field "$output_file" "PROJECT_DONE")
    [[ "$project_done" == "true" ]]
}

# ============================================================================
# STRICT FILE-BASED STATUS EXTRACTION (No fallback)
# ============================================================================

# Parse agent status from status.json ONLY
# Returns error if status.json not properly updated by agent
parse_agent_status_enhanced() {
    local output_file=$1
    local expected_role=$2  # NEW: expected agent role
    local status_json
    
    # Check status.json exists
    local status_file=$(get_agent_status_file)
    if [[ ! -f "$status_file" ]]; then
        log_status "ERROR" "status.json not found at $status_file"
        echo "{}"
        return 1
    fi
    
    # Get status from file
    status_json=$(get_agent_status_json)
    
    if [[ "$status_json" == "{}" || "$status_json" == "null" ]]; then
        log_status "ERROR" "agent_status section missing in status.json"
        echo "{}"
        return 1
    fi
    
    # Check if agent actually updated it (role should not be empty)
    local role=$(echo "$status_json" | jq -r '.role // ""')
    local last_updated=$(echo "$status_json" | jq -r '.last_updated // ""')
    
    if [[ -z "$role" || "$role" == "null" ]]; then
        log_status "ERROR" "Agent did not update status.json - role field is empty"
        log_status "ERROR" "Agent MUST update .sprinty/status.json with jq command"
        echo "{}"
        return 1
    fi
    
    # NEW: Validate role matches expected agent
    if [[ -n "$expected_role" && "$role" != "$expected_role" ]]; then
        log_status "ERROR" "Role mismatch: expected '$expected_role' but got '$role'"
        log_status "ERROR" "Agent crashed or did not update status.json"
        log_status "ERROR" "Cannot proceed with stale status from previous phase"
        echo "{}"
        return 1
    fi
    
    if [[ -z "$last_updated" || "$last_updated" == "null" ]]; then
        log_status "WARN" "status.json last_updated field is empty (agent may not have updated it)"
    fi
    
    log_status "SUCCESS" "Status extracted from status.json (role: $role)"
    echo "$status_json"
    return 0
}

# Strict phase complete check (file-based only)
check_phase_complete_enhanced() {
    local output_file=$1
    
    # Only check status.json
    if is_phase_complete_from_status; then
        log_status "INFO" "Phase complete detected from status.json"
        return 0
    fi
    
    log_debug "Phase not complete (status.json: phase_complete=false)"
    return 1
}

# Strict project done check (file-based + backlog verification + Final QA)
check_project_done_enhanced() {
    local output_file=$1
    
    # CRITICAL: Project is only truly done if Final QA Sprint has passed
    # Even if agent says project_done or backlog is complete, we require Final QA
    if ! has_final_qa_passed 2>/dev/null; then
        log_debug "Project not done - Final QA Sprint not yet passed"
        return 1
    fi
    
    # Final QA has passed - now verify with status.json or backlog
    if is_project_done_from_status; then
        log_status "INFO" "Project done: Final QA passed + status.json confirms"
        return 0
    fi
    
    # Also check backlog completion as safety check
    if is_project_done; then
        log_status "INFO" "Project done: Final QA passed + all backlog items complete"
        return 0
    fi
    
    log_debug "Project not done"
    return 1
}

# ============================================================================
# ERROR DETECTION
# ============================================================================

# Check for rate limit errors in output
# Note: Pattern must be specific to avoid false positives (e.g., "RateLimiter" task name)
detect_rate_limit_error() {
    local output_file=$1
    
    # Look for actual error messages, not task names or code references
    if grep -qiE "rate limit (exceeded|reached|hit|error)|rate.limited|too many requests|quota exceeded|request throttled|throttling error|429|slow down" "$output_file" 2>/dev/null; then
        return 0  # Rate limit detected
    fi
    return 1  # No rate limit
}

# Check for authentication errors
detect_auth_error() {
    local output_file=$1
    
    if grep -qiE "unauthorized|authentication.*failed|invalid.*api.*key|not.*authenticated|access.*denied" "$output_file" 2>/dev/null; then
        return 0  # Auth error detected
    fi
    return 1  # No auth error
}

# Check for connection errors
detect_connection_error() {
    local output_file=$1
    
    if grep -qiE "ConnectError|connection.*refused|connection.*failed|unavailable|network.*error|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|getaddrinfo|DNS.*error|socket.*error|could not connect" "$output_file" 2>/dev/null; then
        return 0  # Connection error detected
    fi
    return 1  # No connection error
}

# Check for permission errors
detect_permission_error() {
    local output_file=$1
    
    if grep -qiE "permission.*denied|not.*allowed|forbidden|blocked.*by.*permission" "$output_file" 2>/dev/null; then
        return 0  # Permission error detected
    fi
    return 1  # No permission error
}

# Check for timeout
detect_timeout() {
    local output_file=$1
    
    if grep -q "TIMEOUT:" "$output_file" 2>/dev/null; then
        return 0  # Timeout detected
    fi
    return 1  # No timeout
}

# Check if agent reported blockers
detect_blockers() {
    local output_file=$1
    
    local blockers=$(get_sprinty_status_field "$output_file" "BLOCKERS")
    if [[ -n "$blockers" && "$blockers" != "none" && "$blockers" != "None" ]]; then
        echo "$blockers"
        return 0  # Has blockers
    fi
    return 1  # No blockers
}

# ============================================================================
# HIGH-LEVEL EXECUTION HELPERS
# ============================================================================

# Execute agent for a specific role/phase combination
# Usage: run_agent <role> <phase> <sprint_id>
# Returns: 0 on success, 1 on error, 2 on rate limit, 3 on timeout, 4 on connection error
# ERROR-PROOF: This function will NOT cause script exit due to set -e
run_agent() {
    local role=$1
    local phase=$2
    local sprint_id=$3
    
    # Generate context (error-proof)
    local context=""
    context=$(generate_context_json 2>/dev/null) || {
        log_status "WARN" "Failed to generate context, using empty context"
        context="{}"
    }
    
    # Generate prompt (error-proof)
    local prompt_file=""
    prompt_file=$(generate_prompt "$role" "$phase" "$sprint_id" "$context" 2>/dev/null) || {
        log_status "ERROR" "Failed to generate prompt for $role in $phase"
        return 1
    }
    
    if [[ -z "$prompt_file" || ! -f "$prompt_file" ]]; then
        log_status "ERROR" "Prompt file not created or empty: $prompt_file"
        return 1
    fi
    
    # Prepare output file
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local output_file="$AGENT_OUTPUT_DIR/output_${role}_${phase}_sprint${sprint_id}_${timestamp}.log"
    
    # Ensure output directory exists
    mkdir -p "$AGENT_OUTPUT_DIR" 2>/dev/null || true
    
    # Create output file to ensure it exists
    touch "$output_file" 2>/dev/null || true
    
    log_status "INFO" "Running $role agent for $phase phase (sprint $sprint_id)"
    
    # Execute agent (error-proof - captures exit code without triggering set -e)
    local exit_code=0
    execute_agent "$prompt_file" "$output_file" || exit_code=$?
    
    log_debug "Agent execution returned: $exit_code"
    
    # Handle timeout specifically
    if [[ $exit_code -eq 124 ]]; then
        log_status "WARN" "Agent execution timed out"
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        return 3
    fi
    
    # Check for specific error types in output (error-proof with || true)
    if detect_rate_limit_error "$output_file" 2>/dev/null; then
        log_status "WARN" "Rate limit detected"
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        return 2
    fi
    
    if detect_auth_error "$output_file" 2>/dev/null; then
        log_status "ERROR" "Authentication error"
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        return 1
    fi
    
    if detect_connection_error "$output_file" 2>/dev/null; then
        log_status "ERROR" "Connection error - check network connectivity"
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        return 4
    fi
    
    # Handle non-zero exit from agent
    if [[ $exit_code -ne 0 ]]; then
        log_status "ERROR" "Agent execution failed (exit code: $exit_code)"
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        return 1
    fi
    
    # Parse and validate response (error-proof)
    local status_json=""
    local parse_result=0
    status_json=$(parse_agent_status_enhanced "$output_file" "$role" 2>/dev/null) || parse_result=$?
    
    if [[ $parse_result -ne 0 || -z "$status_json" || "$status_json" == "{}" ]]; then
        log_status "ERROR" "Agent did not update status.json properly"
        log_status "ERROR" "Agent MUST update .sprinty/status.json with the jq command from prompts"
        log_status "ERROR" "This is a REQUIRED step for Sprinty orchestration"
        
        # Store output file path even on failure
        echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
        
        # Return error to indicate agent failed to follow instructions
        return 1
    fi
    
    log_status "SUCCESS" "Agent completed and updated status.json"
    log_debug "Status: $status_json"
    
    # Store latest output file path
    echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output" 2>/dev/null || true
    
    return 0
}

# Get last agent output file
get_last_agent_output() {
    if [[ -f "$AGENT_OUTPUT_DIR/.last_output" ]]; then
        cat "$AGENT_OUTPUT_DIR/.last_output"
    fi
}

# ============================================================================
# STATUS DISPLAY
# ============================================================================

# Print agent status
print_agent_status() {
    local agent_name
    case "$AGENT_CLI_TOOL" in
        cursor-agent)
            agent_name="Cursor Agent"
            ;;
        opencode)
            agent_name="OpenCode"
            ;;
        *)
            agent_name="Unknown Agent"
            ;;
    esac
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              $agent_name Status                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    # Agent type
    echo -e "Agent CLI:        $AGENT_CLI_TOOL"
    
    # Installation status
    if check_agent_installed 2>/dev/null; then
        echo -e "Installation:     ${GREEN}✓ Installed${NC}"
        echo -e "Version:          $(get_agent_version)"
    else
        echo -e "Installation:     ${RED}✗ Not installed${NC}"
    fi
    
    # Auth status
    if check_agent_auth 2>/dev/null; then
        echo -e "Authentication:   ${GREEN}✓ Configured${NC}"
    else
        echo -e "Authentication:   ${YELLOW}⚠ Unknown${NC}"
    fi
    
    # Config status (for cursor-agent)
    if [[ "$AGENT_CLI_TOOL" == "cursor-agent" && -f "$CURSOR_CONFIG_DIR/cli.json" ]]; then
        echo -e "Project Config:   ${GREEN}✓ Present${NC}"
    elif [[ "$AGENT_CLI_TOOL" == "opencode" && -d ".opencode" ]]; then
        echo -e "Project Config:   ${GREEN}✓ Present${NC}"
    else
        echo -e "Project Config:   ${YELLOW}⚠ Not configured${NC}"
    fi
    
    # Model and settings
    echo -e "Model:            $AGENT_MODEL"
    echo -e "Timeout:          ${AGENT_TIMEOUT_MINUTES} minutes"
    echo -e "Output Format:    $AGENT_OUTPUT_FORMAT"
    
    echo ""
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

# Export configuration
export AGENT_CLI_TOOL AGENT_MODEL AGENT_TIMEOUT_MINUTES AGENT_OUTPUT_FORMAT
export CURSOR_AGENT_CMD CURSOR_OUTPUT_FORMAT CURSOR_MODEL
export CURSOR_CONFIG_DIR CURSOR_TIMEOUT_MINUTES
export PROMPTS_DIR AGENT_OUTPUT_DIR

# Export abstraction layer functions
export -f check_agent_installed
export -f get_agent_version
export -f check_agent_auth
export -f init_agent_project_config
export -f execute_agent
export -f execute_agent_raw

# Export cursor-agent specific functions
export -f check_cursor_agent_installed
export -f get_cursor_agent_version
export -f check_cursor_auth
export -f init_cursor_project_config
export -f execute_cursor_agent
export -f execute_cursor_agent_raw

# Export opencode specific functions
export -f check_opencode_installed
export -f get_opencode_version
export -f check_opencode_auth
export -f init_opencode_project_config
export -f execute_opencode
export -f execute_opencode_raw

# Export common functions
export -f detect_agent_cli_tool
export -f get_agent_model
export -f get_agent_timeout
export -f generate_prompt
export -f generate_context_json
export -f extract_sprinty_status
export -f get_sprinty_status_field
export -f parse_sprinty_status_to_json
export -f parse_agent_status_enhanced
export -f check_phase_complete_from_response
export -f check_project_done_from_response
export -f check_phase_complete_enhanced
export -f check_project_done_enhanced
export -f detect_rate_limit_error
export -f detect_auth_error
export -f detect_connection_error
export -f detect_permission_error
export -f detect_timeout
export -f detect_blockers
export -f run_agent
export -f get_last_agent_output
export -f print_agent_status
