#!/usr/bin/env bash
# ============================================================================
# Sprinty - Sprint-based Software Development Orchestrator
# ============================================================================
# 
# Sprinty orchestrates AI agents through structured sprints:
#   Sprint 0: PRD → Backlog creation (Product Owner)
#   Sprint 1-N: Planning → Implementation → QA → Review
#
# Usage:
#   sprinty init <project> --prd <file>   Initialize new project
#   sprinty run                           Run sprint loop
#   sprinty status [--check-done]         Show current status
#   sprinty backlog list                  List backlog items
#
# Exit Codes:
#   0  - Success
#   1  - General error
#   10 - Circuit breaker opened
#   20 - Project complete
#   21 - Max sprints reached
#
# ============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set prompts directory relative to script location (important for installed version)
export PROMPTS_DIR="$SCRIPT_DIR/prompts"

# Source library modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/circuit_breaker.sh"
source "$SCRIPT_DIR/lib/rate_limiter.sh"
source "$SCRIPT_DIR/lib/backlog_manager.sh"
source "$SCRIPT_DIR/lib/sprint_manager.sh"
source "$SCRIPT_DIR/lib/agent_adapter.sh"
source "$SCRIPT_DIR/lib/done_detector.sh"
source "$SCRIPT_DIR/lib/metrics_collector.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

VERSION="0.1.0"
STATUS_FILE="${SPRINTY_DIR:-.sprinty}/status.json"
PROGRESS_FILE="${SPRINTY_DIR:-.sprinty}/progress.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global loop counter (needed for cleanup)
global_loop_count=0

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize Sprinty for a new project
init_sprinty() {
    local project_name=${1:-"my-project"}
    local prd_file=$2
    
    log_status "INFO" "Initializing Sprinty project: $project_name"
    
    # Create directory structure
    ensure_sprinty_dir
    mkdir -p sprints reviews logs/agent_output
    
    # Initialize config from template if not exists
    if [[ ! -f "$SPRINTY_DIR/config.json" ]]; then
        if [[ -f "$SCRIPT_DIR/templates/config.json" ]]; then
            cp "$SCRIPT_DIR/templates/config.json" "$SPRINTY_DIR/config.json"
            # Update project name in config
            jq --arg name "$project_name" '.project.name = $name' "$SPRINTY_DIR/config.json" > "$SPRINTY_DIR/config.json.tmp" \
                && mv "$SPRINTY_DIR/config.json.tmp" "$SPRINTY_DIR/config.json"
            log_status "SUCCESS" "Created config: $SPRINTY_DIR/config.json"
        else
            log_status "ERROR" "Config template not found: $SCRIPT_DIR/templates/config.json"
            return 1
        fi
    fi
    
    # Initialize backlog
    init_backlog "$project_name"
    
    # Initialize sprint state
    init_sprint_state
    
    # Initialize circuit breaker
    init_circuit_breaker
    
    # Initialize rate limiter
    init_rate_limiter
    
    # Initialize exit signals
    init_exit_signals
    
    # Initialize cursor project config
    init_cursor_project_config "."
    
    # Copy PRD if provided
    if [[ -n "$prd_file" && -f "$prd_file" ]]; then
        mkdir -p specs
        cp "$prd_file" specs/PRD.md
        log_status "SUCCESS" "Copied PRD to specs/PRD.md"
    fi
    
    log_status "SUCCESS" "Sprinty initialized for project: $project_name"
    echo ""
    echo -e "${GREEN}Project initialized! Next steps:${NC}"
    echo "  1. Review specs/PRD.md (or create one)"
    echo "  2. Run: sprinty run"
    echo ""
}

# ============================================================================
# STATUS MANAGEMENT
# ============================================================================

# Update status JSON for external monitoring
update_status() {
    local loop_count=$1
    local phase=$2
    local sprint=$3
    local status=$4
    local exit_reason=${5:-""}
    
    ensure_sprinty_dir
    
    local calls_made=$(get_call_count)
    
    cat > "$STATUS_FILE" << STATUSEOF
{
    "version": "$VERSION",
    "timestamp": "$(get_iso_timestamp)",
    "loop_count": $loop_count,
    "current_sprint": $sprint,
    "current_phase": "$phase",
    "calls_made_this_hour": $calls_made,
    "max_calls_per_hour": $MAX_CALLS_PER_HOUR,
    "status": "$status",
    "exit_reason": "$exit_reason",
    "next_reset": "$(get_next_hour_time)"
}
STATUSEOF
}

# Update progress for monitoring
update_progress() {
    local status=$1
    local indicator=$2
    local elapsed=$3
    local last_output=${4:-""}
    
    ensure_sprinty_dir
    
    cat > "$PROGRESS_FILE" << EOF
{
    "status": "$status",
    "indicator": "$indicator",
    "elapsed_seconds": $elapsed,
    "last_output": "$last_output",
    "timestamp": "$(get_basic_timestamp)"
}
EOF
}

# ============================================================================
# PHASE EXECUTION
# ============================================================================

# Execute a single phase
# Usage: execute_phase <phase> <role>
# Returns: 0 on success, 1 on error, 2 on rate limit, 3 on circuit breaker
execute_phase() {
    local phase=$1
    local role=$2
    local sprint_id=$(get_current_sprint)
    local loop_count=0
    local max_loops=$(get_max_loops_for_phase "$phase")
    
    log_status "PHASE" "Starting $phase phase (role: $role, sprint: $sprint_id)"
    set_current_phase "$phase"
    
    while [[ $loop_count -lt $max_loops ]]; do
        loop_count=$((loop_count + 1))
        global_loop_count=$((global_loop_count + 1))
        
        log_status "LOOP" "=== Phase loop #$loop_count (global #$global_loop_count) ==="
        
        # Check circuit breaker
        if should_halt_execution; then
            log_status "ERROR" "Circuit breaker opened - halting phase execution"
            return 3
        fi
        
        # Check rate limits
        if ! can_make_call; then
            log_status "WARN" "Rate limit reached"
            wait_for_reset
            continue
        fi
        
        # Check for graceful exit
        local exit_reason=$(should_exit_gracefully)
        if [[ -n "$exit_reason" ]]; then
            log_status "SUCCESS" "Graceful exit: $exit_reason"
            return 0
        fi
        
        # Update status
        update_status "$global_loop_count" "$phase" "$sprint_id" "executing"
        
        # Execute agent
        run_agent "$role" "$phase" "$sprint_id"
        local agent_result=$?
        
        # Increment call counter
        increment_call_counter
        
        # Handle agent result
        case $agent_result in
            0)
                log_status "SUCCESS" "Agent execution completed"
                
                # Get output file and analyze
                local output_file=$(get_last_agent_output)
                if [[ -n "$output_file" && -f "$output_file" ]]; then
                    analyze_output_for_completion "$output_file" "$global_loop_count"
                    
                    # Check for PROJECT_DONE signal
                    if check_project_done_from_response "$output_file"; then
                        log_status "SUCCESS" "Agent reported PROJECT_DONE"
                        mark_project_done
                        return 0
                    fi
                    
                    # Check for phase completion
                    if check_phase_complete_from_response "$output_file"; then
                        log_status "SUCCESS" "Phase complete (agent signal)"
                        return 0
                    fi
                    
                    # Record circuit breaker data
                    local files_changed=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
                    local has_errors="false"
                    if grep -qE '(^Error:|^ERROR:|[Ee]xception|Fatal|FATAL)' "$output_file" 2>/dev/null; then
                        has_errors="true"
                    fi
                    local output_length=$(wc -c < "$output_file" 2>/dev/null || echo 0)
                    
                    record_loop_result "$global_loop_count" "$files_changed" "$has_errors" "$output_length"
                    if [[ $? -ne 0 ]]; then
                        log_status "WARN" "Circuit breaker triggered"
                        return 3
                    fi
                fi
                
                # Check if phase is complete (based on state)
                if is_phase_complete "$phase"; then
                    log_status "SUCCESS" "Phase $phase complete (state check)"
                    return 0
                fi
                
                # Brief pause between loops
                wait_between_calls 5
                ;;
            2)
                log_status "WARN" "Rate limit detected"
                record_rate_limit_hit
                wait_for_reset
                ;;
            3)
                log_status "WARN" "Agent execution timed out"
                record_idle_loop "$global_loop_count" "timeout"
                ;;
            *)
                log_status "ERROR" "Agent execution failed (code: $agent_result)"
                record_idle_loop "$global_loop_count" "execution_error"
                sleep 10  # Wait before retry
                ;;
        esac
        
        # Increment phase loop count
        increment_phase_loop
    done
    
    log_status "WARN" "Max loops ($max_loops) reached for phase: $phase"
    return 0
}

# ============================================================================
# SPRINT EXECUTION
# ============================================================================

# Execute Sprint 0 (initialization)
execute_sprint_zero() {
    log_status "SPRINT" "=== Sprint 0: Initialization ==="
    
    # Check if backlog already has items
    if is_backlog_initialized; then
        local item_count=$(jq '.items | length' "$BACKLOG_FILE")
        if [[ $item_count -gt 0 ]]; then
            log_status "INFO" "Backlog already has $item_count items, skipping Sprint 0"
            return 0
        fi
    fi
    
    # Execute initialization phase with Product Owner
    execute_phase "initialization" "product_owner"
    local result=$?
    
    if [[ $result -ne 0 && $result -ne 3 ]]; then
        log_status "ERROR" "Sprint 0 failed"
        return 1
    fi
    
    # Verify backlog was created
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not created during Sprint 0"
        return 1
    fi
    
    local item_count=$(jq '.items | length' "$BACKLOG_FILE")
    log_status "SUCCESS" "Sprint 0 complete: $item_count backlog items created"
    
    return 0
}

# Execute a regular sprint (1-N)
execute_sprint() {
    local sprint_id=$(start_sprint)
    local start_result=$?
    
    if [[ $start_result -eq 21 ]]; then
        log_status "WARN" "Max sprints reached"
        return 21
    fi
    
    log_status "SPRINT" "=== Sprint $sprint_id ==="
    
    local rework_count=0
    local max_rework=$(get_sprint_state "max_rework_cycles" 2>/dev/null || echo "$DEFAULT_MAX_REWORK_CYCLES")
    # Handle jq returning "null" string when field doesn't exist
    [[ "$max_rework" == "null" || -z "$max_rework" ]] && max_rework="$DEFAULT_MAX_REWORK_CYCLES"
    max_rework=${max_rework:-3}
    
    # Planning phase
    execute_phase "planning" "product_owner"
    if [[ $? -eq 3 ]]; then
        return 10  # Circuit breaker
    fi
    
    # Implementation + QA rework loop
    while [[ $rework_count -lt $max_rework ]]; do
        log_status "INFO" "Implementation/QA cycle $((rework_count + 1))/$max_rework"
        
        # Implementation phase
        execute_phase "implementation" "developer"
        if [[ $? -eq 3 ]]; then
            return 10  # Circuit breaker
        fi
        
        # Check if project is done
        if is_project_complete; then
            log_status "SUCCESS" "Project complete after implementation"
            mark_project_done
            return 20
        fi
        
        # QA phase
        execute_phase "qa" "qa"
        if [[ $? -eq 3 ]]; then
            return 10  # Circuit breaker
        fi
        
        # Check if QA failed tasks exist
        if ! has_tasks_to_rework; then
            log_status "SUCCESS" "No QA failures, proceeding to review"
            break
        fi
        
        # Handle rework
        rework_count=$((rework_count + 1))
        increment_rework
        
        if is_rework_limit_exceeded; then
            log_status "WARN" "Rework limit exceeded for sprint $sprint_id"
            break
        fi
        
        log_status "WARN" "QA failures detected, starting rework cycle $rework_count"
    done
    
    # Review phase
    execute_phase "review" "product_owner"
    if [[ $? -eq 3 ]]; then
        return 10  # Circuit breaker
    fi
    
    # Record sprint velocity before ending
    local sprint_done_points=$(get_sprint_completed_points "$sprint_id")
    local sprint_total_points=$(get_sprint_points "$sprint_id")
    record_sprint_velocity "$sprint_id" "$sprint_done_points" "$sprint_total_points"
    
    # End sprint
    end_sprint "completed"
    
    # Check if project is done
    if is_project_complete; then
        mark_project_done
        return 20
    fi
    
    return 0
}

# ============================================================================
# MAIN LOOP
# ============================================================================

# Main Sprinty execution loop
run_sprinty() {
    log_status "SUCCESS" "🚀 Sprinty starting..."
    log_status "INFO" "Version: $VERSION"
    log_status "INFO" "Max calls/hour: $MAX_CALLS_PER_HOUR"
    
    # Check dependencies
    if ! check_dependencies; then
        log_status "ERROR" "Missing dependencies"
        exit 1
    fi
    
    # Check cursor-agent
    if ! check_cursor_agent_installed; then
        log_status "ERROR" "cursor-agent not installed"
        exit 1
    fi
    
    # Check if project is initialized
    if ! is_sprinty_initialized; then
        log_status "ERROR" "Sprinty not initialized in this directory"
        echo ""
        echo "Run: sprinty init <project-name> --prd <prd-file>"
        exit 1
    fi
    
    # Initialize tracking
    init_rate_limiter
    init_circuit_breaker
    reset_exit_signals
    
    # Sprint 0: Create backlog from PRD
    execute_sprint_zero
    local result=$?
    if [[ $result -ne 0 ]]; then
        update_status "$global_loop_count" "initialization" 0 "failed" "sprint_zero_failed"
        exit 1
    fi
    
    # Get config values
    local max_sprints=$(jq -r '.sprint.max_sprints // 10' "$SPRINTY_DIR/config.json" 2>/dev/null || echo "10")
    local sprint_count=0
    
    # Main sprint loop
    while ! is_project_marked_done && [[ $sprint_count -lt $max_sprints ]]; do
        sprint_count=$((sprint_count + 1))
        
        # Check for graceful exit before starting new sprint
        local exit_reason=$(should_exit_gracefully)
        if [[ -n "$exit_reason" ]]; then
            log_status "SUCCESS" "🏁 Graceful exit triggered: $exit_reason"
            update_status "$global_loop_count" "$(get_current_phase)" "$sprint_count" "completed" "$exit_reason"
            break
        fi
        
        execute_sprint
        result=$?
        
        case $result in
            0)
                log_status "SUCCESS" "Sprint $sprint_count completed"
                ;;
            10)
                log_status "ERROR" "Circuit breaker opened"
                update_status "$global_loop_count" "$(get_current_phase)" "$sprint_count" "halted" "circuit_breaker"
                exit 10
                ;;
            20)
                log_status "SUCCESS" "🎉 Project complete!"
                update_status "$global_loop_count" "$(get_current_phase)" "$sprint_count" "completed" "project_done"
                exit 20
                ;;
            21)
                log_status "WARN" "Max sprints reached"
                update_status "$global_loop_count" "$(get_current_phase)" "$sprint_count" "stopped" "max_sprints"
                exit 21
                ;;
        esac
    done
    
    # Final status
    if is_project_marked_done; then
        log_status "SUCCESS" "🎉 Project marked as DONE!"
        show_final_summary
        exit 20
    else
        log_status "INFO" "Sprint loop ended (sprints: $sprint_count)"
        show_final_summary
    fi
}

# ============================================================================
# STATUS DISPLAY
# ============================================================================

# Show current status
show_status() {
    local check_done=${1:-false}
    
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Sprinty Status                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check initialization
    if ! is_sprinty_initialized; then
        echo -e "${RED}Status: Not initialized${NC}"
        echo ""
        echo "Run: sprinty init <project-name>"
        return 1
    fi
    
    # Sprint status
    show_sprint_status
    
    # Backlog summary
    echo ""
    show_backlog_summary
    
    # Circuit breaker status
    echo ""
    show_circuit_status
    
    # Rate limit status
    echo ""
    show_rate_limit_status
    
    # Exit detection status
    echo ""
    show_exit_status
    
    # Check done flag
    if [[ "$check_done" == "true" ]]; then
        echo ""
        if is_project_complete; then
            echo -e "${GREEN}✅ PROJECT DONE - All criteria met${NC}"
            return 20
        else
            echo -e "${YELLOW}⏳ Project in progress${NC}"
            return 0
        fi
    fi
}

# Show final summary
show_final_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Final Summary                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local sprint=$(get_current_sprint)
    local total_calls=$(jq -r '.total_calls_session // 0' "$RATE_LIMIT_STATE_FILE" 2>/dev/null || echo "0")
    
    echo "Total Sprints:        $sprint"
    echo "Total API Calls:      $total_calls"
    echo "Global Loop Count:    $global_loop_count"
    
    if is_backlog_initialized; then
        local total_items=$(jq '.items | length' "$BACKLOG_FILE")
        local done_items=$(jq '[.items[] | select(.status == "done")] | length' "$BACKLOG_FILE")
        local total_points=$(jq '[.items[].story_points] | add // 0' "$BACKLOG_FILE")
        local done_points=$(jq '[.items[] | select(.status == "done") | .story_points] | add // 0' "$BACKLOG_FILE")
        
        echo ""
        echo "Backlog Items:        $done_items / $total_items done"
        echo "Story Points:         $done_points / $total_points completed"
        
        # Record final sprint velocity if sprint completed
        if [[ $sprint -gt 0 ]]; then
            local sprint_done_points=$(get_sprint_completed_points "$sprint")
            local sprint_total_points=$(get_sprint_points "$sprint")
            record_sprint_velocity "$sprint" "$sprint_done_points" "$sprint_total_points"
        fi
        
        # Save metrics snapshot
        save_metrics_snapshot
    fi
    
    echo ""
}

# ============================================================================
# CLI COMMANDS
# ============================================================================

# Show help
show_help() {
    cat << 'HELPEOF'
Sprinty - Sprint-based Software Development Orchestrator

Usage: sprinty <command> [options]

Commands:
    init <project> [--prd <file>]   Initialize new project
    run                              Run sprint loop
    status [--check-done]            Show current status
    backlog list                     List backlog items
    backlog add <title> [options]    Add backlog item
    metrics                          Show sprint metrics

Options:
    -h, --help              Show this help message
    -v, --version           Show version
    --model <model>         Set AI model (default: opus-4.5-thinking)
    --monitor, -m           Launch in tmux dashboard (use with 'run')
    --reset-circuit         Reset circuit breaker
    --reset-rate-limit      Reset rate limiter
    --calls <num>           Set max calls per hour

Available Models:
    opus-4.5-thinking, opus-4.5, sonnet-4.5-thinking, sonnet-4.5,
    opus-4.1, gemini-3-pro, gemini-3-flash, gpt-5.2, gpt-5.1, grok, auto

Examples:
    sprinty init my-project --prd docs/PRD.md
    sprinty run
    sprinty --monitor run                    # Launch with tmux dashboard
    sprinty --model sonnet-4.5 --monitor run # With custom model
    sprinty status --check-done
    sprinty backlog list
    sprinty backlog add "Implement login" --type feature --points 5

Environment Variables:
    CURSOR_MODEL                AI model to use
    MAX_CALLS_PER_HOUR          Rate limit (default: 100)
    SPRINTY_MONITOR_REFRESH     Monitor refresh interval in seconds (default: 5)

Exit Codes:
    0   - Success
    1   - General error
    10  - Circuit breaker opened
    20  - Project complete
    21  - Max sprints reached

HELPEOF
}

# Handle backlog commands
handle_backlog_cmd() {
    local subcmd=$1
    shift
    
    case $subcmd in
        list)
            list_backlog
            ;;
        add)
            local title=$1
            local type="feature"
            local priority=1
            local points=3
            
            shift
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --type) type=$2; shift 2 ;;
                    --priority) priority=$2; shift 2 ;;
                    --points) points=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            
            if [[ -z "$title" ]]; then
                echo "Usage: sprinty backlog add <title> [--type <type>] [--priority <n>] [--points <n>]"
                return 1
            fi
            
            add_backlog_item "$title" "$type" "$priority" "$points"
            ;;
        summary)
            show_backlog_summary
            ;;
        *)
            echo "Unknown backlog command: $subcmd"
            echo "Available: list, add, summary"
            return 1
            ;;
    esac
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    log_status "INFO" "Sprinty interrupted. Cleaning up..."
    update_status "$global_loop_count" "$(get_current_phase 2>/dev/null || echo 'unknown')" "$(get_current_sprint 2>/dev/null || echo 0)" "interrupted"
    exit 0
}

trap cleanup SIGINT SIGTERM

# ============================================================================
# MONITOR MODE (TMUX DASHBOARD)
# ============================================================================

# Launch sprinty in tmux monitor mode with 3 panes
launch_monitor() {
    local session_name="sprinty-monitor"
    local refresh_interval=${SPRINTY_MONITOR_REFRESH:-5}
    
    # Check if tmux is installed
    if ! command -v tmux &> /dev/null; then
        echo -e "${RED}Error: tmux is required for monitor mode${NC}"
        echo ""
        echo "Install tmux:"
        echo "  Ubuntu/Debian: sudo apt install tmux"
        echo "  macOS:         brew install tmux"
        echo "  Fedora:        sudo dnf install tmux"
        exit 1
    fi
    
    # Kill existing session if it exists
    tmux kill-session -t "$session_name" 2>/dev/null || true
    
    # Get the sprinty command path
    local sprinty_cmd
    sprinty_cmd="$(realpath "${BASH_SOURCE[0]}")"
    
    # Build the run command with any passed options
    local run_cmd="$sprinty_cmd"
    [[ -n "${CURSOR_MODEL:-}" ]] && run_cmd="$run_cmd --model $CURSOR_MODEL"
    [[ -n "${MAX_CALLS_PER_HOUR:-}" ]] && run_cmd="$run_cmd --calls $MAX_CALLS_PER_HOUR"
    run_cmd="$run_cmd run"
    
    # Create new tmux session with the run pane (main, left side)
    tmux new-session -d -s "$session_name" -n "sprinty" "$run_cmd; echo ''; echo 'Press Enter to close...'; read"
    
    # Split horizontally (creates right pane)
    tmux split-window -h -t "$session_name:0"
    
    # In right pane, split vertically (creates bottom-right pane)
    tmux split-window -v -t "$session_name:0.1"
    
    # Set up status pane (top-right) with watch
    tmux send-keys -t "$session_name:0.1" "watch -n $refresh_interval -c '$sprinty_cmd status'" C-m
    
    # Set up metrics pane (bottom-right) with watch
    tmux send-keys -t "$session_name:0.2" "watch -n $refresh_interval -c '$sprinty_cmd metrics'" C-m
    
    # Adjust pane sizes (left pane 60%, right panes 40%)
    tmux select-pane -t "$session_name:0.0"
    tmux resize-pane -t "$session_name:0.0" -x 60%
    
    # Set pane titles (if supported)
    tmux select-pane -t "$session_name:0.0" -T "🚀 Sprint Runner"
    tmux select-pane -t "$session_name:0.1" -T "📊 Status"
    tmux select-pane -t "$session_name:0.2" -T "📈 Metrics"
    
    # Enable mouse mode for easy pane switching
    tmux set-option -t "$session_name" mouse on
    
    # Select the run pane
    tmux select-pane -t "$session_name:0.0"
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Sprinty Monitor Launched! 🚀                     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Session: $session_name"
    echo ""
    echo "Layout:"
    echo "  ┌─────────────────┬─────────────┐"
    echo "  │                 │   Status    │"
    echo "  │  Sprint Runner  ├─────────────┤"
    echo "  │                 │   Metrics   │"
    echo "  └─────────────────┴─────────────┘"
    echo ""
    echo "Commands:"
    echo "  Attach:  tmux attach -t $session_name"
    echo "  Detach:  Ctrl+B, then D"
    echo "  Kill:    tmux kill-session -t $session_name"
    echo ""
    
    # Attach to the session
    tmux attach -t "$session_name"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    # Parse global options first
    local monitor_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --model)
                export CURSOR_MODEL="$2"
                shift 2
                ;;
            --calls)
                export MAX_CALLS_PER_HOUR="$2"
                shift 2
                ;;
            --monitor|-m)
                monitor_mode=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    local command=${1:-""}
    shift 2>/dev/null || true
    
    case $command in
        init)
            local project_name=$1
            local prd_file=""
            shift 2>/dev/null || true
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --prd) prd_file=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            
            if [[ -z "$project_name" ]]; then
                echo "Usage: sprinty init <project-name> [--prd <file>]"
                exit 1
            fi
            
            init_sprinty "$project_name" "$prd_file"
            ;;
        run)
            if [[ "$monitor_mode" == "true" ]]; then
                launch_monitor
            else
                run_sprinty
            fi
            ;;
        status)
            local check_done=false
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --check-done) check_done=true; shift ;;
                    *) shift ;;
                esac
            done
            show_status "$check_done"
            ;;
        backlog)
            handle_backlog_cmd "$@"
            ;;
        metrics)
            show_metrics_dashboard
            ;;
        --reset-circuit)
            reset_circuit_breaker "Manual reset via CLI"
            ;;
        --reset-rate-limit)
            reset_rate_limiter
            ;;
        --version|-v)
            echo "Sprinty version $VERSION"
            ;;
        --help|-h|help)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'sprinty --help' for usage"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
