#!/usr/bin/env bash
# Sprinty Agent Adapter
# Cursor-agent CLI integration for Sprinty orchestrator
# Adapted from ralph-cursor-agent/lib/cursor_adapter.sh

set -e

# Source utilities (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

CURSOR_AGENT_CMD="${CURSOR_AGENT_CMD:-cursor-agent}"
CURSOR_OUTPUT_FORMAT="${CURSOR_OUTPUT_FORMAT:-text}"
CURSOR_MODEL="${CURSOR_MODEL:-opus-4.5-thinking}"
CURSOR_CONFIG_DIR=".cursor"
CURSOR_TIMEOUT_MINUTES="${CURSOR_TIMEOUT_MINUTES:-15}"

# Prompts directory
PROMPTS_DIR="${PROMPTS_DIR:-prompts}"

# Output directory for agent responses
AGENT_OUTPUT_DIR="${AGENT_OUTPUT_DIR:-logs/agent_output}"

# ============================================================================
# CURSOR-AGENT DETECTION & VALIDATION
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
    
    local base_prompt_file="$PROMPTS_DIR/${role}.md"
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
execute_cursor_agent() {
    local prompt_file=$1
    local output_file=$2
    local timeout_seconds=${3:-$((CURSOR_TIMEOUT_MINUTES * 60))}
    
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
    
    log_status "INFO" "Executing cursor-agent (timeout: ${timeout_seconds}s)..."
    
    # Execute with timeout
    timeout ${timeout_seconds}s "$CURSOR_AGENT_CMD" "${cmd_args[@]}" > "$output_file" 2>&1
    local exit_code=$?
    
    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        echo "TIMEOUT: cursor-agent execution timed out after ${timeout_seconds}s" >> "$output_file"
        log_status "WARN" "cursor-agent execution timed out"
    fi
    
    return $exit_code
}

# Execute cursor-agent with raw prompt string (not from file)
execute_cursor_agent_raw() {
    local prompt_string=$1
    local output_file=$2
    local timeout_seconds=${3:-$((CURSOR_TIMEOUT_MINUTES * 60))}
    
    local cmd_args=("-p")
    
    if [[ -n "$CURSOR_MODEL" ]]; then
        cmd_args+=("--model" "$CURSOR_MODEL")
    fi
    
    cmd_args+=("$prompt_string")
    
    timeout ${timeout_seconds}s "$CURSOR_AGENT_CMD" "${cmd_args[@]}" > "$output_file" 2>&1
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
# Returns: 0 on success, 1 on error, 2 on rate limit, 3 on timeout
run_agent() {
    local role=$1
    local phase=$2
    local sprint_id=$3
    
    # Generate context
    local context
    context=$(generate_context_json)
    
    # Generate prompt
    local prompt_file
    prompt_file=$(generate_prompt "$role" "$phase" "$sprint_id" "$context")
    if [[ $? -ne 0 ]]; then
        log_status "ERROR" "Failed to generate prompt for $role in $phase"
        return 1
    fi
    
    # Prepare output file
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local output_file="$AGENT_OUTPUT_DIR/output_${role}_${phase}_sprint${sprint_id}_${timestamp}.log"
    
    log_status "INFO" "Running $role agent for $phase phase (sprint $sprint_id)"
    
    # Execute agent
    execute_cursor_agent "$prompt_file" "$output_file"
    local exit_code=$?
    
    # Handle errors
    if [[ $exit_code -eq 124 ]]; then
        log_status "WARN" "Agent execution timed out"
        return 3
    fi
    
    if detect_rate_limit_error "$output_file"; then
        log_status "WARN" "Rate limit detected"
        return 2
    fi
    
    if detect_auth_error "$output_file"; then
        log_status "ERROR" "Authentication error"
        return 1
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log_status "ERROR" "Agent execution failed (exit code: $exit_code)"
        return 1
    fi
    
    # Parse and validate response
    local status_json
    status_json=$(parse_sprinty_status_to_json "$output_file")
    
    if [[ "$status_json" == "{}" ]]; then
        log_status "WARN" "No SPRINTY_STATUS block found in response"
    else
        log_status "SUCCESS" "Agent completed successfully"
        log_debug "Status: $status_json"
    fi
    
    # Store latest output file path
    echo "$output_file" > "$AGENT_OUTPUT_DIR/.last_output"
    
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

# Print cursor-agent status
print_agent_status() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Cursor Agent Status                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    # Installation status
    if check_cursor_agent_installed 2>/dev/null; then
        echo -e "Installation:     ${GREEN}✓ Installed${NC}"
        echo -e "Version:          $(get_cursor_agent_version)"
    else
        echo -e "Installation:     ${RED}✗ Not installed${NC}"
    fi
    
    # Auth status
    if check_cursor_auth 2>/dev/null; then
        echo -e "Authentication:   ${GREEN}✓ Configured${NC}"
    else
        echo -e "Authentication:   ${YELLOW}⚠ Unknown${NC}"
    fi
    
    # Config status
    if [[ -f "$CURSOR_CONFIG_DIR/cli.json" ]]; then
        echo -e "Project Config:   ${GREEN}✓ Present${NC}"
    else
        echo -e "Project Config:   ${YELLOW}⚠ Not configured${NC}"
    fi
    
    # Model and settings
    echo -e "Model:            $CURSOR_MODEL"
    echo -e "Timeout:          ${CURSOR_TIMEOUT_MINUTES} minutes"
    echo -e "Output Format:    $CURSOR_OUTPUT_FORMAT"
    
    echo ""
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export CURSOR_AGENT_CMD CURSOR_OUTPUT_FORMAT CURSOR_MODEL
export CURSOR_CONFIG_DIR CURSOR_TIMEOUT_MINUTES
export PROMPTS_DIR AGENT_OUTPUT_DIR

export -f check_cursor_agent_installed
export -f get_cursor_agent_version
export -f check_cursor_auth
export -f init_cursor_project_config
export -f generate_prompt
export -f generate_context_json
export -f execute_cursor_agent
export -f execute_cursor_agent_raw
export -f extract_sprinty_status
export -f get_sprinty_status_field
export -f parse_sprinty_status_to_json
export -f check_phase_complete_from_response
export -f check_project_done_from_response
export -f detect_rate_limit_error
export -f detect_auth_error
export -f detect_permission_error
export -f detect_timeout
export -f detect_blockers
export -f run_agent
export -f get_last_agent_output
export -f print_agent_status
