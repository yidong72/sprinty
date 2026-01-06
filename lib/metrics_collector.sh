#!/usr/bin/env bash
# ============================================================================
# Sprinty Metrics Collector
# Burndown, velocity, and sprint statistics
# ============================================================================

set -e

# Source utilities and dependencies (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"
source "$_LIB_DIR/backlog_manager.sh"
source "$_LIB_DIR/sprint_manager.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

METRICS_FILE="${SPRINTY_DIR:-.sprinty}/metrics.json"
VELOCITY_HISTORY_FILE="${SPRINTY_DIR:-.sprinty}/velocity_history.json"

# ============================================================================
# BURNDOWN METRICS
# ============================================================================

# Calculate burndown data for a sprint
# Usage: calculate_burndown [sprint_id]
# Returns: JSON with burndown data
calculate_burndown() {
    local sprint_id=${1:-$(get_current_sprint)}
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Get sprint items
    local sprint_items=$(jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s)]
    ' "$BACKLOG_FILE")
    
    local total_items=$(echo "$sprint_items" | jq 'length')
    local total_points=$(echo "$sprint_items" | jq '[.[].story_points] | add // 0')
    
    # Calculate completed items by status
    local done_items=$(echo "$sprint_items" | jq '[.[] | select(.status == "done")] | length')
    local done_points=$(echo "$sprint_items" | jq '[.[] | select(.status == "done") | .story_points] | add // 0')
    
    # In progress items
    local in_progress_items=$(echo "$sprint_items" | jq '[.[] | select(.status == "in_progress" or .status == "implemented" or .status == "qa_in_progress")] | length')
    local in_progress_points=$(echo "$sprint_items" | jq '[.[] | select(.status == "in_progress" or .status == "implemented" or .status == "qa_in_progress") | .story_points] | add // 0')
    
    # QA passed items (waiting for review)
    local qa_passed_items=$(echo "$sprint_items" | jq '[.[] | select(.status == "qa_passed")] | length')
    local qa_passed_points=$(echo "$sprint_items" | jq '[.[] | select(.status == "qa_passed") | .story_points] | add // 0')
    
    # QA failed items (need rework)
    local qa_failed_items=$(echo "$sprint_items" | jq '[.[] | select(.status == "qa_failed")] | length')
    local qa_failed_points=$(echo "$sprint_items" | jq '[.[] | select(.status == "qa_failed") | .story_points] | add // 0')
    
    # Remaining points (not done)
    local remaining_points=$((total_points - done_points))
    
    # Calculate completion percentage
    local completion_pct=0
    if [[ $total_points -gt 0 ]]; then
        completion_pct=$((done_points * 100 / total_points))
    fi
    
    # Output burndown data as JSON
    jq -n \
        --argjson sprint "$sprint_id" \
        --argjson total_items "$total_items" \
        --argjson total_points "$total_points" \
        --argjson done_items "$done_items" \
        --argjson done_points "$done_points" \
        --argjson in_progress_items "$in_progress_items" \
        --argjson in_progress_points "$in_progress_points" \
        --argjson qa_passed_items "$qa_passed_items" \
        --argjson qa_passed_points "$qa_passed_points" \
        --argjson qa_failed_items "$qa_failed_items" \
        --argjson qa_failed_points "$qa_failed_points" \
        --argjson remaining_points "$remaining_points" \
        --argjson completion_pct "$completion_pct" \
        --arg timestamp "$(get_iso_timestamp)" \
        '{
            sprint: $sprint,
            timestamp: $timestamp,
            items: {
                total: $total_items,
                done: $done_items,
                in_progress: $in_progress_items,
                qa_passed: $qa_passed_items,
                qa_failed: $qa_failed_items
            },
            points: {
                total: $total_points,
                done: $done_points,
                in_progress: $in_progress_points,
                qa_passed: $qa_passed_points,
                qa_failed: $qa_failed_points,
                remaining: $remaining_points
            },
            completion_percentage: $completion_pct
        }'
}

# ============================================================================
# VELOCITY METRICS
# ============================================================================

# Initialize velocity history file
init_velocity_history() {
    ensure_sprinty_dir
    
    if [[ ! -f "$VELOCITY_HISTORY_FILE" ]]; then
        cat > "$VELOCITY_HISTORY_FILE" << 'EOF'
{
    "sprints": [],
    "average_velocity": 0,
    "total_points_completed": 0
}
EOF
    fi
}

# Record sprint velocity
# Usage: record_sprint_velocity <sprint_id> <points_completed> <points_planned>
record_sprint_velocity() {
    local sprint_id=$1
    local points_completed=$2
    local points_planned=$3
    
    init_velocity_history
    
    local timestamp=$(get_iso_timestamp)
    
    # Check if sprint already recorded
    local exists=$(jq --argjson s "$sprint_id" '.sprints[] | select(.sprint == $s) | length > 0' "$VELOCITY_HISTORY_FILE" 2>/dev/null || echo "false")
    
    if [[ "$exists" == "true" ]]; then
        # Update existing sprint
        jq --argjson s "$sprint_id" \
           --argjson completed "$points_completed" \
           --argjson planned "$points_planned" \
           --arg ts "$timestamp" '
            (.sprints[] | select(.sprint == $s)) |= {
                sprint: $s,
                points_completed: $completed,
                points_planned: $planned,
                updated_at: $ts
            }
        ' "$VELOCITY_HISTORY_FILE" > "${VELOCITY_HISTORY_FILE}.tmp" && mv "${VELOCITY_HISTORY_FILE}.tmp" "$VELOCITY_HISTORY_FILE"
    else
        # Add new sprint
        jq --argjson s "$sprint_id" \
           --argjson completed "$points_completed" \
           --argjson planned "$points_planned" \
           --arg ts "$timestamp" '
            .sprints += [{
                sprint: $s,
                points_completed: $completed,
                points_planned: $planned,
                recorded_at: $ts
            }]
        ' "$VELOCITY_HISTORY_FILE" > "${VELOCITY_HISTORY_FILE}.tmp" && mv "${VELOCITY_HISTORY_FILE}.tmp" "$VELOCITY_HISTORY_FILE"
    fi
    
    # Recalculate average velocity
    jq '
        .total_points_completed = ([.sprints[].points_completed] | add // 0) |
        .average_velocity = (if (.sprints | length) > 0 then 
            ([.sprints[].points_completed] | add) / (.sprints | length) | floor
        else 0 end)
    ' "$VELOCITY_HISTORY_FILE" > "${VELOCITY_HISTORY_FILE}.tmp" && mv "${VELOCITY_HISTORY_FILE}.tmp" "$VELOCITY_HISTORY_FILE"
    
    log_debug "Recorded velocity for sprint $sprint_id: $points_completed points"
}

# Calculate team velocity
# Usage: calculate_velocity [num_sprints]
# Returns: JSON with velocity metrics
calculate_velocity() {
    local num_sprints=${1:-5}  # Default to last 5 sprints
    
    init_velocity_history
    
    # If we have sprint history, use it
    if [[ -f "$VELOCITY_HISTORY_FILE" ]]; then
        local sprint_count=$(jq '.sprints | length' "$VELOCITY_HISTORY_FILE")
        
        if [[ $sprint_count -gt 0 ]]; then
            jq --argjson n "$num_sprints" '
                .sprints[-$n:] as $recent |
                {
                    sprints_analyzed: ($recent | length),
                    total_points_completed: ([.sprints[].points_completed] | add // 0),
                    average_velocity: .average_velocity,
                    recent_velocity: (if ($recent | length) > 0 then
                        ([$recent[].points_completed] | add) / ($recent | length) | floor
                    else 0 end),
                    velocity_trend: (
                        if ($recent | length) >= 2 then
                            (($recent[-1].points_completed // 0) - ($recent[-2].points_completed // 0))
                        else 0 end
                    ),
                    sprint_history: $recent
                }
            ' "$VELOCITY_HISTORY_FILE"
            return 0
        fi
    fi
    
    # Calculate from current backlog if no history
    if ! is_backlog_initialized; then
        jq -n '{
            sprints_analyzed: 0,
            total_points_completed: 0,
            average_velocity: 0,
            recent_velocity: 0,
            velocity_trend: 0,
            sprint_history: []
        }'
        return 0
    fi
    
    # Get velocity from backlog data
    local done_points=$(jq '[.items[] | select(.status == "done") | .story_points] | add // 0' "$BACKLOG_FILE")
    local current_sprint=$(get_current_sprint)
    
    local avg_velocity=0
    if [[ $current_sprint -gt 0 ]]; then
        avg_velocity=$((done_points / current_sprint))
    fi
    
    jq -n \
        --argjson sprints "$current_sprint" \
        --argjson total "$done_points" \
        --argjson avg "$avg_velocity" \
        '{
            sprints_analyzed: $sprints,
            total_points_completed: $total,
            average_velocity: $avg,
            recent_velocity: $avg,
            velocity_trend: 0,
            sprint_history: []
        }'
}

# ============================================================================
# SPRINT SUMMARY
# ============================================================================

# Get comprehensive sprint summary
# Usage: get_sprint_summary [sprint_id]
# Returns: JSON with sprint summary
get_sprint_summary() {
    local sprint_id=${1:-$(get_current_sprint)}
    
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    # Get sprint state info
    local phase=$(get_current_phase)
    local loop_count=$(get_phase_loop_count)
    local rework_count=$(get_rework_count)
    
    # Get burndown data
    local burndown=$(calculate_burndown "$sprint_id")
    
    # Get items by status for this sprint
    local status_breakdown=$(jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s)] | group_by(.status) | 
        map({status: .[0].status, count: length, points: ([.[].story_points] | add // 0)})
    ' "$BACKLOG_FILE")
    
    # Get items by type for this sprint
    local type_breakdown=$(jq --argjson s "$sprint_id" '
        [.items[] | select(.sprint_id == $s)] | group_by(.type) | 
        map({type: .[0].type, count: length, points: ([.[].story_points] | add // 0)})
    ' "$BACKLOG_FILE")
    
    # Calculate sprint health score (0-100)
    local total_items=$(echo "$burndown" | jq '.items.total')
    local done_items=$(echo "$burndown" | jq '.items.done')
    local qa_failed=$(echo "$burndown" | jq '.items.qa_failed')
    
    local health_score=100
    # Deduct for QA failures (each failure = -10 points)
    local failure_penalty=$((qa_failed * 10))
    health_score=$((health_score - failure_penalty))
    # Deduct for rework cycles (each cycle = -15 points)
    local rework_penalty=$((rework_count * 15))
    health_score=$((health_score - rework_penalty))
    # Ensure score is within bounds
    if [[ $health_score -lt 0 ]]; then health_score=0; fi
    
    # Build summary JSON
    jq -n \
        --argjson sprint "$sprint_id" \
        --arg phase "$phase" \
        --argjson loop_count "$loop_count" \
        --argjson rework_count "$rework_count" \
        --argjson burndown "$burndown" \
        --argjson status_breakdown "$status_breakdown" \
        --argjson type_breakdown "$type_breakdown" \
        --argjson health_score "$health_score" \
        --arg timestamp "$(get_iso_timestamp)" \
        '{
            sprint: $sprint,
            timestamp: $timestamp,
            phase: $phase,
            loop_count: $loop_count,
            rework_count: $rework_count,
            health_score: $health_score,
            burndown: $burndown,
            status_breakdown: $status_breakdown,
            type_breakdown: $type_breakdown
        }'
}

# ============================================================================
# PROJECT-LEVEL METRICS
# ============================================================================

# Get overall project metrics
get_project_metrics() {
    if ! is_backlog_initialized; then
        log_status "ERROR" "Backlog not initialized"
        return 1
    fi
    
    local total_items=$(jq '.items | length' "$BACKLOG_FILE")
    local total_points=$(jq '[.items[].story_points] | add // 0' "$BACKLOG_FILE")
    local done_items=$(jq '[.items[] | select(.status == "done")] | length' "$BACKLOG_FILE")
    local done_points=$(jq '[.items[] | select(.status == "done") | .story_points] | add // 0' "$BACKLOG_FILE")
    
    local current_sprint=$(get_current_sprint)
    local project_done=$(get_sprint_state "project_done")
    
    # Calculate overall completion
    local completion_pct=0
    if [[ $total_points -gt 0 ]]; then
        completion_pct=$((done_points * 100 / total_points))
    fi
    
    # Get velocity data
    local velocity=$(calculate_velocity)
    local avg_velocity=$(echo "$velocity" | jq '.average_velocity')
    
    # Estimate remaining sprints
    local remaining_points=$((total_points - done_points))
    local estimated_sprints=0
    if [[ $avg_velocity -gt 0 ]]; then
        estimated_sprints=$(( (remaining_points + avg_velocity - 1) / avg_velocity ))
    fi
    
    jq -n \
        --argjson total_items "$total_items" \
        --argjson total_points "$total_points" \
        --argjson done_items "$done_items" \
        --argjson done_points "$done_points" \
        --argjson current_sprint "$current_sprint" \
        --argjson completion_pct "$completion_pct" \
        --argjson avg_velocity "$avg_velocity" \
        --argjson remaining_points "$remaining_points" \
        --argjson estimated_sprints "$estimated_sprints" \
        --argjson project_done "$project_done" \
        --arg timestamp "$(get_iso_timestamp)" \
        '{
            timestamp: $timestamp,
            items: {
                total: $total_items,
                done: $done_items,
                remaining: ($total_items - $done_items)
            },
            points: {
                total: $total_points,
                done: $done_points,
                remaining: $remaining_points
            },
            sprints: {
                current: $current_sprint,
                estimated_remaining: $estimated_sprints
            },
            completion_percentage: $completion_pct,
            average_velocity: $avg_velocity,
            project_done: $project_done
        }'
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

# Display burndown chart (ASCII)
show_burndown_chart() {
    local sprint_id=${1:-$(get_current_sprint)}
    local burndown=$(calculate_burndown "$sprint_id")
    
    local total=$(echo "$burndown" | jq '.points.total')
    local done=$(echo "$burndown" | jq '.points.done')
    local remaining=$(echo "$burndown" | jq '.points.remaining')
    local pct=$(echo "$burndown" | jq '.completion_percentage')
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║               Sprint $sprint_id Burndown                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Progress bar
    local bar_width=40
    local filled=$((pct * bar_width / 100))
    local empty=$((bar_width - filled))
    
    printf "  Progress: ["
    printf "${GREEN}%${filled}s${NC}" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %d%%\n" "$pct"
    echo ""
    
    # Stats
    echo -e "  ${GREEN}Done:${NC}      $done points"
    echo -e "  ${YELLOW}Remaining:${NC} $remaining points"
    echo -e "  ${CYAN}Total:${NC}     $total points"
    echo ""
    
    # Status breakdown
    local in_progress=$(echo "$burndown" | jq '.points.in_progress')
    local qa_passed=$(echo "$burndown" | jq '.points.qa_passed')
    local qa_failed=$(echo "$burndown" | jq '.points.qa_failed')
    
    echo "  Status Breakdown:"
    echo -e "    In Progress: ${YELLOW}$in_progress${NC} pts"
    echo -e "    QA Passed:   ${CYAN}$qa_passed${NC} pts"
    echo -e "    QA Failed:   ${RED}$qa_failed${NC} pts"
}

# Display velocity metrics
show_velocity_metrics() {
    local velocity=$(calculate_velocity)
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   Velocity Metrics                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local avg=$(echo "$velocity" | jq '.average_velocity')
    local recent=$(echo "$velocity" | jq '.recent_velocity')
    local trend=$(echo "$velocity" | jq '.velocity_trend')
    local total=$(echo "$velocity" | jq '.total_points_completed')
    local sprints=$(echo "$velocity" | jq '.sprints_analyzed')
    
    echo -e "  Average Velocity:  ${GREEN}$avg${NC} pts/sprint"
    echo -e "  Recent Velocity:   ${CYAN}$recent${NC} pts/sprint"
    
    # Trend indicator
    if [[ $trend -gt 0 ]]; then
        echo -e "  Velocity Trend:    ${GREEN}↑ +$trend${NC} (improving)"
    elif [[ $trend -lt 0 ]]; then
        echo -e "  Velocity Trend:    ${RED}↓ $trend${NC} (declining)"
    else
        echo -e "  Velocity Trend:    ${YELLOW}→ 0${NC} (stable)"
    fi
    
    echo ""
    echo -e "  Total Completed:   $total pts across $sprints sprints"
}

# Display full metrics dashboard
show_metrics_dashboard() {
    echo ""
    
    # Project overview
    local project=$(get_project_metrics 2>/dev/null)
    
    if [[ -z "$project" || "$project" == "null" ]]; then
        echo -e "${YELLOW}No metrics available. Initialize a project first.${NC}"
        return 1
    fi
    
    local completion=$(echo "$project" | jq '.completion_percentage')
    local total_items=$(echo "$project" | jq '.items.total')
    local done_items=$(echo "$project" | jq '.items.done')
    local total_points=$(echo "$project" | jq '.points.total')
    local done_points=$(echo "$project" | jq '.points.done')
    local estimated=$(echo "$project" | jq '.sprints.estimated_remaining')
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                  Project Overview                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Overall progress bar
    local bar_width=40
    local filled=$((completion * bar_width / 100))
    local empty=$((bar_width - filled))
    
    printf "  Overall Progress: ["
    printf "${GREEN}%${filled}s${NC}" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %d%%\n" "$completion"
    echo ""
    
    echo -e "  Items:  ${done_items}/${total_items} done"
    echo -e "  Points: ${done_points}/${total_points} completed"
    
    if [[ $estimated -gt 0 ]]; then
        echo -e "  Estimated Remaining: ${YELLOW}~$estimated sprints${NC}"
    fi
    
    echo ""
    
    # Show burndown for current sprint
    local current=$(get_current_sprint)
    if [[ $current -gt 0 ]]; then
        show_burndown_chart "$current"
        echo ""
    fi
    
    # Show velocity
    show_velocity_metrics
}

# ============================================================================
# SAVE/LOAD METRICS
# ============================================================================

# Save current metrics snapshot
save_metrics_snapshot() {
    ensure_sprinty_dir
    
    local sprint_id=$(get_current_sprint)
    local burndown=$(calculate_burndown "$sprint_id")
    local velocity=$(calculate_velocity)
    local project=$(get_project_metrics)
    
    jq -n \
        --arg ts "$(get_iso_timestamp)" \
        --argjson sprint "$sprint_id" \
        --argjson burndown "$burndown" \
        --argjson velocity "$velocity" \
        --argjson project "$project" \
        '{
            timestamp: $ts,
            sprint: $sprint,
            burndown: $burndown,
            velocity: $velocity,
            project: $project
        }' > "$METRICS_FILE"
    
    log_debug "Saved metrics snapshot to $METRICS_FILE"
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export METRICS_FILE VELOCITY_HISTORY_FILE

export -f calculate_burndown
export -f init_velocity_history
export -f record_sprint_velocity
export -f calculate_velocity
export -f get_sprint_summary
export -f get_project_metrics
export -f show_burndown_chart
export -f show_velocity_metrics
export -f show_metrics_dashboard
export -f save_metrics_snapshot
