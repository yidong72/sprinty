#!/usr/bin/env bash
# Sprinty Sprint Manager
# Sprint state management and phase tracking

set -e

# Source utilities and backlog manager (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"
source "$_LIB_DIR/backlog_manager.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

SPRINT_STATE_FILE="${SPRINTY_DIR:-.sprinty}/sprint_state.json"
SPRINTS_DIR="${SPRINTS_DIR:-sprints}"
REVIEWS_DIR="${REVIEWS_DIR:-reviews}"

# Valid phases
VALID_PHASES=("initialization" "planning" "implementation" "qa" "review")

# Default max loops per phase
DEFAULT_PLANNING_MAX_LOOPS=${PLANNING_MAX_LOOPS:-3}
DEFAULT_IMPLEMENTATION_MAX_LOOPS=${IMPLEMENTATION_MAX_LOOPS:-20}
DEFAULT_QA_MAX_LOOPS=${QA_MAX_LOOPS:-5}
DEFAULT_REVIEW_MAX_LOOPS=${REVIEW_MAX_LOOPS:-2}
DEFAULT_MAX_REWORK_CYCLES=${MAX_REWORK_CYCLES:-3}
DEFAULT_MAX_SPRINTS=${MAX_SPRINTS:-10}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize sprint state
init_sprint_state() {
    ensure_sprinty_dir
    mkdir -p "$SPRINTS_DIR"
    mkdir -p "$REVIEWS_DIR"
    
    if [[ -f "$SPRINT_STATE_FILE" ]]; then
        # Validate existing state
        if jq '.' "$SPRINT_STATE_FILE" > /dev/null 2>&1; then
            log_debug "Sprint state already initialized"
            return 0
        fi
        # Invalid JSON, recreate
        rm -f "$SPRINT_STATE_FILE"
    fi
    
    cat > "$SPRINT_STATE_FILE" << EOF
{
    "current_sprint": 0,
    "current_phase": "initialization",
    "phase_loop_count": 0,
    "rework_count": 0,
    "project_done": false,
    "started_at": "$(get_iso_timestamp)",
    "last_updated": "$(get_iso_timestamp)",
    "sprints_history": []
}
EOF
    
    log_status "SUCCESS" "Initialized sprint state"
}

# ============================================================================
# STATE QUERIES
# ============================================================================

# Get sprint state value
get_sprint_state() {
    local field=$1
    
    if [[ ! -f "$SPRINT_STATE_FILE" ]]; then
        init_sprint_state
    fi
    
    local value
    # Use 'has' to check if field exists, then get the value
    # This properly handles false values (jq's // treats false as falsey)
    if jq -e "has(\"$field\")" "$SPRINT_STATE_FILE" >/dev/null 2>&1; then
        value=$(jq -r ".$field" "$SPRINT_STATE_FILE" 2>/dev/null)
    else
        value=""
    fi
    echo "$value"
}

# Get current sprint number
get_current_sprint() {
    get_sprint_state "current_sprint"
}

# Get current phase
get_current_phase() {
    get_sprint_state "current_phase"
}

# Get phase loop count
get_phase_loop_count() {
    get_sprint_state "phase_loop_count"
}

# Get rework count
get_rework_count() {
    get_sprint_state "rework_count"
}

# Check if project is marked done
is_project_marked_done() {
    local done=$(get_sprint_state "project_done")
    [[ "$done" == "true" ]]
}

# ============================================================================
# STATE UPDATES
# ============================================================================

# Update sprint state field
update_sprint_state() {
    local field=$1
    local value=$2
    
    if [[ ! -f "$SPRINT_STATE_FILE" ]]; then
        init_sprint_state
    fi
    
    local timestamp=$(get_iso_timestamp)
    
    # Handle different value types
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        jq --arg field "$field" --argjson val "$value" --arg ts "$timestamp" '
            .[$field] = $val | .last_updated = $ts
        ' "$SPRINT_STATE_FILE" > "${SPRINT_STATE_FILE}.tmp" && mv "${SPRINT_STATE_FILE}.tmp" "$SPRINT_STATE_FILE"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        jq --arg field "$field" --argjson val "$value" --arg ts "$timestamp" '
            .[$field] = $val | .last_updated = $ts
        ' "$SPRINT_STATE_FILE" > "${SPRINT_STATE_FILE}.tmp" && mv "${SPRINT_STATE_FILE}.tmp" "$SPRINT_STATE_FILE"
    else
        jq --arg field "$field" --arg val "$value" --arg ts "$timestamp" '
            .[$field] = $val | .last_updated = $ts
        ' "$SPRINT_STATE_FILE" > "${SPRINT_STATE_FILE}.tmp" && mv "${SPRINT_STATE_FILE}.tmp" "$SPRINT_STATE_FILE"
    fi
    
    log_debug "Updated sprint state: $field = $value"
}

# Set current phase
set_current_phase() {
    local phase=$1
    
    # Validate phase
    local valid=false
    for p in "${VALID_PHASES[@]}"; do
        if [[ "$phase" == "$p" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" == "false" ]]; then
        log_status "ERROR" "Invalid phase: $phase"
        return 1
    fi
    
    update_sprint_state "current_phase" "$phase"
    update_sprint_state "phase_loop_count" 0
    
    log_status "PHASE" "Entered phase: $phase"
}

# Increment phase loop count
increment_phase_loop() {
    local current=$(get_phase_loop_count)
    current=$((current + 1))
    update_sprint_state "phase_loop_count" "$current"
    echo "$current"
}

# ============================================================================
# SPRINT LIFECYCLE
# ============================================================================

# Start a new sprint
start_sprint() {
    local current=$(get_current_sprint)
    local new_sprint=$((current + 1))
    
    # Read max_sprints from config, fallback to default
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    local max_sprints=$DEFAULT_MAX_SPRINTS
    if [[ -f "$config_file" ]]; then
        max_sprints=$(jq -r '.sprint.max_sprints // 10' "$config_file" 2>/dev/null || echo "$DEFAULT_MAX_SPRINTS")
    fi
    
    # Check max sprints
    if [[ $new_sprint -gt $max_sprints ]]; then
        log_status "WARN" "Max sprints reached ($max_sprints)"
        return 21  # Exit code for max sprints
    fi
    
    update_sprint_state "current_sprint" "$new_sprint"
    update_sprint_state "current_phase" "planning"
    update_sprint_state "phase_loop_count" 0
    update_sprint_state "rework_count" 0
    
    # Record sprint start in history
    local timestamp=$(get_iso_timestamp)
    jq --argjson sprint "$new_sprint" --arg ts "$timestamp" '
        .sprints_history += [{
            sprint: $sprint,
            started_at: $ts,
            ended_at: null,
            status: "in_progress"
        }]
    ' "$SPRINT_STATE_FILE" > "${SPRINT_STATE_FILE}.tmp" && mv "${SPRINT_STATE_FILE}.tmp" "$SPRINT_STATE_FILE"
    
    # Create sprint directory
    mkdir -p "$SPRINTS_DIR/sprint_$new_sprint"
    
    log_status "SPRINT" "Started Sprint $new_sprint"
    echo "$new_sprint"
}

# End current sprint
end_sprint() {
    local status=${1:-"completed"}
    local sprint=$(get_current_sprint)
    local timestamp=$(get_iso_timestamp)
    
    # Update sprint history AND reset phase to "planning"
    # Resetting phase prevents false resume detection on next iteration
    # The next execute_sprint() will call start_sprint() which increments sprint number
    jq --argjson sprint "$sprint" --arg ts "$timestamp" --arg status "$status" '
        (.sprints_history[] | select(.sprint == $sprint)).ended_at = $ts |
        (.sprints_history[] | select(.sprint == $sprint)).status = $status |
        .current_phase = "planning" |
        .rework_count = 0
    ' "$SPRINT_STATE_FILE" > "${SPRINT_STATE_FILE}.tmp" && mv "${SPRINT_STATE_FILE}.tmp" "$SPRINT_STATE_FILE"
    
    log_status "SPRINT" "Ended Sprint $sprint ($status)"
}

# Increment rework count
increment_rework() {
    local current=$(get_rework_count)
    current=$((current + 1))
    update_sprint_state "rework_count" "$current"
    
    # Get max from config for display
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    local max_rework=$DEFAULT_MAX_REWORK_CYCLES
    if [[ -f "$config_file" ]]; then
        local config_value=$(jq -r '.sprint.max_rework_cycles // empty' "$config_file" 2>/dev/null)
        [[ -n "$config_value" && "$config_value" != "null" ]] && max_rework=$config_value
    fi
    
    log_status "WARN" "Rework cycle: $current/$max_rework"
    echo "$current"
}

# Check if rework limit exceeded (reads from config.json)
is_rework_limit_exceeded() {
    local count=$(get_rework_count)
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    local max_rework=$DEFAULT_MAX_REWORK_CYCLES
    
    if [[ -f "$config_file" ]]; then
        local config_value=$(jq -r '.sprint.max_rework_cycles // empty' "$config_file" 2>/dev/null)
        [[ -n "$config_value" && "$config_value" != "null" ]] && max_rework=$config_value
    fi
    
    [[ $count -ge $max_rework ]]
}

# ============================================================================
# PHASE COMPLETION CHECKS
# ============================================================================

# Check if phase is complete
is_phase_complete() {
    local phase=${1:-$(get_current_phase)}
    local sprint_id=$(get_current_sprint)
    
    case "$phase" in
        "initialization")
            # Complete when backlog is initialized with items
            if is_backlog_initialized; then
                local count=$(jq '.items | length' "$BACKLOG_FILE")
                [[ $count -gt 0 ]]
            else
                return 1
            fi
            ;;
            
        "planning")
            # Complete when sprint plan exists
            [[ -f "$SPRINTS_DIR/sprint_${sprint_id}/plan.md" ]] || \
            [[ -f "$SPRINTS_DIR/sprint_${sprint_id}_plan.md" ]]
            ;;
            
        "implementation")
            # Complete when no ready/in_progress tasks remain
            local remaining=$(jq --argjson s "$sprint_id" '
                [.items[] | select(.sprint_id == $s and (.status == "ready" or .status == "in_progress"))] | length
            ' "$BACKLOG_FILE")
            [[ $remaining -eq 0 ]]
            ;;
            
        "qa")
            # Complete when no implemented tasks remain (all tested)
            local untested=$(jq --argjson s "$sprint_id" '
                [.items[] | select(.sprint_id == $s and .status == "implemented")] | length
            ' "$BACKLOG_FILE")
            [[ $untested -eq 0 ]]
            ;;
            
        "review")
            # Complete when review document exists
            [[ -f "$REVIEWS_DIR/sprint_${sprint_id}_review.md" ]] || \
            [[ -f "$REVIEWS_DIR/sprint_${sprint_id}/review.md" ]]
            ;;
            
        *)
            return 1
            ;;
    esac
}

# Check if implementation has QA failed tasks
has_tasks_to_rework() {
    local sprint_id=$(get_current_sprint)
    local count=$(jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s and .status == "qa_failed")] | length
    ' "$BACKLOG_FILE")
    [[ $count -gt 0 ]]
}

# Get max loops for current phase (reads from config.json)
get_max_loops_for_phase() {
    local phase=${1:-$(get_current_phase)}
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    
    # Try to read from config, fallback to defaults
    local value=""
    if [[ -f "$config_file" ]]; then
        case "$phase" in
            "planning")       value=$(jq -r '.sprint.planning_max_loops // empty' "$config_file" 2>/dev/null) ;;
            "implementation") value=$(jq -r '.sprint.implementation_max_loops // empty' "$config_file" 2>/dev/null) ;;
            "qa")             value=$(jq -r '.sprint.qa_max_loops // empty' "$config_file" 2>/dev/null) ;;
            "review")         value=$(jq -r '.sprint.review_max_loops // empty' "$config_file" 2>/dev/null) ;;
            "final_qa")       value=$(jq -r '.sprint.qa_max_loops // empty' "$config_file" 2>/dev/null) ;;
        esac
    fi
    
    # Fallback to defaults if config value is empty
    if [[ -z "$value" || "$value" == "null" ]]; then
        case "$phase" in
            "planning")       echo "$DEFAULT_PLANNING_MAX_LOOPS" ;;
            "implementation") echo "$DEFAULT_IMPLEMENTATION_MAX_LOOPS" ;;
            "qa"|"final_qa")  echo "$DEFAULT_QA_MAX_LOOPS" ;;
            "review")         echo "$DEFAULT_REVIEW_MAX_LOOPS" ;;
            *)                echo "10" ;;
        esac
    else
        echo "$value"
    fi
}

# Check if phase loop limit exceeded
is_phase_loop_limit_exceeded() {
    local phase=${1:-$(get_current_phase)}
    local current=$(get_phase_loop_count)
    local max=$(get_max_loops_for_phase "$phase")
    
    [[ $current -ge $max ]]
}

# ============================================================================
# PROJECT COMPLETION
# ============================================================================

# Mark project as done
mark_project_done() {
    update_sprint_state "project_done" "true"
    end_sprint "completed"
    log_status "SUCCESS" "🎉 Project marked as DONE!"
}

# Check if project should be marked done
check_project_completion() {
    # Check backlog completion
    if ! is_backlog_initialized; then
        return 1
    fi
    
    # All items must be done or cancelled
    local undone=$(jq '
        [.items[] | select(.status != "done" and .status != "cancelled")] | length
    ' "$BACKLOG_FILE")
    
    if [[ $undone -eq 0 ]]; then
        local total=$(jq '.items | length' "$BACKLOG_FILE")
        if [[ $total -gt 0 ]]; then
            return 0  # Project complete
        fi
    fi
    
    return 1
}

# ============================================================================
# STATUS DISPLAY
# ============================================================================

# Show agent configuration status
show_agent_config_status() {
    local config_file="${SPRINTY_DIR}/config.json"
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 Agent Configuration                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    if [[ -f "$config_file" ]]; then
        local cli_tool=$(jq -r '.agent.cli_tool // "cursor-agent"' "$config_file" 2>/dev/null || echo "cursor-agent")
        local model=$(jq -r '.agent.model // "unknown"' "$config_file" 2>/dev/null || echo "unknown")
        local timeout=$(jq -r '.agent.timeout_minutes // 15' "$config_file" 2>/dev/null || echo "15")
        
        # Check if agent is installed
        local agent_status=""
        case "$cli_tool" in
            opencode)
                if command -v opencode &> /dev/null; then
                    agent_status="${GREEN}✓ Installed${NC} ($(opencode --version 2>/dev/null || echo 'version unknown'))"
                else
                    agent_status="${RED}✗ Not installed${NC}"
                fi
                ;;
            cursor-agent)
                if command -v cursor-agent &> /dev/null; then
                    agent_status="${GREEN}✓ Installed${NC} ($(cursor-agent --version 2>/dev/null || echo 'version unknown'))"
                else
                    agent_status="${RED}✗ Not installed${NC}"
                fi
                ;;
            *)
                agent_status="${YELLOW}⚠ Unknown agent${NC}"
                ;;
        esac
        
        echo -e "Agent CLI Tool:    ${CYAN}$cli_tool${NC}"
        echo -e "Agent Status:      $agent_status"
        echo -e "Model:             ${CYAN}$model${NC}"
        echo -e "Timeout:           ${timeout} minutes"
    else
        echo -e "${YELLOW}⚠ No configuration file found${NC}"
        echo -e "Using defaults: cursor-agent with opus-4.5-thinking"
    fi
}

# Show sprint status
show_sprint_status() {
    if [[ ! -f "$SPRINT_STATE_FILE" ]]; then
        log_status "WARN" "Sprint state not initialized"
        return 1
    fi
    
    local sprint=$(get_current_sprint)
    local phase=$(get_current_phase)
    local loop=$(get_phase_loop_count)
    local rework=$(get_rework_count)
    local done=$(get_sprint_state "project_done")
    
    # Get max values from config
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    local max_rework=$DEFAULT_MAX_REWORK_CYCLES
    local max_sprints=$DEFAULT_MAX_SPRINTS
    if [[ -f "$config_file" ]]; then
        local config_value=$(jq -r '.sprint.max_rework_cycles // empty' "$config_file" 2>/dev/null)
        [[ -n "$config_value" && "$config_value" != "null" ]] && max_rework=$config_value
        
        config_value=$(jq -r '.sprint.max_sprints // empty' "$config_file" 2>/dev/null)
        [[ -n "$config_value" && "$config_value" != "null" ]] && max_sprints=$config_value
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Sprint Status                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "Current Sprint:    $sprint / $max_sprints"
    echo -e "Current Phase:     $phase"
    echo -e "Phase Loop:        $loop / $(get_max_loops_for_phase)"
    echo -e "Rework Cycles:     $rework / $max_rework"
    echo -e "Project Done:      $done"
    echo ""
    
    # Show sprint-specific stats if we have a backlog
    if is_backlog_initialized && [[ $sprint -gt 0 ]]; then
        local sprint_items=$(jq --argjson s "$sprint" '[.items[] | select(.sprint_id == $s)] | length' "$BACKLOG_FILE")
        local sprint_done=$(jq --argjson s "$sprint" '[.items[] | select(.sprint_id == $s and .status == "done")] | length' "$BACKLOG_FILE")
        local sprint_points=$(get_sprint_points "$sprint")
        local completed_points=$(get_sprint_completed_points "$sprint")
        
        echo -e "${GREEN}Sprint $sprint Progress:${NC}"
        echo -e "  Tasks: $sprint_done / $sprint_items"
        echo -e "  Points: $completed_points / $sprint_points"
    fi
}

# Get phase-specific role
get_role_for_phase() {
    local phase=${1:-$(get_current_phase)}
    
    case "$phase" in
        "initialization") echo "product_owner" ;;
        "planning")       echo "product_owner" ;;
        "implementation") echo "developer" ;;
        "qa")             echo "qa" ;;
        "review")         echo "product_owner" ;;
        *)                echo "developer" ;;
    esac
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export SPRINT_STATE_FILE SPRINTS_DIR REVIEWS_DIR
export VALID_PHASES
export DEFAULT_PLANNING_MAX_LOOPS DEFAULT_IMPLEMENTATION_MAX_LOOPS
export DEFAULT_QA_MAX_LOOPS DEFAULT_REVIEW_MAX_LOOPS
export DEFAULT_MAX_REWORK_CYCLES DEFAULT_MAX_SPRINTS

export -f init_sprint_state
export -f get_sprint_state
export -f get_current_sprint
export -f get_current_phase
export -f get_phase_loop_count
export -f get_rework_count
export -f is_project_marked_done
export -f update_sprint_state
export -f set_current_phase
export -f increment_phase_loop
export -f start_sprint
export -f end_sprint
export -f increment_rework
export -f is_rework_limit_exceeded
export -f is_phase_complete
export -f has_tasks_to_rework
export -f get_max_loops_for_phase
export -f is_phase_loop_limit_exceeded
export -f mark_project_done
export -f check_project_completion
export -f show_agent_config_status
export -f show_sprint_status
export -f get_role_for_phase
